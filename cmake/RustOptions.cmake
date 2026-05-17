# This module centralizes Rust-related configuration.
# It handles `RUST_FEATURES`, Cargo environment variables, and `cxxbridge` setup.

macro(myproject_configure_rust)
  include(FetchContent)
  # Ensure Corrosion and cxxbridge are available when Rust features are enabled.
  if(WIN32)
    # Use cargo wrapper script that retries transient Windows file-lock failures
    set(Rust_CARGO
        "${CMAKE_SOURCE_DIR}/scripts/windows/cargo-retry.cmd"
        CACHE FILEPATH "Cargo wrapper used to retry transient Windows file-lock failures" FORCE)
  endif()

  FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG master)
  FetchContent_MakeAvailable(Corrosion)
endmacro()
