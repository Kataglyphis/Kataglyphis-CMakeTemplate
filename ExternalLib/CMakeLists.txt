include(FetchContent)

message(STATUS "ExternalLib/CMakeLists: RUST_FEATURES=${RUST_FEATURES} CMAKE_CXX_COMPILER_ID=${CMAKE_CXX_COMPILER_ID}")

#include google test to project
if(BUILD_TESTING)
  FetchContent_Declare(googletest
                       URL https://github.com/google/googletest/archive/73a63ea05dc8ca29ec1d2c1d66481dd0de1950f1.zip)
  set(gtest_force_shared_crt
      ON
      CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)
endif()
#For Windows : Prevent overriding the parent project's compiler/linker settings

#We will not need to test benchmark lib itself.
set(BENCHMARK_ENABLE_TESTING
    OFF
    CACHE BOOL "Disable benchmark testing as we don't need it.")
#We will not need to test benchmark lib itself.
set(BENCHMARK_INSTALL_DOCS
    OFF
    CACHE BOOL "Disable benchmark testing as we don't need it.")
#We will not need to install benchmark since we link it statically.
set(BENCHMARK_ENABLE_INSTALL
    OFF
    CACHE BOOL "Disable benchmark install to avoid overwriting vendor install.")
set(BENCHMARK_USE_BUNDLED_GTEST
    OFF
    CACHE BOOL "Disable the bundled GTest usage.")

add_subdirectory(GOOGLE_BENCHMARK)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND BUILD_TESTING AND (CMAKE_BUILD_TYPE STREQUAL "Debug" ))

  if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang" AND NOT USE_THREAD_SANITIZER)

    message("Adding Fuzztest")

    option(
      KATAGLYPHIS_ENABLE_FUZZTEST_FUZZING_MODE
      "Build FUZZTEST in fuzzing mode (injects AddressSanitizer/coverage flags; keep OFF for normal builds)"
      ON)

    # We explicitly turn OFF FUZZTEST_FUZZING_MODE here because if it is ON,
    # the fuzztest framework adds global coverage flags to itself in its own
    # CMakeLists.txt, which causes infinite recursion with AddressSanitizer.
    set(FUZZTEST_FUZZING_MODE
        OFF
        CACHE BOOL "" FORCE)

    add_subdirectory(FUZZTEST)
  endif()
endif()

FetchContent_Declare(
  GSL
  GIT_REPOSITORY "https://github.com/microsoft/GSL"
  GIT_TAG "v4.2.1")
FetchContent_MakeAvailable(GSL)

if(myproject_DISABLE_EXCEPTIONS)
  set(SPDLOG_NO_EXCEPTIONS
      ON
      CACHE BOOL "Disable SPDLOG exceptions.")
endif()
#set spdlog options before adding it
set(SPDLOG_BUILD_EXAMPLES OFF  CACHE BOOL "Disable spdlog examples" FORCE)
set(SPDLOG_BUILD_TESTS    OFF  CACHE BOOL "Disable spdlog tests"    FORCE)
set(SPDLOG_BUILD_BENCH    OFF  CACHE BOOL "Disable spdlog bench"    FORCE)
set(SPDLOG_INSTALL        OFF  CACHE BOOL "Disable spdlog install"  FORCE)
set(SPDLOG_FMT_EXTERNAL   OFF   CACHE BOOL "Use external fmt"         FORCE)

add_subdirectory(SPDLOG)

# Enable building nlohmann.json as a C++20 module by default so consumers
# that import the module (import nlohmann.json;) get the module target.
# This is a cache variable so users can override it when configuring.
set(NLOHMANN_JSON_BUILD_MODULES
    ON
    CACHE BOOL "Build nlohmann JSON as a C++20 module.")

add_subdirectory(NLOHMANN_JSON)

# Configure nlohmann::json to build with exceptions disabled to match the
# project's exception configuration. The library checks JSON_NOEXCEPTION to
# avoid throwing, but the module provider also needs to be compiled with the
# same exception-handling compiler flags. We therefore set the preprocessor
# define and ensure the module target inherits myproject_options when
# available.
if(TARGET nlohmann_json)
  # Only disable nlohmann exceptions when the project requests exceptions be
  # disabled. The library respects the JSON_NOEXCEPTION macro to avoid
  # throwing and to switch to abort()-style behavior.
  if(DEFINED myproject_DISABLE_EXCEPTIONS AND myproject_DISABLE_EXCEPTIONS)
    # If Rust integration requires exceptions, avoid forcing exception-free
    # builds for consumers that need unwind semantics.
    if(NOT (DEFINED RUST_FEATURES) OR NOT RUST_FEATURES)
      target_compile_definitions(nlohmann_json INTERFACE JSON_NOEXCEPTION)
    else()
      message(STATUS "RUST_FEATURES=ON: keeping nlohmann::json exceptions enabled (not defining JSON_NOEXCEPTION)")
    endif()
  endif()
