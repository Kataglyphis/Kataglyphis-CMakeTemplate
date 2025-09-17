include(InstallRequiredSystemLibraries)
set(CPACK_PACKAGE_NAME "${PROJECT_NAME}")
# Experience shows that explicit package naming can help make it easier to sort
# out potential ABI related issues before they start, while helping you
# track a build to a specific GIT SHA
set(CPACK_PACKAGE_FILE_NAME
    "${CMAKE_PROJECT_NAME}-${CMAKE_PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_BUILD_TYPE}-${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}"
)
set(CPACK_PACKAGE_VENDOR "${AUTHOR}")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_RESOURCE_FILE_README "${CMAKE_CURRENT_SOURCE_DIR}/README.md")
set(CPACK_PACKAGE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(CPACK_PACKAGE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(CPACK_PACKAGE_DESCRIPTION "${CMAKE_PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_HOMEPAGE_URL "${CMAKE_PROJECT_HOMEPAGE_URL}")
# There is a bug in NSI that does not handle full UNIX paths properly.
# Make sure there is at least one set of four backlashes.
# https://gitlab.kitware.com/cmake/community/-/wikis/doc/cpack/Packaging-With-CPack
set(CPACK_PACKAGE_ICON ${CMAKE_CURRENT_SOURCE_DIR}/images\\\\Engine_logo.bmp)
set(CPACK_RESOURCE_FILE_WELCOME ${CMAKE_CURRENT_SOURCE_DIR}/docs/packaging/WelcomeFile.txt)
# try to use all cores
set(CPACK_THREADS 0)
set(CPACK_SOURCE_IGNORE_FILES /.git /.*build.*)

# Windows (egal ob MSVC oder Clang/clang-cl) -> NSIS + WIX Binaries erzeugen
if(WIN32)
  # Beide Generatoren aktivieren; CPack erzeugt dann sowohl .exe (NSIS) als auch .msi (WiX)
  # Zusätzlich auch ein reines ZIP-Binary-Package erzeugen
  set(CPACK_GENERATOR "NSIS;WIX;ZIP")
  # Quellpaket-Format für Windows (optional, sonst ZIP/TGZ). Kann bei Bedarf angepasst werden.
  set(CPACK_SOURCE_GENERATOR "ZIP")

  # Gemeinsame Einstellungen für NSIS
  set(CPACK_NSIS_WELCOME_TITLE "Get ready for epic graphics.")
  set(CPACK_NSIS_FINISH_TITLE "Now you are ready to render :)")
  set(CPACK_NSIS_MUI_HEADERIMAGE ${CMAKE_CURRENT_SOURCE_DIR}/images/Engine_logo.bmp)
  set(CPACK_NSIS_MUI_WELCOMEFINISHPAGE_BITMAP ${CMAKE_CURRENT_SOURCE_DIR}/images/Engine_logo.bmp)
  set(CPACK_NSIS_MUI_UNWELCOMEFINISHPAGE_BITMAP ${CMAKE_CURRENT_SOURCE_DIR}/images/Engine_logo.bmp)
  set(CPACK_NSIS_INSTALLED_ICON_NAME bin/${PROJECT_NAME}.exe)
  set(CPACK_NSIS_PACKAGE_NAME "${PROJECT_NAME}")
  set(CPACK_NSIS_DISPLAY_NAME "${PROJECT_NAME}")
  set(CPACK_NSIS_CONTACT "${CMAKE_PROJECT_HOMEPAGE_URL}")
  set(CPACK_PACKAGE_EXECUTABLES "${PROJECT_NAME}" "${PROJECT_NAME}")
  set(CPACK_PACKAGE_INSTALL_REGISTRY_KEY "${PROJECT_NAME}-${PROJECT_VERSION}")
  set(CPACK_NSIS_MENU_LINKS "${CMAKE_PROJECT_HOMEPAGE_URL}" "Homepage for ${PROJECT_NAME}")
  set(CPACK_CREATE_DESKTOP_LINKS "${PROJECT_NAME}")
  set(CPACK_NSIS_URL_INFO_ABOUT "${CMAKE_PROJECT_HOMEPAGE_URL}")
  set(CPACK_NSIS_HELP_LINK "${CMAKE_PROJECT_HOMEPAGE_URL}")
  set(CPACK_NSIS_MUI_ICON ${CMAKE_CURRENT_SOURCE_DIR}/images/faviconNew.ico)
  set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
  set(CPACK_NSIS_MODIFY_PATH "ON")

  # WiX spezifische Einstellungen
  # WICHTIG: Diese Upgrade GUID MUSS STABIL BLEIBEN, sonst funktionieren Upgrades/Deinstallationen nicht korrekt.
  # Falls bereits ein Wert existiert, NICHT ändern. Bei erstmaliger Einführung einmalig generieren.
  set(CPACK_WIX_UPGRADE_GUID "A8B86F5E-5B3E-4C38-9D7F-4F4923F9E5C2")
  set(CPACK_WIX_PRODUCT_ICON ${CMAKE_CURRENT_SOURCE_DIR}/images/faviconNew.ico)
  set(CPACK_WIX_PROGRAM_MENU_FOLDER "${PROJECT_NAME}")
  # Optional eigenes Banner/Logo (muss BMP 493x58 bzw. 493x312 sein, wenn gesetzt)
  # set(CPACK_WIX_UI_BANNER ${CMAKE_CURRENT_SOURCE_DIR}/images/your_banner.bmp)
  # set(CPACK_WIX_UI_DIALOG  ${CMAKE_CURRENT_SOURCE_DIR}/images/your_dialog.bmp)

  # License RTF: WiX benötigt echtes RTF. Falls keine LICENSE.rtf vorhanden ist, einfach weglassen.
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.rtf")
    set(CPACK_WIX_LICENSE_RTF "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.rtf")
  endif()

  # Beispiel für zusätzliche Einträge in ARP (Add/Remove Programs) - optional
  set(CPACK_WIX_PROPERTY_ARPURLINFOABOUT "${CMAKE_PROJECT_HOMEPAGE_URL}")
  set(CPACK_WIX_PROPERTY_ARPHELPLINK "${CMAKE_PROJECT_HOMEPAGE_URL}")

  # Standard-Installationsverzeichnis (unter Program Files)
  set(CPACK_PACKAGE_INSTALL_DIRECTORY "${PROJECT_NAME}")

else()
  # Nicht Windows -> klassisch TGZ (kann um DEB/RPM erweitert werden)
  set(CPACK_SOURCE_GENERATOR "TGZ")
endif()

include(CPack)
