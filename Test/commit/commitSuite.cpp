#include <gtest/gtest.h>

#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>

// NOLINTNEXTLINE
import kataglyphis_config;

// Demonstrate some basic assertions.
// NOLINTBEGIN(misc-use-internal-linkage, modernize-use-trailing-return-type, readability-named-parameter,
// hicpp-named-parameter)
TEST(HelloTestCommit, BasicAssertions)
{
    constexpr auto expected_result = 42;
    constexpr auto multiplier1 = 7;
    constexpr auto multiplier2 = 6;

    // Expect two strings not to be equal.
    EXPECT_STRNE("hello", "world");
    // Expect equality.
    EXPECT_EQ(multiplier1 * multiplier2, expected_result);
    EXPECT_STRNE("", kataglyphis::config::renderer_version_major);
}

TEST(Integration, VulkanEngine)
{
    constexpr auto expected_result = 42;
    constexpr auto multiplier1 = 7;
    constexpr auto multiplier2 = 6;
    EXPECT_EQ(multiplier1 * multiplier2, expected_result);
}
// NOLINTEND(misc-use-internal-linkage, modernize-use-trailing-return-type, readability-named-parameter,
// hicpp-named-parameter)