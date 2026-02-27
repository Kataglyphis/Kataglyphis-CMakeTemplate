#include <benchmark/benchmark.h>

#include "KataglyphisCppProjectConfig.hpp"


static void BM_StringCreation(benchmark::State &state)
{
    for (auto _ : state) {
        std::string empty_string;
        auto renderer_version_minor = kataglyphis::config::renderer_version_minor;
        benchmark::DoNotOptimize(empty_string);
        benchmark::DoNotOptimize(renderer_version_minor);
    }
}
// Register the function as a benchmark
BENCHMARK(BM_StringCreation);

// Define another benchmark
static void BM_StringCopy(benchmark::State &state)
{
    std::string x = "hello";
    for (auto _ : state) std::string copy(x);
}
BENCHMARK(BM_StringCopy);

BENCHMARK_MAIN();