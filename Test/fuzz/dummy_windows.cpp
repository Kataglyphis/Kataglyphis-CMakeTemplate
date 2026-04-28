#include "gtest/gtest.h"

TEST(MyTestSuite, OnePlustTwoIsTwoPlusOne) { EXPECT_EQ(1 + 2, 2 + 1); }

TEST(MyTestSuite, IntegerAdditionCommutes) {
  int a = 5;
  int b = 3;
  EXPECT_EQ(a + b, b + a);
}

TEST(MyTestSuite, SimpleFuzz) {
  for (int i = 0; i < 100; ++i) {
    EXPECT_EQ(i, i);
  }
}