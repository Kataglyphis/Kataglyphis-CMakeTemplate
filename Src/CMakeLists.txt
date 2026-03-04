# update current positions
set(PROJECT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(PROJECT_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(EXTERNAL_LIB_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}../ExternalLib/)

include(cmake/filters/SetProjectFilters.cmake)
include(cmake/SetSourceGroups.cmake)

file(GLOB_RECURSE KataglyphisCppProject_SOURCES "*.cpp")
file(GLOB_RECURSE KataglyphisCppProject_HEADERS "*.hpp")
file(
  GLOB_RECURSE
  KataglyphisCppProject_MODULES
  "*.ixx"
  "*.cppm")

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|MSVC|GNU")
  set(KATAGLYPHIS_ENABLE_MODULES ON)
else()
  set(KATAGLYPHIS_ENABLE_MODULES OFF)
endif()

set(_KATAGLYPHIS_MAIN_MODULES "${CMAKE_CURRENT_SOURCE_DIR}/Main.cpp")
set(_KATAGLYPHIS_CONFIG_MODULE "${CMAKE_CURRENT_SOURCE_DIR}/KataglyphisCppProjectConfig.ixx")

configure_file(KataglyphisCppProjectConfig.ixx.in "${_KATAGLYPHIS_CONFIG_MODULE}" @ONLY)
list(APPEND KataglyphisCppProject_MODULES "${_KATAGLYPHIS_CONFIG_MODULE}")
list(REMOVE_DUPLICATES KataglyphisCppProject_MODULES)

if(RUST_FEATURES)

  corrosion_import_crate(MANIFEST_PATH rusty_code/Cargo.toml)
  if(WIN32)
    corrosion_set_env_vars(rusty_code CXXFLAGS=/EHsc)
  else()
    # Native-only corrosion/toolchain setup (no cross-building)
    # Optionally override with -DGCC_TOOLCHAIN_PATH=/path/to/gcc when configuring.
    if(NOT DEFINED GCC_TOOLCHAIN_PATH)
      set(GCC_TOOLCHAIN_PATH
          ""
          CACHE PATH "Optional GCC toolchain root")
    endif()

    # Determine which compiler Rust/C++ bridge should use.
    # Keep this aligned with the selected CMake compiler.
    set(RUST_CC "${CMAKE_C_COMPILER}")
    set(RUST_CXX "${CMAKE_CXX_COMPILER}")
    if(NOT RUST_CC)
      set(RUST_CC "cc")
    endif()
    if(NOT RUST_CXX)
      set(RUST_CXX "c++")
    endif()

    # For Clang, optionally point it at a GCC toolchain for libstdc++/headers.
    # Prefer explicit GCC_TOOLCHAIN_PATH, otherwise fall back to MYPROJECT_GCC_TOOLCHAIN_PATH (top-level).
    set(_gcc_toolchain_root "")
    if(GCC_TOOLCHAIN_PATH AND EXISTS "${GCC_TOOLCHAIN_PATH}")
      set(_gcc_toolchain_root "${GCC_TOOLCHAIN_PATH}")
    elseif(DEFINED MYPROJECT_GCC_TOOLCHAIN_PATH AND EXISTS "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
      set(_gcc_toolchain_root "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
    endif()

    set(RUST_CXXFLAGS "-fexceptions")
    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND _gcc_toolchain_root)
      set(RUST_CXXFLAGS "--gcc-toolchain=${_gcc_toolchain_root} -fexceptions")
    endif()
    if(DEFINED ENV{CXXFLAGS})
      set(RUST_CXXFLAGS "$ENV{CXXFLAGS} ${RUST_CXXFLAGS}")
    endif()

    # detect host arch for logging (no cross-compile behavior)
    string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" _hostproc)
    if(_hostproc MATCHES "^(x86_64|amd64)$")
      set(HOST_ARCH "x86_64")
    elseif(_hostproc MATCHES "^(aarch64|arm64|armv8)$")
      set(HOST_ARCH "aarch64")
    elseif(_hostproc MATCHES "^(riscv64)$")
      set(HOST_ARCH "riscv64")
    else()
      set(HOST_ARCH "${_hostproc}")
    endif()

    message(STATUS "Native-only build. HOST_ARCH=${HOST_ARCH}")

    # If building with GNU and a GCC_TOOLCHAIN_PATH is provided, prefer that gcc/g++ for Rust.
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU"
       AND GCC_TOOLCHAIN_PATH
       AND EXISTS "${GCC_TOOLCHAIN_PATH}")
      if(HOST_ARCH STREQUAL "x86_64")
        find_program(GCC_TOOLCHAIN_GCC NAMES "${GCC_TOOLCHAIN_PATH}/bin/x86_64-pc-linux-gnu-gcc"
                                             "${GCC_TOOLCHAIN_PATH}/bin/gcc")
        find_program(GCC_TOOLCHAIN_GXX NAMES "${GCC_TOOLCHAIN_PATH}/bin/x86_64-pc-linux-gnu-g++"
                                             "${GCC_TOOLCHAIN_PATH}/bin/g++")
      elseif(HOST_ARCH STREQUAL "aarch64")
        find_program(GCC_TOOLCHAIN_GCC NAMES "${GCC_TOOLCHAIN_PATH}/bin/aarch64-linux-gnu-gcc"
                                             "${GCC_TOOLCHAIN_PATH}/bin/gcc")
        find_program(GCC_TOOLCHAIN_GXX NAMES "${GCC_TOOLCHAIN_PATH}/bin/aarch64-linux-gnu-g++"
                                             "${GCC_TOOLCHAIN_PATH}/bin/g++")
      elseif(HOST_ARCH STREQUAL "riscv64")
        find_program(GCC_TOOLCHAIN_GCC NAMES "${GCC_TOOLCHAIN_PATH}/bin/riscv64-unknown-linux-gnu-gcc"
                                             "${GCC_TOOLCHAIN_PATH}/bin/gcc")
        find_program(GCC_TOOLCHAIN_GXX NAMES "${GCC_TOOLCHAIN_PATH}/bin/riscv64-unknown-linux-gnu-g++"
                                             "${GCC_TOOLCHAIN_PATH}/bin/g++")
      else()
        find_program(GCC_TOOLCHAIN_GCC NAMES "${GCC_TOOLCHAIN_PATH}/bin/gcc")
        find_program(GCC_TOOLCHAIN_GXX NAMES "${GCC_TOOLCHAIN_PATH}/bin/g++")
      endif()

      if(GCC_TOOLCHAIN_GCC)
        set(RUST_CC "${GCC_TOOLCHAIN_GCC}")
      else()
        message(WARNING "Toolchain gcc not found in ${GCC_TOOLCHAIN_PATH}; falling back to system compiler")
      endif()
      if(GCC_TOOLCHAIN_GXX)
        set(RUST_CXX "${GCC_TOOLCHAIN_GXX}")
      else()
        message(WARNING "Toolchain g++ not found in ${GCC_TOOLCHAIN_PATH}; falling back to system compiler")
      endif()
    endif()

    # Always set deterministic env for corrosion on non-Windows hosts.
    corrosion_set_env_vars(
      rusty_code
      CC=${RUST_CC}
      CXX=${RUST_CXX}
      "CXXFLAGS=${RUST_CXXFLAGS}")

    message(STATUS "Configured native corrosion: CC=${RUST_CC} CXX=${RUST_CXX} CXXFLAGS=${RUST_CXXFLAGS}")
  endif()

  corrosion_add_cxxbridge(
    rusty_bridge
    CRATE
    rusty_code
    FILES
    lib.rs)

endif()

# add the executable
add_executable(${PROJECT_NAME})

if(RUST_FEATURES)
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=1)
else()
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=0)
endif()