endif()

## tomlplusplus - header-only TOML parser
# Enable building optional C++ modules for tomlplusplus. tomlplusplus's
# modules provider requires CMake 3.28+; the top-level project already
# requires CMake 4.x so this is acceptable. Consumers can still opt-out by
# overriding the cache variable when configuring.
set(TOMLPLUSPLUS_BUILD_MODULES
    ON
    CACHE BOOL "Build tomlplusplus as a C++ module provider" FORCE)

add_subdirectory(tomlplusplus)

if(TARGET tomlplusplus_modules AND TARGET tomlplusplus_tomlplusplus)
  # Link the implementation target to the module provider so consumers get
  # the BMI when they link against the public tomlplusplus target (the
  # alias tomlplusplus::tomlplusplus forwards to tomlplusplus_tomlplusplus).
  target_link_libraries(tomlplusplus_tomlplusplus INTERFACE tomlplusplus_modules)

  # Remove the header include directories from the interface to discourage
  # header-only usage; consumers should import the module instead.
  set_target_properties(tomlplusplus_tomlplusplus PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "")
  # Ensure consumers that link against the public interface also get the
  # TOML_EXCEPTIONS compile definition so header-only usage (if any) matches
  # the module provider configuration (exceptions disabled).
  target_compile_definitions(tomlplusplus_tomlplusplus INTERFACE TOML_EXCEPTIONS=0)
endif()

