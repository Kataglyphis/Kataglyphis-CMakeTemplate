include(GoogleTest)
include(${CMAKE_SOURCE_DIR}/Test/cmake/CommonTestBuild.cmake)

set(COMPILE_TEST_SUITE compileTestSuite)

file(GLOB_RECURSE KataglyphisCppProject_COMPILE_TEST_FILTER "*.cpp")

add_executable(${COMPILE_TEST_SUITE} ${KataglyphisCppProject_COMPILE_TEST_FILTER})
kataglyphis_configure_project_test_target(${COMPILE_TEST_SUITE})

target_link_libraries(
  ${COMPILE_TEST_SUITE}
  PRIVATE KataglyphisCppProject_Lib
          gtest_main
          gtest
          GSL
          spdlog)

kataglyphis_configure_gtest_discovery(${COMPILE_TEST_SUITE})
