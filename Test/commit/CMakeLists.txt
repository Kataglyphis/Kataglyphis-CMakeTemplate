include(GoogleTest)
include(${CMAKE_SOURCE_DIR}/Test/cmake/CommonTestBuild.cmake)

set(COMMIT_TEST_SUITE commitTestSuite)

file(GLOB_RECURSE KataglyphisCppProject_COMMIT_TEST_FILTER "*.cpp")

add_executable(${COMMIT_TEST_SUITE} ${KataglyphisCppProject_COMMIT_TEST_FILTER})
kataglyphis_configure_project_test_target(${COMMIT_TEST_SUITE})

target_link_libraries(
  ${COMMIT_TEST_SUITE}
  PRIVATE KataglyphisCppProject_Lib
          gtest
          gtest_main
          GSL
          spdlog)

kataglyphis_configure_gtest_discovery(${COMMIT_TEST_SUITE})

if(RUST_FEATURES)
  target_link_libraries(${COMMIT_TEST_SUITE} PUBLIC rusty_code)
endif()
