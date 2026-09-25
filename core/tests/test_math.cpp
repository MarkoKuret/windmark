// conventions.md §6: check values bit-exact, the vector file, accuracy on the stated domains.
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

#include "doctest.h"
#include "math/rng.h"
#include "math/wm_math.h"
#include "test_util.h"

using wm_test::bits;
using wm_test::from_bits;

namespace {
constexpr double kPi = 3.14159265358979323846;
}

TEST_CASE("§6.6 check values: wm_sincos") {
  struct Row {
    float x;
    std::uint32_t s, c;
  };
  const Row rows[] = {
      {0.5f, 0x3EF57744u, 0x3F60A940u},
      {1.0f, 0x3F576AA4u, 0x3F0A5140u},
      {-3.0f, 0xBE1081C3u, 0xBF7D7026u},
      {100.0f, 0xBF01A12Eu, 0x3F5CC0EEu},
  };
  for (const Row& r : rows) {
    CAPTURE(r.x);
    const wm::SinCos sc = wm::wm_sincos(r.x);
    CHECK(bits(sc.s) == r.s);
    CHECK(bits(sc.c) == r.c);
    CHECK(bits(wm::wm_sin(r.x)) == r.s);
    CHECK(bits(wm::wm_cos(r.x)) == r.c);
  }
}

TEST_CASE("§6.6 check values: atan, asin, exp (decimal values as binary32)") {
  CHECK(wm::wm_atan(2.0f) == 1.10714877f);
  CHECK(wm::wm_asin(0.9f) == 1.11976957f);
  CHECK(wm::wm_exp(1.0f) == 2.71828175f);
  // Their bit patterns, for the record in the spec.
  CHECK(bits(wm::wm_atan(2.0f)) == 0x3F8DB70Du);
  CHECK(bits(wm::wm_asin(0.9f)) == 0x3F8F549Cu);
  CHECK(bits(wm::wm_exp(1.0f)) == 0x402DF854u);
}

TEST_CASE("wm_atan2 quadrants and axes") {
  CHECK(wm::wm_atan2(0.0f, 0.0f) == 0.0f);
  CHECK(wm::wm_atan2(1.0f, 0.0f) == wm::HALF_PI);
  CHECK(wm::wm_atan2(-1.0f, 0.0f) == -wm::HALF_PI);
  CHECK(wm::wm_atan2(0.0f, -1.0f) == wm::PI);
  CHECK(wm::wm_atan2(1.0f, 1.0f) == doctest::Approx(0.785398163).epsilon(1e-7));
  CHECK(wm::wm_atan2(1.0f, -1.0f) == doctest::Approx(2.35619449).epsilon(1e-7));
  CHECK(wm::wm_atan2(-1.0f, -1.0f) == doctest::Approx(-2.35619449).epsilon(1e-7));
  CHECK(wm::wm_atan2(-1.0f, 1.0f) == doctest::Approx(-0.785398163).epsilon(1e-7));
}

TEST_CASE("accuracy on the stated domains") {
  double worst_sc = 0, worst_atan = 0, worst_asin = 0, worst_exp = 0;
  for (int i = 0; i <= 200000; ++i) {
    const float x = -8192.0f + 16384.0f * static_cast<float>(i) / 200000.0f;
    const wm::SinCos sc = wm::wm_sincos(x);
    worst_sc = std::fmax(worst_sc, std::fabs(static_cast<double>(sc.s) - std::sin(static_cast<double>(x))));
    worst_sc = std::fmax(worst_sc, std::fabs(static_cast<double>(sc.c) - std::cos(static_cast<double>(x))));
  }
  for (int i = 0; i <= 100000; ++i) {
    const float x = -50.0f + 100.0f * static_cast<float>(i) / 100000.0f;
    worst_atan = std::fmax(worst_atan, std::fabs(static_cast<double>(wm::wm_atan(x)) - std::atan(static_cast<double>(x))));
    const float a = -1.0f + 2.0f * static_cast<float>(i) / 100000.0f;
    worst_asin = std::fmax(worst_asin, std::fabs(static_cast<double>(wm::wm_asin(a)) - std::asin(static_cast<double>(a))));
    const float e = -10.0f + 20.0f * static_cast<float>(i) / 100000.0f;
    const double ref = std::exp(static_cast<double>(e));
    worst_exp = std::fmax(worst_exp, std::fabs(static_cast<double>(wm::wm_exp(e)) - ref) / ref);
  }
  MESSAGE("worst abs error: sincos " << worst_sc << ", atan " << worst_atan << ", asin " << worst_asin
                                     << "; exp relative " << worst_exp);
  // The spec's "about 1e-7": a few binary32 ulps near 1. sincos over |x| <= 8192 loses the argument's own
  // rounding in the reduction; 1e-6 bounds all of these with margin.
  CHECK(worst_sc < 1e-6);
  CHECK(worst_atan < 1e-6);
  CHECK(worst_asin < 1e-6);
  CHECK(worst_exp < 1e-6);
  CHECK(wm::wm_exp(-80.0f) > 0.0f);  // a denormal, not flushed
  CHECK(std::isfinite(wm::wm_exp(80.0f)));
  CHECK(wm::wm_pow10(2.0f) == doctest::Approx(100.0).epsilon(1e-6));
  CHECK(wm::wm_acos(1.0f) == 0.0f);
}

