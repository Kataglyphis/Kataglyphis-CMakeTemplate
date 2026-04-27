include(CMakeDependentOption)
include(CheckCXXCompilerFlag)

macro(myproject_supports_sanitizers)
  # AddressSanitizer support: Generally Clang/GNU, or Clang-cl (MSVC with Clang frontend)
  if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*")
    set(SUPPORTS_ASAN ON)
  else()
    set(SUPPORTS_ASAN OFF)
  endif()

  # UndefinedBehaviorSanitizer support: Generally Clang/GNU, not typically on MSVC/Clang-cl
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT MSVC)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()
endmacro()

macro(myproject_setup_options)
  option(myproject_ENABLE_HARDENING "Enable hardening" ON)
  option(myproject_ENABLE_COVERAGE "Enable coverage reporting" ON)
  option(myproject_DISABLE_EXCEPTIONS "Disable C++ exceptions" ON)
  option(myproject_ENABLE_GPROF "Enable profiling with gprof or gperftools (RelWithDebInfo on Linux)" OFF)
  # for now disable global hardening, as it is not supported by all dependencies
  option(myproject_ENABLE_GLOBAL_HARDENING "Enable global hardening for all dependencies" OFF)

  myproject_supports_sanitizers()

  option(USE_THREAD_SANITIZER "Use ThreadSanitizer instead of Address/UndefinedBehavior Sanitizer" OFF)

  if(CMAKE_BUILD_TYPE STREQUAL "Debug" AND NOT USE_THREAD_SANITIZER)
    set(DEFAULT_ASAN ${SUPPORTS_ASAN})
    set(DEFAULT_UBSAN ${SUPPORTS_UBSAN})
    set(DEFAULT_TSAN OFF)
  elseif(USE_THREAD_SANITIZER)
    set(DEFAULT_ASAN OFF)
    set(DEFAULT_UBSAN OFF)
    set(DEFAULT_TSAN ON)
  else()
    set(DEFAULT_ASAN OFF)
    set(DEFAULT_UBSAN OFF)
    set(DEFAULT_TSAN OFF)
  endif()

  option(myproject_ENABLE_IPO "Enable IPO/LTO" ON)
  option(myproject_ENABLE_STATIC_ANALYZER "Enable Static Analyzer" OFF)
  option(myproject_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
  option(myproject_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${DEFAULT_ASAN})
  option(myproject_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
  option(myproject_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${DEFAULT_UBSAN})
  option(myproject_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" ${DEFAULT_TSAN})
  option(myproject_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
  option(myproject_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
  option(myproject_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
  option(myproject_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
  option(myproject_ENABLE_PCH "Enable precompiled headers" OFF)
  option(myproject_ENABLE_CACHE "Enable ccache" ON)
  option(myproject_ENABLE_IWYU "Enable IWYU" ON)

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      myproject_ENABLE_IPO
      myproject_ENABLE_STATIC_ANALYZER
      myproject_WARNINGS_AS_ERRORS
      myproject_ENABLE_SANITIZER_ADDRESS
      myproject_ENABLE_SANITIZER_LEAK
      myproject_ENABLE_SANITIZER_UNDEFINED
      myproject_ENABLE_SANITIZER_THREAD
      myproject_ENABLE_SANITIZER_MEMORY
      myproject_ENABLE_UNITY_BUILD
      myproject_ENABLE_CLANG_TIDY
      myproject_ENABLE_CPPCHECK
      myproject_ENABLE_COVERAGE
      myproject_ENABLE_PCH
      myproject_ENABLE_CACHE
      myproject_DISABLE_EXCEPTIONS)
  endif()

endmacro()

macro(myproject_global_options)

  # specify the C/C++ standard
  set(CMAKE_CXX_STANDARD 23)
  set(CMAKE_CXX_STANDARD_REQUIRED True)

  set(CMAKE_C_STANDARD 17)
  set(CMAKE_C_STANDARD_REQUIRED True)

  set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

  # set build type specific flags
  if(MSVC AND NOT (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"))
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} /DEBUG /Od /std:c++23preview")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /O2 /GL /std:c++23preview")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O0 -std=c++23 -ggdb")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -std=c++23 -DNDEBUG")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC)
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}  /Od")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /O2  -DNDEBUG")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O0 -g -ggdb -std=c++23 -fcolor-diagnostics")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG -std=c++23 -fcolor-diagnostics")
  endif()

  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR})
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR})
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR})

  if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_LINK_WHAT_YOU_USE FALSE)
  else()
    set(CMAKE_LINK_WHAT_YOU_USE TRUE)
  endif()

  if(myproject_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    if(NOT (CMAKE_BUILD_TYPE STREQUAL "Debug"))
      myproject_enable_ipo()
    endif()
  endif()

  myproject_supports_sanitizers()

  if(myproject_ENABLE_HARDENING AND myproject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    # ENABLE_UBSAN_MINIMAL_RUNTIME is always set to FALSE below, so the preceding logic is redundant.
    set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)

    myproject_enable_hardening(myproject_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(myproject_local_options)

  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(myproject_warnings INTERFACE)
  add_library(myproject_options INTERFACE)

  target_compile_features(myproject_options INTERFACE cxx_std_${CMAKE_CXX_STANDARD})

  include(cmake/CompilerWarnings.cmake)
  myproject_set_project_warnings(
    myproject_warnings
    ${myproject_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(myproject_ENABLE_GPROF
     AND CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo"
     AND (CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
     AND NOT WIN32)

    find_library(PROFILER_LIB profiler)

  elseif(myproject_ENABLE_GPROF)

  endif()

  if(myproject_DISABLE_EXCEPTIONS)

  else()

  endif()

  if(RUST_FEATURES AND MSVC)
    target_compile_options(myproject_options INTERFACE /EHsc)
  endif()

  if(NOT
     CMAKE_BUILD_TYPE
     STREQUAL
     "Release")
    include(cmake/Sanitizers.cmake)
    myproject_enable_sanitizers(
      myproject_options
      ${myproject_ENABLE_SANITIZER_ADDRESS}
      ${myproject_ENABLE_SANITIZER_LEAK}
      ${myproject_ENABLE_SANITIZER_UNDEFINED}
      ${myproject_ENABLE_SANITIZER_THREAD}
      ${myproject_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(myproject_options PROPERTIES UNITY_BUILD ${myproject_ENABLE_UNITY_BUILD})

  if(myproject_ENABLE_PCH)
    target_precompile_headers(
      myproject_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(myproject_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    myproject_enable_cache()
  endif()

  if(NOT
     CMAKE_BUILD_TYPE
     STREQUAL
     "Release")
    include(cmake/StaticAnalyzers.cmake)
    if(myproject_ENABLE_CLANG_TIDY)
      myproject_enable_clang_tidy(myproject_options ${myproject_WARNINGS_AS_ERRORS})
    endif()

    if(myproject_ENABLE_CPPCHECK)
      myproject_enable_cppcheck(${myproject_WARNINGS_AS_ERRORS} "" # override cppcheck options
      )
    endif()

    if(myproject_ENABLE_COVERAGE)
      include(cmake/Tests.cmake)
      myproject_enable_coverage(myproject_options)
    endif()
  endif()

  if(myproject_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(myproject_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(myproject_ENABLE_HARDENING AND NOT myproject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    # ENABLE_UBSAN_MINIMAL_RUNTIME is always set to FALSE below, so the preceding logic is redundant.
    set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    myproject_enable_hardening(myproject_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

  if(NOT
     CMAKE_BUILD_TYPE
     STREQUAL
     "Release")

    include(cmake/Doxygen.cmake)
    enable_doxygen()

  endif()

  include(cmake/Speedup.cmake)

endmacro()
