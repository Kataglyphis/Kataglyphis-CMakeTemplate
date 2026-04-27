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

# Ensure the Abseil flags translation unit is compiled and linked into the
# executable. We add it explicitly so module-aware compilers see the TU even
# if the global glob was run before the file was created.
list(APPEND KataglyphisCppProject_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/flags.cc")

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

if(ENABLE_RUST AND RUST_FEATURES)

  message(STATUS "RUST_FEATURES enabled and ENABLE_RUST=ON; importing ${RUSTY_CRATE_NAME} crate")
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

    # Avoid hard-coding /MDd. Derive debug C/C++ flags for Cargo from the
    # configured MSVC runtime selection so AddressSanitizer and other build
    # decisions that force /MD are respected. Use generator-expressions to
    # select appropriate flags for Debug vs non-Debug configurations.
    # Default debug flags: enable iterator debug level 2 for debug CRT, 0
    # for release CRT. Use /MD when the forced CMAKE_MSVC_RUNTIME_LIBRARY is
    # MultiThreadedDLL (ASan case) and /MDd when MultiThreadedDebugDLL is set.
    set(_RUST_WINDOWS_DEBUG_CXXFLAGS
        "$<$<STREQUAL:${CMAKE_MSVC_RUNTIME_LIBRARY},MultiThreadedDebugDLL>:/MDd /D_DEBUG /D_ITERATOR_DEBUG_LEVEL=2>$<$<STREQUAL:${CMAKE_MSVC_RUNTIME_LIBRARY},MultiThreadedDLL>:/MD /D_ITERATOR_DEBUG_LEVEL=0>"
    )
    set(_RUST_WINDOWS_DEBUG_CFLAGS
        "$<$<STREQUAL:${CMAKE_MSVC_RUNTIME_LIBRARY},MultiThreadedDebugDLL>:/MDd /D_DEBUG>$<$<STREQUAL:${CMAKE_MSVC_RUNTIME_LIBRARY},MultiThreadedDLL>:/MD>"
    )

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

    # Make Cargo invocation explicit about the profile used. For RelWithDebInfo
    # and Release builds ask Cargo to build the release profile so the crate
    # receives the optimized/release settings (the project's Cargo.toml keeps
    # debug info in the release profile where appropriate).
    set(_RUST_CARGO_FLAGS --message-format=json --verbose)
    # Corrosion now selects the appropriate Cargo profile for Release/RelWithDebInfo
    # configurations. Avoid adding an explicit --release here to prevent passing
    # duplicate --release flags when Corrosion already injects it.
    corrosion_set_cargo_flags(${RUSTY_CRATE_NAME} ${_RUST_CARGO_FLAGS})

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

    # Make Cargo invocation explicit about the profile used. For RelWithDebInfo
    # and Release builds ask Cargo to build the release profile so the crate
    # receives the optimized/release settings (the project's Cargo.toml keeps
    # debug info in the release profile where appropriate).
    set(_RUST_CARGO_FLAGS --message-format=json --verbose)
    # Corrosion now selects the appropriate Cargo profile for Release/RelWithDebInfo
    # configurations. Avoid adding an explicit --release here to prevent passing
    # duplicate --release flags when Corrosion already injects it.
    corrosion_set_cargo_flags(${RUSTY_CRATE_NAME} ${_RUST_CARGO_FLAGS})

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

set(KATAGLYPHIS_CORE_TARGET "${PROJECT_NAME}_Lib")

add_library(${KATAGLYPHIS_CORE_TARGET} OBJECT)
add_library(${PROJECT_NAME}::Lib ALIAS ${KATAGLYPHIS_CORE_TARGET})

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
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PRIVATE RELATIVE_RESOURCE_PATH="/../../Resources/"
                                                                RELATIVE_INCLUDE_PATH="/../../Src/")
else()
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PRIVATE RELATIVE_RESOURCE_PATH="/../Resources/"
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
         ${KataglyphisCppProject_HEADERS}
  PUBLIC FILE_SET
         CXX_MODULES
         BASE_DIRS
         ${PROJECT_INCLUDE_DIR}
         ${CMAKE_CURRENT_BINARY_DIR}
         FILES
         ${KataglyphisCppProject_MODULES})

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC modules enabled")
endif()
set_target_properties(${KATAGLYPHIS_CORE_TARGET} PROPERTIES CXX_SCAN_FOR_MODULES ON)

target_link_libraries(
  ${KATAGLYPHIS_CORE_TARGET}
  PUBLIC ${CMAKE_DL_LIBS}
         Threads::Threads
         # enable compiler warnings
         myproject_warnings
         # enable sanitizers
         myproject_options
  PUBLIC GSL spdlog::spdlog)

if(TARGET nlohmann_json_modules)
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC nlohmann_json_modules)
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC NLOHMANN_JSON_MODULE_AVAILABLE)
endif()

# Link Abseil flags and strings libraries for command-line flag parsing.
# Only link if Abseil was fetched by ExternalLib/CMakeLists (FetchContent makes
# the absl targets available globally when FetchContent_MakeAvailable was called).
if(TARGET absl::flags AND TARGET absl::flags_parse)
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC absl::flags absl::flags_parse absl::strings)
endif()

