@{
  Build = @{
    WorkspaceRootEnv   = 'GITHUB_WORKSPACE'
    LogDir             = 'logs'

    # Build output directories (relative to workspace root)
    BuildDirMsvc        = 'build'
    BuildDirClangCl     = 'build-clangcl'
    BuildDirProfile     = 'build-release-profile'
    BuildDirRelease     = 'build-release'

    # CMake presets
    Presets = @{
      MsvcDebug        = 'x64-MSVC-Windows-Debug'
      ClangClDebug     = 'x64-ClangCL-Windows-Debug'
      ClangClProfile   = 'x64-ClangCL-Windows-Profile'
      ClangClRelease   = 'x64-ClangCL-Windows-Release'
    }

    # Extra configure args
    DisableCppcheckDefine = 'myproject_ENABLE_CPPCHECK=OFF'
  }

  Msix = @{
    PackageNameDefault = 'KataglyphisCppProject'
    ManifestTemplate   = 'scripts/windows/msix/AppxManifest.xml.template'
    Publisher          = 'CN=Kataglyphis'
    Version            = '1.0.0.0'
    MinVersion         = '10.0.17763.0'
  }
}
