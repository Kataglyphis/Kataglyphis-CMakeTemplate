include(FetchContent)

# include google test to project
FetchContent_Declare(googletest
                     URL https://github.com/google/googletest/archive/df1544bcee0c7ce35cd5ea0b3eb8cc81855a4140.zip)

# For Windows: Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt
    ON
    CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

# We will not need to test benchmark lib itself.
set(BENCHMARK_ENABLE_TESTING
    OFF
    CACHE BOOL "Disable benchmark testing as we don't need it.")
# We will not need to test benchmark lib itself.
set(BENCHMARK_INSTALL_DOCS
    OFF
    CACHE BOOL "Disable benchmark testing as we don't need it.")
# We will not need to install benchmark since we link it statically.
set(BENCHMARK_ENABLE_INSTALL
    OFF
    CACHE BOOL "Disable benchmark install to avoid overwriting vendor install.")
set(BENCHMARK_USE_BUNDLED_GTEST
    OFF
    CACHE BOOL "Disable the bundled GTest usage.")

add_subdirectory(GOOGLE_BENCHMARK)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(STATUS "This is a Linux system.")
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    message("Adding Fuzztest")
    add_subdirectory(FUZZTEST)
    if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
      set(FUZZTEST_FUZZING_MODE
          ON
          CACHE BOOL "" FORCE)
    endif()
  endif()
endif()

FetchContent_Declare(
  GSL
  GIT_REPOSITORY "https://github.com/microsoft/GSL"
  GIT_TAG "v4.1.0")
FetchContent_MakeAvailable(GSL)

if(myproject_DISABLE_EXCEPTIONS)
  set(SPDLOG_NO_EXCEPTIONS
      ON
      CACHE BOOL "Disable SPDLOG exceptions.")
endif()

add_subdirectory(SPDLOG)

add_subdirectory(NLOHMANN_JSON)

if(RUST_FEATURES)
  FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG master)
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
