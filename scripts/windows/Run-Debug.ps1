param(
    [switch]$SkipTests,
    [switch]$SkipFuzzTests,
    [string]$BuildDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultBuildDir = Join-Path $repoRoot 'build-clangcl-debug'
$buildDir = if (-not [string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir } else { $defaultBuildDir }

if (-not (Test-Path $buildDir)) {
    throw "Debug build directory not found: $buildDir`nRun Build-Windows.ps1 -Configurations 'clangcl-debug' first."
}

$compileTestExe = Join-Path $buildDir 'compileTestSuite.exe'
$commitTestExe = Join-Path $buildDir 'commitTestSuite.exe'
$fuzzTestExe = Join-Path $buildDir 'first_fuzz_test.exe'

if (-not (Test-Path $compileTestExe)) {
    throw "compileTestSuite.exe not found at: $compileTestExe`nEnsure debug build completed successfully."
}
if (-not (Test-Path $commitTestExe)) {
    throw "commitTestSuite.exe not found at: $commitTestExe`nEnsure debug build completed successfully."
}

Write-Host "=== Running Debug Tests (clangcl-debug) ===" -ForegroundColor Cyan
Write-Host "Build directory: $buildDir"
Write-Host ""

if (-not $SkipTests) {
    Write-Host "--- Running compileTestSuite ---" -ForegroundColor Yellow
    & $compileTestExe --gtest_output=xml:$buildDir\compile_test_results.xml
    if ($LASTEXITCODE -ne 0) {
        throw "compileTestSuite failed with exit code: $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "--- Running commitTestSuite ---" -ForegroundColor Yellow
    & $commitTestExe --gtest_output=xml:$buildDir\commit_test_results.xml
    if ($LASTEXITCODE -ne 0) {
        throw "commitTestSuite failed with exit code: $LASTEXITCODE"
    }
} else {
    Write-Host "Skipping tests (-SkipTests)."
}

if (-not $SkipFuzzTests) {
    if (Test-Path $fuzzTestExe) {
        Write-Host ""
        Write-Host "--- Running first_fuzz_test ---" -ForegroundColor Yellow
        & $fuzzTestExe --gtest_output=xml:$buildDir\fuzz_test_results.xml
        if ($LASTEXITCODE -ne 0) {
            throw "first_fuzz_test failed with exit code: $LASTEXITCODE"
        }
    } else {
        Write-Host ""
        Write-Host "--- Skipping fuzz tests (first_fuzz_test.exe not found) ---" -ForegroundColor Gray
    }
} else {
    Write-Host ""
    Write-Host "Skipping fuzz tests (-SkipFuzzTests)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Debug tests completed successfully ===" -ForegroundColor Green