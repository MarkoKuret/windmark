// conventions.md §5: binary32, round to nearest, no contraction, denormals kept.
#include <cfloat>
#include <cmath>
#include <limits>

#include "base/fp_env.h"
#include "doctest.h"
#include "math/wm_math.h"
#include "test_util.h"

using wm_test::bits;
using wm_test::from_bits;

TEST_CASE("float is IEEE binary32 and evaluated in its own precision") {
  static_assert(sizeof(float) == 4);
  static_assert(std::numeric_limits<float>::is_iec559);
  static_assert(std::numeric_limits<float>::digits == 24);
  CHECK(FLT_EVAL_METHOD == 0);  // no excess precision (x87)
}

TEST_CASE("the FP environment is round to nearest with denormals kept") {
  CHECK(wm::fp_env_ok());
  WM_DEBUG_CHECK_FP_ENV();
}

TEST_CASE("no fused multiply-add: a*b + c rounds twice") {
  // a = 1 + 2^-12: a*a = 1 + 2^-11 + 2^-24 rounds (tie to even) to 1 + 2^-11, so a*a - (1 + 2^-11) is 0 when
  // the product is rounded, and 2^-24 when it is fused with the addition.
  volatile float a = from_bits(0x3F800800u);  // 1 + 2^-12
  volatile float c = -from_bits(0x3F801000u); // -(1 + 2^-11)
  CHECK(wm::fp_probe_mul_add(a, a, c) == 0.0f);

  // The same in this translation unit, which builds with the same flags.
  const float x = a;
  const float z = c;
  const float r = x * x + z;
  CHECK(r == 0.0f);

  // For reference: the fused result is 2^-24.
  CHECK(std::fma(static_cast<float>(a), static_cast<float>(a), static_cast<float>(c)) == from_bits(0x33800000u));
}

TEST_CASE("constants have the spec's bits") {
  CHECK(bits(wm::KNOT) == 0x3F03B2A2u);
  CHECK(bits(wm::DEG) == 0x3C8EFA35u);
  CHECK(bits(wm::DT) == 0x3D4CCCCDu);
  CHECK(wm::PI == static_cast<float>(3.14159265358979323846));
  CHECK(wm::TWO_PI == static_cast<float>(6.28318530717958647692));
  CHECK(wm::HALF_PI == static_cast<float>(1.57079632679489661923));
  CHECK(wm::QUARTER_PI == static_cast<float>(0.78539816339744830962));
}

TEST_CASE("scalar helpers follow rule 12 and sgn of §3") {
  const float nan = std::numeric_limits<float>::quiet_NaN();
  CHECK(wm::clamp(2.0f, 0.0f, 1.0f) == 1.0f);
  CHECK(wm::clamp(-2.0f, 0.0f, 1.0f) == 0.0f);
  CHECK(std::isnan(wm::clamp(nan, 0.0f, 1.0f)));
  CHECK(wm::lerp(3.0f, 3.0f, 0.0f) == 3.0f);
  CHECK(wm::lerp(1.0f, 3.0f, 0.5f) == 2.0f);
  CHECK(wm::sgn(0.0f) == 1.0f);
  CHECK(wm::sgn(-0.0f) == 1.0f);
  CHECK(wm::sgn(-1e-30f) == -1.0f);
  CHECK(wm::min(1.0f, 2.0f) == 1.0f);
  CHECK(wm::max(1.0f, 2.0f) == 2.0f);
}
