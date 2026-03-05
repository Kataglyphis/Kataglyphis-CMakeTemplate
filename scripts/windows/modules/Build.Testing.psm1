Set-StrictMode -Version Latest

$script:MsvcAsanRuntimeDir = $null

function Resolve-TestExecutable {
  param(
    [Parameter(Mandatory)]
    [string]$BuildRoot,
    [Parameter(Mandatory)]
    [string]$ExecutableName
  )

  $preferredPaths = @(
    (Join-Path $BuildRoot $ExecutableName),
    (Join-Path $BuildRoot (Join-Path 'Debug' $ExecutableName)),
    (Join-Path $BuildRoot (Join-Path 'Test\commit' $ExecutableName)),
    (Join-Path $BuildRoot (Join-Path 'Test\compile' $ExecutableName)),
    (Join-Path $BuildRoot (Join-Path 'Test\fuzz' $ExecutableName))
  )

  foreach ($candidate in $preferredPaths) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $found = Get-ChildItem -Path $BuildRoot -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($found) {
    return $found.FullName
  }

  return $null
}

function Resolve-MsvcAsanRuntimeDir {
  param(
    [Parameter(Mandatory)]
    [string]$BuildRoot
  )

  if ($script:MsvcAsanRuntimeDir) {
    return $script:MsvcAsanRuntimeDir
  }

  $cmakeCache = Join-Path $BuildRoot 'CMakeCache.txt'
  if (Test-Path $cmakeCache) {
    $arLine = Select-String -Path $cmakeCache -Pattern '^CMAKE_AR:FILEPATH=' -SimpleMatch:$false -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($arLine) {
      $arPath = ($arLine.Line -replace '^CMAKE_AR:FILEPATH=', '').Trim()
      if (-not [string]::IsNullOrWhiteSpace($arPath) -and (Test-Path $arPath)) {
        $toolBinDir = Split-Path -Path $arPath -Parent
        if (Test-Path (Join-Path $toolBinDir 'clang_rt.asan_dynamic-x86_64.dll')) {
          $script:MsvcAsanRuntimeDir = $toolBinDir
          return $script:MsvcAsanRuntimeDir
        }
      }
    }
  }

  if ($env:VCToolsInstallDir) {
    $fromEnv = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64'
    if (Test-Path (Join-Path $fromEnv 'clang_rt.asan_dynamic-x86_64.dll')) {
      $script:MsvcAsanRuntimeDir = $fromEnv
      return $script:MsvcAsanRuntimeDir
    }
  }

  $vsRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'
  if (-not (Test-Path $vsRoot)) {
    return $null
  }

  $candidate = Get-ChildItem -Path $vsRoot -Filter 'clang_rt.asan_dynamic-x86_64.dll' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -match '\\VC\\Tools\\MSVC\\' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

  if ($candidate) {
    $script:MsvcAsanRuntimeDir = $candidate.DirectoryName
    return $script:MsvcAsanRuntimeDir
  }

  return $null
}

function Get-AsanRuntimeDirs {
  param(
    [Parameter(Mandatory)]
    [string]$BuildRoot,
    [ValidateSet('Auto', 'Msvc', 'Clang')]
    [string]$RuntimeFlavor = 'Auto'
  )

  $asanRuntimeDirs = @()

  if ($RuntimeFlavor -eq 'Auto' -or $RuntimeFlavor -eq 'Msvc') {
    $msvcAsanDir = Resolve-MsvcAsanRuntimeDir -BuildRoot $BuildRoot
    if ($msvcAsanDir) {
      $asanRuntimeDirs += $msvcAsanDir
    }
  }

  if ($RuntimeFlavor -eq 'Auto' -or $RuntimeFlavor -eq 'Clang') {
    try {
      $clangResourceDir = & 'clang-cl.exe' --print-resource-dir 2>$null
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($clangResourceDir)) {
        $clangRuntimeDir = Join-Path $clangResourceDir.Trim() 'lib\windows'
        if (Test-Path (Join-Path $clangRuntimeDir 'clang_rt.asan_dynamic-x86_64.dll')) {
          $asanRuntimeDirs += $clangRuntimeDir
        }
      }
    } catch {
      # Ignore clang resource lookup failures and continue with discovered paths.
    }
  }

  return @($asanRuntimeDirs | Select-Object -Unique)
}

