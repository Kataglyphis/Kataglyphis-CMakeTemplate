module;

#include <cstdint>
#include <iostream>

export module kataglyphis_core;

import kataglyphis_config;
// Always import the nlohmann.json C++ module. The project is configured to
// build nlohmann.json as a module (nlohmann_json_modules) and consumers must
// use the module interface rather than the header-only form.
import nlohmann.json;

#if defined(TOMLPLUSPLUS_MODULE_AVAILABLE)
import tomlplusplus;
#endif

#if USE_RUST
extern "C" {
auto rusty_extern_c_integer() -> int32_t;
}
#endif

export namespace kataglyphis {
// NOLINTNEXTLINE(misc-use-internal-linkage)
auto run() -> int
{
#if USE_RUST
    std::cout << "A value given directly by extern c function " << rusty_extern_c_integer() << "\n";
#endif

    std::cout << "Kataglyphis version " << kataglyphis::config::renderer_version_major << "."
              << kataglyphis::config::renderer_version_minor << "\n";

    std::cout << "Hello World! \n";

    auto data = nlohmann::json::parse(R"({"module": "nlohmann.json", "status": "ok"})");
    std::cout << "JSON module test: " << data["module"].get<std::string>() << " -> " << data["status"].get<std::string>()
              << "\n";

#if defined(TOMLPLUSPLUS_MODULE_AVAILABLE)
    // Parse the example TOML resource to demonstrate module usage.
    // Use the no-exceptions API (parse_result) so this code compiles when
    // exceptions are disabled for the toolchain.
    {
        auto res = toml::parse_file("${CMAKE_SOURCE_DIR}/Src/resources/example.toml");
        if (res) {
            // parse_result is convertible to toml::table when successful
            const auto &t = static_cast<const toml::table &>(res);
            if (auto app = t["application"]) {
                if (auto name = app["name"].value<std::string>()) {
                    std::cout << "TOML module test: application.name = " << *name << "\n";
                }
            }
        } else {
            // parse_result provides access to the parse_error when failed
            std::cout << "Failed to parse TOML example: " << res.error() << "\n";
        }
    }
#endif

    return 0;
}
} // namespace kataglyphis
