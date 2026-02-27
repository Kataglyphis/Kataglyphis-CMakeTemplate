module;

#include <cstdint>
#include <iostream>

export module kataglyphis.cppproject;

import kataglyphis.config;

#if USE_RUST
extern "C" {
int32_t rusty_extern_c_integer();
}
#endif

export namespace kataglyphis {
int run();
}

namespace kataglyphis {
int run()
{
#if USE_RUST
    std::cout << "A value given directly by extern c function " << rusty_extern_c_integer() << "\n";
#endif

    std::cout << "Kataglyphis version " << kataglyphis::config::renderer_version_major << "."
              << kataglyphis::config::renderer_version_minor << "\n";

    std::cout << "Hello World! \n";
    return 0;
}
} // namespace kataglyphis
