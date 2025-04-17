function(myproject_enable_cache)
  # Allow selecting cache: on MSVC only sccache, otherwise ccache or sccache
  set(CACHE_OPTION "compiler_cache" CACHE STRING "Compiler cache to be used")
  if(MSVC AND WIN32)
    set(_allowed_values sccache)
  else()
    set(_allowed_values ccache sccache)
  endif()
  set_property(CACHE CACHE_OPTION PROPERTY STRINGS ${_allowed_values})

  # Validate user choice
  list(FIND _allowed_values ${CACHE_OPTION} _idx)
  if(_idx EQUAL -1)
    message(STATUS
      "Using custom compiler cache: '${CACHE_OPTION}'. Supported: ${_allowed_values}")
  endif()

  # Find the cache binary
  find_program(CACHE_BINARY
    NAMES ${CACHE_OPTION}
    DOC "Path to the compiler cache executable")

  if(CACHE_BINARY)
    message(STATUS "${CACHE_OPTION} found at ${CACHE_BINARY}. Enabling cache.")
    # Set compiler launcher
    set(CMAKE_C_COMPILER_LAUNCHER  "${CACHE_BINARY}" CACHE STRING "C compiler cache launcher")
    set(CMAKE_CXX_COMPILER_LAUNCHER"${CACHE_BINARY}" CACHE STRING "CXX compiler cache launcher")

    # For MSVC: embed debug info for cache-friendly PDBs
    if(MSVC)
      # Requires CMake >=3.25
      if(POLICY CMP0141)
        cmake_policy(SET CMP0141 NEW)
        set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded CACHE STRING "Cache-friendly debug info format")
        message(STATUS "Configured MSVC to embed PDB info (/Z7) for cache consistency.")
      else()
        # Fallback: manual flag replacement for older CMake
        string(REPLACE "/Zi" "/Z7" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
        string(REPLACE "/Zi" "/Z7" CMAKE_C_FLAGS_DEBUG   "${CMAKE_C_FLAGS_DEBUG}")
        message(STATUS "Replaced /Zi with /Z7 in debug flags for cache consistency.")
      endif()
    endif()
  else()
    message(WARNING
      "${CACHE_OPTION} is enabled but not found (searched: ${_allowed_values}). Skipping cache integration.")
  endif()
endfunction()