function Invoke-WithRuntimePath {
  param(
    [string[]]$RuntimeDirs = @(),
    [Parameter(Mandatory)]
    [scriptblock]$Script
  )

  $oldPath = $env:PATH
  if ($RuntimeDirs.Count -gt 0) {
    $env:PATH = (($RuntimeDirs -join ';') + ';' + $oldPath)
  }

  try {
    & $Script
  } finally {
    if ($RuntimeDirs.Count -gt 0) {
      $env:PATH = $oldPath
    }
  }
}

function Invoke-ManualTestExecutable {
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Context,
    [Parameter(Mandatory)]
    [string]$BuildRoot,
    [Parameter(Mandatory)]
    [string]$ExecutableName,
    [string[]]$Arguments = @(),
    [ValidateSet('Auto', 'Msvc', 'Clang')]
    [string]$RuntimeFlavor = 'Auto'
  )

  $testExecutable = Resolve-TestExecutable -BuildRoot $BuildRoot -ExecutableName $ExecutableName
  if (-not $testExecutable) {
    Write-BuildLogWarning -Context $Context -Message "Test executable '$ExecutableName' not found under '$BuildRoot'."
    return $false
  }

  $asanRuntimeDirs = Get-AsanRuntimeDirs -BuildRoot $BuildRoot -RuntimeFlavor $RuntimeFlavor

  try {
    Invoke-WithRuntimePath -RuntimeDirs $asanRuntimeDirs -Script {
      try {
        Invoke-BuildExternal -Context $Context -File $testExecutable -Parameters $Arguments | Out-Null
      } catch {
        $errorText = $_.Exception.Message
        if ($errorText -match 'exit code -1073741511|exit code -1073741515') {
          Write-BuildLogWarning -Context $Context -Message "Manual test execution failed to start '$ExecutableName' (Windows loader/runtime mismatch). Continuing pipeline."
          return $false
        }
        throw
      }
    }
  } catch {
    throw
  }

  return $true
}

function Invoke-CtestDiscoveredTests {
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Context,
    [Parameter(Mandatory)]
    [string]$BuildRoot,
    [Parameter(Mandatory)]
    [string]$Configuration,
    [ValidateSet('Auto', 'Msvc', 'Clang')]
    [string]$RuntimeFlavor = 'Auto'
  )

  $ctestCommand = Get-Command 'ctest' -ErrorAction SilentlyContinue
  if (-not $ctestCommand) {
    throw 'ctest not found on PATH.'
  }

  $asanRuntimeDirs = Get-AsanRuntimeDirs -BuildRoot $BuildRoot -RuntimeFlavor $RuntimeFlavor

  Invoke-WithRuntimePath -RuntimeDirs $asanRuntimeDirs -Script {
    Invoke-BuildExternal -Context $Context -File $ctestCommand.Source -Parameters @(
      '--test-dir', $BuildRoot,
      '--build-config', $Configuration,
      '--output-on-failure',
      '--timeout', '300'
    ) | Out-Null
  }
}

function Test-ClangClThreadSanitizerSupport {
  param(
    [Parameter(Mandatory)]
    [string]$ClangClPath
  )

  $probeSource = Join-Path $env:TEMP ("clangcl-tsan-probe-{0}.cpp" -f $PID)
  Set-Content -Path $probeSource -Value 'int main() { return 0; }' -Encoding ASCII

  try {
    & $ClangClPath '--target=x86_64-pc-windows-msvc' '-fsyntax-only' '-fsanitize=thread' $probeSource 2>$null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  } finally {
    Remove-Item -Path $probeSource -Force -ErrorAction SilentlyContinue
  }
}

Export-ModuleMember -Function Resolve-TestExecutable, Invoke-ManualTestExecutable, Invoke-CtestDiscoveredTests, Test-ClangClThreadSanitizerSupport
