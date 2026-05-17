set(PROJECT_SRC_DIR ${CMAKE_SOURCE_DIR}/Src/)

include(${CMAKE_SOURCE_DIR}/Test/cmake/CommonTestBuild.cmake)

set(PERF_TEST_SUITE perfTestSuite)
set(PERF_TEST_FILTER "perfSuite.cpp")

source_group("PERF_TEST_FILES" FILES ${PERF_TEST_FILTER})

kataglyphis_collect_project_sources(KataglyphisCppProject_SOURCES ${PROJECT_SRC_DIR})

add_executable(${PERF_TEST_SUITE})
kataglyphis_add_config_module_to_target(${PERF_TEST_SUITE} ${PROJECT_SRC_DIR})
kataglyphis_configure_project_test_target(${PERF_TEST_SUITE})

target_sources(${PERF_TEST_SUITE} PRIVATE ${PERF_TEST_FILTER} ${KataglyphisCppProject_SOURCES})

target_link_libraries(
  ${PERF_TEST_SUITE}
  PRIVATE benchmark::benchmark
          benchmark::benchmark_main
          GSL
          spdlog)

if(RUST_FEATURES)
  target_link_libraries(${PERF_TEST_SUITE} PUBLIC rusty_code)
endif()
add_test(NAME ${PERF_TEST_SUITE} COMMAND ${PERF_TEST_SUITE})
