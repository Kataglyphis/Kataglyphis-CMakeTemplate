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

function Escape-Xml([AllowNull()][string]$Value) {
  if ($null -eq $Value) { return '' }
  return [System.Security.SecurityElement]::Escape($Value)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$containerHubModulesRoot = Join-Path $repoRoot 'ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules'

$sharedModulePath = Join-Path $containerHubModulesRoot 'WindowsScripts.Shared.psm1'
$buildModulePath = Join-Path $containerHubModulesRoot 'WindowsBuild.Common.psm1'
$toolchainModulePath = Join-Path $containerHubModulesRoot 'WindowsToolchain.Common.psm1'

if (-not (Test-Path $sharedModulePath)) {
  throw "ContainerHub shared module not found: $sharedModulePath"
}
if (-not (Test-Path $buildModulePath)) {
  throw "ContainerHub build module not found: $buildModulePath"
}
if (-not (Test-Path $toolchainModulePath)) {
  throw "ContainerHub toolchain module not found: $toolchainModulePath"
}

Import-Module $buildModulePath -Force
Import-Module $toolchainModulePath -Force
Import-Module $sharedModulePath

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
$buildProfileDir = Get-OrDefault $env:BUILD_DIR_PROFILE (Get-ConfigValue -Config $config -Path 'Build.BuildDirProfile')
$buildReleaseDir = Get-OrDefault $env:BUILD_DIR_RELEASE (Get-ConfigValue -Config $config -Path 'Build.BuildDirRelease')

$presetMsvcDebug = Get-OrDefault $env:PRESET_MSVC_DEBUG (Get-ConfigValue -Config $config -Path 'Build.Presets.MsvcDebug')
$presetClangClDebug = Get-OrDefault $env:PRESET_CLANGCL_DEBUG (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClDebug')
$clangProfilePreset = Get-OrDefault $env:CLANG_PROFILE_PRESET (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClProfile')
$presetClangClRelease = Get-OrDefault $env:PRESET_CLANGCL_RELEASE (Get-ConfigValue -Config $config -Path 'Build.Presets.ClangClRelease')

$disableCppcheckDefine = Get-OrDefault $env:DISABLE_CPPCHECK_DEFINE (Get-ConfigValue -Config $config -Path 'Build.DisableCppcheckDefine')

$workspacePath = Resolve-WorkspacePath -Path $workspaceRoot
$buildPathMsvc = Join-Path $workspacePath $buildDirMsvc
$buildPathClangCl = Join-Path $workspacePath $buildDirClangCl
$buildProfilePath = Join-Path $workspacePath $buildProfileDir
$buildReleasePath = Join-Path $workspacePath $buildReleaseDir

if ($buildPathClangCl -eq $buildPathMsvc) {
  $buildPathClangCl = Join-Path $workspacePath ("${buildDirMsvc}-clangcl")
}
if ($buildProfilePath -eq $buildReleasePath) {
  $buildProfilePath = Join-Path $workspacePath ("${buildReleaseDir}-profile")
}

$context = New-BuildContext -Workspace $workspacePath -LogDir $logDir -StopOnError

function Try-RemoveBuildRoot([pscustomobject]$ctx, [string]$path, [string]$label) {
  if (Remove-BuildRoot -Context $ctx -Path $path) {
    return
  }

  Write-BuildLogWarning -Context $ctx -Message "Could not remove build directory ($label): $path. Continuing with in-place configure/build."
}

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

  Invoke-BuildStep -Context $context -StepName 'Configure/Build: x64-MSVC-Windows-Debug' -Critical -Script {
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @('-B', $buildPathMsvc, '--preset', $presetMsvcDebug) | Out-Null
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @('--build', $buildPathMsvc, '--config', 'Debug') | Out-Null
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Test: MSVC' -Critical -Script {
    Push-Location $buildPathMsvc
    try {
      Invoke-BuildExternal -Context $context -File 'ctest' -Parameters @('--output-on-failure') | Out-Null
    } finally {
      Pop-Location
    }
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Configure/Build: x64-ClangCL-Windows-Debug' -Critical -Script {
    Try-RemoveBuildRoot -ctx $context -path $buildPathClangCl -label $presetClangClDebug
    Invoke-BuildExternal -Context $context -File 'clang' -Parameters @('--version') | Out-Null

    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
      '-B', $buildPathClangCl,
      '--preset', $presetClangClDebug,
      "-D$disableCppcheckDefine"
    ) | Out-Null
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @('--build', $buildPathClangCl, '--config', 'Debug') | Out-Null
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Test: ClangCL (incl. coverage export)' -Critical -Script {
    Push-Location $buildPathClangCl
    try {
      Invoke-BuildExternal -Context $context -File 'ctest' -Parameters @('--output-on-failure') | Out-Null

      Invoke-BuildExternal -Context $context -File 'llvm-profdata.exe' -Parameters @(
        'merge', '-sparse', 'Test\compile\default.profraw',
        '-o', (Join-Path $buildPathClangCl 'compileTestSuite.profdata')
      ) | Out-Null

      Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
        'report', 'compileTestSuite.exe',
        "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')"
      ) | Out-Null

      $coverageJsonPath = Join-Path $buildPathClangCl 'coverage.json'
      $instrProfileArg = "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')"
      Write-BuildLog -Context $context -Message "CMD: llvm-cov.exe export compileTestSuite.exe -format=text $instrProfileArg > $coverageJsonPath"

      $global:LASTEXITCODE = 0
      & 'llvm-cov.exe' export 'compileTestSuite.exe' '-format=text' $instrProfileArg | Out-File -FilePath $coverageJsonPath -Encoding UTF8
      if ($LASTEXITCODE -ne 0) {
        throw "llvm-cov export failed with exit code $LASTEXITCODE"
      }

      Invoke-BuildExternal -Context $context -File 'llvm-cov.exe' -Parameters @(
        'show', 'compileTestSuite.exe',
        "-instr-profile=$(Join-Path $buildPathClangCl 'compileTestSuite.profdata')"
      ) | Out-Null
    } finally {
      Pop-Location
    }
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName "Configure/Build: $clangProfilePreset" -Critical -Script {
    Try-RemoveBuildRoot -ctx $context -path $buildProfilePath -label $clangProfilePreset
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
      '-B', $buildProfilePath,
      '--preset', $clangProfilePreset,
      "-D$disableCppcheckDefine"
    ) | Out-Null
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @('--build', $buildProfilePath) | Out-Null
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Benchmarks' -Critical -Script {
    Push-Location $buildProfilePath
    try {
      Invoke-BuildExternal -Context $context -File (Join-Path $buildProfilePath 'perfTestSuite.exe') -Parameters @(
        '--benchmark_out=results.json',
        '--benchmark_out_format=json'
      ) | Out-Null
    } finally {
      Pop-Location
    }
  } | Out-Null

  Invoke-BuildStep -Context $context -StepName 'Release build/package: x64-ClangCL-Windows-Release' -Critical -Script {
    Try-RemoveBuildRoot -ctx $context -path $buildReleasePath -label $presetClangClRelease

    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
      '-B', $buildReleasePath,
      '--preset', $presetClangClRelease,
      "-D$disableCppcheckDefine"
    ) | Out-Null
    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @('--build', $buildReleasePath) | Out-Null

    Invoke-BuildExternal -Context $context -File 'cmake' -Parameters @(
      '--build', $buildReleasePath,
      '--target', 'package'
    ) | Out-Null
  } | Out-Null

  Invoke-BuildOptional -Context $context -Name 'MSIX packaging' -Script {
    $makeappx = Get-Command 'makeappx.exe' -ErrorAction SilentlyContinue
    if (-not $makeappx) {
      throw 'makeappx.exe not found on PATH (Windows SDK). Skipping MSIX packaging.'
    }

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

    $exeRelPath = "bin\\$msixName.exe"
    $manifestPath = Join-Path $msixStaging 'AppxManifest.xml'
    $storeLogoRel = 'Assets\\StoreLogo.png'
    $logo150Rel = 'Assets\\Square150x150Logo.png'
    $logo44Rel = 'Assets\\Square44x44Logo.png'

    $manifestTemplateRel = Get-OrDefault $env:MSIX_MANIFEST_TEMPLATE (Get-ConfigValue -Config $config -Path 'Msix.ManifestTemplate')
    $manifestTemplatePath = if ([System.IO.Path]::IsPathRooted($manifestTemplateRel)) { $manifestTemplateRel } else { Join-Path $workspacePath $manifestTemplateRel }
    if (-not (Test-Path $manifestTemplatePath)) {
      throw "MSIX manifest template not found: $manifestTemplatePath"
    }

    $template = Get-Content -Path $manifestTemplatePath -Raw -Encoding UTF8
    $manifestXml = $template
    $manifestXml = $manifestXml -replace '__MSIX_NAME__', (Escape-Xml $msixName)
    $manifestXml = $manifestXml -replace '__MSIX_PUBLISHER__', (Escape-Xml $msixPublisher)
    $manifestXml = $manifestXml -replace '__MSIX_VERSION__', (Escape-Xml $msixVersion)
    $manifestXml = $manifestXml -replace '__MSIX_MIN_VERSION__', (Escape-Xml $msixMinVersion)
    $manifestXml = $manifestXml -replace '__EXE_REL_PATH__', (Escape-Xml $exeRelPath)
    $manifestXml = $manifestXml -replace '__STORE_LOGO_REL__', (Escape-Xml $storeLogoRel)
    $manifestXml = $manifestXml -replace '__LOGO150_REL__', (Escape-Xml $logo150Rel)
    $manifestXml = $manifestXml -replace '__LOGO44_REL__', (Escape-Xml $logo44Rel)

    Set-Content -Path $manifestPath -Value $manifestXml -Encoding UTF8

    $createPng = {
      param([string]$Path, [int]$Width, [int]$Height)
      Add-Type -AssemblyName System.Drawing
      $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
      } finally {
        $gfx.Dispose()
        $bmp.Dispose()
      }
    }

    & $createPng (Join-Path $msixStaging 'Assets\StoreLogo.png') 50 50
    & $createPng (Join-Path $msixStaging 'Assets\Square150x150Logo.png') 150 150
    & $createPng (Join-Path $msixStaging 'Assets\Square44x44Logo.png') 44 44

    if (-not (Test-Path (Join-Path $msixStaging $exeRelPath))) {
      throw "Expected executable not found in MSIX staging: $exeRelPath"
    }

    $msixOutPath = Join-Path $buildReleasePath "$msixName.msix"
    Invoke-BuildExternal -Context $context -File 'makeappx.exe' -Parameters @(
      'pack',
      '/d', $msixStaging,
      '/p', $msixOutPath,
      '/o'
    ) | Out-Null
  }

  Write-BuildLogSuccess -Context $context -Message '=== Windows container CI completed ==='
} finally {
  Write-BuildSummary -Context $context
  Close-BuildLog -Context $context
}

if ($context.Results.Failed.Count -gt 0) {
  throw "Windows container CI completed with failures ($($context.Results.Failed.Count) steps failed)."
}
