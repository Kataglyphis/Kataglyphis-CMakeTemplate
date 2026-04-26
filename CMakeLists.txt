cmake_minimum_required(VERSION 4.2.1)

#set the project name
project(
  KataglyphisCppProject
  VERSION 0.0.1
  DESCRIPTION "Lore ipsum"
  HOMEPAGE_URL "https://jonasheinle.de/"
  LANGUAGES CXX C)

set(AUTHOR "Jonas Heinle")

set(RUST_FEATURES
    ON
    CACHE BOOL "Enable Rust features in our project.")
set(MYPROJECT_GCC_TOOLCHAIN_PATH
    ""
    CACHE PATH "Optional GCC toolchain root used by Clang and Rust tooling on Linux (for example /opt/gcc-15.2.0)")

include(FetchContent)

# Fetch Corrosion from GitHub
if(RUST_FEATURES)
  # Fetch Corrosion from GitHub (only when Rust integration is enabled)
  FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG master)
  FetchContent_MakeAvailable(Corrosion)

  # Ensure cxxbridge-cmd is available for Corrosion/C++ bridge generation.
  # Search common cargo bin locations and the system PATH. If not found try to
  # infer cargo location from a discovered rustc, then attempt a cargo
  # install of cxxbridge-cmd.
  find_program(
    CXXBRIDGE
    NAMES cxxbridge cxxbridge.exe
    HINTS "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.cargo/bin" "$ENV{USERPROFILE}/scoop/persist/rustup/.cargo/bin")

  if(NOT CXXBRIDGE)
    message(STATUS "Could not find cxxbridge; attempting to install cxxbridge-cmd via cargo")

    find_program(
      CARGO
      NAMES cargo cargo.exe
      HINTS "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.cargo/bin" "$ENV{USERPROFILE}/scoop/persist/rustup/.cargo/bin")

    # If cargo is still not found, try to locate rustc and infer cargo's bin
    # directory (they are co-located under the same toolchain/bin directory).
    if(NOT CARGO)
      find_program(RUSTC NAMES rustc rustc.exe)
      if(RUSTC)
        get_filename_component(_rustc_bin_dir ${RUSTC} DIRECTORY)
        find_program(
          CARGO
          NAMES cargo cargo.exe
          PATHS ${_rustc_bin_dir})
      endif()
    endif()

    if(NOT CARGO)
      message(
        FATAL_ERROR
          "Rust cargo not found in PATH; install rustup/cargo (https://rustup.rs/) before enabling RUST_FEATURES")
    endif()

    execute_process(
      COMMAND ${CARGO} install cxxbridge-cmd
      RESULT_VARIABLE _CARGO_INSTALL_RESULT
      OUTPUT_VARIABLE _CARGO_INSTALL_OUT
      ERROR_VARIABLE _CARGO_INSTALL_ERR)
    if(NOT
       _CARGO_INSTALL_RESULT
       EQUAL
       0)
      message(
        FATAL_ERROR "Failed to install cxxbridge-cmd via cargo. Output: ${_CARGO_INSTALL_OUT}\n${_CARGO_INSTALL_ERR}")
    endif()

    # Try locating again after install
    find_program(
      CXXBRIDGE
      NAMES cxxbridge cxxbridge.exe
      HINTS "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.cargo/bin" "$ENV{USERPROFILE}/scoop/persist/rustup/.cargo/bin")
    if(NOT CXXBRIDGE)
      message(
        FATAL_ERROR
          "cxxbridge still not found after cargo install. Ensure your cargo bin directory (for example $ENV{USERPROFILE}/.cargo/bin) is on PATH and rerun CMake."
      )
    endif()
    message(STATUS "Installed cxxbridge and found at: ${CXXBRIDGE}")
  endif()
endif()

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

if(myproject_ENABLE_SANITIZER_ADDRESS)
  if(MSVC)
    # Keep STL annotation settings consistent for all targets (including gtest)
    # to avoid LNK2038 mismatches with AddressSanitizer builds.
    add_compile_definitions(_DISABLE_VECTOR_ANNOTATION _DISABLE_STRING_ANNOTATION)
    if(NOT
       CMAKE_CXX_COMPILER_ID
       STREQUAL
       "Clang")
      add_compile_options(/fsanitize=address /Zi)
      add_link_options(/INCREMENTAL:NO)
    endif()
  else()
    add_compile_options(-fsanitize=address)
    add_link_options(-fsanitize=address)
  endif()

endif()

if(myproject_ENABLE_COVERAGE
   AND NOT
       CMAKE_BUILD_TYPE
       STREQUAL
       "Release"
   AND CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")

  add_compile_options(-fprofile-instr-generate -fcoverage-mapping)

  add_link_options(-fprofile-instr-generate -fcoverage-mapping)

endif()

add_subdirectory(ExternalLib)

# Enable maximum Corrosion/Cargo verbosity by default so CI and local builds
# produce detailed Rust/Cargo logs for debugging integration issues.
set(CORROSION_VERBOSE_OUTPUT
    ON
    CACHE BOOL "Enables verbose output from Corrosion and Cargo" FORCE)
option(ENABLE_RUST_CXXBRIDGE "Enable generation of the CXX bridge for Rust crates" ON)

# If the nlohmann.json module target was created, expose a compile-time macro
# so consumer module units can conditionally import the module. This lets
# translation units fall back to the header-only include if the module BMI
# cannot be used due to configuration mismatches (for example differing
# exception handling settings between provider and consumer).
if(TARGET nlohmann_json_modules)
  add_compile_definitions(NLOHMANN_JSON_MODULE_AVAILABLE=1)
endif()

# If the tomlplusplus module provider was created, expose a compile-time macro
# so module consumers can import it conditionally.
if(TARGET tomlplusplus_modules)
  add_compile_definitions(TOMLPLUSPLUS_MODULE_AVAILABLE=1)
endif()

add_subdirectory(Src)

if(BUILD_TESTING)
  include(CTest)
  enable_testing()
  message(STATUS "BUILD_TESTING is ON - enabling CTest.")
else()
  message(STATUS "BUILD_TESTING is OFF - skipping CTest enablement.")
endif()

if(BUILD_TESTING)
  message(STATUS "Tests are enabled.!")
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_subdirectory(Test/commit)
    add_subdirectory(Test/compile)
    if(NOT USE_THREAD_SANITIZER)
      add_subdirectory(Test/fuzz)
      message(STATUS "Building test suites: commit, compile, fuzz (Debug)")
    else()
      message(STATUS "Building test suites: commit, compile (Debug, fuzz disabled for ThreadSanitizer)")
    endif()
  elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_subdirectory(Test/perf)
    message(STATUS "Building test suite: perf (RelWithDebInfo)")
  else()
    message(
      STATUS
        "Skipping test suites for CMAKE_BUILD_TYPE='${CMAKE_BUILD_TYPE}'. Use Debug for commit/compile/fuzz or RelWithDebInfo for perf."
    )
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
