# update current positions
set(PROJECT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(PROJECT_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(EXTERNAL_LIB_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}../ExternalLib/)

include(cmake/filters/SetProjectFilters.cmake)
include(cmake/SetSourceGroups.cmake)

file(GLOB_RECURSE KataglyphisCppProject_SOURCES "*.cpp")
file(GLOB_RECURSE KataglyphisCppProject_HEADERS "*.hpp")
set(KATAGLYPHIS_MAIN_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Main.cpp")
list(REMOVE_ITEM KataglyphisCppProject_SOURCES "${KATAGLYPHIS_MAIN_SOURCE}")

file(
  GLOB_RECURSE
  KataglyphisCppProject_MODULES
  "*.ixx"
  "*.cppm")

set(KATAGLYPHIS_ENABLE_MODULES ON)

set(_KATAGLYPHIS_CONFIG_MODULE "${CMAKE_CURRENT_BINARY_DIR}/KataglyphisCppProjectConfig.ixx")

configure_file(KataglyphisCppProjectConfig.ixx.in "${_KATAGLYPHIS_CONFIG_MODULE}" @ONLY)
list(APPEND KataglyphisCppProject_MODULES "${_KATAGLYPHIS_CONFIG_MODULE}")
list(REMOVE_DUPLICATES KataglyphisCppProject_MODULES)

if(RUST_FEATURES)

  message(STATUS "RUST_FEATURES is enabled; importing rusty_code crate")
  message(STATUS "About to run corrosion_import_crate for rusty_code/Cargo.toml")
  corrosion_import_crate(MANIFEST_PATH rusty_code/Cargo.toml)

  # Configure environment for Cargo/Corrosion before importing the crate.
  message(STATUS "RUST_FEATURES is enabled; configuring Rust/Cargo environment")
  # Disable sccache for the rust crate build to avoid stale file handles on
  # Windows that can prevent Cargo from removing temporary archives
  # (observed as "os error 32" on temp-archive removal). This keeps the build
  # environment deterministic and reduces file-locking races with external
  # caching wrappers.
  if(WIN32)
    message(STATUS "Configuring corrosion env for Windows: setting CXXFLAGS=/EHsc SCCACHE_DISABLE=1")
    # Also forward verbose flag to ensure cargo prints full output when Corrosion runs it
    set_property(GLOBAL PROPERTY CORROSION_VERBOSE_OUTPUT ON)
    # Set environment variables to increase cargo/rust verbosity and diagnostics
    corrosion_set_env_vars(
      rusty_code
      CXXFLAGS=/EHsc
      SCCACHE_DISABLE=1
      RUST_BACKTRACE=1
      CARGO_TERM_VERBOSE=true
      RUST_LOG=debug
      CARGO_TERM_COLOR=never
      CRATE_CC_NO_DEFAULTS=1)
    # Request cargo to produce verbose output and machine-readable messages
    corrosion_set_cargo_flags(rusty_code --verbose --message-format=json)
    # Also export MSVC-targeted CC/CXX variables if available in the environment
    if(DEFINED ENV{CC_x86_64-pc-windows-msvc})
      message(STATUS "Using environment CC_x86_64-pc-windows-msvc=${ENV{CC_x86_64-pc-windows-msvc}}")
      corrosion_set_env_vars(rusty_code CC_x86_64-pc-windows-msvc=$ENV{CC_x86_64-pc-windows-msvc})
    elseif(DEFINED ENV{CC})
      corrosion_set_env_vars(rusty_code CC_x86_64-pc-windows-msvc=$ENV{CC})
    endif()
    if(DEFINED ENV{CXX_x86_64-pc-windows-msvc})
      corrosion_set_env_vars(rusty_code CXX_x86_64-pc-windows-msvc=$ENV{CXX_x86_64-pc-windows-msvc})
    elseif(DEFINED ENV{CXX})
      corrosion_set_env_vars(rusty_code CXX_x86_64-pc-windows-msvc=$ENV{CXX})
    endif()
    if(DEFINED ENV{AR})
      corrosion_set_env_vars(rusty_code AR=$ENV{AR})
    endif()
  else()
    if(NOT DEFINED GCC_TOOLCHAIN_PATH)
      set(GCC_TOOLCHAIN_PATH
          ""
          CACHE PATH "Optional GCC toolchain root")
    endif()

    set(RUST_CC "${CMAKE_C_COMPILER}")
    set(RUST_CXX "${CMAKE_CXX_COMPILER}")
    if(NOT RUST_CC)
      set(RUST_CC "cc")
    endif()
    if(NOT RUST_CXX)
      set(RUST_CXX "c++")
    endif()

    set(_gcc_toolchain_root "")
    if(GCC_TOOLCHAIN_PATH AND EXISTS "${GCC_TOOLCHAIN_PATH}")
      set(_gcc_toolchain_root "${GCC_TOOLCHAIN_PATH}")
    elseif(DEFINED MYPROJECT_GCC_TOOLCHAIN_PATH AND EXISTS "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
      set(_gcc_toolchain_root "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
    endif()

    set(RUST_CXXFLAGS "-fexceptions")
    if(_gcc_toolchain_root AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      set(RUST_CXXFLAGS "--gcc-toolchain=${_gcc_toolchain_root} -fexceptions")
    endif()
    if(DEFINED ENV{CXXFLAGS})
      set(RUST_CXXFLAGS "$ENV{CXXFLAGS} ${RUST_CXXFLAGS}")
    endif()
    message(
      STATUS "Configuring corrosion env: CC=${RUST_CC} CXX=${RUST_CXX} CXXFLAGS=${RUST_CXXFLAGS} SCCACHE_DISABLE=1")
    corrosion_set_env_vars(
      rusty_code
      CC=${RUST_CC}
      CXX=${RUST_CXX}
      "CXXFLAGS=${RUST_CXXFLAGS}"
      SCCACHE_DISABLE=1
      RUST_BACKTRACE=1
      CARGO_TERM_VERBOSE=true
      RUST_LOG=debug
      CARGO_TERM_COLOR=never)
    corrosion_set_cargo_flags(rusty_code --message-format=json --verbose)

    message(STATUS "Configured native corrosion: CC=${RUST_CC} CXX=${RUST_CXX} CXXFLAGS=${RUST_CXXFLAGS}")
  endif()

  # (crate already imported above)

  # If possible, generate a per-crate Cargo config to pin the linker/ar for the
  # x86_64-pc-windows-msvc target. This helps when forcing clang-cl or lld-link
  # in CI/container environments where the system defaults are not present.
  set(RUSTY_CARGO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rusty_code/.cargo")
  file(MAKE_DIRECTORY "${RUSTY_CARGO_DIR}")
  set(RUSTY_CARGO_CONFIG "${RUSTY_CARGO_DIR}/config.toml")
  # Only write the file if we can determine a linker from environment
  if(DEFINED ENV{CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER}
     OR DEFINED ENV{CC_x86_64-pc-windows-msvc}
     OR DEFINED ENV{CC})
    if(DEFINED ENV{CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER})
      set(_linker_path "$ENV{CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER}")
    elseif(DEFINED ENV{CC_x86_64-pc-windows-msvc})
      set(_linker_path "$ENV{CC_x86_64-pc-windows-msvc}")
    else()
      set(_linker_path "$ENV{CC}")
    endif()
    # Optional ar from environment
    if(DEFINED ENV{AR})
      set(_ar_path "$ENV{AR}")
    else()
      set(_ar_path "")
    endif()
    file(WRITE "${RUSTY_CARGO_CONFIG}" "[target.x86_64-pc-windows-msvc]\n")
    file(APPEND "${RUSTY_CARGO_CONFIG}" "linker = \"${_linker_path}\"\n")
    if(_ar_path)
      file(APPEND "${RUSTY_CARGO_CONFIG}" "ar = \"${_ar_path}\"\n")
    endif()
    message(STATUS "Wrote ${RUSTY_CARGO_CONFIG} (linker=${_linker_path})")
  else()
    message(STATUS "Skipping generation of ${RUSTY_CARGO_CONFIG}: no linker detected in environment")
  endif()

  message(STATUS "Adding cxxbridge target for rusty_code (rusty_bridge)")
  corrosion_add_cxxbridge(
    rusty_bridge
    CRATE
    rusty_code
    FILES
    lib.rs)

  message(STATUS "corrosion_add_cxxbridge completed for rusty_code")

  # If Corrosion imported the crate target, on Windows ensure the Rust staticlib
  # carries necessary system libraries so final link resolves Windows system
  # symbols when linking the crate into a C++ executable.
  if(WIN32 AND TARGET rusty_code)
    target_link_libraries(rusty_code INTERFACE kernel32 ntdll userenv ws2_32 dbghelp)
  endif()

endif()

set(KATAGLYPHIS_CORE_TARGET ${PROJECT_NAME})

add_executable(${KATAGLYPHIS_CORE_TARGET} "${KATAGLYPHIS_MAIN_SOURCE}")

if(RUST_FEATURES)
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC USE_RUST=1)
else()
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC USE_RUST=0)
endif()

# Ensure exceptions are enabled for the main target on MSVC/clang-cl builds.
# Some dependent libraries and STL internals expect exception unwind semantics
# to be available; explicitly enforce /EHsc for the executable to avoid
# mismatches caused by interface targets that disable exceptions.
if(MSVC)
  target_compile_options(${KATAGLYPHIS_CORE_TARGET} PRIVATE /EHsc)
endif()

# Treat MSVC and clang-cl on Windows differently in a sense of deployment
# https://clang.llvm.org/docs/UsersManual.html
if(WIN32 AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC))
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC RELATIVE_RESOURCE_PATH="/../../Resources/"
                                                               RELATIVE_INCLUDE_PATH="/../../Src/")
else()
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC RELATIVE_RESOURCE_PATH="/../Resources/"
                                                               RELATIVE_INCLUDE_PATH="/../Src/")
endif()

target_sources(
  ${KATAGLYPHIS_CORE_TARGET}
  PRIVATE ${KataglyphisCppProject_SOURCES}
  PUBLIC FILE_SET
         HEADERS
         BASE_DIRS
         ${PROJECT_INCLUDE_DIR}
         FILES
         ${KataglyphisCppProject_HEADERS})

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC modules enabled")
endif()
set_target_properties(${KATAGLYPHIS_CORE_TARGET} PROPERTIES CXX_SCAN_FOR_MODULES ON)
target_sources(
  ${KATAGLYPHIS_CORE_TARGET}
  PRIVATE FILE_SET
          CXX_MODULES
          BASE_DIRS
          ${PROJECT_INCLUDE_DIR}
          ${CMAKE_CURRENT_BINARY_DIR}
          FILES
          ${KataglyphisCppProject_MODULES})

target_link_libraries(
  ${KATAGLYPHIS_CORE_TARGET}
  PUBLIC ${CMAKE_DL_LIBS}
         Threads::Threads
         # enable compiler warnings
         myproject_warnings
         # enable sanitizers
         myproject_options
  PUBLIC GSL spdlog::spdlog nlohmann_json_modules)

# Ensure the tomlplusplus module provider is linked so module BMIs and
# module-mapping information are available to consumers at compile time.
if(TARGET tomlplusplus_modules)
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC tomlplusplus_modules)
endif()

