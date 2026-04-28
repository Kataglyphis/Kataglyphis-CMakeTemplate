#include <gtest/gtest.h>
#include <filesystem>
#include <string>

import kataglyphis_config;
import kataglyphis_core;
import kataglyphis_resources;

using namespace kataglyphis::resources;

TEST(ResourceReaderTest, JsonParseString)
{
    auto json_obj = ResourceReader::read_json_string(R"({"key": "value", "number": 42})");
    EXPECT_TRUE(ResourceReader::json_has_key(json_obj, "key"));
    EXPECT_EQ(ResourceReader::json_get_string(json_obj, "key"), "value");
    EXPECT_TRUE(ResourceReader::json_has_key(json_obj, "number"));
    EXPECT_EQ(ResourceReader::json_get_int(json_obj, "number"), 42);
}

TEST(ResourceReaderTest, JsonGetDifferentTypes)
{
    auto json_obj = ResourceReader::read_json_string(R"({
        "string_val": "hello",
        "int_val": 123,
        "bool_val": true,
        "double_val": 3.14
    })");

    EXPECT_EQ(ResourceReader::json_get_string(json_obj, "string_val"), "hello");
    EXPECT_EQ(ResourceReader::json_get_int(json_obj, "int_val"), 123);
    EXPECT_EQ(ResourceReader::json_get_bool(json_obj, "bool_val"), true);
    EXPECT_DOUBLE_EQ(ResourceReader::json_get_double(json_obj, "double_val"), 3.14);
}

TEST(ResourceReaderTest, JsonMissingKey)
{
    auto json_obj = ResourceReader::read_json_string(R"({"existing": "value"})");
    EXPECT_FALSE(ResourceReader::json_has_key(json_obj, "nonexistent"));
    EXPECT_THROW(ResourceReader::json_get_string(json_obj, "nonexistent"), std::runtime_error);
}

TEST(ResourceReaderTest, TomlParseString)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        name = "test"
        value = 42
    )");

    EXPECT_TRUE(ResourceReader::toml_has_key(tbl, "name"));
    EXPECT_EQ(ResourceReader::toml_get_string(tbl, "name"), "test");
    EXPECT_TRUE(ResourceReader::toml_has_key(tbl, "value"));
    EXPECT_EQ(ResourceReader::toml_get_int(tbl, "value"), 42);
}

TEST(ResourceReaderTest, TomlGetDifferentTypes)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        string_val = "hello"
        int_val = 123
        bool_val = true
        double_val = 2.718
    )");

    EXPECT_EQ(ResourceReader::toml_get_string(tbl, "string_val"), "hello");
    EXPECT_EQ(ResourceReader::toml_get_int(tbl, "int_val"), 123);
    EXPECT_EQ(ResourceReader::toml_get_bool(tbl, "bool_val"), true);
    EXPECT_DOUBLE_EQ(ResourceReader::toml_get_double(tbl, "double_val"), 2.718);
}

TEST(ResourceReaderTest, TomlMissingKey)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        existing = "value"
    )");
    EXPECT_FALSE(ResourceReader::toml_has_key(tbl, "nonexistent"));
    EXPECT_THROW(ResourceReader::toml_get_string(tbl, "nonexistent"), std::runtime_error);
}

TEST(ResourceReaderTest, TomlNestedTable)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        [application]
        name = "MyApp"
        version = "1.0.0"
    )");

    EXPECT_TRUE(ResourceReader::toml_has_key(tbl, "application"));
    auto app_table = ResourceReader::toml_get_table(tbl, "application");
    EXPECT_EQ(ResourceReader::toml_get_string(app_table, "name"), "MyApp");
    EXPECT_EQ(ResourceReader::toml_get_string(app_table, "version"), "1.0.0");
}

TEST(ResourceReaderTest, JsonNestedObject)
{
    auto json_obj = ResourceReader::read_json_string(R"({
        "application": {
            "name": "MyApp",
            "version": "1.0.0"
        }
    })");

    EXPECT_TRUE(ResourceReader::json_has_key(json_obj, "application"));
    EXPECT_TRUE(json_obj["application"].is_object());
    auto& app_obj = json_obj["application"];
    EXPECT_EQ(ResourceReader::json_get_string(app_obj, "name"), "MyApp");
    EXPECT_EQ(ResourceReader::json_get_string(app_obj, "version"), "1.0.0");
}

TEST(ResourceReaderTest, JsonArray)
{
    auto json_obj = ResourceReader::read_json_string(R"({
        "items": ["a", "b", "c"],
        "numbers": [1, 2, 3]
    })");

    EXPECT_TRUE(json_obj["items"].is_array());
    EXPECT_EQ(json_obj["items"].size(), 3);
    EXPECT_EQ(json_obj["items"][0].get<std::string>(), "a");
    EXPECT_TRUE(json_obj["numbers"].is_array());
    EXPECT_EQ(json_obj["numbers"].size(), 3);
    EXPECT_EQ(json_obj["numbers"][0].get<int>(), 1);
}

TEST(ResourceReaderTest, TomlArray)
{
    auto tbl = ResourceReader::read_toml_string(R"(
        items = ["a", "b", "c"]
        numbers = [1, 2, 3]
    )");

    auto items_node = tbl.get("items");
    ASSERT_NE(items_node, nullptr);
    auto items = items_node->as_array();
    ASSERT_NE(items, nullptr);
    EXPECT_EQ(items->size(), 3);

    auto numbers_node = tbl.get("numbers");
    ASSERT_NE(numbers_node, nullptr);
    auto numbers = numbers_node->as_array();
    ASSERT_NE(numbers, nullptr);
    EXPECT_EQ(numbers->size(), 3);
}
