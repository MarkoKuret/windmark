#include "table/table.h"

#include <cassert>
#include <cmath>
#include <utility>

#include "math/wm_math.h"

namespace wm {

namespace {

struct Name {
  std::string_view name;
  std::uint8_t value;
};

constexpr Name kQuantities[] = {
    {"tws", static_cast<std::uint8_t>(Quantity::tws)},
    {"twa_abs", static_cast<std::uint8_t>(Quantity::twa_abs)},
    {"awa_abs", static_cast<std::uint8_t>(Quantity::awa_abs)},
    {"trim_error", static_cast<std::uint8_t>(Quantity::trim_error)},
    {"boat_speed", static_cast<std::uint8_t>(Quantity::boat_speed)},
    {"boat_speed_abs", static_cast<std::uint8_t>(Quantity::boat_speed_abs)},
    {"helm_abs", static_cast<std::uint8_t>(Quantity::helm_abs)},
    {"heel_abs", static_cast<std::uint8_t>(Quantity::heel_abs)},
    {"aws", static_cast<std::uint8_t>(Quantity::aws)},
};

constexpr Name kUnits[] = {
    {"m/s", static_cast<std::uint8_t>(Unit::m_s)},   {"rad", static_cast<std::uint8_t>(Unit::rad)},
    {"m/s2", static_cast<std::uint8_t>(Unit::m_s2)}, {"rad/s", static_cast<std::uint8_t>(Unit::rad_s)},
    {"s", static_cast<std::uint8_t>(Unit::s)},       {"1", static_cast<std::uint8_t>(Unit::one)},
};

}  // namespace

bool quantity_from_name(std::string_view name, Quantity& out) {
  for (const Name& n : kQuantities) {
    if (n.name == name) {
      out = static_cast<Quantity>(n.value);
      return true;
    }
  }
  return false;
}

std::string_view quantity_name(Quantity q) {
  for (const Name& n : kQuantities) {
    if (n.value == static_cast<std::uint8_t>(q)) return n.name;
  }
  return "?";
}

bool unit_from_name(std::string_view name, Unit& out) {
  for (const Name& n : kUnits) {
    if (n.name == name) {
      out = static_cast<Unit>(n.value);
      return true;
    }
  }
  return false;
}

std::string_view unit_name(Unit u) {
  for (const Name& n : kUnits) {
    if (n.value == static_cast<std::uint8_t>(u)) return n.name;
  }
  return "?";
}

Bracket bracket(const float* a, std::uint32_t n, float x) {
  if (n == 1) return {0, 0, 0.0f};
  if (!(x >= a[0])) return {0, 0, 0.0f};              // below the range, and NaN
  if (x >= a[n - 1]) return {n - 1, n - 1, 0.0f};     // above the range
  // Largest i with a[i] <= x. Invariant: a[lo] <= x < a[hi]; lo ends at most n - 2.
  std::uint32_t lo = 0;
  std::uint32_t hi = n - 1;
  while (hi - lo > 1) {
    const std::uint32_t mid = lo + (hi - lo) / 2;
    if (a[mid] <= x) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  // a[lo] <= x < a[lo + 1], so the divisor is > 0.
  const float t = (x - a[lo]) / (a[lo + 1] - a[lo]);
  return {lo, lo + 1, t};
}

const char* check_axis_points(const std::vector<float>& points) {
  if (points.empty()) return "axis has no points";
  if (points.size() > 256) return "axis has more than 256 points";
  for (std::size_t i = 0; i < points.size(); ++i) {
    if (!std::isfinite(points[i])) return "axis point is not finite";
    if (i > 0 && points[i] < points[i - 1]) return "axis points decrease";
    if (i > 1 && points[i] == points[i - 1] && points[i] == points[i - 2]) {
      return "three equal axis points in a row";
    }
  }
  return nullptr;
}

Table::Table(std::vector<Axis> axes, Unit unit, std::vector<float> values)
    : axes_(std::move(axes)), unit_(unit), values_(std::move(values)) {}

float Table::at(float x) const {
  assert(rank() == 1);
  const Axis& ax = axes_[0];
  const Bracket b = bracket(ax.points.data(), static_cast<std::uint32_t>(ax.points.size()), x);
  return lerp(values_[b.i0], values_[b.i1], b.t);
}

float Table::at(float x, float y) const {
  assert(rank() == 2);
  const Axis& ax = axes_[0];
  const Axis& ay = axes_[1];
  const std::uint32_t n1 = static_cast<std::uint32_t>(ay.points.size());
  const Bracket bx = bracket(ax.points.data(), static_cast<std::uint32_t>(ax.points.size()), x);
  const Bracket by = bracket(ay.points.data(), n1, y);
  const float* v = values_.data();
  const float r0 = lerp(v[bx.i0 * n1 + by.i0], v[bx.i0 * n1 + by.i1], by.t);
  const float r1 = lerp(v[bx.i1 * n1 + by.i0], v[bx.i1 * n1 + by.i1], by.t);
  return lerp(r0, r1, bx.t);
}

void Table::at_each(float x, std::span<const float> ys, std::span<float> out) const {
  assert(rank() == 2 && out.size() == ys.size());
  const Axis& ax = axes_[0];
  const float* a = axes_[1].points.data();
  const std::uint32_t n1 = static_cast<std::uint32_t>(axes_[1].points.size());
  const Bracket bx = bracket(ax.points.data(), static_cast<std::uint32_t>(ax.points.size()), x);
  const float* v = values_.data();
  std::uint32_t lo = 0;  // a[lo] <= y for the current and every later y
  for (std::size_t k = 0; k < ys.size(); ++k) {
    const float y = ys[k];
    assert(k == 0 || !(y < ys[k - 1]));
    // bracket(a, n1, y) of §8.1, the same three cases.
    Bracket by;
    if (n1 == 1 || !(y >= a[0])) {
      by = {0, 0, 0.0f};
    } else if (y >= a[n1 - 1]) {
      by = {n1 - 1, n1 - 1, 0.0f};
    } else {
      // The unique lo with a[lo] <= y < a[lo + 1] (lo <= n1 - 2 since y < a[n1 - 1]).
      while (a[lo + 1] <= y) ++lo;
      by = {lo, lo + 1, (y - a[lo]) / (a[lo + 1] - a[lo])};
    }
    const float r0 = lerp(v[bx.i0 * n1 + by.i0], v[bx.i0 * n1 + by.i1], by.t);
    const float r1 = lerp(v[bx.i1 * n1 + by.i0], v[bx.i1 * n1 + by.i1], by.t);
    out[k] = lerp(r0, r1, bx.t);
  }
}

float Table::at(float x, float y, float w) const {
  assert(rank() == 3);
  const Axis& ax = axes_[0];
  const Axis& ay = axes_[1];
  const Axis& aw = axes_[2];
  const std::uint32_t n1 = static_cast<std::uint32_t>(ay.points.size());
  const std::uint32_t n2 = static_cast<std::uint32_t>(aw.points.size());
  const Bracket bx = bracket(ax.points.data(), static_cast<std::uint32_t>(ax.points.size()), x);
  const Bracket by = bracket(ay.points.data(), n1, y);
  const Bracket bw = bracket(aw.points.data(), n2, w);
  const float* v = values_.data();
  auto along_w = [&](std::uint32_t i, std::uint32_t j) {
    const std::uint32_t base = (i * n1 + j) * n2;
    return lerp(v[base + bw.i0], v[base + bw.i1], bw.t);
  };
  // Along w at the four (i, j) corners, then along y, then along x.
  const float c00 = along_w(bx.i0, by.i0);
  const float c01 = along_w(bx.i0, by.i1);
  const float c10 = along_w(bx.i1, by.i0);
  const float c11 = along_w(bx.i1, by.i1);
  const float r0 = lerp(c00, c01, by.t);
  const float r1 = lerp(c10, c11, by.t);
  return lerp(r0, r1, bx.t);
}

}  // namespace wm
