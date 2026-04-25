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

  corrosion_import_crate(MANIFEST_PATH rusty_code/Cargo.toml)
  # Disable sccache for the rust crate build to avoid stale file handles on
  # Windows that can prevent Cargo from removing temporary archives
  # (observed as "os error 32" on temp-archive removal). This keeps the build
  # environment deterministic and reduces file-locking races with external
  # caching wrappers.
  if(WIN32)
    corrosion_set_env_vars(rusty_code CXXFLAGS=/EHsc SCCACHE_DISABLE=1)
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
      rusty_code
      CC=${RUST_CC}
      CXX=${RUST_CXX}
      "CXXFLAGS=${RUST_CXXFLAGS}"
      SCCACHE_DISABLE=1)

    message(STATUS "Configured native corrosion: CC=${RUST_CC} CXX=${RUST_CXX} CXXFLAGS=${RUST_CXXFLAGS}")
  endif()

  corrosion_add_cxxbridge(
    rusty_bridge
    CRATE
    rusty_code
    FILES
    lib.rs)

endif()

set(KATAGLYPHIS_CORE_TARGET ${PROJECT_NAME})

add_executable(${KATAGLYPHIS_CORE_TARGET} "${KATAGLYPHIS_MAIN_SOURCE}")

if(RUST_FEATURES)
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC USE_RUST=1)
else()
  target_compile_definitions(${KATAGLYPHIS_CORE_TARGET} PUBLIC USE_RUST=0)
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
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC rusty_code)
endif()

if(TARGET ${KATAGLYPHIS_CORE_TARGET} AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  message(STATUS "GCC detected — module dependency flags are managed by CMake")

  message(STATUS "GCC modules enabled — adding -fmodules-ts to target ${KATAGLYPHIS_CORE_TARGET}")
  target_compile_options(${KATAGLYPHIS_CORE_TARGET} PUBLIC $<$<COMPILE_LANGUAGE:CXX>:-fmodules-ts>)
endif()