# Treat MSVC and clang-cl on Windows differently in a sense of deployment
# https://clang.llvm.org/docs/UsersManual.html
if(WIN32 AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC))
  target_compile_definitions(${PROJECT_NAME} PRIVATE RELATIVE_RESOURCE_PATH="/../../Resources/"
                                                     RELATIVE_INCLUDE_PATH="/../../Src/")
else()
  target_compile_definitions(${PROJECT_NAME} PRIVATE RELATIVE_RESOURCE_PATH="/../Resources/"
                                                     RELATIVE_INCLUDE_PATH="/../Src/")
endif()

target_sources(
  ${PROJECT_NAME}
  PRIVATE ${KataglyphisCppProject_SOURCES}
  PUBLIC FILE_SET
         HEADERS
         BASE_DIRS
         ${PROJECT_INCLUDE_DIR}
         FILES
         ${KataglyphisCppProject_HEADERS})

if(KATAGLYPHIS_ENABLE_MODULES)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    message(STATUS "GCC modules enabled")
  endif()
  set_target_properties(${PROJECT_NAME} PROPERTIES CXX_SCAN_FOR_MODULES ON)
  target_sources(
    ${PROJECT_NAME}
    PRIVATE FILE_SET
            CXX_MODULES
            FILES
            ${KataglyphisCppProject_MODULES})
endif()

target_link_libraries(
  ${PROJECT_NAME}
  PUBLIC ${CMAKE_DL_LIBS}
         Threads::Threads
         # enable compiler warnings
         myproject_warnings
         # enable sanitizers
         myproject_options
  PRIVATE GSL spdlog::spdlog nlohmann_json::nlohmann_json)

if(RUST_FEATURES)
  target_link_libraries(${PROJECT_NAME} PUBLIC rusty_code)
endif()

if(TARGET ${PROJECT_NAME} AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC detected — module dependency flags are managed by CMake")

  if(KATAGLYPHIS_ENABLE_MODULES)
    message(STATUS "GCC modules enabled — adding -fmodules-ts to target ${PROJECT_NAME}")
    target_compile_options(${PROJECT_NAME} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fmodules-ts>)
  endif()
endif()
