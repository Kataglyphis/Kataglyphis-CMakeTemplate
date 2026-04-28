module;

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string_view>

#if !defined(NLOHMANN_JSON_MODULE_AVAILABLE)
#include <nlohmann/json.hpp>
#endif

#if !defined(TOMLPLUSPLUS_MODULE_AVAILABLE)
#define TOML_UNDEF_MACROS 0
#include <toml++/toml.hpp>
#endif

export module kataglyphis_resources;

#if defined(NLOHMANN_JSON_MODULE_AVAILABLE)
import nlohmann.json;
#endif

#if defined(TOMLPLUSPLUS_MODULE_AVAILABLE)
import tomlplusplus;
#endif

export namespace kataglyphis::resources {

class ResourceReader {
public:
    static auto read_json_file(const std::filesystem::path& file_path) -> nlohmann::json {
        std::ifstream file(file_path);
        if (!file.is_open()) {
            throw std::runtime_error("Failed to open JSON file: " + file_path.string());
        }
        return nlohmann::json::parse(file);
    }

    static auto read_json_string(std::string_view json_string) -> nlohmann::json {
        return nlohmann::json::parse(json_string);
    }

    static auto read_toml_file(const std::filesystem::path& file_path) -> toml::table {
        auto result = toml::parse_file(file_path.string());
        if (!result) {
            throw std::runtime_error("Failed to parse TOML file: " + file_path.string() + " - " + std::string(result.error().description()));
        }
        return static_cast<toml::table&&>(result);
    }

    static auto read_toml_string(std::string_view toml_string) -> toml::table {
        auto result = toml::parse(toml_string);
        if (!result) {
            throw std::runtime_error("Failed to parse TOML string: " + std::string(result.error().description()));
        }
        return static_cast<toml::table&&>(result);
    }

    static auto json_get_string(const nlohmann::json& json_obj, const std::string& key) -> std::string {
        if (json_obj.contains(key) && json_obj[key].is_string()) {
            return json_obj[key].get<std::string>();
        }
        throw std::runtime_error("JSON object does not contain string key: " + key);
    }

    static auto json_get_int(const nlohmann::json& json_obj, const std::string& key) -> int64_t {
        if (json_obj.contains(key) && json_obj[key].is_number_integer()) {
            return json_obj[key].get<int64_t>();
        }
        throw std::runtime_error("JSON object does not contain integer key: " + key);
    }

    static auto json_get_bool(const nlohmann::json& json_obj, const std::string& key) -> bool {
        if (json_obj.contains(key) && json_obj[key].is_boolean()) {
            return json_obj[key].get<bool>();
        }
        throw std::runtime_error("JSON object does not contain boolean key: " + key);
    }

    static auto json_get_double(const nlohmann::json& json_obj, const std::string& key) -> double {
        if (json_obj.contains(key) && json_obj[key].is_number()) {
            return json_obj[key].get<double>();
        }
        throw std::runtime_error("JSON object does not contain number key: " + key);
    }

    static auto toml_get_string(const toml::table& tbl, const std::string& key) -> std::string {
        if (auto node = tbl.get(key)) {
            if (auto val = node->value<std::string>()) {
                return *val;
            }
        }
        throw std::runtime_error("TOML table does not contain string key: " + key);
    }

    static auto toml_get_int(const toml::table& tbl, const std::string& key) -> int64_t {
        if (auto node = tbl.get(key)) {
            if (auto val = node->value<int64_t>()) {
                return *val;
            }
        }
        throw std::runtime_error("TOML table does not contain integer key: " + key);
    }

    static auto toml_get_bool(const toml::table& tbl, const std::string& key) -> bool {
        if (auto node = tbl.get(key)) {
            if (auto val = node->value<bool>()) {
                return *val;
            }
        }
        throw std::runtime_error("TOML table does not contain boolean key: " + key);
    }

    static auto toml_get_double(const toml::table& tbl, const std::string& key) -> double {
        if (auto node = tbl.get(key)) {
            if (auto val = node->value<double>()) {
                return *val;
            }
        }
        throw std::runtime_error("TOML table does not contain number key: " + key);
    }

    static auto toml_get_table(const toml::table& tbl, const std::string& key) -> toml::table {
        if (auto node = tbl.get(key)) {
            if (node->is_table()) {
                return *node->as_table();
            }
        }
        throw std::runtime_error("TOML table does not contain table key: " + key);
    }

    static auto json_has_key(const nlohmann::json& json_obj, const std::string& key) -> bool {
        return json_obj.contains(key);
    }

    static auto toml_has_key(const toml::table& tbl, const std::string& key) -> bool {
        return tbl.get(key) != nullptr;
    }
};

}