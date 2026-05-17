# update current positions
set(PROJECT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(PROJECT_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(EXTERNAL_LIB_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../ExternalLib/)

file(GLOB_RECURSE KataglyphisCppProject_SOURCES "*.cpp")
file(GLOB_RECURSE KataglyphisCppProject_HEADERS "*.hpp")
set(KATAGLYPHIS_MAIN_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/Main.cpp")
list(REMOVE_ITEM KataglyphisCppProject_SOURCES "${KATAGLYPHIS_MAIN_SOURCE}")
source_group("main" FILES "${KATAGLYPHIS_MAIN_SOURCE}")

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

add_executable(${PROJECT_NAME} Main.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE ${KATAGLYPHIS_CORE_TARGET})

if(TARGET nlohmann_json_modules)
  target_link_libraries(${PROJECT_NAME} PRIVATE nlohmann_json_modules)
endif()

if(TARGET tomlplusplus_modules)
  target_link_libraries(${PROJECT_NAME} PRIVATE tomlplusplus_modules)
endif()

if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /EHsc)
endif()

install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION bin)

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

endif()

# Configure Rust if enabled (outside GNU block so it applies to clang-cl/MSVC too)
if(RUST_FEATURES)
  set(RUSTY_MANIFEST_PATH
      "${CMAKE_CURRENT_SOURCE_DIR}/rusty_code/Cargo.toml"
      CACHE PATH "Path to the Rust crate Cargo.toml to import")
  set(RUSTY_CRATE_NAME
      "rusty_code"
      CACHE STRING "Name of the Rust crate target")

  corrosion_import_crate(
    MANIFEST_PATH
    ${RUSTY_MANIFEST_PATH}
    CRATE_TYPES
    staticlib
    CRATES
    ${RUSTY_CRATE_NAME})

  if(ENABLE_RUST_CXXBRIDGE)
    corrosion_add_cxxbridge(
      rusty_bridge
      CRATE
      ${RUSTY_CRATE_NAME}
      FILES
      lib.rs)
    target_include_directories(${KATAGLYPHIS_CORE_TARGET}
                               PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/corrosion_generated/cxxbridge/rusty_bridge/include")
    add_dependencies(${KATAGLYPHIS_CORE_TARGET} rusty_bridge)
  endif()
  target_link_libraries(${KATAGLYPHIS_CORE_TARGET} PUBLIC rusty_code)

  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
    message(STATUS "Detected clang-cl; instructing Corrosion to use clang-cl for crate builds")
    corrosion_set_env_vars(${RUSTY_CRATE_NAME} CC_x86_64-pc-windows-msvc=clang-cl CXX_x86_64-pc-windows-msvc=clang-cl)
  endif()
endif()

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

# Ensure the core library is fully compiled (including its module BMI) before
# compiling the executable. clang-cl may schedule Main.cpp compilation before
# the kataglyphis_core module is available, causing "module not found" errors.
add_dependencies(${PROJECT_NAME} ${KATAGLYPHIS_CORE_TARGET})