# If Abseil was fetched and built, prefer to align our executable's MSVC runtime
# and iterator-debug level with Abseil's choice to avoid /failifmismatch and
# _ITERATOR_DEBUG_LEVEL LNK2038 errors when linking against Abseil libraries.
if(TARGET absl::flags_parse AND MSVC)
  # Prefer using a concrete MSVC runtime selection for the main target.
  # Some dependencies (Abseil) may expose a generator-expression for
  # MSVC_RUNTIME_LIBRARY (for example: MultiThreaded$<$<CONFIG:Debug>:Debug>DLL)
  # which, if copied directly, causes per-config flags like /MDd to appear
  # and can conflict with AddressSanitizer. Avoid adopting generator
  # expressions from deps; prefer a concrete runtime resolved from the
  # project's cached CMAKE_MSVC_RUNTIME_LIBRARY when necessary.
  get_target_property(_absl_runtime absl::flags_parse MSVC_RUNTIME_LIBRARY)
  if(_absl_runtime)
    string(FIND "${_absl_runtime}" "$<" _absl_has_genexpr)
    if(_absl_has_genexpr EQUAL -1)
      # Abseil provided a concrete runtime string; use it.
      set(_runtime_to_use "${_absl_runtime}")
    else()
      # Fall back to resolving a concrete runtime from the cached
      # CMAKE_MSVC_RUNTIME_LIBRARY value so we don't copy generator-exprs.
      get_property(
        _cached_msvc_runtime
        CACHE CMAKE_MSVC_RUNTIME_LIBRARY
        PROPERTY VALUE)
      if(_cached_msvc_runtime)
        string(FIND "${_cached_msvc_runtime}" "$<" _cached_has_genexpr)
        if(_cached_has_genexpr EQUAL -1)
          set(_runtime_to_use "${_cached_msvc_runtime}")
        else()
          if(CMAKE_BUILD_TYPE STREQUAL "Debug")
            string(
              REPLACE "$<$<CONFIG:Debug>:Debug>"
                      "Debug"
                      _runtime_to_use
                      "${_cached_msvc_runtime}")
          else()
            string(
              REPLACE "$<$<CONFIG:Debug>:Debug>"
                      ""
                      _runtime_to_use
                      "${_cached_msvc_runtime}")
          endif()
        endif()
      else()
        # No cached value; fall back to Abseil's runtime (generator-expr).
        set(_runtime_to_use "${_absl_runtime}")
      endif()
    endif()

    if(_runtime_to_use)
      message(STATUS "Aligning ${KATAGLYPHIS_CORE_TARGET} MSVC_RUNTIME_LIBRARY to concrete value: ${_runtime_to_use}")
      set_property(TARGET ${KATAGLYPHIS_CORE_TARGET} PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime_to_use}")

      # And also apply to all sources explicitly just in case CMake misses it due to being an interface
      get_target_property(_target_sources ${KATAGLYPHIS_CORE_TARGET} SOURCES)
      foreach(_source IN LISTS _target_sources)
        set_property(SOURCE "${_source}" PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime_to_use}")
      endforeach()
      set_property(SOURCE "${KATAGLYPHIS_MAIN_SOURCE}" PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime_to_use}")

      if(_runtime_to_use STREQUAL "MultiThreadedDLL")
        target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PRIVATE _ITERATOR_DEBUG_LEVEL=0)
      elseif(_runtime_to_use STREQUAL "MultiThreadedDebugDLL")
        target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PRIVATE _ITERATOR_DEBUG_LEVEL=2)
      endif()
    endif()
  endif()
endif()

# Ensure the tomlplusplus module provider is linked so module BMIs and
# module-mapping information are available to consumers at compile time.
if(TARGET tomlplusplus_modules)
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC tomlplusplus_modules)
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC TOMLPLUSPLUS_MODULE_AVAILABLE)
  add_dependencies(${KATAGLYPHIS_CORE_TARGET} tomlplusplus_modules)
endif()

# Ensure the nlohmann.json module target is built before compiling the
# project's module interface units. Some generators/compilers (clang-cl on
# Windows) can attempt to compile module-importing translation units before
# the provider target has produced its BMI, which yields "module not found".
if(TARGET nlohmann_json_modules)
  add_dependencies(${KATAGLYPHIS_CORE_TARGET} nlohmann_json_modules)
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

# Create the main executable target and link it to the core project library.
# Dividing the project into a library and a small executable allows test suites
# to link against the library logic and properly record code coverage.
add_executable(${PROJECT_NAME} "${KATAGLYPHIS_MAIN_SOURCE}")
set_target_properties(${PROJECT_NAME} PROPERTIES CXX_SCAN_FOR_MODULES ON)
target_link_libraries(${PROJECT_NAME} PUBLIC ${KATAGLYPHIS_CORE_TARGET})

# Forward core definitions to the executable
if(RUST_FEATURES)
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=1)
else()
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=0)
endif()

if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /EHsc)
endif()
