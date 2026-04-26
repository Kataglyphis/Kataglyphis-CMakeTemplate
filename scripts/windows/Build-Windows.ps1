param(
  [switch]$SkipFormat,
  [switch]$SkipTidy,
  [switch]$SkipMsix,
  [string]$Configurations = '',
  [string]$WorkspaceDir = '',
  # Configuration file path (overrides default config file)
  [string]$ConfigPath = '',
  # Build and logging directories (override config values)
  [string]$LogDir = '',
  [string]$BuildDirMsvc = '',
  [string]$BuildDirClangClTsan = '',
  [string]$BuildDirProfile = '',
  [string]$BuildDirRelease = '',
  # Preset overrides
  [string]$PresetMsvcDebug = '',
  [string]$PresetClangClDebugTsan = '',
  [string]$ClangProfilePreset = '',
  [string]$PresetClangClRelease = '',
  # MSIX / tooling overrides
  [string]$MakeAppxOverride = '',
  [string]$MsixPackageName = '',
  [string]$MsixPublisher = '',
  [string]$MsixVersion = '',
  [string]$MsixMinVersion = '',
  [string]$MsixManifestTemplate = '',
  # Optional: remove transient build artifacts (coverage/msix-staging) after a successful run
  [switch]$CleanupAfter
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Note: CONFIGURATIONS environment variable support removed.
# Configurations must be provided explicitly via the -Configurations parameter.

## Use WindowsConfig.Common helpers to parse / validate selected configurations when
## possible. We still keep a local set of valid configuration names for quick
## validation and help text.
$validConfigs = @('clangcl-debug','clangcl-profile','clangcl-release','msvc-debug')
[string[]]$script:Configurations = @()

# Accept configurations passed in via the -Configurations parameter. If the
# explicit parameter binding is lost (for example when invoked through docker
# / entrypoint wrappers), attempt to recover a value from positional args.
if ([string]::IsNullOrWhiteSpace($Configurations) -and $args.Count -gt 0) {
  # Parse common positional patterns: '-Configurations value',
  # '-Configurations=value', or a single positional value like
  # 'clangcl-debug,clangcl-profile'.
  for ($i = 0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    if ($a -match '^(?:-+|/+)Configurations(?:=(.*))?$') {
      if ($Matches[1]) {
        $Configurations = $Matches[1]
      } elseif ($i + 1 -lt $args.Count) {
        $Configurations = $args[$i + 1]
      }
      break
    }
  }

  if ([string]::IsNullOrWhiteSpace($Configurations)) {
    foreach ($a in $args) {
      # Choose the first token that doesn't look like a switch.
      if (-not ($a -like '-*') -and -not ($a -like '/*')) {
        $Configurations = $a
        break
      }
    }
  }
}

# If we're still missing configurations and there are no $args (this can
# happen when the script is invoked via docker/entrypoint wrappers that
# don't populate $args or named parameter bindings), attempt to recover the
# value from the raw process command line. We try to locate either a
# '-Configurations=val' token or a '-Configurations val' pair. If neither is
# present, look for the first non-switch token after the script path that
# doesn't look like an absolute path.
if ([string]::IsNullOrWhiteSpace($Configurations) -and $args.Count -eq 0) {
  $cmdArgs = [Environment]::GetCommandLineArgs()
  for ($i = 0; $i -lt $cmdArgs.Length; $i++) {
    $a = $cmdArgs[$i]
    if ($a -match '^(?:-+|/+)Configurations(?:=(.*))?$') {
      if ($Matches[1]) {
        $Configurations = $Matches[1]
      } elseif ($i + 1 -lt $cmdArgs.Length) {
        $Configurations = $cmdArgs[$i + 1]
      }
      break
    }
  }

  if ([string]::IsNullOrWhiteSpace($Configurations)) {
    # Try to find the script token (ends with .ps1) and start searching after
    # it; otherwise start at index 1 (skip the executable path at 0).
    $scriptIndex = -1
    for ($si = 0; $si -lt $cmdArgs.Length; $si++) {
      if ($cmdArgs[$si] -match '\.ps1$') { $scriptIndex = $si; break }
    }
    $start = if ($scriptIndex -ge 0) { $scriptIndex + 1 } else { 1 }

    for ($i = $start; $i -lt $cmdArgs.Length; $i++) {
      $a = $cmdArgs[$i]
      # Skip switches and absolute paths (script path, mounts, etc.).
      if (-not ($a -like '-*') -and -not ($a -like '/*') -and -not ($a -match '^[A-Za-z]:\\')) {
        $Configurations = $a
        break
      }
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($Configurations)) {
  $script:Configurations = $Configurations -split '[,\s]+' | Where-Object { $_ -ne '' }
  foreach ($c in $script:Configurations) {
    if ($c -notin $validConfigs) {
      throw "Invalid configuration '$c'. Valid values: $($validConfigs -join ', ')"
    }
  }
}

## Use Get-OrDefault and Get-ConfigValue from WindowsConfig.Common (ContainerHub) to
## maximize reuse of shared logic. Those modules are preloaded/imported below.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$containerHubModulesRoot = Join-Path $repoRoot 'ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules'

$sharedModulePath = Join-Path $containerHubModulesRoot 'WindowsScripts.Shared.psm1'
$buildModulePath = Join-Path $containerHubModulesRoot 'WindowsBuild.Common.psm1'
$toolchainModulePath = Join-Path $containerHubModulesRoot 'WindowsToolchain.Common.psm1'
## Additional ContainerHub modules we can reuse instead of local copies
$containerFormattingModulePath = Join-Path $containerHubModulesRoot 'WindowsFormatting.Common.psm1'
$containerCmakeModulePath = Join-Path $containerHubModulesRoot 'WindowsCMake.Common.psm1'
$containerTestingModulePath = Join-Path $containerHubModulesRoot 'WindowsTesting.Common.psm1'
$containerMsixModulePath = Join-Path $containerHubModulesRoot 'WindowsMsix.Common.psm1'
## uv (astral "uv") helpers used by formatting/python steps
$containerUvModulePath = Join-Path $containerHubModulesRoot 'WindowsUv.Common.psm1'
$localModulesRoot = Join-Path $PSScriptRoot 'modules'
$localCmakeModulePath = Join-Path $localModulesRoot 'Build.CMake.psm1'
$localFormattingModulePath = Join-Path $localModulesRoot 'Build.Formatting.psm1'
$localTestingModulePath = Join-Path $localModulesRoot 'Build.Testing.psm1'
$localPackagingModulePath = Join-Path $localModulesRoot 'Build.Packaging.psm1'

if (-not (Test-Path $sharedModulePath)) {
  throw "ContainerHub shared module not found: $sharedModulePath"
}
if (-not (Test-Path $buildModulePath)) {
  throw "ContainerHub build module not found: $buildModulePath"
}
if (-not (Test-Path $toolchainModulePath)) {
  throw "ContainerHub toolchain module not found: $toolchainModulePath"
}
if (-not (Test-Path $containerFormattingModulePath)) {
  throw "ContainerHub formatting module not found: $containerFormattingModulePath"
}
if (-not (Test-Path $containerCmakeModulePath)) {
  throw "ContainerHub CMake module not found: $containerCmakeModulePath"
}
if (-not (Test-Path $containerTestingModulePath)) {
  throw "ContainerHub testing module not found: $containerTestingModulePath"
}
if (-not (Test-Path $containerMsixModulePath)) {
  throw "ContainerHub MSIX module not found: $containerMsixModulePath"
}
if (-not (Test-Path $containerUvModulePath)) {
  throw "ContainerHub uv module not found: $containerUvModulePath"
}
## Preload all ContainerHub module files to avoid ordering/import timing issues
## (some modules expect helpers from other ContainerHub modules to already be
## loaded; importing them all up-front makes the behavior consistent across
## environments and avoids runtime "function not found" errors).
  try {
    $containerModuleFiles = Get-ChildItem -Path $containerHubModulesRoot -Filter '*.psm1' -File -ErrorAction SilentlyContinue
    foreach ($mf in $containerModuleFiles) {
      try {
        # Ensure the module file is not blocked (downloaded files can be blocked on Windows).
        Unblock-File -LiteralPath $mf.FullName -ErrorAction SilentlyContinue
        Import-Module $mf.FullName -Force -ErrorAction Stop
        Write-Host "DEBUG: Imported container module: $($mf.Name)"
      } catch {
        Write-Host "DEBUG: Import-Module failed for container module $($mf.FullName): $($_.Exception.Message)"
      }
    }
  } catch {
    Write-Host "DEBUG: Failed enumerating container modules in ${containerHubModulesRoot}: $($_.Exception.Message)"
  }
## Local modules are optional. Prefer ContainerHub shared modules and allow
## the local modules only as optional overrides. This makes it safe to remove
## the local copies: when absent, the ContainerHub implementations are used.

## Import local helper modules first. They provide project-specific glue
## but should defer to the shared ContainerHub implementations when
## available. Importing the ContainerHub modules after the local modules
## with -Force ensures the ContainerHub versions override duplicates,
## maximising reuse while preserving any local extensions.
if (Test-Path $localCmakeModulePath) { Import-Module $localCmakeModulePath -Force }
if (Test-Path $localFormattingModulePath) { Import-Module $localFormattingModulePath -Force }
if (Test-Path $localTestingModulePath) { Import-Module $localTestingModulePath -Force }
if (Test-Path $localPackagingModulePath) { Import-Module $localPackagingModulePath -Force }

## Now import the ContainerHub shared modules and force them to override
## any duplicate function definitions from the local modules so we reuse
## the authoritative implementations from ExternalLib/Kataglyphis-ContainerHub.
Import-Module $buildModulePath -Force
Import-Module $toolchainModulePath -Force
Import-Module $sharedModulePath -Force

## Import additional ContainerHub modules that provide CMake/format/testing/packaging
## implementations. These will override local copies when present.
## The uv helpers are required by the formatting module; import them first so
## functions like New-UvProjectEnvironment are available when formatting code
## runs those helpers at runtime.
Import-Module $containerUvModulePath -Force
Import-Module $containerFormattingModulePath -Force
Import-Module $containerCmakeModulePath -Force
Import-Module $containerTestingModulePath -Force
Import-Module $containerMsixModulePath -Force

## Sanity check: ensure essential functions are available. Import-Module should
## export these symbols, but in some environments module loading can behave
## unexpectedly (missing submodule, execution policy, etc.). If a function is
## missing, attempt to dot-source the module file as a fallback so the
## definitions are available in the current scope. If that also fails, emit a
## clear error with remediation steps.
$essentialFunctionMap = @{
  'Resolve-WorkspacePath'          = $sharedModulePath
  'New-BuildContext'               = $buildModulePath
  'Invoke-BuildExternal'           = $buildModulePath
  'Invoke-ToolchainChecks'         = $toolchainModulePath
  'Invoke-CmakeFormatStep'         = $containerFormattingModulePath
  'Invoke-ClangFormatStep'         = $containerFormattingModulePath
  'Invoke-CmakeConfigureAndBuild'  = $containerCmakeModulePath
  'Test-ClangClThreadSanitizerSupport' = $containerCmakeModulePath
  'Resolve-TestExecutable'         = $containerTestingModulePath
  'Invoke-CtestDiscoveredTests'    = $containerTestingModulePath
  'Invoke-ManualTestExecutable'    = $containerTestingModulePath
  'Resolve-WindowsSdkToolPath'     = $containerMsixModulePath
  'Expand-XmlTemplateTokens'       = $containerMsixModulePath
  'New-TransparentPng'             = $containerMsixModulePath
  # uv helpers (virtualenv/astral uv) used by formatting/python steps
  'New-UvProjectEnvironment'      = $containerUvModulePath
  'Invoke-UvCommand'               = $containerUvModulePath
  'Remove-UvProjectEnvironment'    = $containerUvModulePath
  'Sync-UvProjectDependencies'     = $containerUvModulePath
}

foreach ($fn in $essentialFunctionMap.Keys) {
  if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
    $modulePath = $essentialFunctionMap[$fn]
    if (-not (Test-Path $modulePath)) {
      throw "Required function '$fn' is missing and module file not found: $modulePath`nEnsure the ContainerHub submodule is initialized: `n  git submodule update --init --recursive"
    }

    Write-Host "DEBUG: Function '$fn' not found after Import-Module; attempting Import-Module on $modulePath as a fallback"
    # Try Import-Module first; in some constrained or module-aware environments importing
    # the .psm1 file succeeds where dot-sourcing may fail. If Import-Module fails,
    # fall back to dot-sourcing and emit richer diagnostics to help CI/container
    # debugging (file metadata, head of file and full exception details).
    $importSucceeded = $false
    try {
      Import-Module $modulePath -Force -ErrorAction Stop
      $importSucceeded = $true
    } catch {
      Write-Host "DEBUG: Import-Module failed for '$modulePath': $($_.Exception.Message)"
      Write-Host "DEBUG: Exception details:"
      Write-Host ($_.Exception | Format-List * -Force)
    }

    if (-not $importSucceeded) {
      Write-Host "DEBUG: Falling back to dot-sourcing $modulePath"
      try {
        . $modulePath
      } catch {
        # Collect some contextual diagnostics to help root-cause the "token" error
        $fileInfo = $null
        try { $fileInfo = Get-Item -LiteralPath $modulePath -ErrorAction SilentlyContinue } catch {}
        $fileHead = $null
        try { $fileHead = Get-Content -LiteralPath $modulePath -TotalCount 60 -ErrorAction SilentlyContinue | Out-String } catch {}

        $excDetails = $null
        try { $excDetails = $_ | Format-List * -Force | Out-String } catch { $excDetails = $_.Exception.Message }

        throw "Failed to load required function '$fn' from module file: $modulePath`nException: $($_.Exception.Message)`nFile: $($fileInfo.FullName) Size=$($fileInfo.Length) LastWrite=$($fileInfo.LastWriteTime)`n--- File head ---`n$fileHead`n--- Exception details ---`n$excDetails"
      }
    }

    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
      throw "Failed to load required function '$fn' from module file: $modulePath"
    }
  }
}

$defaultConfigPath = Join-Path $PSScriptRoot 'Build-Windows.config.psd1'
$configPath = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath } else { $defaultConfigPath }
if (-not (Test-Path $configPath)) {
  throw "Build config not found: $configPath"
}

