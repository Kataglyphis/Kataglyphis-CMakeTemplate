param(
  [switch]$SkipFormat,
  [switch]$SkipTidy,
  [switch]$SkipMsix
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-OrDefault([string]$Value, [string]$DefaultValue) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $DefaultValue }
  return $Value
}

function Get-ConfigValue {
  param(
    [Parameter(Mandatory)]
    $Config,
    [Parameter(Mandatory)]
    [string]$Path
  )

  $cursor = $Config
  foreach ($segment in ($Path -split '\.')) {
    if ($null -eq $cursor) { return $null }
    try {
      $cursor = $cursor[$segment]
    } catch {
      return $null
    }
  }

  return $cursor
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$containerHubModulesRoot = Join-Path $repoRoot 'ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules'

$sharedModulePath = Join-Path $containerHubModulesRoot 'WindowsScripts.Shared.psm1'
$buildModulePath = Join-Path $containerHubModulesRoot 'WindowsBuild.Common.psm1'
$toolchainModulePath = Join-Path $containerHubModulesRoot 'WindowsToolchain.Common.psm1'
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
if (-not (Test-Path $localCmakeModulePath)) {
  throw "Local CMake module not found: $localCmakeModulePath"
}
if (-not (Test-Path $localFormattingModulePath)) {
  throw "Local formatting module not found: $localFormattingModulePath"
}
if (-not (Test-Path $localTestingModulePath)) {
  throw "Local testing module not found: $localTestingModulePath"
}
if (-not (Test-Path $localPackagingModulePath)) {
  throw "Local packaging module not found: $localPackagingModulePath"
}

Import-Module $buildModulePath -Force
Import-Module $toolchainModulePath -Force
Import-Module $sharedModulePath
Import-Module $localCmakeModulePath -Force
Import-Module $localFormattingModulePath -Force
Import-Module $localTestingModulePath -Force
Import-Module $localPackagingModulePath -Force

$defaultConfigPath = Join-Path $PSScriptRoot 'Build-Windows.config.psd1'
$configPath = Get-OrDefault $env:BUILD_WINDOWS_CONFIG $defaultConfigPath
if (-not (Test-Path $configPath)) {
  throw "Build config not found: $configPath"
}

$config = Import-PowerShellDataFile -Path $configPath

$workspaceRootEnvVar = Get-OrDefault $env:WORKSPACE_ROOT_ENV (Get-ConfigValue -Config $config -Path 'Build.WorkspaceRootEnv')
$workspaceEnvItem = Get-Item -Path "Env:$workspaceRootEnvVar" -ErrorAction SilentlyContinue
$workspaceRootFromEnv = if ($null -ne $workspaceEnvItem) { $workspaceEnvItem.Value } else { $null }
$workspaceRoot = Get-OrDefault $workspaceRootFromEnv $repoRoot
$logDir = Get-OrDefault $env:BUILD_LOG_DIR (Get-ConfigValue -Config $config -Path 'Build.LogDir')

$buildDirMsvc = Get-OrDefault $env:BUILD_DIR_MSVC (Get-ConfigValue -Config $config -Path 'Build.BuildDirMsvc')
$buildDirClangCl = Get-OrDefault $env:BUILD_DIR_CLANGCL (Get-ConfigValue -Config $config -Path 'Build.BuildDirClangCl')
$buildDirClangClTsan = Get-OrDefault $env:BUILD_DIR_CLANGCL_TSAN (Get-ConfigValue -Config $config -Path 'Build.BuildDirClangClTsan')
$buildProfileDir = Get-OrDefault $env:BUILD_DIR_PROFILE (Get-ConfigValue -Config $config -Path 'Build.BuildDirProfile')
$buildReleaseDir = Get-OrDefault $env:BUILD_DIR_RELEASE (Get-ConfigValue -Config $config -Path 'Build.BuildDirRelease')

$presetMsvcDebug = Get-OrDefault $env:PRESET_MSVC_DEBUG (Get-ConfigValue -Config $config -Path 'Build.Presets.MsvcDebug')
$presetClangClDebug = Get-OrDefault $env:PRESET_CLANGCL_DEBUG (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClDebug')
$presetClangClDebugTsan = Get-OrDefault $env:PRESET_CLANGCL_DEBUG_TSAN (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClDebugTsan')
$clangProfilePreset = Get-OrDefault $env:CLANG_PROFILE_PRESET (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClProfile')
$presetClangClRelease = Get-OrDefault $env:PRESET_CLANGCL_RELEASE (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClRelease')

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

function Invoke-ClangTidyFixStep {
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Context,
    [Parameter(Mandatory)]
    [string]$WorkspacePath,
    [Parameter(Mandatory)]
    [string]$BuildRoot
  )

  $clangTidyCommand = Get-Command 'clang-tidy' -ErrorAction SilentlyContinue
  if (-not $clangTidyCommand) {
    throw 'clang-tidy not found on PATH.'
  }

  $compileDb = Join-Path $BuildRoot 'compile_commands.json'
  if (-not (Test-Path $compileDb)) {
    throw "compile_commands.json not found at: $compileDb"
  }

  $srcDir = Join-Path $WorkspacePath 'Src'
  $tidyFiles = @(Get-ChildItem -Path $srcDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.cpp', '.cc', '.cxx') } |
    Select-Object -ExpandProperty FullName)

  if ($tidyFiles.Count -eq 0) {
    Write-BuildLog -Context $Context -Message 'No C/C++ source files found under Src for clang-tidy.'
    return
  }

  foreach ($tidyFile in $tidyFiles) {
    Invoke-BuildExternal -Context $Context -File $clangTidyCommand.Source -Parameters @(
      '-p', $BuildRoot,
      # include-cleaner can incorrectly add textual includes for C++ module imports.
      '--checks=-misc-include-cleaner',
      '--fix',
      '--fix-errors',
      $tidyFile
    ) | Out-Null
  }
}

$context = New-BuildContext -Workspace $workspacePath -LogDir $logDir -StopOnError

try {
  Open-BuildLog -Context $context

  Write-BuildLog -Context $context -Message "=== Windows CI inside container ==="
  Write-BuildLog -Context $context -Message "Workspace: $workspacePath"

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

  Invoke-BuildStep -Context $context -StepName 'Configure/Build: x64-MSVC-Windows-Debug' -Critical -Script {
    Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $buildPathMsvc -Preset $presetMsvcDebug -Configuration 'Debug'
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Test: MSVC' -Critical -Script {
    Invoke-CtestDiscoveredTests -Context $context -BuildRoot $buildPathMsvc -Configuration 'Debug' -RuntimeFlavor 'Msvc'
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Configure/Build: x64-ClangCL-Windows-Debug' -Critical -Script {
    $clangClCommand = Get-Command 'clang-cl.exe' -ErrorAction SilentlyContinue
    if (-not $clangClCommand) {
      throw 'clang-cl.exe not found on PATH. Install LLVM/Visual Studio Clang tools and run from a Developer PowerShell.'
    }

    Invoke-BuildExternal -Context $context -File $clangClCommand.Source -Parameters @('--version') | Out-Null

    Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $buildPathClangCl -Preset $presetClangClDebug -Configuration 'Debug' -CleanBuildRoot
  } | Out-Null

  if (-not $SkipTidy) {
    Invoke-BuildStep -Context $context -StepName 'clang-tidy --fix (Src)' -Script {
      Invoke-ClangTidyFixStep -Context $context -WorkspacePath $workspacePath -BuildRoot $buildPathClangCl
    } | Out-Null
  } else {
    Write-BuildLog -Context $context -Message 'Skipping clang-tidy step (-SkipTidy).'
  }

  Invoke-BuildStep -Context $context -StepName 'Test: ClangCL (ctest + coverage export)' -Critical -Script {
    Invoke-CtestDiscoveredTests -Context $context -BuildRoot $buildPathClangCl -Configuration 'Debug' -RuntimeFlavor 'Clang'

    $compileTestExe = Resolve-TestExecutable -BuildRoot $buildPathClangCl -ExecutableName 'compileTestSuite.exe'
    if (-not $compileTestExe) {
      Write-BuildLogWarning -Context $context -Message "compileTestSuite.exe not found under '$buildPathClangCl'. Skipping coverage export."
      return
    }

    $profrawPath = Join-Path $buildPathClangCl 'Test\compile\default.profraw'
    if (Test-Path $profrawPath) {
      Remove-Item -Path $profrawPath -Force -ErrorAction SilentlyContinue
    }

    $oldProfileFile = $env:LLVM_PROFILE_FILE
    $env:LLVM_PROFILE_FILE = $profrawPath
    try {
      $compileStarted = Invoke-ManualTestExecutable -Context $context -BuildRoot $buildPathClangCl -ExecutableName 'compileTestSuite.exe' -RuntimeFlavor 'Clang'
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
      '-o', (Join-Path $buildPathClangCl 'compileTestSuite.profdata')
    ) | Out-Null

    # Keep project coverage focused on production code by excluding tests and vendored deps.
    $coverageIgnoreRegex = '(^|[\\/])(_deps|Test)([\\/]|$)'

    Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
      'report', $compileTestExe,
      "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')",
      "-ignore-filename-regex=$coverageIgnoreRegex"
    ) | Out-Null

    $coverageJsonPath = Join-Path $buildPathClangCl 'coverage.json'
    $instrProfileArg = "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')"
    $ignoreArg = "-ignore-filename-regex=$coverageIgnoreRegex"
    Write-BuildLog -Context $context -Message "CMD: llvm-cov.exe export $compileTestExe -format=text $instrProfileArg $ignoreArg > $coverageJsonPath"

    $global:LASTEXITCODE = 0
    & 'llvm-cov.exe' export $compileTestExe '-format=text' $instrProfileArg $ignoreArg | Out-File -FilePath $coverageJsonPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
      throw "llvm-cov export failed with exit code $LASTEXITCODE"
    }

    Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
      'show', $compileTestExe,
      "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')",
      "-ignore-filename-regex=$coverageIgnoreRegex"
    ) | Out-Null
  } | Out-Null

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

  Invoke-BuildStep -Context $context -StepName "Configure/Build: $clangProfilePreset" -Critical -Script {
    Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $buildProfilePath -Preset $clangProfilePreset -Configuration 'RelWithDebInfo' -CleanBuildRoot
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Benchmarks' -Critical -Script {
    Push-Location $buildProfilePath
    try {
      $benchmarkExe = Join-Path $buildProfilePath 'perfTestSuite.exe'
      if (-not (Test-Path $benchmarkExe)) {
        $candidate = Get-ChildItem -Path $buildProfilePath -Filter 'perfTestSuite.exe' -File -Recurse -ErrorAction SilentlyContinue |
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

  Invoke-BuildStep -Context $context -StepName 'Release build/package: x64-ClangCL-Windows-Release' -Critical -Script {
    Invoke-CmakeConfigureAndBuild -Context $context -BuildPath $buildReleasePath -Preset $presetClangClRelease -Configuration 'Release' -CleanBuildRoot

    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
      '--build', $buildReleasePath,
      '--target', 'package',
      '--config', 'Release'
    ) | Out-Null
  } | Out-Null

  if (-not $SkipMsix) {
    Invoke-BuildOptional -Context $context -Name 'MSIX packaging' -Script {
      $makeappxOverride = Get-OrDefault $env:MAKEAPPX_PATH (Get-ConfigValue -Config $config -Path 'Msix.MakeAppxPath')
      $makeappxPath = Resolve-WindowsSdkToolPath -ToolName 'makeappx.exe' -OverridePath $makeappxOverride
      if (-not $makeappxPath) {
        throw 'makeappx.exe not found. Install Windows SDK or set MAKEAPPX_PATH (or Msix.MakeAppxPath in config). Skipping MSIX packaging.'
      }

      Write-BuildLog -Context $context -Message "Using makeappx: $makeappxPath"

      $msixName = Get-OrDefault $env:MSIX_PACKAGE_NAME $env:PROJECT_NAME
      if ([string]::IsNullOrWhiteSpace($msixName)) {
        $msixName = Get-OrDefault (Get-ConfigValue -Config $config -Path 'Msix.PackageNameDefault') 'KataglyphisCppProject'
      }

      $msixPublisher = Get-OrDefault $env:MSIX_PUBLISHER (Get-ConfigValue -Config $config -Path 'Msix.Publisher')
      $msixVersion = Get-OrDefault $env:MSIX_VERSION (Get-ConfigValue -Config $config -Path 'Msix.Version')
      $msixMinVersion = Get-OrDefault $env:MSIX_MIN_VERSION (Get-ConfigValue -Config $config -Path 'Msix.MinVersion')

      $msixStaging = Join-Path $buildReleasePath 'msix-staging'
      $assetsDir = Join-Path $msixStaging 'Assets'
      if (Test-Path $msixStaging) {
        Remove-BuildRoot -Context $context -Path $msixStaging | Out-Null
      }

      Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
        '--install', $buildReleasePath,
        '--config', 'Release',
        '--prefix', $msixStaging
      ) | Out-Null

      Resolve-DirectoryPath -Path $assetsDir | Out-Null

      $exeRelPath = "bin/$msixName.exe"
      $manifestPath = Join-Path $msixStaging 'AppxManifest.xml'
      $storeLogoRel = 'Assets/StoreLogo.png'
      $logo150Rel = 'Assets/Square150x150Logo.png'
      $logo44Rel = 'Assets/Square44x44Logo.png'

      $manifestTemplateRel = Get-OrDefault $env:MSIX_MANIFEST_TEMPLATE (Get-ConfigValue -Config $config -Path 'Msix.ManifestTemplate')
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

      $msixOutPath = Join-Path $buildReleasePath "$msixName.msix"
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

  Write-BuildLogSuccess -Context $context -Message '=== Windows container CI completed ==='
} finally {
  Write-BuildSummary -Context $context
  Close-BuildLog -Context $context
}

if ($context.Results.Failed.Count -gt 0) {
  throw "Windows container CI completed with failures ($($context.Results.Failed.Count) steps failed)."
}