# Ensure the nlohmann.json module target is built before compiling the
# project's module interface units. Some generators/compilers (clang-cl on
# Windows) can attempt to compile module-importing translation units before
# the provider target has produced its BMI, which yields "module not found".
add_dependencies(${KATAGLYPHIS_CORE_TARGET} nlohmann_json_modules)

# Ensure the tomlplusplus module provider is built before consumers import it.
# Some generators/compilers (clang-cl on Windows) may attempt to compile
# module-importing translation units before the provider has produced its BMI
# which yields "module not found". Make the provider a dependency when present.
if(TARGET tomlplusplus_modules)
  add_dependencies(${KATAGLYPHIS_CORE_TARGET} tomlplusplus_modules)
  # Also link the tomlplusplus interface target so consumers inherit include dirs
  if(TARGET tomlplusplus::tomlplusplus)
    target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC tomlplusplus::tomlplusplus)
  endif()
endif()

if(RUST_FEATURES)
  if(ENABLE_RUST_CXXBRIDGE)
    # Ensure the main C++ target can include headers generated by cxxbridge and
    # waits for the bridge target to be generated before compiling.
    target_include_directories(${KATAGLYPHIS_CORE_TARGET} PRIVATE
      "${CMAKE_CURRENT_BINARY_DIR}/corrosion_generated/cxxbridge/rusty_bridge/include")
    add_dependencies(${KATAGLYPHIS_CORE_TARGET} rusty_bridge)
  endif()
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC rusty_code)
endif()

if(TARGET ${KATAGLYPHIS_CORE_TARGET} AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC detected — module dependency flags are managed by CMake")

  message(STATUS "GCC modules enabled — adding -fmodules-ts to target ${KATAGLYPHIS_CORE_TARGET}")
  target_compile_options(${KATAGLYPHIS_CORE_TARGET} PUBLIC $<$<COMPILE_LANGUAGE:CXX>:-fmodules-ts>)
endif()
