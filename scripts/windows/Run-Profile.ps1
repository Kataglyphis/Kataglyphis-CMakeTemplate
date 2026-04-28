param(
    [switch]$SkipBenchmarks,
    [string]$BuildDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultBuildDir = Join-Path $repoRoot 'build-clangcl-profile'
$buildDir = if (-not [string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir } else { $defaultBuildDir }

if (-not (Test-Path $buildDir)) {
    throw "Profile build directory not found: $buildDir`nRun Build-Windows.ps1 -Configurations 'clangcl-profile' first."
}

$perfTestExe = Join-Path $buildDir 'perfTestSuite.exe'
if (-not (Test-Path $perfTestExe)) {
    $candidate = Get-ChildItem -Path $buildDir -Filter 'perfTestSuite.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($candidate) {
        $perfTestExe = $candidate.FullName
    } else {
        throw "perfTestSuite.exe not found in: $buildDir`nEnsure profile build completed successfully."
    }
}

Write-Host "=== Running Benchmarks (clangcl-profile) ===" -ForegroundColor Cyan
Write-Host "Build directory: $buildDir"
Write-Host ""

if (-not $SkipBenchmarks) {
    Write-Host "--- Running perfTestSuite ---" -ForegroundColor Yellow
    & $perfTestExe --benchmark_out=$buildDir\benchmark_results.json --benchmark_out_format=json
    if ($LASTEXITCODE -ne 0) {
        throw "perfTestSuite failed with exit code: $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "Benchmark results saved to: $buildDir\benchmark_results.json" -ForegroundColor Green
} else {
    Write-Host "Skipping benchmarks (-SkipBenchmarks)."
}

Write-Host ""
Write-Host "=== Profile benchmarks completed successfully ===" -ForegroundColor Green