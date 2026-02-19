$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-OrDefault([string]$Value, [string]$DefaultValue) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $DefaultValue }
  return $Value
}

$WorkspaceRoot = Get-OrDefault $env:GITHUB_WORKSPACE 'C:\workspace'
$BuildDir = Get-OrDefault $env:BUILD_DIR 'build'
$BuildReleaseDir = Get-OrDefault $env:BUILD_DIR_RELEASE 'build-release'
$ClangProfilePreset = Get-OrDefault $env:CLANG_PROFILE_PRESET 'x64-ClangCL-Windows-Profile'

$BuildPath = Join-Path $WorkspaceRoot $BuildDir
$BuildReleasePath = Join-Path $WorkspaceRoot $BuildReleaseDir
$LogDir = Join-Path $WorkspaceRoot 'logs'

$buildCommonModule = Join-Path $PSScriptRoot '..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsBuild.Common.psm1'
if (-not (Test-Path $buildCommonModule)) {
  throw "Required generic module not found: $buildCommonModule"
}

Import-Module $buildCommonModule -Force

$Context = New-BuildContext -Workspace $WorkspaceRoot -LogDir $LogDir -StopOnError
Open-BuildLog -Context $Context

try {
  Write-BuildLog -Context $Context -Message '=== Windows CI inside container ==='
  Write-BuildLog -Context $Context -Message "Workspace: $WorkspaceRoot"

  Invoke-BuildStep -Context $Context -StepName 'Tool versions' -Critical -Script {
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--version') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'ninja' -Parameters @('--version') | Out-Null
  }

  Invoke-BuildStep -Context $Context -StepName 'Configure/Build: x64-MSVC-Windows-Debug' -Critical -Script {
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('-B', $BuildPath, '--preset', 'x64-MSVC-Windows-Debug') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--build', $BuildPath, '--preset', 'x64-MSVC-Windows-Debug') | Out-Null
  }

  Invoke-BuildStep -Context $Context -StepName 'Test: MSVC' -Critical -Script {
    Push-Location $BuildPath
    try {
      Invoke-BuildExternal -Context $Context -File 'ctest' -Parameters @('--output-on-failure') | Out-Null
    } finally {
      Pop-Location
    }
  }

  Invoke-BuildStep -Context $Context -StepName 'Configure/Build: x64-ClangCL-Windows-Debug' -Critical -Script {
    $removed = Remove-BuildRoot -Context $Context -Path $BuildPath
    if (-not $removed) {
      throw "Failed to clean build directory: $BuildPath"
    }

    Invoke-BuildExternal -Context $Context -File 'clang' -Parameters @('--version') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('-B', $BuildPath, '--preset', 'x64-ClangCL-Windows-Debug', '-Dmyproject_ENABLE_CPPCHECK=OFF') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--build', $BuildPath, '--preset', 'x64-ClangCL-Windows-Debug') | Out-Null
  }

  Invoke-BuildStep -Context $Context -StepName 'Test: ClangCL (incl. coverage export)' -Critical -Script {
    $profdataPath = Join-Path $BuildPath 'compileTestSuite.profdata'
    $coverageJsonPath = Join-Path $BuildPath 'coverage.json'

    Push-Location $BuildPath
    try {
      Invoke-BuildExternal -Context $Context -File 'ctest' -Parameters @('--output-on-failure') | Out-Null
      Invoke-BuildExternal -Context $Context -File 'llvm-profdata.exe' -Parameters @('merge', '-sparse', 'Test\compile\default.profraw', '-o', $profdataPath) | Out-Null
      Invoke-BuildExternal -Context $Context -File 'llvm-cov.exe' -Parameters @('report', 'compileTestSuite.exe', "-instr-profile=$profdataPath") | Out-Null
      Invoke-BuildExternal -Context $Context -File 'llvm-cov.exe' -Parameters @('export', 'compileTestSuite.exe', '-format=text', "-instr-profile=$profdataPath") | Out-File -FilePath $coverageJsonPath -Encoding UTF8
      Invoke-BuildExternal -Context $Context -File 'llvm-cov.exe' -Parameters @('show', 'compileTestSuite.exe', "-instr-profile=$profdataPath") | Out-Null
    } finally {
      Pop-Location
    }
  }

  Invoke-BuildStep -Context $Context -StepName "Configure/Build: $ClangProfilePreset" -Critical -Script {
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('-B', $BuildReleasePath, '--preset', $ClangProfilePreset, '-Dmyproject_ENABLE_CPPCHECK=OFF') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--build', $BuildReleasePath, '--preset', $ClangProfilePreset) | Out-Null
  }

  Invoke-BuildStep -Context $Context -StepName 'Benchmarks' -Critical -Script {
    Push-Location $BuildReleasePath
    try {
      Invoke-BuildExternal -Context $Context -File '.\perfTestSuite.exe' -Parameters @('--benchmark_out=results.json', '--benchmark_out_format=json') | Out-Null
    } finally {
      Pop-Location
    }
  }

  Invoke-BuildStep -Context $Context -StepName 'Release build/package: x64-ClangCL-Windows-Release' -Critical -Script {
    $removed = Remove-BuildRoot -Context $Context -Path $BuildReleasePath
    if (-not $removed) {
      throw "Failed to clean release build directory: $BuildReleasePath"
    }

    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('-B', $BuildReleasePath, '--preset', 'x64-ClangCL-Windows-Release', '-Dmyproject_ENABLE_CPPCHECK=OFF') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--build', $BuildReleasePath, '--preset', 'x64-ClangCL-Windows-Release') | Out-Null
    Invoke-BuildExternal -Context $Context -File 'cmake' -Parameters @('--build', $BuildReleasePath, '--preset', 'x64-ClangCL-Windows-Release', '--target', 'package') | Out-Null
  }

  Write-BuildLogSuccess -Context $Context -Message '=== Windows container CI completed ==='
} finally {
  Write-BuildSummary -Context $Context
  Close-BuildLog -Context $Context
}

if ($Context.Results.Failed.Count -gt 0) {
  throw "Windows build pipeline failed with $($Context.Results.Failed.Count) failed step(s)."
}
