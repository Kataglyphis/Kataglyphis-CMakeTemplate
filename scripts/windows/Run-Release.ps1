param(
    [string]$BuildDir = '',
    [string]$ExecutableName = '',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultBuildDir = Join-Path $repoRoot 'build-clangcl-release'
$buildDir = if (-not [string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir } else { $defaultBuildDir }

if (-not (Test-Path $buildDir)) {
    throw "Release build directory not found: $buildDir`nRun Build-Windows.ps1 -Configurations 'clangcl-release' first."
}

$exeName = if (-not [string]::IsNullOrWhiteSpace($ExecutableName)) { $ExecutableName } else { 'KataglyphisCppProject.exe' }
$exePath = Join-Path $buildDir $exeName

if (-not (Test-Path $exePath)) {
    throw "Executable not found at: $exePath`nEnsure release build completed successfully."
}

Write-Host "=== Running Release Build ===" -ForegroundColor Cyan
Write-Host "Build directory: $buildDir"
Write-Host "Executable: $exePath"
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf: Would execute '$exePath' with arguments: $($args -join ' ')" -ForegroundColor Yellow
    return
}

& $exePath $args

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Executable failed with exit code: $exitCode"
}

Write-Host ""
Write-Host "=== Release executable completed successfully ===" -ForegroundColor Green