TEST_CASE("wrap_pi, wrap_2pi, angle_diff, angle_lerp") {
  CHECK(wm::wrap_pi(0.5f) == 0.5f);
  CHECK(wm::wrap_pi(-wm::PI) == -wm::PI);
  // PI and TWO_PI as binary32 lie slightly above pi and 2 pi; the two-part reduction subtracts the true 2 pi, so
  // they wrap to just above -pi and just above 0.
  CHECK(bits(wm::wrap_pi(wm::PI)) == 0xC0490FDAu);  // -3.1415925, one ulp above -PI
  CHECK(wm::wrap_pi(wm::PI) > -wm::PI);
  CHECK(bits(wm::wrap_2pi(wm::TWO_PI)) == 0x343BC000u);  // 1.74855813e-7
  CHECK(wm::wrap_2pi(-0.0f) == 0.0f);
  CHECK(wm::wrap_2pi(-1e-9f) >= 0.0f);
  CHECK(wm::wrap_2pi(-1e-9f) < wm::TWO_PI);
  for (int i = -20000; i <= 20000; ++i) {
    const float a = static_cast<float>(i) * 0.00731f;
    const float p = wm::wrap_pi(a);
    const float q = wm::wrap_2pi(a);
    CAPTURE(a);
    REQUIRE(p >= -wm::PI);
    REQUIRE(p < wm::PI);
    REQUIRE(q >= 0.0f);
    REQUIRE(q < wm::TWO_PI);
    const double k = std::round((static_cast<double>(a) - static_cast<double>(p)) / (2.0 * kPi));
    REQUIRE(std::fabs(static_cast<double>(a) - k * 2.0 * kPi - static_cast<double>(p)) < 2e-5);
  }
  CHECK(wm::angle_diff(0.1f, wm::TWO_PI - 0.1f) == doctest::Approx(0.2).epsilon(1e-5));
  CHECK(wm::angle_lerp(wm::TWO_PI - 0.1f, 0.1f, 0.5f) == doctest::Approx(0.0).epsilon(1e-5).scale(1));
  CHECK(wm::compass({1.0f, 0.0f}) == wm::HALF_PI);  // east
  CHECK(wm::compass({0.0f, 1.0f}) == 0.0f);         // north
  CHECK(wm::compass({-1.0f, 0.0f}) == doctest::Approx(3.0 * kPi / 2.0).epsilon(1e-7));
  const wm::Vec2 e = wm::dir(wm::HALF_PI);
  CHECK(e.x == doctest::Approx(1.0));
  CHECK(e.y == doctest::Approx(0.0).scale(1));
}

TEST_CASE("math vector file: every line reproduces bit-exact") {
  std::ifstream in(WINDMARK_VECTORS_FILE);
  REQUIRE_MESSAGE(in.good(), "missing " WINDMARK_VECTORS_FILE);
  std::string line;
  int checked = 0;
  int failed = 0;
  auto h = [](const std::string& s) { return static_cast<std::uint32_t>(std::stoul(s, nullptr, 16)); };
  while (std::getline(in, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::istringstream ls(line);
    std::string fn, a, b, c, d, e;
    ls >> fn >> a >> b >> c >> d >> e;
    bool ok = true;
    if (fn == "sincos") {
      const wm::SinCos sc = wm::wm_sincos(from_bits(h(a)));
      ok = bits(sc.s) == h(b) && bits(sc.c) == h(c);
    } else if (fn == "atan") {
      ok = bits(wm::wm_atan(from_bits(h(a)))) == h(b);
    } else if (fn == "atan2") {
      ok = bits(wm::wm_atan2(from_bits(h(a)), from_bits(h(b)))) == h(c);
    } else if (fn == "asin") {
      ok = bits(wm::wm_asin(from_bits(h(a)))) == h(b);
    } else if (fn == "acos") {
      ok = bits(wm::wm_acos(from_bits(h(a)))) == h(b);
    } else if (fn == "exp") {
      ok = bits(wm::wm_exp(from_bits(h(a)))) == h(b);
    } else if (fn == "pow10") {
      ok = bits(wm::wm_pow10(from_bits(h(a)))) == h(b);
    } else if (fn == "wrap_pi") {
      ok = bits(wm::wrap_pi(from_bits(h(a)))) == h(b);
    } else if (fn == "wrap_2pi") {
      ok = bits(wm::wrap_2pi(from_bits(h(a)))) == h(b);
    } else if (fn == "angle_lerp") {
      ok = bits(wm::angle_lerp(from_bits(h(a)), from_bits(h(b)), from_bits(h(c)))) == h(d);
    } else if (fn == "rng") {
      const std::uint64_t seed = std::stoull(a, nullptr, 16);
      const std::uint64_t stream = std::stoull(b, nullptr, 16);
      const std::uint64_t index = std::stoull(c, nullptr, 16);
      ok = wm::rng_u64(seed, stream, index) == std::stoull(d, nullptr, 16) &&
           bits(wm::rng_unit(seed, stream, index)) == h(e);
    } else {
      FAIL("unknown function in the vector file: " << fn);
    }
    if (!ok) {
      if (failed < 20) MESSAGE("mismatch: " << line);
      ++failed;
    }
    ++checked;
  }
  MESSAGE(checked << " vectors checked");
  CHECK(checked > 1000);
  CHECK(failed == 0);
}
