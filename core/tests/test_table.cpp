// conventions.md §8: bracket, steps, clamping, interpolation order.
#include <cmath>
#include <limits>
#include <vector>

#include "doctest.h"
#include "math/wm_math.h"
#include "table/table.h"

namespace {

wm::Bracket br(const std::vector<float>& a, float x) {
  return wm::bracket(a.data(), static_cast<std::uint32_t>(a.size()), x);
}

}  // namespace

TEST_CASE("bracket: single point, clamping below, above and NaN") {
  const std::vector<float> one{5.0f};
  const wm::Bracket b1 = br(one, 7.0f);
  CHECK(b1.i0 == 0);
  CHECK(b1.i1 == 0);
  CHECK(b1.t == 0.0f);

  const std::vector<float> a{0.0f, 1.0f, 2.0f, 4.0f};
  wm::Bracket b = br(a, -1.0f);
  CHECK((b.i0 == 0 && b.i1 == 0 && b.t == 0.0f));
  b = br(a, std::numeric_limits<float>::quiet_NaN());
  CHECK((b.i0 == 0 && b.i1 == 0 && b.t == 0.0f));
  b = br(a, 4.0f);
  CHECK((b.i0 == 3 && b.i1 == 3 && b.t == 0.0f));
  b = br(a, 100.0f);
  CHECK((b.i0 == 3 && b.i1 == 3 && b.t == 0.0f));
  b = br(a, 3.0f);
  CHECK((b.i0 == 2 && b.i1 == 3 && b.t == 0.5f));
  b = br(a, 0.0f);
  CHECK((b.i0 == 0 && b.i1 == 1 && b.t == 0.0f));
  b = br(a, 1.0f);
  CHECK((b.i0 == 1 && b.i1 == 2 && b.t == 0.0f));
}

TEST_CASE("bracket: a doubled breakpoint is a right-continuous step") {
  const std::vector<float> a{0.0f, 1.0f, 1.0f, 2.0f};
  wm::Bracket b = br(a, 1.0f);
  CHECK((b.i0 == 2 && b.i1 == 3 && b.t == 0.0f));  // x == a[k] gives the value at k+1
  b = br(a, 0.5f);
  CHECK((b.i0 == 0 && b.i1 == 1 && b.t == 0.5f));
  b = br(a, 1.5f);
  CHECK((b.i0 == 2 && b.i1 == 3 && b.t == 0.5f));

  // A table stepping from 10 to 20 at x = 1.
  const wm::Table t({{wm::Quantity::twa_abs, a}}, wm::Unit::one, {0.0f, 10.0f, 20.0f, 30.0f});
  CHECK(t.at(0.999999f) == doctest::Approx(10.0f).epsilon(1e-5));
  CHECK(t.at(1.0f) == 20.0f);
  CHECK(t.at(1.5f) == 25.0f);

  // Step at the ends.
  const std::vector<float> lo{0.0f, 0.0f, 1.0f};
  b = br(lo, 0.0f);
  CHECK((b.i0 == 1 && b.i1 == 2 && b.t == 0.0f));
  const std::vector<float> hi{0.0f, 1.0f, 1.0f};
  b = br(hi, 1.0f);
  CHECK((b.i0 == 2 && b.i1 == 2 && b.t == 0.0f));
  b = br(hi, 0.25f);
  CHECK((b.i0 == 0 && b.i1 == 1 && b.t == 0.25f));
}

TEST_CASE("bracket agrees with a linear scan") {
  std::vector<float> a;
  for (int i = 0; i < 40; ++i) {
    a.push_back(static_cast<float>(i) * 0.25f);
    if (i % 7 == 3) a.push_back(static_cast<float>(i) * 0.25f);  // steps
  }
  for (int k = -10; k < 1100; ++k) {
    const float x = static_cast<float>(k) * 0.01f;
    const wm::Bracket b = br(a, x);
    if (x < a.front() || x >= a.back()) continue;
    std::uint32_t lin = 0;
    for (std::uint32_t i = 0; i < a.size(); ++i) {
      if (a[i] <= x) lin = i;
    }
    CAPTURE(x);
    REQUIRE(b.i0 == lin);
    REQUIRE(b.i1 == lin + 1);
    REQUIRE(b.t == (x - a[lin]) / (a[lin + 1] - a[lin]));
  }
}

TEST_CASE("axis validation") {
  CHECK(wm::check_axis_points({0.0f, 1.0f, 1.0f, 2.0f}) == nullptr);
  CHECK(wm::check_axis_points({3.0f}) == nullptr);
  CHECK(wm::check_axis_points({}) != nullptr);
  CHECK(wm::check_axis_points({0.0f, 1.0f, 1.0f, 1.0f}) != nullptr);
  CHECK(wm::check_axis_points({0.0f, 2.0f, 1.0f}) != nullptr);
  CHECK(wm::check_axis_points({0.0f, std::numeric_limits<float>::infinity()}) != nullptr);
  CHECK(wm::check_axis_points(std::vector<float>(257, 0.0f)) != nullptr);
}

TEST_CASE("2-D and 3-D interpolation: row-major, lerp order of §8.2") {
  // v(x, y) = 10 x + y on a 3 x 2 grid.
  const wm::Table t2({{wm::Quantity::tws, {0.0f, 1.0f, 3.0f}}, {wm::Quantity::twa_abs, {0.0f, 2.0f}}}, wm::Unit::m_s,
                     {0.0f, 2.0f, 10.0f, 12.0f, 30.0f, 32.0f});
  CHECK(t2.at(0.5f, 1.0f) == 6.0f);
  CHECK(t2.at(2.0f, 0.5f) == 20.5f);
  CHECK(t2.at(-1.0f, 5.0f) == 2.0f);  // clamped both ways
  CHECK(t2.at(9.0f, -1.0f) == 30.0f);
  // Exact grid points give the stored value bit for bit.
  CHECK(t2.at(1.0f, 2.0f) == 12.0f);

  // Order of the operations: r0 = lerp along y at i0, r1 at i1, then along x.
  const float x = 0.3f, y = 0.7f;
  const float tx = (x - 0.0f) / (1.0f - 0.0f);
  const float ty = (y - 0.0f) / (2.0f - 0.0f);
  const float r0 = wm::lerp(0.0f, 2.0f, ty);
  const float r1 = wm::lerp(10.0f, 12.0f, ty);
  CHECK(t2.at(x, y) == wm::lerp(r0, r1, tx));

  // v(x, y, w) = 100 x + 10 y + w on 2 x 2 x 3.
  std::vector<float> v;
  const float xs[] = {0.0f, 1.0f}, ys[] = {0.0f, 1.0f}, ws[] = {0.0f, 1.0f, 2.0f};
  for (float a : xs)
    for (float b : ys)
      for (float c : ws) v.push_back(100.0f * a + 10.0f * b + c);
  const wm::Table t3({{wm::Quantity::tws, {0.0f, 1.0f}},
                      {wm::Quantity::awa_abs, {0.0f, 1.0f}},
                      {wm::Quantity::trim_error, {0.0f, 1.0f, 2.0f}}},
                     wm::Unit::one, v);
  CHECK(t3.at(0.5f, 0.5f, 1.5f) == 56.5f);
  CHECK(t3.at(1.0f, 0.0f, 2.0f) == 102.0f);
  CHECK(t3.at(0.25f, 0.75f, -3.0f) == 32.5f);
}
