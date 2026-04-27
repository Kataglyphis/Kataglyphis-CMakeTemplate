function(myproject_enable_coverage project_name)
  # Restrict coverage instrumentation to Debug builds only. Enabling
  # profile/coverage instrumentation for RelWithDebInfo/Release can
  # interact poorly with LTO/IPO and sanitizers; keep coverage confined
  # to Debug where tooling and runtime expectations are predictable.
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      message(" -- ** Enabling coverage reporting (gcov-style)**")
      target_compile_options(${project_name} INTERFACE --coverage -O0 -g)
      target_link_libraries(${project_name} INTERFACE --coverage)
      # second case covers clang-cl
    elseif(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang" OR (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND MSVC))
      message(" -- ** Enabling coverage reporting (clang source-based)**")
      target_compile_options(${project_name} INTERFACE -fprofile-instr-generate -fcoverage-mapping)
      target_link_libraries(${project_name} INTERFACE -fprofile-instr-generate -fcoverage-mapping)
    endif()
  else()
    message(STATUS "Coverage instrumentation is enabled only for Debug builds; skipping for ${CMAKE_BUILD_TYPE}.")
  endif()
endfunction()
