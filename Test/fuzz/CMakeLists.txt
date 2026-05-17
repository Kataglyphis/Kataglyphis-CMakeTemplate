include(${CMAKE_SOURCE_DIR}/cmake/BuildTypeHelpers.cmake)
include(GoogleTest)
include(${CMAKE_SOURCE_DIR}/Test/cmake/CommonTestBuild.cmake)

if(NOT MYPROJECT_BUILD_IS_RELWITHDEBINFO)
  message(STATUS "Fuzz testing enabled for ${CMAKE_SYSTEM_NAME} (${CMAKE_CXX_COMPILER_ID})")

  if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Windows")
      add_executable(first_fuzz_test dummy.cpp)

      if(CMAKE_SYSTEM_NAME STREQUAL "Windows" AND FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer")
        message(FATAL_ERROR "FUZZTEST_COMPATIBILITY_MODE=libfuzzer is not supported on Windows clang-cl.")
      endif()

      if(KATAGLYPHIS_ENABLE_FUZZTEST_FUZZING_MODE OR (FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer"))
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
          target_compile_options(
            first_fuzz_test
            PRIVATE -g
                    -UNDEBUG
                    -fsanitize=address
                    -fsanitize-coverage=inline-8bit-counters
                    -fsanitize-coverage=trace-cmp)
          target_compile_definitions(first_fuzz_test PRIVATE FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION ADDRESS_SANITIZER)
          target_link_options(first_fuzz_test PRIVATE -fsanitize=address)
        elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
          target_compile_options(
            first_fuzz_test
            PRIVATE /fsanitize=address
                    /fsanitize-coverage=inline-8bit-counters
                    /fsanitize-coverage=trace-cmp
                    /Z7
                    /Od)
          target_compile_definitions(first_fuzz_test PRIVATE FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION ADDRESS_SANITIZER)
          target_link_options(
            first_fuzz_test
            PRIVATE
            /fsanitize=address
            /INCREMENTAL:NO)
        endif()
      endif()

      if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND FUZZTEST_COMPATIBILITY_MODE STREQUAL "libfuzzer")
        target_compile_options(first_fuzz_test PRIVATE -fsanitize=fuzzer-no-link)
        target_compile_definitions(first_fuzz_test PRIVATE FUZZTEST_COMPATIBILITY_MODE)
      endif()

      link_fuzztest(first_fuzz_test)
      kataglyphis_configure_gtest_discovery(first_fuzz_test)
    endif()
  endif()
endif()
