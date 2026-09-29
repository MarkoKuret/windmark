// Rectilinear tables of 1 to 3 axes: bracket and interpolation (conventions.md §8), vocabulary of axis
// quantities and value units (data_format.md §5).
#pragma once

#include <cstdint>
#include <span>
#include <string_view>
#include <vector>

namespace wm {

// data_format.md §5: the quantity of an axis fixes its unit and range.
enum class Quantity : std::uint8_t {
  tws,             // m/s, >= 0
  twa_abs,         // rad, [0, pi]
  awa_abs,         // rad, [0, pi]
  trim_error,      // rad, any
  boat_speed,      // m/s, any
  boat_speed_abs,  // m/s, >= 0
  helm_abs,        // -, [0, 1]
  heel_abs,        // rad, [0, pi/2]
  aws,             // m/s, >= 0
};

// Units of table values.
enum class Unit : std::uint8_t { m_s, rad, m_s2, rad_s, s, one };

bool quantity_from_name(std::string_view name, Quantity& out);
std::string_view quantity_name(Quantity q);
bool unit_from_name(std::string_view name, Unit& out);
std::string_view unit_name(Unit u);

// §8.1 result: value index pair and weight toward i1.
struct Bracket {
  std::uint32_t i0;
  std::uint32_t i1;
  float t;
};

// §8.1. `a` has n >= 1 non-decreasing breakpoints, never three equal in a row. Never extrapolates; NaN and
// values below the range clamp to the first point; a step (a[k] == a[k+1]) is right-continuous.
Bracket bracket(const float* a, std::uint32_t n, float x);

// Checks the §8.1 / data_format.md §5 axis rules: 1..256 points, finite, non-decreasing, at most two equal in a
// row. Returns nullptr when valid, else a reason.
const char* check_axis_points(const std::vector<float>& points);

struct Axis {
  Quantity q = Quantity::tws;
  std::vector<float> points;
};

// §8.2: values row-major, last axis fastest.
class Table {
 public:
  Table() = default;
  Table(std::vector<Axis> axes, Unit unit, std::vector<float> values);

  std::uint32_t rank() const { return static_cast<std::uint32_t>(axes_.size()); }
  const std::vector<Axis>& axes() const { return axes_; }
  const Axis& axis(std::uint32_t i) const { return axes_[i]; }
  Unit unit() const { return unit_; }
  const std::vector<float>& values() const { return values_; }
  bool empty() const { return axes_.empty(); }

  // Lookups; the number of arguments must equal rank() (asserted in debug builds).
  float at(float x) const;
  float at(float x, float y) const;
  float at(float x, float y, float w) const;
  // at(x, y) for every y of `ys` into `out` (same size), bit for bit the same as one at(x, y) per value: the x bracket
  // is found once and, `ys` being non-decreasing, the y bracket moves forward along the axis instead of searching.
  void at_each(float x, std::span<const float> ys, std::span<float> out) const;

 private:
  std::vector<Axis> axes_;
  Unit unit_ = Unit::one;
  std::vector<float> values_;
};

// A table the spec marks optional (§8.3): absent is not the same as empty.
struct OptionalTable {
  bool present = false;
  Table table;
};

}  // namespace wm
