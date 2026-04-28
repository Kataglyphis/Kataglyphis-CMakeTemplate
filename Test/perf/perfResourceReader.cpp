#include <benchmark/benchmark.h>
#include <string>
#include <sstream>

import kataglyphis_config;
import kataglyphis_resources;

using namespace kataglyphis::resources;

static void BM_JsonParseSmallString(benchmark::State& state)
{
    const std::string json_string = R"({"key": "value", "number": 42})";
    for (auto _ : state) {
        auto json_obj = ResourceReader::read_json_string(json_string);
        benchmark::DoNotOptimize(json_obj);
    }
}
BENCHMARK(BM_JsonParseSmallString);

static void BM_JsonParseMediumString(benchmark::State& state)
{
    const std::string json_string = R"({
        "application": {
            "name": "Kataglyphis",
            "version": "1.0.0",
            "settings": {
                "width": 800,
                "height": 600,
                "fullscreen": false
            }
        },
        "items": ["a", "b", "c", "d", "e"],
        "count": 100
    })";
    for (auto _ : state) {
        auto json_obj = ResourceReader::read_json_string(json_string);
        benchmark::DoNotOptimize(json_obj);
    }
}
BENCHMARK(BM_JsonParseMediumString);

static void BM_JsonGetString(benchmark::State& state)
{
    auto json_obj = ResourceReader::read_json_string(R"({"key": "test_value", "number": 42})");
    for (auto _ : state) {
        auto result = ResourceReader::json_get_string(json_obj, "key");
        benchmark::DoNotOptimize(result);
    }
}
BENCHMARK(BM_JsonGetString);

static void BM_JsonGetInt(benchmark::State& state)
{
    auto json_obj = ResourceReader::read_json_string(R"({"key": "test_value", "number": 42})");
    for (auto _ : state) {
        auto result = ResourceReader::json_get_int(json_obj, "number");
        benchmark::DoNotOptimize(result);
    }
}
BENCHMARK(BM_JsonGetInt);

static void BM_TomlParseSmallString(benchmark::State& state)
{
    const std::string toml_string = R"(
        name = "test"
        value = 42
    )";
    for (auto _ : state) {
        auto tbl = ResourceReader::read_toml_string(toml_string);
        benchmark::DoNotOptimize(tbl);
    }
}
BENCHMARK(BM_TomlParseSmallString);

static void BM_TomlParseMediumString(benchmark::State& state)
{
    const std::string toml_string = R"(
        [application]
        name = "Kataglyphis"
        version = "1.0.0"

        [application.settings]
        width = 800
        height = 600
        fullscreen = false

        items = ["a", "b", "c", "d", "e"]
        count = 100
    )";
    for (auto _ : state) {
        auto tbl = ResourceReader::read_toml_string(toml_string);
        benchmark::DoNotOptimize(tbl);
    }
}
BENCHMARK(BM_TomlParseMediumString);

static void BM_TomlGetString(benchmark::State& state)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        name = "test_value"
        value = 42
    )");
    for (auto _ : state) {
        auto result = ResourceReader::toml_get_string(tbl, "name");
        benchmark::DoNotOptimize(result);
    }
}
BENCHMARK(BM_TomlGetString);

static void BM_TomlGetInt(benchmark::State& state)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        name = "test_value"
        value = 42
    )");
    for (auto _ : state) {
        auto result = ResourceReader::toml_get_int(tbl, "value");
        benchmark::DoNotOptimize(result);
    }
}
BENCHMARK(BM_TomlGetInt);

static void BM_TomlNestedTableAccess(benchmark::State& state)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        [application]
        name = "Kataglyphis"
        version = "1.0.0"

        [application.settings]
        width = 800
        height = 600
    )");
    for (auto _ : state) {
        auto app_table = ResourceReader::toml_get_table(tbl, "application");
        auto name = ResourceReader::toml_get_string(app_table, "name");
        auto settings = ResourceReader::toml_get_table(app_table, "settings");
        auto width = ResourceReader::toml_get_int(settings, "width");
        benchmark::DoNotOptimize(name);
        benchmark::DoNotOptimize(width);
    }
}
BENCHMARK(BM_TomlNestedTableAccess);

BENCHMARK_MAIN();