# Also ensure the public interface target enforces no-exceptions for consumers
# so header-only usage compiles consistently with the module provider.
if(TARGET tomlplusplus_tomlplusplus)
  # Prefer inheriting the project's compile options (including exception handling)
  # so that BMI/module consumers and providers are built with consistent flags.
  if(TARGET myproject_options)
    target_link_libraries(tomlplusplus_tomlplusplus INTERFACE myproject_options)
  else()
    if(MSVC AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"))
      target_compile_options(tomlplusplus_tomlplusplus INTERFACE /EHs-)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
      target_compile_options(tomlplusplus_tomlplusplus INTERFACE /EHs-)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      target_compile_options(tomlplusplus_tomlplusplus INTERFACE -fno-exceptions)
    endif()
  endif()
endif()

## tomlplusplus: compile the module provider with exceptions disabled by default
## to avoid BMI/consumer configuration mismatches on MSVC/clang-cl.
## The module's own CMakeLists will also set these options; keep this here
## minimal to avoid accidentally propagating myproject_options which can
## enable exception handling.
if(TARGET tomlplusplus_modules)
  if(TARGET myproject_options)
    # Let the module provider inherit the project's options to avoid BMI
    # configuration mismatches (exception handling, sanitizer flags, etc.).
    target_link_libraries(tomlplusplus_modules PUBLIC myproject_options)
  else()
    if(MSVC AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"))
      target_compile_options(tomlplusplus_modules PUBLIC /EHs-)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
      target_compile_options(tomlplusplus_modules PUBLIC /EHs-)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      target_compile_options(tomlplusplus_modules PUBLIC -fno-exceptions)
    endif()
  endif()
  target_compile_definitions(tomlplusplus_modules PUBLIC TOML_EXCEPTIONS=0)
endif()

# Configure the nlohmann.json module provider so it is compiled with the
# same exception-handling configuration as the rest of the project. clang-cl
# rejects loading BMIs built with different /EH settings, so we explicitly
# apply the project's exception flags to the module provider target.
if(TARGET nlohmann_json_modules)
  # Prefer linking the project's options interface so compile flags are
  # inherited where CMake propagates them. This avoids BMI config mismatches
  # between module providers and consumers.
  if(TARGET myproject_options)
    target_link_libraries(nlohmann_json_modules PUBLIC myproject_options)
  endif()

  if(DEFINED myproject_DISABLE_EXCEPTIONS AND myproject_DISABLE_EXCEPTIONS)
    if(NOT (DEFINED RUST_FEATURES) OR NOT RUST_FEATURES)
      target_compile_definitions(nlohmann_json_modules PUBLIC JSON_NOEXCEPTION)
      target_compile_definitions(nlohmann_json_modules PUBLIC _HAS_EXCEPTIONS=0)
    else()
      message(STATUS "RUST_FEATURES=ON: building nlohmann_json_modules with exceptions enabled to avoid BMI config mismatch")
    endif()
  endif()

  # If myproject_options is not available (older cmake flow), fall back to
  # the previous per-compiler logic for setting exception flags.
  if(NOT TARGET myproject_options)
    # Ensure compile options match the project's myproject_DISABLE_EXCEPTIONS
    # setting; mirror the logic from ProjectOptions.cmake.
    if(DEFINED myproject_DISABLE_EXCEPTIONS AND myproject_DISABLE_EXCEPTIONS)
      if(MSVC AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"))
        if(NOT (DEFINED RUST_FEATURES) OR NOT RUST_FEATURES)
          target_compile_options(nlohmann_json_modules PUBLIC /EHs-)
          target_compile_definitions(nlohmann_json_modules PUBLIC _HAS_EXCEPTIONS=0)
        else()
          message(STATUS "RUST_FEATURES=ON: building nlohmann_json_modules with exceptions enabled on MSVC to avoid BMI config mismatch")
        endif()
      elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
        if(NOT (DEFINED RUST_FEATURES) OR NOT RUST_FEATURES)
          target_compile_options(nlohmann_json_modules PUBLIC /EHs-)
          target_compile_definitions(nlohmann_json_modules PUBLIC _HAS_EXCEPTIONS=0)
        else()
          message(STATUS "RUST_FEATURES=ON with clang-cl: building nlohmann_json_modules with exceptions enabled to avoid BMI config mismatch")
        endif()
      elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(nlohmann_json_modules PUBLIC -fno-exceptions)
        target_compile_definitions(nlohmann_json_modules PUBLIC _HAS_EXCEPTIONS=0)
      endif()
    else()
      if(MSVC AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"))
        target_compile_options(nlohmann_json_modules PUBLIC /EHsc)
      elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
        target_compile_options(nlohmann_json_modules PUBLIC /EHsc)
      elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(nlohmann_json_modules PUBLIC -fexceptions)
      endif()
    endif()
  endif()
endif()

if(RUST_FEATURES)

  FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG master)
  # Enable verbose output from Corrosion/Cargo so that cargo/rustc stdout/stderr
  # are forwarded into the CMake logs. This helps debugging Rust build failures
  # in CI by ensuring full compiler output is captured. Set as a cache variable
  # so the option inside the Corrosion subproject picks it up.
  set(CORROSION_VERBOSE_OUTPUT ON CACHE BOOL "Enable verbose output from Corrosion and Cargo" FORCE)
  message(STATUS "Corrosion verbose output enabled (CORROSION_VERBOSE_OUTPUT=ON)")
  FetchContent_MakeAvailable(Corrosion)

  find_program(CXXBRIDGE cxxbridge PATHS "$ENV{HOME}/.cargo/bin/")
  if(CXXBRIDGE STREQUAL "CXXBRIDGE-NOTFOUND")
    message("Could not find cxxbridge, trying to install with `cargo install cxxbridge-cmd'")
    find_program(CARGO cargo PATHS "$ENV{HOME}/.cargo/bin/")
    if(CARGO STREQUAL "CARGO-NOTFOUND")
      message(FATAL_ERROR "Requires cargo available in path, install via rustup https://rustup.rs/")
    endif()
    execute_process(COMMAND ${CARGO} install cxxbridge-cmd)
    find_program(CXXBRIDGE cxxbridge PATHS "$ENV{HOME}/.cargo/bin/")
  endif()

endif()

# Enforce module-only usage: make the legacy nlohmann_json interface target
# forward to the module provider. This ensures that targets linking against
# nlohmann_json will actually depend on the compiled C++ module (nlohmann_json_modules)
# instead of consuming the header-only include paths.
if(TARGET nlohmann_json_modules AND TARGET nlohmann_json)
  # Link the public interface to the module provider so consumers get the BMI
  target_link_libraries(nlohmann_json INTERFACE nlohmann_json_modules)

  # Remove the header include directories from the interface to discourage
  # header-only usage; consumers should import the module instead.
  set_target_properties(nlohmann_json PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "")
endif()
