$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-OrDefault([string]$Value, [string]$DefaultValue) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $DefaultValue }
  return $Value
}

$WorkspaceRoot = Get-OrDefault $env:GITHUB_WORKSPACE 'C:\workspace'
$BuildDir = Get-OrDefault $env:BUILD_DIR 'build'
$BuildReleaseDir = Get-OrDefault $env:BUILD_DIR_RELEASE 'build_release'
$ClangProfilePreset = Get-OrDefault $env:CLANG_PROFILE_PRESET 'x64-ClangCL-Windows-Profile'

Write-Host "=== Windows CI inside container ==="
Write-Host "Workspace: $WorkspaceRoot"

Write-Host "Tool versions:"
cmake --version
ninja --version

# MSVC Debug
Write-Host "=== Configure/Build: x64-MSVC-Windows-Debug ==="
cmake -B "$WorkspaceRoot\$BuildDir" --preset x64-MSVC-Windows-Debug
cmake --build "$WorkspaceRoot\$BuildDir" --preset x64-MSVC-Windows-Debug

Write-Host "=== Test: MSVC ==="
Push-Location "$WorkspaceRoot\$BuildDir"
ctest --output-on-failure
Pop-Location

# ClangCL Debug
Write-Host "=== Configure/Build: x64-ClangCL-Windows-Debug ==="
if (Test-Path "$WorkspaceRoot\$BuildDir") {
  Remove-Item -Path "$WorkspaceRoot\$BuildDir" -Recurse -Force
}

clang --version

cmake -B "$WorkspaceRoot\$BuildDir" --preset x64-ClangCL-Windows-Debug -Dmyproject_ENABLE_CPPCHECK=OFF
cmake --build "$WorkspaceRoot\$BuildDir" --preset x64-ClangCL-Windows-Debug

Write-Host "=== Test: ClangCL (incl. coverage export) ==="
Push-Location "$WorkspaceRoot\$BuildDir"
ctest --output-on-failure

& "llvm-profdata.exe" merge -sparse "Test\compile\default.profraw" -o "$WorkspaceRoot\$BuildDir\compileTestSuite.profdata"
& "llvm-cov.exe" report "compileTestSuite.exe" -instr-profile="$WorkspaceRoot\$BuildDir\compileTestSuite.profdata"
& "llvm-cov.exe" export "compileTestSuite.exe" -format=text -instr-profile="$WorkspaceRoot\$BuildDir\compileTestSuite.profdata" | Out-File -FilePath "coverage.json" -Encoding UTF8
& "llvm-cov.exe" show "compileTestSuite.exe" -instr-profile="$WorkspaceRoot\$BuildDir\compileTestSuite.profdata"
Pop-Location

# Profiling preset (clang-cl)
Write-Host "=== Configure/Build: $ClangProfilePreset ==="
cmake -B "$WorkspaceRoot\$BuildReleaseDir" --preset "$ClangProfilePreset" -Dmyproject_ENABLE_CPPCHECK=OFF
cmake --build "$WorkspaceRoot\$BuildReleaseDir" --preset "$ClangProfilePreset"

Write-Host "=== Benchmarks ==="
Push-Location "$WorkspaceRoot\$BuildReleaseDir"
.\perfTestSuite.exe --benchmark_out=results.json --benchmark_out_format=json
Pop-Location

Write-Host "=== Release build/package: x64-ClangCL-Windows-Release ==="
if (Test-Path "$WorkspaceRoot\$BuildReleaseDir") {
  Remove-Item -Path "$WorkspaceRoot\$BuildReleaseDir" -Recurse -Force
}

cmake -B "$WorkspaceRoot\$BuildReleaseDir" --preset x64-ClangCL-Windows-Release -Dmyproject_ENABLE_CPPCHECK=OFF
cmake --build "$WorkspaceRoot\$BuildReleaseDir" --preset x64-ClangCL-Windows-Release
cmake --build "$WorkspaceRoot\$BuildReleaseDir" --preset x64-ClangCL-Windows-Release --target package

Write-Host "=== Windows container CI completed ==="
