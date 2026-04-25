module;

#include <cstdint>
#include <iostream>

export module kataglyphis_core;

import kataglyphis_config;
// Always import the nlohmann.json C++ module. The project is configured to
// build nlohmann.json as a module (nlohmann_json_modules) and consumers must
// use the module interface rather than the header-only form.
import nlohmann.json;

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

    return 0;
}
} // namespace kataglyphis
