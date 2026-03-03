cmake_minimum_required(VERSION 4.1.1)

#set the project name
project(
  KataglyphisCppProject
  VERSION 0.0.1
  DESCRIPTION "Lore ipsum"
  HOMEPAGE_URL "https://jonasheinle.de/"
  LANGUAGES CXX C)

set(AUTHOR "Jonas Heinle")

#Set WINDOWS_CI to OFF by default
#WINDOWS CI is only able to verify successful compiling... Windows... lel
#i will stay on linux...
set(WINDOWS_CI
    OFF
    CACHE BOOL "Enable Windows CI build options")
set(RUST_FEATURES
    ON
    CACHE BOOL "Enable Rust features in our project.")
set(MYPROJECT_GCC_TOOLCHAIN_PATH
    ""
    CACHE PATH
          "Optional GCC toolchain root used by Clang and Rust tooling on Linux (for example /opt/gcc-15.2.0)")

# Auto-detect custom GCC toolchain for Clang on Linux to avoid workflow env setup
if(UNIX
   AND NOT APPLE
   AND MYPROJECT_GCC_TOOLCHAIN_PATH
   AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  set(_GCC_TOOLCHAIN_ROOT "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
  set(_GCC_TOOLCHAIN_LIB "${_GCC_TOOLCHAIN_ROOT}/lib64")
  if(NOT EXISTS "${_GCC_TOOLCHAIN_LIB}")
    set(_GCC_TOOLCHAIN_LIB "${_GCC_TOOLCHAIN_ROOT}/lib")
  endif()

  if(EXISTS "${_GCC_TOOLCHAIN_LIB}")
    message(STATUS "Using GCC toolchain at ${_GCC_TOOLCHAIN_ROOT} for Clang")
    string(APPEND CMAKE_C_FLAGS " --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_CXX_FLAGS " --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_EXE_LINKER_FLAGS
           " -L${_GCC_TOOLCHAIN_LIB} -Wl,-rpath,${_GCC_TOOLCHAIN_LIB} --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_SHARED_LINKER_FLAGS
           " -L${_GCC_TOOLCHAIN_LIB} -Wl,-rpath,${_GCC_TOOLCHAIN_LIB} --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
  else()
    message(WARNING "GCC toolchain found at ${_GCC_TOOLCHAIN_ROOT}, but no lib or lib64 dir exists.")
  endif()
endif()

if(RUST_FEATURES)
  message(STATUS "Rust features are enabled.")
  if(MSVC)
    message(STATUS "On a windows machine you must use MSVC or clang-cl when integrating rust features.")
  endif()
else()
  message(STATUS "Rust features are disabled.")
  message(
    STATUS "Your are going to use a non MSVC/clang-cl compiler on windows. Therefore no rust integration possible.")
endif()

include(cmake/PreventInSourceBuilds.cmake)
include(cmake/ProjectOptions.cmake)

myproject_setup_options()

myproject_global_options()

message(STATUS "About to call the local options function.")
myproject_local_options()

include(cmake/SystemLibDependencies.cmake)

# Enable global sanitizers for third-party/fuzz integration builds.
if(NOT WIN32)
  set(_MYPROJECT_GLOBAL_SANITIZERS "")

  if(myproject_ENABLE_SANITIZER_ADDRESS)
    list(APPEND _MYPROJECT_GLOBAL_SANITIZERS "address")
  endif()

  if(myproject_ENABLE_SANITIZER_UNDEFINED)
    list(APPEND _MYPROJECT_GLOBAL_SANITIZERS "undefined")
  endif()

  if(_MYPROJECT_GLOBAL_SANITIZERS)
    list(JOIN _MYPROJECT_GLOBAL_SANITIZERS "," _MYPROJECT_GLOBAL_SANITIZERS_LIST)
    add_compile_options(-fsanitize=${_MYPROJECT_GLOBAL_SANITIZERS_LIST})
    add_link_options(-fsanitize=${_MYPROJECT_GLOBAL_SANITIZERS_LIST})
  endif()
endif()
add_subdirectory(ExternalLib)

add_subdirectory(Src)

if(NOT WINDOWS_CI AND BUILD_TESTING)
  include(CTest)
  enable_testing()
  message(STATUS "WINDOWS_CI is OFF or not defined.")
else()
  message(STATUS "WINDOWS_CI is OFF or not defined.")
endif()

if(BUILD_TESTING)
  message(STATUS "Tests are enabled.!")

  # For single-config generators (e.g. Ninja), gate which suites are configured.
  # For multi-config generators (e.g. Visual Studio), CMAKE_BUILD_TYPE is empty at
  # configure time; in that case we keep the previous behavior and configure all suites.
  if(CMAKE_CONFIGURATION_TYPES)
    add_subdirectory(Test/commit)
    add_subdirectory(Test/compile)
    add_subdirectory(Test/perf)
    add_subdirectory(Test/fuzz)
  elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_subdirectory(Test/commit)
    add_subdirectory(Test/compile)
    add_subdirectory(Test/fuzz)
  elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_subdirectory(Test/perf)
  else()
    message(STATUS "Skipping test suites for build type: ${CMAKE_BUILD_TYPE}")
  endif()
else()
  message(STATUS "Tests are disabled.!")
endif()

#for correct library output needed
install(
  TARGETS ${PROJECT_NAME}
  CONFIGURATIONS Release
  RUNTIME DESTINATION bin)

#we keep the relative paths in the install dir
#keep in mind that install dir will be in front of this relative path...
install(DIRECTORY images/ DESTINATION images/)
install(
  FILES docs/packaging/KataglyphisCppProject.desktop
  DESTINATION usr/share/applications
  RENAME org.kataglyphis.KataglyphisCppProject.desktop)
install(
  FILES docs/packaging/KataglyphisCppProject.appdata.xml
  DESTINATION usr/share/metainfo
  RENAME org.kataglyphis.KataglyphisCppProject.appdata.xml)
install(
  FILES images/Engine_logo.png
  DESTINATION usr/share/icons/hicolor/256x256/apps
  RENAME Engine_logo.png)
install(
  FILES images/Engine_logo.png
  DESTINATION usr/share/icons/hicolor/256x256/apps
  RENAME Engine_logo)
install(
  FILES images/Engine_logo.png
  DESTINATION .
  RENAME Engine_logo.png)

include(cmake/CPackOptions.cmake)
