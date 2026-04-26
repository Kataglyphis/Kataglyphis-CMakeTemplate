# Run a cargo build for the in-tree rusty_code crate with the same
# environment variables that CMake/Corrosion uses when invoking Cargo.
# This helper is used for debugging Rust build failures inside the
# Windows build container. It is intentionally non-destructive.

param()

$ErrorActionPreference = 'Stop'

# Resolve the repository root relative to this script (scripts/windows)
$scriptDir = (Resolve-Path $PSScriptRoot).Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')

Write-Host "Repository root: $repoRoot"

$crateDir = Join-Path $repoRoot 'Src\rusty_code'
if (-not (Test-Path $crateDir)) {
  Write-Error "rusty_code crate not found at: $crateDir"
  exit 2
}

Set-Location -Path $crateDir

Write-Host "Working directory: $(Get-Location)"

# Mirror the environment that CMake used when it invoked Cargo via Corrosion.
[System.Environment]::SetEnvironmentVariable('CXXFLAGS', '/EHsc /MD /D_ITERATOR_DEBUG_LEVEL=0', 'Process')
[System.Environment]::SetEnvironmentVariable('CFLAGS', '/MD', 'Process')
[System.Environment]::SetEnvironmentVariable('SCCACHE_DISABLE', '1', 'Process')
[System.Environment]::SetEnvironmentVariable('RUST_BACKTRACE', '1', 'Process')
[System.Environment]::SetEnvironmentVariable('CARGO_TERM_VERBOSE', 'true', 'Process')
[System.Environment]::SetEnvironmentVariable('RUST_LOG', 'debug', 'Process')
[System.Environment]::SetEnvironmentVariable('CARGO_TERM_COLOR', 'never', 'Process')
[System.Environment]::SetEnvironmentVariable('CRATE_CC_NO_DEFAULTS', '1', 'Process')

# Prefer clang-cl as used by the Clang/MSVC flow. If absolute path is
# available in the environment use it (CMake usually forwards the full path).
if ($env:CLANG_CL_PATH) {
  [System.Environment]::SetEnvironmentVariable('CC_x86_64-pc-windows-msvc', $env:CLANG_CL_PATH, 'Process')
  [System.Environment]::SetEnvironmentVariable('CXX_x86_64-pc-windows-msvc', $env:CLANG_CL_PATH, 'Process')
} else {
  [System.Environment]::SetEnvironmentVariable('CC_x86_64-pc-windows-msvc', 'clang-cl', 'Process')
  [System.Environment]::SetEnvironmentVariable('CXX_x86_64-pc-windows-msvc', 'clang-cl', 'Process')
}

Write-Host "Environment preview: CC=$([System.Environment]::GetEnvironmentVariable('CC_x86_64-pc-windows-msvc','Process')) CXX=$([System.Environment]::GetEnvironmentVariable('CXX_x86_64-pc-windows-msvc','Process'))"

# Locate cargo executable
try {
  $gc = Get-Command cargo -ErrorAction Stop
  $cargoCmd = $gc.Source
} catch {
  $candidates = @(
    "$env:USERPROFILE\.cargo\bin\cargo.exe",
    "$env:USERPROFILE\scoop\persist\rustup\.cargo\bin\cargo.exe",
    "C:\Users\ContainerAdministrator\scoop\persist\rustup\.cargo\bin\cargo.exe"
  )
  foreach ($cand in $candidates) {
    if (Test-Path $cand) { $cargoCmd = $cand; break }
  }
}

if (-not $cargoCmd) {
  Write-Error "cargo not found on PATH and not found in candidate locations. Aborting."
  exit 2
}

Write-Host "Using cargo: $cargoCmd"
Write-Host "Invoking: cargo build --verbose"
& "$cargoCmd" build --verbose
$rc = $LASTEXITCODE
Write-Host "cargo exit code: $rc"
exit $rc
