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

option(ENABLE_RUST "Enable building the Rust helper crate" ON)
option(ENABLE_RUST_CXXBRIDGE "Enable generation of the CXX bridge" ON)

# Force the CXX bridge to be enabled unconditionally (including Emscripten builds).
# This ensures the cxx bridge headers are always generated.
set(ENABLE_RUST_CXXBRIDGE
    ON
    CACHE BOOL "Enable generation of the CXX bridge" FORCE)

# Allow configuring which Cargo manifest to import and the crate name. The
# defaults point at the in-tree rusty_code crate under Src/. Adjust via the
# cache if you want to import a different crate (for example an external
# Kataglyphis-RustProjectTemplate crate).
set(RUSTY_MANIFEST_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/rusty_code/Cargo.toml"
    CACHE PATH "Path to the Rust crate Cargo.toml to import")
set(RUSTY_CRATE_NAME
    "rusty_code"
    CACHE STRING "Name of the Rust crate target")

if(ENABLE_RUST OR RUST_FEATURES)

  message(STATUS "RUST_FEATURES is enabled; importing ${RUSTY_CRATE_NAME} crate")
  message(STATUS "About to run corrosion_import_crate for ${RUSTY_MANIFEST_PATH}")
  corrosion_import_crate(
    MANIFEST_PATH
    ${RUSTY_MANIFEST_PATH}
    CRATE_TYPES
    staticlib
    CRATES
    ${RUSTY_CRATE_NAME})

  # Keep Rust build flags simple and aligned with the working repository.
  if(WIN32)
    # Minimal Windows set of system libraries — matches the working repo.
    target_link_libraries(
      ${RUSTY_CRATE_NAME}
      INTERFACE kernel32
                ntdll
                userenv
                ws2_32
                dbghelp)

    set(_RUST_WINDOWS_DEBUG_CXXFLAGS "/MDd /D_DEBUG /D_ITERATOR_DEBUG_LEVEL=2")
    set(_RUST_WINDOWS_DEBUG_CFLAGS "/MDd /D_DEBUG")

    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
       AND MSVC
       AND myproject_ENABLE_SANITIZER_ADDRESS)
      set(_RUST_WINDOWS_DEBUG_CXXFLAGS "/MD /D_ITERATOR_DEBUG_LEVEL=0")
      set(_RUST_WINDOWS_DEBUG_CFLAGS "/MD")
    endif()

    set(_RUST_WINDOWS_CXXFLAGS
        "/EHsc $<$<CONFIG:Debug>:${_RUST_WINDOWS_DEBUG_CXXFLAGS}>$<$<NOT:$<CONFIG:Debug>>:/MD /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0>"
    )
    set(_RUST_WINDOWS_CFLAGS "$<$<CONFIG:Debug>:${_RUST_WINDOWS_DEBUG_CFLAGS}>$<$<NOT:$<CONFIG:Debug>>:/MD /DNDEBUG>")

    # Ensure Corrosion/Cargo produce verbose output for diagnostic purposes
    set_property(GLOBAL PROPERTY CORROSION_VERBOSE_OUTPUT ON)

    corrosion_set_env_vars(
      ${RUSTY_CRATE_NAME}
      "CXXFLAGS=${_RUST_WINDOWS_CXXFLAGS}"
      "CFLAGS=${_RUST_WINDOWS_CFLAGS}"
      SCCACHE_DISABLE=1
      RUST_BACKTRACE=1
      CARGO_TERM_VERBOSE=true
      RUST_LOG=debug
      CARGO_TERM_COLOR=never
      CRATE_CC_NO_DEFAULTS=1)

    corrosion_set_cargo_flags(${RUSTY_CRATE_NAME} --verbose --message-format=json)

    # Forward any MSVC-targeted CC/CXX values from the environment so
    # Cargo uses the same compiler as the CMake build when present. Prefer
    # explicit environment-provided values (which may be absolute paths)
    # over the fallback clang-cl string below.
    if(DEFINED ENV{CC_x86_64-pc-windows-msvc})
      message(STATUS "Using environment CC_x86_64-pc-windows-msvc=${ENV{CC_x86_64-pc-windows-msvc}}")
      corrosion_set_env_vars(${RUSTY_CRATE_NAME} CC_x86_64-pc-windows-msvc=$ENV{CC_x86_64-pc-windows-msvc})
      set(_RUSTY_CC_FORWARDED TRUE)
    elseif(DEFINED ENV{CC})
      corrosion_set_env_vars(${RUSTY_CRATE_NAME} CC_x86_64-pc-windows-msvc=$ENV{CC})
      set(_RUSTY_CC_FORWARDED TRUE)
    endif()

    if(DEFINED ENV{CXX_x86_64-pc-windows-msvc})
      corrosion_set_env_vars(${RUSTY_CRATE_NAME} CXX_x86_64-pc-windows-msvc=$ENV{CXX_x86_64-pc-windows-msvc})
      set(_RUSTY_CXX_FORWARDED TRUE)
    elseif(DEFINED ENV{CXX})
      corrosion_set_env_vars(${RUSTY_CRATE_NAME} CXX_x86_64-pc-windows-msvc=$ENV{CXX})
      set(_RUSTY_CXX_FORWARDED TRUE)
    endif()

    if(DEFINED ENV{AR})
      corrosion_set_env_vars(${RUSTY_CRATE_NAME} AR=$ENV{AR})
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

    corrosion_set_env_vars(
      ${RUSTY_CRATE_NAME}
      CC=${RUST_CC}
      CXX=${RUST_CXX}
      "CXXFLAGS=${RUST_CXXFLAGS}")

    corrosion_set_cargo_flags(${RUSTY_CRATE_NAME} --message-format=json --verbose)

    message(STATUS "Configured native corrosion: CC=${RUST_CC} CXX=${RUST_CXX} CXXFLAGS=${RUST_CXXFLAGS}")
  endif()

  if(ENABLE_RUST_CXXBRIDGE)
    corrosion_add_cxxbridge(
      rusty_bridge
      CRATE
      ${RUSTY_CRATE_NAME}
      FILES
      lib.rs)
  endif()

  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
    message(STATUS "Detected clang-cl; instructing Corrosion to use clang-cl for crate builds")
    corrosion_set_env_vars(${RUSTY_CRATE_NAME} CC_x86_64-pc-windows-msvc=clang-cl CXX_x86_64-pc-windows-msvc=clang-cl)
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
    target_include_directories(${KATAGLYPHIS_CORE_TARGET}
                               PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/corrosion_generated/cxxbridge/rusty_bridge/include")
    add_dependencies(${KATAGLYPHIS_CORE_TARGET} rusty_bridge)
  endif()
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC rusty_code)
endif()

if(TARGET ${KATAGLYPHIS_CORE_TARGET} AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC detected — module dependency flags are managed by CMake")

  message(STATUS "GCC modules enabled — adding -fmodules-ts to target ${KATAGLYPHIS_CORE_TARGET}")
  target_compile_options(${KATAGLYPHIS_CORE_TARGET} PUBLIC $<$<COMPILE_LANGUAGE:CXX>:-fmodules-ts>)
endif()
