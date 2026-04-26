# Debug helper: run the exact cargo rustc invocation used by CMake/Corrosion
# to reproduce failures that only occur when Cargo is invoked via CMake.

param()

$ErrorActionPreference = 'Stop'

# Repository root (scripts/windows is two levels under repo root)
$scriptDir = (Resolve-Path $PSScriptRoot).Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')

$crateDir = Join-Path $repoRoot 'Src\rusty_code'
if (-not (Test-Path $crateDir)) { Write-Error "rusty_code crate not found at: $crateDir"; exit 2 }

Set-Location -Path $crateDir

Write-Host "Working directory: $(Get-Location)"

# Mirror the environment that CMake set in the failing ninja command.
[System.Environment]::SetEnvironmentVariable('CXXFLAGS', '/EHsc /MD /D_ITERATOR_DEBUG_LEVEL=0', 'Process')
[System.Environment]::SetEnvironmentVariable('CFLAGS', '/MD', 'Process')
[System.Environment]::SetEnvironmentVariable('SCCACHE_DISABLE', '1', 'Process')
[System.Environment]::SetEnvironmentVariable('RUST_BACKTRACE', '1', 'Process')
[System.Environment]::SetEnvironmentVariable('CARGO_TERM_VERBOSE', 'true', 'Process')
[System.Environment]::SetEnvironmentVariable('RUST_LOG', 'debug', 'Process')
[System.Environment]::SetEnvironmentVariable('CARGO_TERM_COLOR', 'never', 'Process')
[System.Environment]::SetEnvironmentVariable('CRATE_CC_NO_DEFAULTS', '1', 'Process')

# Use the absolute clang-cl path observed in the container's build log
$clangClPath = 'C:/Users/ContainerAdministrator/scoop/apps/llvm/current/bin/clang-cl.exe'
[System.Environment]::SetEnvironmentVariable('CC_x86_64-pc-windows-msvc', $clangClPath, 'Process')
[System.Environment]::SetEnvironmentVariable('CXX_x86_64-pc-windows-msvc', $clangClPath, 'Process')

# Corrosion/CMake-specific envs
[System.Environment]::SetEnvironmentVariable('CORROSION_BUILD_DIR', 'C:/workspace/build-clangcl-debug/Src', 'Process')
[System.Environment]::SetEnvironmentVariable('CARGO_BUILD_RUSTC', 'C:/Users/ContainerAdministrator/scoop/persist/rustup/.rustup/toolchains/stable-x86_64-pc-windows-msvc/bin/rustc.exe', 'Process')

# Determine cargo executable
try { $gc = Get-Command cargo -ErrorAction Stop; $cargo = $gc.Source } catch { $cargo = 'C:/Users/ContainerAdministrator/scoop/persist/rustup/.cargo/bin/cargo.exe' }
Write-Host "Using cargo: $cargo"

$args = @('rustc', '--lib', '--target=x86_64-pc-windows-msvc', '--package', 'rusty_code', '--crate-type=staticlib', '--manifest-path', 'C:/workspace/Src/rusty_code/Cargo.toml', '--target-dir', 'C:/workspace/build-clangcl-debug/cargo/rusty_code_debug', '--profile=dev', '--verbose', '--message-format=json', '--', '-Cdefault-linker-libraries=yes')

Write-Host "Running: $cargo $($args -join ' ')"
try {
  & "$cargo" @args 2>&1 | ForEach-Object { Write-Host $_ }
  $rc = $LASTEXITCODE
} catch {
  Write-Host "cargo rustc failed: $($_.Exception.Message)"
  $rc = 1
}

Write-Host "cargo rustc exit code: $rc"
exit $rc