$config = Import-PowerShellDataFile -Path $configPath

# Resolve workspace root strictly from parameter or default to the repository root.
# Do not consult environment variables.
if (-not [string]::IsNullOrWhiteSpace($WorkspaceDir)) {
  $workspaceRoot = $WorkspaceDir
} else {
  $workspaceRoot = $repoRoot
}

# Use parameter overrides where provided; otherwise fall back to config file values.
$logDir = Get-OrDefault $LogDir (Get-ConfigValue -Config $config -Path 'Build.LogDir')

$buildDirMsvc = Get-OrDefault $BuildDirMsvc (Get-ConfigValue -Config $config -Path 'Build.BuildDirMsvc')
$buildDirClangCl = Get-ConfigValue -Config $config -Path 'Build.BuildDirClangCl'
$buildDirClangClTsan = Get-OrDefault $BuildDirClangClTsan (Get-ConfigValue -Config $config -Path 'Build.BuildDirClangClTsan')
$buildProfileDir = Get-OrDefault $BuildDirProfile (Get-ConfigValue -Config $config -Path 'Build.BuildDirProfile')
$buildReleaseDir = Get-OrDefault $BuildDirRelease (Get-ConfigValue -Config $config -Path 'Build.BuildDirRelease')

$presetMsvcDebug = Get-OrDefault $PresetMsvcDebug (Get-ConfigValue -Config $config -Path 'Build.Presets.MsvcDebug')
$presetClangClDebug = Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClDebug'
$presetClangClDebugTsan = Get-OrDefault $PresetClangClDebugTsan (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClDebugTsan')
$clangProfilePreset = Get-OrDefault $ClangProfilePreset (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClProfile')
$presetClangClRelease = Get-OrDefault $PresetClangClRelease (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClRelease')

$workspacePath = Resolve-WorkspacePath -Path $workspaceRoot
$buildPathMsvc = Join-Path $workspacePath $buildDirMsvc
$buildPathClangCl = Join-Path $workspacePath $buildDirClangCl
$buildPathClangClTsan = Join-Path $workspacePath $buildDirClangClTsan
$buildProfilePath = Join-Path $workspacePath $buildProfileDir
$buildReleasePath = Join-Path $workspacePath $buildReleaseDir

if ($buildPathClangCl -eq $buildPathMsvc) {
  $buildPathClangCl = Join-Path $workspacePath ("${buildDirMsvc}-clangcl")
}
if ($buildPathClangClTsan -eq $buildPathClangCl) {
  $buildPathClangClTsan = Join-Path $workspacePath ("${buildDirClangCl}-tsan")
}
if ($buildProfilePath -eq $buildReleasePath) {
  $buildProfilePath = Join-Path $workspacePath ("${buildReleaseDir}-profile")
}

 # Define available build stages. Each entry maps a configuration name (what
 # you pass with -Configurations) to a preset, build path and stage flags.
 $stageDefinitions = [ordered]@{
   'clangcl-debug'   = @{
     Preset        = $presetClangClDebug
     BuildPath     = $buildPathClangCl
     Configuration = 'Debug'
     Test          = $true
     Coverage      = $true
     ClangTidy     = $true
     Benchmark     = $false
     Package       = $false
     RequiresClang = $true
     RuntimeFlavor = 'Clang'
   }
   'clangcl-profile' = @{
     Preset        = $clangProfilePreset
     BuildPath     = $buildProfilePath
     Configuration = 'RelWithDebInfo'
     Test          = $false
     Coverage      = $false
     ClangTidy     = $false
     Benchmark     = $true
     Package       = $false
     RequiresClang = $true
     RuntimeFlavor = 'Clang'
   }
   'clangcl-release' = @{
     Preset        = $presetClangClRelease
     BuildPath     = $buildReleasePath
     Configuration = 'Release'
     Test          = $false
     Coverage      = $false
     ClangTidy     = $false
     Benchmark     = $false
     Package       = $true
     RequiresClang = $true
     RuntimeFlavor = 'Clang'
   }
   # MSVC is treated as a normal stage now; it will only run when explicitly
   # requested via -Configurations (e.g. -Configurations 'msvc-debug').
   'msvc-debug' = @{
     Preset        = $presetMsvcDebug
     BuildPath     = $buildPathMsvc
     Configuration = 'Debug'
     Test          = $true
     Coverage      = $false
     ClangTidy     = $false
     Benchmark     = $false
     Package       = $false
     RequiresClang = $false
     RuntimeFlavor = 'Msvc'
   }
 }

if ($script:Configurations.Count -gt 0) {
  # Normalize & validate the requested configurations using the shared
  # WindowsConfig.Common implementation from the ContainerHub. This ensures
  # consistent parsing (commas, casing) and centralises error handling.
  $selected = Get-SelectedConfigurations -Configurations $script:Configurations -AvailableConfigurations $stageDefinitions.Keys
  # Replace the script variable with the normalized selection (HashSet enumerates values)
  $script:Configurations = @($selected)
}

## Delegate clang-tidy invocation to the ContainerHub implementation when
## available. This keeps logic consistent across projects and centralizes
## maintenance. The ContainerHub module provides Invoke-ClangTidyFixStep which
## accepts -Context, -WorkspacePath and -BuildRoot and supports configurable
## checks.

$context = New-BuildContext -Workspace $workspacePath -LogDir $logDir -StopOnError

try {
  Open-BuildLog -Context $context
  # Initialize fast-build cache environment if configured. This sets up
  # GLOBAL_CACHE_DIR, SCCACHE_DIR, CARGO_HOME, and PUB_CACHE. The config value
  # Build.FastBuildDir or the -FastBuildDir parameter may be used to override
  # the location. When set, we will attempt to pull prebuilt artifacts before
  # building and push artifacts back after a successful build.
  $fastBuildDir = Get-OrDefault $null (Get-ConfigValue -Config $config -Path 'Build.FastBuildDir')
  if (-not [string]::IsNullOrWhiteSpace($fastBuildDir)) {
    Invoke-BuildStep -Context $context -StepName 'Init fast cache' -Script {
      Initialize-BuildCacheEnvironment -Context $context -FastBuildDir $fastBuildDir | Out-Null
      Write-BuildLog -Context $context -Message "Fast build dir configured: $fastBuildDir"
    } | Out-Null
  } else {
    Write-BuildLog -Context $context -Message 'No FastBuildDir configured; skipping fast cache initialization.'
  }
  # Emit debug information to help diagnose why the -Configurations
  # parameter may be lost when the script is invoked via docker/entrypoint
  # wrappers. This does not change behavior; it only records the current
  # PowerShell binding state and the raw process command line for inspection
  # in the build log.
  try {
    $cmdArgs = [Environment]::GetCommandLineArgs()

    Write-BuildLog -Context $context -Message "DEBUG: MyInvocation.Line: $($MyInvocation.Line)"
    Write-BuildLog -Context $context -Message "DEBUG: PSBoundParameters keys: $($PSBoundParameters.Keys -join ', ')"
    if ($PSBoundParameters.Keys.Count -gt 0) {
      foreach ($k in $PSBoundParameters.Keys) {
        Write-BuildLog -Context $context -Message "DEBUG: PSBoundParameters[$k] = $($PSBoundParameters[$k])"
      }
    }

    Write-BuildLog -Context $context -Message "DEBUG: script variable 'Configurations' = '$Configurations'"
    Write-BuildLog -Context $context -Message "DEBUG: script parameter 'WorkspaceDir' = '$WorkspaceDir'"
    Write-BuildLog -Context $context -Message "DEBUG: CLI overrides: ConfigPath='$ConfigPath' LogDir='$LogDir' BuildDirMsvc='$BuildDirMsvc' BuildDirClangCl='$BuildDirClangCl'"

    if ($args.Count -gt 0) {
      Write-BuildLog -Context $context -Message "DEBUG: script args (count $($args.Count)):"
      for ($i = 0; $i -lt $args.Count; $i++) {
        Write-BuildLog -Context $context -Message "DEBUG: args[$i] = '$($args[$i])'"
      }
    } else {
      Write-BuildLog -Context $context -Message "DEBUG: args array is empty"
    }

    Write-BuildLog -Context $context -Message "DEBUG: Process command line args: $([string]::Join(' | ', $cmdArgs))"
  } catch {
    Write-BuildLog -Context $context -Message "DEBUG: Failed to write debug info: $_"
  }

  Write-BuildLog -Context $context -Message "=== Windows CI inside container ==="
  Write-BuildLog -Context $context -Message "Workspace: $workspacePath"
  Write-BuildLog -Context $context -Message "Configurations param: '$Configurations' | Parsed: $($script:Configurations -join ', ') | Count: $($script:Configurations.Count)"

  Invoke-BuildStep -Context $context -StepName 'Tool versions' -Critical -Script {
    Invoke-ToolchainChecks -Context $context -ToolArguments @{
      'cmake'  = @('--version')
      'ninja'  = @('--version')
    } -RequiredTools @('cmake', 'ninja') -FailOnMissingRequiredTools
  } | Out-Null

  if (-not $SkipFormat) {
    Invoke-BuildStep -Context $context -StepName 'Python tooling + cmake-format' -Critical -Script {
      Invoke-CmakeFormatStep -Context $context -WorkspacePath $workspacePath
    } | Out-Null
  } else {
    Write-BuildLog -Context $context -Message 'Skipping cmake-format step (-SkipFormat).'
  }

  if (-not $SkipFormat) {
    Invoke-BuildStep -Context $context -StepName 'clang-format (C/C++)' -Critical -Script {
      Invoke-ClangFormatStep -Context $context -WorkspacePath $workspacePath
    } | Out-Null
  }

  # Only build stages explicitly requested via -Configurations. If no
  # configurations were provided, we don't run any build stages.
  $runStages = $script:Configurations

  # Prepare fast-build artifact sync parameters. If the config contains
  # Build.FastBuildDir, use it as the remote cache root. The expectation is
  # that the FastBuildDir points at a host-accessible path that already
  # mirrors the workspace layout (i.e. contains Src/ and build directories).
  $fastBuildDir = Get-OrDefault $null (Get-ConfigValue -Config $config -Path 'Build.FastBuildDir')
  $fastCacheEnabled = -not [string]::IsNullOrWhiteSpace($fastBuildDir)

  if ($fastCacheEnabled) {
    Invoke-BuildStep -Context $context -StepName 'Sync artifacts (pull before build)' -Script {
      # Attempt to pull previously-built artifacts into the workspace build
      # directories. Use the ContainerHub helper which wraps robocopy and
      # supports exclude patterns for common build cache files.
      $source = $fastBuildDir
      $dest = $workspacePath
      Sync-BuildArtifacts -Context $context -Source $source -Destination $dest -ExcludeCommonRustAndCppCache
    } | Out-Null
  }

  if ($runStages.Count -eq 0) {
    # Fail fast with a clear message so invocations that intended to build
    # don't silently skip the build stage. Keep the message helpful with
    # valid options and an example invocation.
    $validList = $stageDefinitions.Keys -join ', '
    $example = "-Configurations 'clangcl-debug,clangcl-profile,clangcl-release'"
    Write-BuildLog -Context $context -Message "No configurations specified. Build stages require the -Configurations parameter. Valid: $validList. Example: $example"
    throw "No configurations specified. Pass -Configurations to run build stages (e.g. $example)."
  }

  foreach ($stageName in $runStages) {
    $stageDef = $stageDefinitions[$stageName]
    $stageLabel = "Configure/Build: $($stageDef.Preset)"

    Invoke-BuildStep -Context $context -StepName $stageLabel -Critical -Script {
      if ($stageDef.RequiresClang) {
        $clangClCommand = Get-Command 'clang-cl.exe' -ErrorAction SilentlyContinue
        if (-not $clangClCommand) {
          throw 'clang-cl.exe not found on PATH. Install LLVM/Visual Studio Clang tools and run from a Developer PowerShell.'
        }

        Invoke-BuildExternal -Context $context -File $clangClCommand.Source -Parameters @('--version') | Out-Null
      }

      Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $stageDef.BuildPath -Preset $stageDef.Preset -Configuration $stageDef.Configuration -CleanBuildRoot
    } | Out-Null

    # If fast cache is enabled, push artifacts back after a successful build
    if ($fastCacheEnabled) {
      Invoke-BuildStep -Context $context -StepName "Sync artifacts (push after $stageName)" -Script {
        $source = $stageDef.BuildPath
        $destination = $fastBuildDir
        Sync-BuildArtifacts -Context $context -Source $source -Destination $destination -ExcludeCommonRustAndCppCache
      } | Out-Null
    }

    if ($stageDef.ClangTidy -and -not $SkipTidy) {
      Invoke-BuildStep -Context $context -StepName 'clang-tidy --fix (Src)' -Script {
        Invoke-ClangTidyFixStep -Context $context -WorkspacePath $workspacePath -BuildRoot $stageDef.BuildPath
      } | Out-Null
    }

    if ($stageDef.Test) {
      # Determine runtime flavor in a way that works for both hashtables and
      # PSCustomObjects. Prefer an explicit RuntimeFlavor entry if present,
      # otherwise default to 'Clang'.
      $runtimeFlavor = 'Clang'
      if ($stageDef -is [System.Collections.IDictionary]) {
        if ($stageDef.Contains('RuntimeFlavor')) { $runtimeFlavor = $stageDef['RuntimeFlavor'] }
      } else {
        if ($stageDef.PSObject.Properties.Name -contains 'RuntimeFlavor') { $runtimeFlavor = $stageDef.RuntimeFlavor }
      }
      Invoke-BuildStep -Context $context -StepName "Test: $stageName (ctest + coverage export)" -Critical -Script {
        Invoke-CtestDiscoveredTests -Context $context -BuildRoot $stageDef.BuildPath -Configuration $stageDef.Configuration -RuntimeFlavor $runtimeFlavor

        if ($stageDef.Coverage) {
          $compileTestExe = Resolve-TestExecutable -BuildRoot $stageDef.BuildPath -ExecutableName 'compileTestSuite.exe'
          if (-not $compileTestExe) {
            Write-BuildLogWarning -Context $context -Message "compileTestSuite.exe not found under '$($stageDef.BuildPath)'. Skipping coverage export."
            return
          }

          $profrawPath = Join-Path $stageDef.BuildPath 'Test\compile\default.profraw'
          if (Test-Path $profrawPath) {
            Remove-Item -Path $profrawPath -Force -ErrorAction SilentlyContinue
          }

          $oldProfileFile = $env:LLVM_PROFILE_FILE
          $env:LLVM_PROFILE_FILE = $profrawPath
          try {
            $compileStarted = Invoke-ManualTestExecutable -Context $context -BuildRoot $stageDef.BuildPath -ExecutableName 'compileTestSuite.exe' -RuntimeFlavor 'Clang'
            if (-not $compileStarted) {
              return
            }
          } finally {
            if ($null -eq $oldProfileFile) {
              Remove-Item Env:LLVM_PROFILE_FILE -ErrorAction SilentlyContinue
            } else {
              $env:LLVM_PROFILE_FILE = $oldProfileFile
            }
          }

          if (-not (Test-Path $profrawPath)) {
            Write-BuildLogWarning -Context $context -Message "Coverage profile not found at $profrawPath. Skipping llvm-profdata/llvm-cov export."
            return
          }

          Invoke-BuildExternal -Context $context -File 'llvm-profdata.exe' -Parameters @(
            'merge', '-sparse', $profrawPath,
            '-o', (Join-Path $stageDef.BuildPath 'compileTestSuite.profdata')
          ) | Out-Null

          $coverageIgnoreRegex = '(^|[\\/])(_deps|Test)([\\/]|$)'

          Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
            'report', $compileTestExe,
            "-instr-profile=$(Join-Path $stageDef.BuildPath 'compileTestSuite.profdata')",
            "-ignore-filename-regex=$coverageIgnoreRegex"
          ) | Out-Null

          $coverageJsonPath = Join-Path $stageDef.BuildPath 'coverage.json'
          $instrProfileArg = "-instr-profile=$(Join-Path $stageDef.BuildPath 'compileTestSuite.profdata')"
          $ignoreArg = "-ignore-filename-regex=$coverageIgnoreRegex"
          Write-BuildLog -Context $context -Message "CMD: llvm-cov.exe export $compileTestExe -format=text $instrProfileArg $ignoreArg > $coverageJsonPath"

          $global:LASTEXITCODE = 0
          & 'llvm-cov.exe' export $compileTestExe '-format=text' $instrProfileArg $ignoreArg | Out-File -FilePath $coverageJsonPath -Encoding UTF8
          if ($LASTEXITCODE -ne 0) {
            throw "llvm-cov export failed with exit code $LASTEXITCODE"
          }

          Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
            'show', $compileTestExe,
            "-instr-profile=$(Join-Path $stageDef.BuildPath 'compileTestSuite.profdata')",
            "-ignore-filename-regex=$coverageIgnoreRegex"
          ) | Out-Null
        }
      } | Out-Null
    }

    if ($stageName -eq 'clangcl-debug') {
      Invoke-BuildOptional -Context $context -Name 'ClangCL-TSan (optional)' -Script {
        $clangClCommand = Get-Command 'clang-cl.exe' -ErrorAction SilentlyContinue
        if (-not $clangClCommand) {
          throw 'clang-cl.exe not found on PATH. Install LLVM/Visual Studio Clang tools and run from a Developer PowerShell.'
        }

        Invoke-BuildExternal -Context $context -File $clangClCommand.Source -Parameters @('--version') | Out-Null

        if (-not (Test-ClangClThreadSanitizerSupport -ClangClPath $clangClCommand.Source)) {
          throw 'clang-cl ThreadSanitizer is not supported for target x86_64-pc-windows-msvc in this toolchain. Skipping optional TSan build/test.'
        }

        Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $buildPathClangClTsan -Preset $presetClangClDebugTsan -Configuration 'Debug' -CleanBuildRoot

        Invoke-CtestDiscoveredTests -Context $context -BuildRoot $buildPathClangClTsan -Configuration 'Debug' -RuntimeFlavor 'Clang'
      }
    }

    if ($stageDef.Benchmark) {
      Invoke-BuildStep -Context $context -StepName 'Benchmarks' -Critical -Script {
        Push-Location $stageDef.BuildPath
        try {
          $benchmarkExe = Join-Path $stageDef.BuildPath 'perfTestSuite.exe'
          if (-not (Test-Path $benchmarkExe)) {
            $candidate = Get-ChildItem -Path $stageDef.BuildPath -Filter 'perfTestSuite.exe' -File -Recurse -ErrorAction SilentlyContinue |
              Select-Object -First 1
            if ($candidate) {
              $benchmarkExe = $candidate.FullName
            } else {
              Write-BuildLog -Context $context -Message 'Benchmark executable not found. Skipping benchmark run.'
              return
            }
          }

          Invoke-BuildExternal -Context $context -File $benchmarkExe -Parameters @(
            '--benchmark_out=results.json',
            '--benchmark_out_format=json'
          ) | Out-Null
        } finally {
          Pop-Location
        }
      } | Out-Null
    }

  if ($stageDef.Package) {
      Invoke-BuildStep -Context $context -StepName "Release build/package: $($stageDef.Preset)" -Critical -Script {
        Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
          '--build', $stageDef.BuildPath,
          '--target', 'package',
          '--config', $stageDef.Configuration
        ) | Out-Null
      } | Out-Null

      if (-not $SkipMsix) {
        Invoke-BuildOptional -Context $context -Name 'MSIX packaging' -Script {
          $makeappxOverride = Get-OrDefault $MakeAppxOverride (Get-ConfigValue -Config $config -Path 'Msix.MakeAppxPath')
          $makeappxPath = Resolve-WindowsSdkToolPath -ToolName 'makeappx.exe' -OverridePath $makeappxOverride
          if (-not $makeappxPath) {
            throw 'makeappx.exe not found. Install Windows SDK or set MAKEAPPX_PATH (or Msix.MakeAppxPath in config). Skipping MSIX packaging.'
          }

          Write-BuildLog -Context $context -Message "Using makeappx: $makeappxPath"

          $msixName = Get-OrDefault $MsixPackageName (Get-OrDefault $env:PROJECT_NAME (Get-ConfigValue -Config $config -Path 'Msix.PackageNameDefault'))

          $msixPublisher = Get-OrDefault $MsixPublisher (Get-ConfigValue -Config $config -Path 'Msix.Publisher')
          $msixVersion = Get-OrDefault $MsixVersion (Get-ConfigValue -Config $config -Path 'Msix.Version')
          $msixMinVersion = Get-OrDefault $MsixMinVersion (Get-ConfigValue -Config $config -Path 'Msix.MinVersion')

          $msixStaging = Join-Path $stageDef.BuildPath 'msix-staging'
          $assetsDir = Join-Path $msixStaging 'Assets'
          if (Test-Path $msixStaging) {
            Remove-BuildRoot -Context $context -Path $msixStaging | Out-Null
          }

          Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
            '--install', $stageDef.BuildPath,
            '--config', $stageDef.Configuration,
            '--prefix', $msixStaging
          ) | Out-Null

          Resolve-DirectoryPath -Path $assetsDir | Out-Null

          $exeRelPath = "bin/$msixName.exe"
          $manifestPath = Join-Path $msixStaging 'AppxManifest.xml'
          $storeLogoRel = 'Assets/StoreLogo.png'
          $logo150Rel = 'Assets/Square150x150Logo.png'
          $logo44Rel = 'Assets/Square44x44Logo.png'

          $manifestTemplateRel = Get-OrDefault $MsixManifestTemplate (Get-ConfigValue -Config $config -Path 'Msix.ManifestTemplate')
          $manifestTemplatePath = if ([System.IO.Path]::IsPathRooted($manifestTemplateRel)) { $manifestTemplateRel } else { Join-Path $workspacePath $manifestTemplateRel }
          if (-not (Test-Path $manifestTemplatePath)) {
            throw "MSIX manifest template not found: $manifestTemplatePath"
          }

          $template = Get-Content -Path $manifestTemplatePath -Raw -Encoding UTF8
          $manifestXml = Expand-XmlTemplateTokens -Template $template -TokenMap @{
            '__MSIX_NAME__'      = $msixName
            '__MSIX_PUBLISHER__' = $msixPublisher
            '__MSIX_VERSION__'   = $msixVersion
            '__MSIX_MIN_VERSION__' = $msixMinVersion
            '__EXE_REL_PATH__'   = $exeRelPath
            '__STORE_LOGO_REL__' = $storeLogoRel
            '__LOGO150_REL__'    = $logo150Rel
            '__LOGO44_REL__'     = $logo44Rel
          }

          Set-Content -Path $manifestPath -Value $manifestXml -Encoding UTF8

          New-TransparentPng -Path (Join-Path $msixStaging 'Assets\StoreLogo.png') -Width 50 -Height 50
          New-TransparentPng -Path (Join-Path $msixStaging 'Assets\Square150x150Logo.png') -Width 150 -Height 150
          New-TransparentPng -Path (Join-Path $msixStaging 'Assets\Square44x44Logo.png') -Width 44 -Height 44

          if (-not (Test-Path (Join-Path $msixStaging $exeRelPath))) {
            throw "Expected executable not found in MSIX staging: $exeRelPath"
          }

          $msixOutPath = Join-Path $stageDef.BuildPath "$msixName.msix"
          Invoke-BuildExternal -Context $context -File $makeappxPath -Parameters @(
            'pack',
            '/d', $msixStaging,
            '/p', $msixOutPath,
            '/o'
          ) | Out-Null
        }
      } else {
        Write-BuildLog -Context $context -Message 'Skipping MSIX packaging step (-SkipMsix).'
      }
    }
  }

  Write-BuildLogSuccess -Context $context -Message '=== Windows container CI completed ==='
} finally {
  # Optionally remove transient artifacts produced by build/test/package steps.
  # This is intentionally opt-in because deleting outputs can be destructive.
  if ($CleanupAfter -and $context -and ($context.Results.Failed.Count -eq 0)) {
    Invoke-BuildStep -Context $context -StepName 'Cleanup outputs' -Script {
      foreach ($stageName in $runStages) {
        $stageDef = $stageDefinitions[$stageName]

        # Coverage artifacts
        $profrawPath = Join-Path $stageDef.BuildPath 'Test\compile\default.profraw'
        if (Test-Path $profrawPath) { Remove-Item -Path $profrawPath -Force -ErrorAction SilentlyContinue }

        $profdataPath = Join-Path $stageDef.BuildPath 'compileTestSuite.profdata'
        if (Test-Path $profdataPath) { Remove-Item -Path $profdataPath -Force -ErrorAction SilentlyContinue }

        $coverageJsonPath = Join-Path $stageDef.BuildPath 'coverage.json'
        if (Test-Path $coverageJsonPath) { Remove-Item -Path $coverageJsonPath -Force -ErrorAction SilentlyContinue }

        # MSIX staging and packages
        $msixStaging = Join-Path $stageDef.BuildPath 'msix-staging'
        if (Test-Path $msixStaging) { Remove-BuildRoot -Context $context -Path $msixStaging | Out-Null }
        Get-ChildItem -Path $stageDef.BuildPath -Filter '*.msix' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
      }
    } | Out-Null
  }

  Write-BuildSummary -Context $context
  Close-BuildLog -Context $context
}

if ($context.Results.Failed.Count -gt 0) {
  throw "Windows container CI completed with failures ($($context.Results.Failed.Count) steps failed)."
}
