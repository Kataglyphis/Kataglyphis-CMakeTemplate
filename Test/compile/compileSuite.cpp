#include <gtest/gtest.h>

import kataglyphis_config;

// Demonstrate some basic assertions.
TEST(HelloTestCompile, BasicAssertions)
{

    // Expect two strings not to be equal.
    EXPECT_STRNE("hello", "world");
    // Expect equality.
    EXPECT_EQ(7 * 6, 42);
    EXPECT_STRNE("", kataglyphis::config::renderer_version_major);
}

TEST(HelloTestCompile, blob)
{

    // VulkanBuffer vulkanBuffer;

    int count = 0;

    // Test that counter 0 returns 0
    EXPECT_EQ(0, count);

    // EXPECT_EQ() evaluates its arguments exactly once, so they
    // can have side effects.

    EXPECT_EQ(0, count++);
    EXPECT_EQ(1, count++);
    EXPECT_EQ(2, count++);

    EXPECT_EQ(3, count++);
}