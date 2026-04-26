#include <gtest/gtest.h>
#include <cstdint>

extern "C" int32_t rusty_extern_c_integer();

TEST(RustIntegration, ExternCFunctionReturnsExpectedValue) {
#if USE_RUST
  EXPECT_EQ(322, rusty_extern_c_integer());
#else
  GTEST_SKIP() << "Rust features disabled; skipping rust integration test";
#endif
}
