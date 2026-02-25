@{
  Build = @{
    WorkspaceRootEnv = 'WORKSPACE_PATH'
    LogDir = 'logs'

    BuildDirMsvc = 'build'
    BuildDirClangCl = 'build'
    BuildDirProfile = 'build-profile'
    BuildDirRelease = 'build-release'

    Presets = @{
      MsvcDebug = 'x64-MSVC-Windows-Debug'
      ClangClDebug = 'x64-ClangCL-Windows-Debug'
      ClangClProfile = 'x64-ClangCL-Windows-Profile'
      ClangClRelease = 'x64-ClangCL-Windows-Release'
    }

    DisableCppcheckDefine = 'myproject_ENABLE_CPPCHECK=OFF'
  }

  Msix = @{
    PackageNameDefault = 'KataglyphisCppProject'
    Publisher = 'CN=Kataglyphis'
    Version = '1.0.0.0'
    MinVersion = '10.0.17763.0'
    ManifestTemplate = 'scripts/windows/msix/AppxManifest.xml.template'
  }
}
