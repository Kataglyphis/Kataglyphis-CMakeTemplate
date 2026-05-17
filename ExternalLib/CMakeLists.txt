include(FetchContent)

include(${CMAKE_SOURCE_DIR}/cmake/BuildTypeHelpers.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/CompilerConfigHelpers.cmake)

if(BUILD_TESTING)
  FetchContent_Declare(googletest
                       GIT_REPOSITORY https://github.com/google/googletest.git
                       GIT_TAG d72f9c8aea6817cdf1ca0ac10887f328de7f3da2)
  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)
endif()

set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "Disable benchmark testing as we don't need it.")
set(BENCHMARK_INSTALL_DOCS OFF CACHE BOOL "Disable benchmark testing as we don't need it.")
set(BENCHMARK_ENABLE_INSTALL OFF CACHE BOOL "Disable benchmark install to avoid overwriting vendor install.")
set(BENCHMARK_USE_BUNDLED_GTEST OFF CACHE BOOL "Disable the bundled GTest usage.")

add_subdirectory(GOOGLE_BENCHMARK)

set(_kataglyphis_enable_fuzztest FALSE)
if(BUILD_TESTING
   AND MYPROJECT_BUILD_IS_DEBUG
   AND CMAKE_CXX_COMPILER_ID MATCHES ".*Clang"
   AND NOT USE_THREAD_SANITIZER
   AND (CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Windows"))
  set(_kataglyphis_enable_fuzztest TRUE)
endif()

if(_kataglyphis_enable_fuzztest)
  if(CMAKE_SYSTEM_NAME STREQUAL "Windows" AND FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer")
    message(FATAL_ERROR "FUZZTEST_COMPATIBILITY_MODE=libfuzzer is not supported on Windows clang-cl.")
  endif()

  set(_kataglyphis_default_fuzztest_fuzzing_mode OFF)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(_kataglyphis_default_fuzztest_fuzzing_mode ON)
  endif()

  option(KATAGLYPHIS_ENABLE_FUZZTEST_FUZZING_MODE
         "Build FUZZTEST in fuzzing mode (injects AddressSanitizer/coverage flags; keep OFF for normal builds)"
         ${_kataglyphis_default_fuzztest_fuzzing_mode})
  set(FUZZTEST_FUZZING_MODE OFF CACHE BOOL "" FORCE)
  add_subdirectory(FUZZTEST)
endif()

FetchContent_Declare(GSL GIT_REPOSITORY "https://github.com/microsoft/GSL" GIT_TAG "v4.2.1")
FetchContent_MakeAvailable(GSL)

FetchContent_Declare(abseil-cpp GIT_REPOSITORY https://github.com/abseil/abseil-cpp.git GIT_TAG 20260107.1)
FetchContent_MakeAvailable(abseil-cpp)

if(myproject_DISABLE_EXCEPTIONS)
  set(SPDLOG_NO_EXCEPTIONS ON CACHE BOOL "Disable SPDLOG exceptions.")
endif()
set(SPDLOG_BUILD_EXAMPLES OFF CACHE BOOL "Disable spdlog examples" FORCE)
set(SPDLOG_BUILD_TESTS OFF CACHE BOOL "Disable spdlog tests" FORCE)
set(SPDLOG_BUILD_BENCH OFF CACHE BOOL "Disable spdlog bench" FORCE)
set(SPDLOG_INSTALL OFF CACHE BOOL "Disable spdlog install" FORCE)
set(SPDLOG_FMT_EXTERNAL OFF CACHE BOOL "Use external fmt" FORCE)

add_subdirectory(SPDLOG)

set(NLOHMANN_JSON_BUILD_MODULES ON CACHE BOOL "Build nlohmann JSON as a C++20 module.")
add_subdirectory(NLOHMANN_JSON)

if(TARGET nlohmann_json AND DEFINED myproject_DISABLE_EXCEPTIONS AND myproject_DISABLE_EXCEPTIONS)
  if(NOT (DEFINED RUST_FEATURES AND RUST_FEATURES))
    target_compile_definitions(nlohmann_json INTERFACE JSON_NOEXCEPTION)
  endif()
endif()

set(TOMLPLUSPLUS_BUILD_MODULES ON CACHE BOOL "Build tomlplusplus as a C++ module provider" FORCE)
add_subdirectory(tomlplusplus)

if(TARGET tomlplusplus_modules AND TARGET tomlplusplus_tomlplusplus)
  set_target_properties(tomlplusplus_tomlplusplus PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "")
  target_compile_definitions(tomlplusplus_tomlplusplus INTERFACE TOML_EXCEPTIONS=0)
endif()

if(TARGET tomlplusplus_tomlplusplus)
  if(TARGET myproject_options)
    target_link_libraries(tomlplusplus_tomlplusplus INTERFACE myproject_options)
  else()
    myproject_configure_target_exceptions(tomlplusplus_tomlplusplus)
  endif()
endif()

if(TARGET tomlplusplus_modules)
  if(TARGET myproject_options)
    target_link_libraries(tomlplusplus_modules PUBLIC myproject_options)
  else()
    myproject_configure_target_exceptions(tomlplusplus_modules)
  endif()
  target_compile_definitions(tomlplusplus_modules PUBLIC TOML_EXCEPTIONS=0)
endif()

if(TARGET nlohmann_json_modules)
  if(TARGET myproject_options)
    target_link_libraries(nlohmann_json_modules PUBLIC myproject_options)
  endif()
  if(DEFINED myproject_DISABLE_EXCEPTIONS AND myproject_DISABLE_EXCEPTIONS)
    if(NOT (DEFINED RUST_FEATURES AND RUST_FEATURES))
      target_compile_definitions(nlohmann_json_modules PUBLIC JSON_NOEXCEPTION _HAS_EXCEPTIONS=0)
    endif()
  endif()
endif()

if(TARGET nlohmann_json_modules AND TARGET nlohmann_json)
  set_target_properties(nlohmann_json PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "")
endif()
