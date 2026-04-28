include(GoogleTest)

if(NOT CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
  message(STATUS "Fuzz testing enabled for ${CMAKE_SYSTEM_NAME} (${CMAKE_CXX_COMPILER_ID})")

  if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      add_executable(first_fuzz_test dummy.cpp)

      if(KATAGLYPHIS_ENABLE_FUZZTEST_FUZZING_MODE OR (FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer"))
        target_compile_options(
          first_fuzz_test
          PRIVATE -g
                  -UNDEBUG
                  -fsanitize=address
                  -fsanitize-coverage=inline-8bit-counters
                  -fsanitize-coverage=trace-cmp)
        target_compile_definitions(first_fuzz_test PRIVATE FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION ADDRESS_SANITIZER)
        target_link_options(first_fuzz_test PRIVATE -fsanitize=address)
      endif()

      if(FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer")
        target_compile_options(first_fuzz_test PRIVATE -fsanitize=fuzzer-no-link)
        target_compile_definitions(first_fuzz_test PRIVATE FUZZTEST_COMPATIBILITY_MODE)
      endif()

      link_fuzztest(first_fuzz_test)
      gtest_discover_tests(first_fuzz_test)

    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows" AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      add_executable(first_fuzz_test dummy_windows.cpp)

      if(FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer" OR KATAGLYPHIS_ENABLE_FUZZTEST_FUZZING_MODE)
        target_compile_options(
          first_fuzz_test
          PRIVATE /fsanitize=address
                  /fsanitize-coverage=inline-8bit-counters
                  /fsanitize-coverage=trace-cmp
                  /Z7
                  /Od)
        target_compile_definitions(first_fuzz_test PRIVATE FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION ADDRESS_SANITIZER)
        target_link_options(first_fuzz_test PRIVATE /fsanitize=address /INCREMENTAL:NO)
      endif()

      target_link_libraries(first_fuzz_test PRIVATE gtest gtest_main)
      gtest_discover_tests(first_fuzz_test)
    endif()
  endif()
endif()