@{
  Build = @{
    WorkspaceRootEnv = 'WORKSPACE_PATH'
    LogDir = 'logs'

    BuildDirMsvc = 'build-msvc-debug'
    BuildDirClangCl = 'build-clangcl-debug'
    BuildDirClangClTsan = 'build-clangcl-tsan'
    BuildDirProfile = 'build-clangcl-profile'
    BuildDirRelease = 'build-clangcl-release'

    Presets = @{
      MsvcDebug = 'x64-MSVC-Windows-Debug'
      ClangClDebug = 'x64-ClangCL-Windows-Debug'
      ClangClDebugTsan = 'x64-ClangCL-Windows-Debug-TSan'
      ClangClProfile = 'x64-ClangCL-Windows-profile'
      ClangClRelease = 'x64-ClangCL-Windows-Release'
    }
  }

  Msix = @{
    PackageNameDefault = 'KataglyphisCppProject'
    Publisher = 'CN=Kataglyphis'
    Version = '1.0.0.0'
    MinVersion = '10.0.17763.0'
    ManifestTemplate = 'Resources/AppxManifest.xml.template'
  }
}
