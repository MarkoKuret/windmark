#include "data/venue.h"

#include <cmath>
#include <span>

#include "data/json.h"
#include "data/table_reader.h"
#include "state/sha256.h"

namespace wm {

namespace {

using data::member;
using data::read_float;
using data::read_float_value;
using json::Value;

constexpr float kBoundsMax = 8000.0f;     // §6.1
constexpr std::int64_t kGridMaxSide = 1024;  // §6.6

// Load-time geometry in double: every difference of two binary32 coordinates of a venue is exact in double, and
// the results only decide accept or refuse.
struct D {
  double x, y;
};
D dv(Vec2 p) { return {static_cast<double>(p.x), static_cast<double>(p.y)}; }

// Orientation of (a, b, c): > 0 counter-clockwise.
double orient(Vec2 pa, Vec2 pb, Vec2 pc) {
  const D a = dv(pa), b = dv(pb), c = dv(pc);
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

bool on_segment(Vec2 a, Vec2 b, Vec2 p) {  // p collinear with a-b: inside its box
  return std::fmin(a.x, b.x) <= p.x && p.x <= std::fmax(a.x, b.x) && std::fmin(a.y, b.y) <= p.y &&
         p.y <= std::fmax(a.y, b.y);
}

// Closed segments a-b and c-d share a point.
bool segments_touch(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  const double o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
  if (((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0)) && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0))) return true;
  if (o1 == 0 && on_segment(a, b, c)) return true;
  if (o2 == 0 && on_segment(a, b, d)) return true;
  if (o3 == 0 && on_segment(c, d, a)) return true;
  if (o4 == 0 && on_segment(c, d, b)) return true;
  return false;
}

double twice_area(const std::vector<Vec2>& p) {
  double s = 0.0;
  for (std::size_t i = 0; i < p.size(); ++i) {
    const D a = dv(p[i]), b = dv(p[(i + 1) % p.size()]);
    s += a.x * b.y - b.x * a.y;
  }
  return s;
}

// nullptr when the closed polygon is simple: >= 3 points, no zero-length edge, adjacent edges do not fold back
// onto each other, non-adjacent edges do not touch. `bad` receives the offending vertex index.
const char* check_simple(const std::vector<Vec2>& p, std::size_t& bad) {
  const std::size_t n = p.size();
  if (n < 3) return (bad = 0, "a polygon needs at least 3 points");
  for (std::size_t i = 0; i < n; ++i) {
    const Vec2 a = p[i], b = p[(i + 1) % n];
    if (a.x == b.x && a.y == b.y) return (bad = (i + 1) % n, "two consecutive points are equal");
  }
  for (std::size_t i = 0; i < n; ++i) {
    // Adjacent edges a-b, b-c: collinear and turning back means they overlap.
    const D a = dv(p[i]), b = dv(p[(i + 1) % n]), c = dv(p[(i + 2) % n]);
    const double dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y);
    if (orient(p[i], p[(i + 1) % n], p[(i + 2) % n]) == 0 && dot < 0) {
      return (bad = (i + 1) % n, "polygon folds back on itself");
    }
  }
  for (std::size_t i = 0; i < n; ++i) {
    for (std::size_t k = i + 2; k < n; ++k) {
      if (i == 0 && k == n - 1) continue;  // adjacent through the closing edge
      if (segments_touch(p[i], p[(i + 1) % n], p[k], p[(k + 1) % n])) {
        return (bad = k, "polygon is not simple (edges intersect)");
      }
    }
  }
  return nullptr;
}

bool has_em_dash(std::string_view s) { return s.find("\xE2\x80\x94") != std::string_view::npos; }

// menus.md §1.3: the preset whose band holds an explicit shift amplitude.
ShiftPreset shift_band(float a) {
  const float deg = a / DEG;
  if (deg < 1.5f) return ShiftPreset::steady;
  if (deg < 5.5f) return ShiftPreset::stable;
  if (deg < 11.5f) return ShiftPreset::oscillating;
  if (deg < 20.0f) return ShiftPreset::shifty;
  return ShiftPreset::unstable;
}

class VenueReader {
 public:
  VenueReader(ErrorSink& sink, VenueData& out) : sink_(sink), out_(out) {}

  bool read(const Value& root) {
    if (!data::check_schema(root, "windmark.venue", 1, sink_)) return false;
    return header(root) && wind_field(root) && current_field(root) && exposure(root) && land(root) &&
           obstacles(root) && conditions(root) && briefing(root);
  }

 private:
  ErrorSink& sink_;
  VenueData& out_;

  bool fail(const std::string& path, std::string_view why) { return sink_.fail(path, why); }

  bool ranged(const Value& obj, const std::string& path, std::string_view key, float& out, float lo, float hi) {
    if (!read_float(obj, path, key, out, sink_)) return false;
    if (out < lo || out > hi) return fail(path_key(path, key), "value outside its allowed range");
    return true;
  }

  bool header(const Value& root) {
    if (!data::read_string(root, "$", "id", out_.id, sink_)) return false;
    if (!data::is_valid_id(out_.id)) return fail("$.id", "ids are lowercase [a-z0-9_]");
    if (!data::read_string(root, "$", "name", out_.name, sink_)) return false;
    if (has_em_dash(out_.name)) return fail("$.name", "player-facing: no em dashes");
    if (!data::read_int(root, "$", "version", out_.version, sink_)) return false;
    if (out_.version < 1) return fail("$.version", "must be >= 1");

    if (const Value* o = root.find("origin")) {
      if (!data::expect_object(*o, "$.origin", sink_)) return false;
      if (!ranged(*o, "$.origin", "lat", out_.origin_lat, -90.0f, 90.0f)) return false;
      if (!ranged(*o, "$.origin", "lon", out_.origin_lon, -180.0f, 180.0f)) return false;
      out_.has_origin = true;
    }

    const Value* b = member(root, "$", "bounds", true, sink_);
    if (b == nullptr) return false;
    if (!b->is_array() || b->items.size() != 4) return fail("$.bounds", "expected [xmin, ymin, xmax, ymax]");
    for (std::size_t i = 0; i < 4; ++i) {
      const std::string p = path_index("$.bounds", i);
      if (!read_float_value(b->items[i], p, out_.bounds[i], sink_)) return false;
      if (out_.bounds[i] < -kBoundsMax || out_.bounds[i] > kBoundsMax) return fail(p, "bounds lie within ±8000 m");
    }
    if (!(out_.bounds[0] < out_.bounds[2]) || !(out_.bounds[1] < out_.bounds[3])) {
      return fail("$.bounds", "needs xmin < xmax and ymin < ymax");
    }

    if (root.find("fetch") != nullptr) {
      if (!read_float(root, "$", "fetch", out_.fetch, sink_)) return false;
      if (!(out_.fetch > 0.0f)) return fail("$.fetch", "must be > 0");
    }
    if (root.find("exposure_default") != nullptr &&
        !ranged(root, "$", "exposure_default", out_.exposure_default, 0.0f, 1.0f)) {
      return false;
    }
    return true;
  }

  // §6.6
  bool grid(const Value& obj, const std::string& path, Grid& g) {
    const Value* gv = member(obj, path, "grid", true, sink_);
    const std::string p = path_key(path, "grid");
    if (gv == nullptr || !data::expect_object(*gv, p, sink_)) return false;
    if (!read_float(*gv, p, "x0", g.x0, sink_) || !read_float(*gv, p, "y0", g.y0, sink_)) return false;
    if (!read_float(*gv, p, "dx", g.dx, sink_)) return false;
    if (!(g.dx > 0.0f)) return fail(path_key(p, "dx"), "must be > 0");
    if (!read_float(*gv, p, "dy", g.dy, sink_)) return false;
    if (!(g.dy > 0.0f)) return fail(path_key(p, "dy"), "must be > 0");
    std::int64_t nx = 0, ny = 0;
    if (!data::read_int(*gv, p, "nx", nx, sink_)) return false;
    if (nx < 2 || nx > kGridMaxSide) return fail(path_key(p, "nx"), "a grid side has 2 to 1024 nodes");
    if (!data::read_int(*gv, p, "ny", ny, sink_)) return false;
    if (ny < 2 || ny > kGridMaxSide) return fail(path_key(p, "ny"), "a grid side has 2 to 1024 nodes");
    g.nx = static_cast<std::uint32_t>(nx);
    g.ny = static_cast<std::uint32_t>(ny);
    return true;
  }

  // One value array of nx*ny finite numbers, each in [lo, hi].
  bool values(const Value& obj, const std::string& path, std::string_view key, const Grid& g,
              std::vector<float>& out, float lo, float hi) {
    const Value* v = member(obj, path, key, true, sink_);
    if (v == nullptr) return false;
    const std::string p = path_key(path, key);
    if (!v->is_array()) return fail(p, "expected an array");
    const std::size_t n = g.node_count();
    if (v->items.size() != n) {
      return fail(p, "expected " + std::to_string(n) + " values (nx*ny), found " + std::to_string(v->items.size()));
    }
    out.resize(n);
    for (std::size_t i = 0; i < n; ++i) {
      if (!read_float_value(v->items[i], path_index(p, i), out[i], sink_)) return false;
      if (out[i] < lo || out[i] > hi) return fail(path_index(p, i), "value outside its allowed range");
    }
    return true;
  }

  // §6.2
  bool wind_field(const Value& root) {
    const Value* wv = root.find("wind_field");
    if (wv == nullptr) return true;
    const std::string p = "$.wind_field";
    if (!data::expect_object(*wv, p, sink_)) return false;
    VenueWindField& w = out_.wind_field;
    if (!grid(*wv, p, w.grid)) return false;
    const Value* sv = member(*wv, p, "sectors", true, sink_);
    if (sv == nullptr) return false;
    const std::string sp = p + ".sectors";
    if (!sv->is_array() || sv->items.size() != 8) return fail(sp, "expected 8 sectors (from N, NE, E, SE, S, SW, W, NW)");
    for (std::size_t k = 0; k < 8; ++k) {
      const std::string kp = path_index(sp, k);
      if (!data::expect_object(sv->items[k], kp, sink_)) return false;
      if (!values(sv->items[k], kp, "f", w.grid, w.f[k], 0.0f, INFINITY)) return false;
      if (!values(sv->items[k], kp, "d", w.grid, w.d[k], -PI, PI)) return false;
      for (std::uint32_t j = 0; j < w.grid.ny; ++j) {
        for (std::uint32_t i = 0; i < w.grid.nx; ++i) {
          if (i != 0 && j != 0 && i != w.grid.nx - 1 && j != w.grid.ny - 1) continue;
          const std::size_t r = static_cast<std::size_t>(j) * w.grid.nx + i;
          if (w.f[k][r] != 1.0f) return fail(path_index(kp + ".f", r), "border nodes must be f = 1");
          if (w.d[k][r] != 0.0f) return fail(path_index(kp + ".d", r), "border nodes must be d = 0");
        }
      }
    }
    out_.has_wind_field = true;
    return true;
  }

  // §6.3
  bool current_field(const Value& root) {
    const Value* cv = root.find("current_field");
    if (cv == nullptr) return true;
    const std::string p = "$.current_field";
    if (!data::expect_object(*cv, p, sink_)) return false;
    VenueCurrentField& c = out_.current_field;
    if (!grid(*cv, p, c.grid)) return false;
    if (!values(*cv, p, "vx", c.grid, c.vx, -INFINITY, INFINITY)) return false;
    if (!values(*cv, p, "vy", c.grid, c.vy, -INFINITY, INFINITY)) return false;
    if (cv->find("ref_speed") != nullptr) {
      if (!read_float(*cv, p, "ref_speed", out_.ref_speed, sink_)) return false;
      if (!(out_.ref_speed >= 0.0f)) return fail(p + ".ref_speed", "must be >= 0");
      out_.has_ref_speed = true;
    }
    out_.has_current_field = true;
    return true;
  }

  // §6.4
  bool exposure(const Value& root) {
    const Value* ev = root.find("exposure");
    if (ev == nullptr) return true;
    const std::string p = "$.exposure";
    if (!data::expect_object(*ev, p, sink_)) return false;
    VenueExposure& e = out_.exposure;
    if (!grid(*ev, p, e.grid)) return false;
    if (!values(*ev, p, "e", e.grid, e.e, 0.0f, 1.0f)) return false;
    out_.has_exposure = true;
    return true;
  }

  // ---- §6.7 conditions --------------------------------------------------------------------------------------

  // An optional number at obj.key, in [lo, hi]; `out` keeps its value when the key is absent.
  bool opt(const Value& obj, const std::string& path, std::string_view key, float& out, float lo, float hi,
           bool* given = nullptr) {
    if (obj.find(key) == nullptr) return true;
    if (!read_float(obj, path, key, out, sink_)) return false;
    if (out < lo || out > hi) return fail(path_key(path, key), "value outside its allowed range");
    if (given != nullptr) *given = true;
    return true;
  }

  // [min, max] with lo <= min <= max <= hi.
  bool range(const Value& obj, const std::string& path, std::string_view key, float& a, float& b, float lo, float hi) {
    const Value* v = obj.find(key);
    if (v == nullptr) return true;
    const std::string p = path_key(path, key);
    if (!v->is_array() || v->items.size() != 2) return fail(p, "expected [min, max]");
    if (!read_float_value(v->items[0], path_index(p, 0), a, sink_)) return false;
    if (!read_float_value(v->items[1], path_index(p, 1), b, sink_)) return false;
    if (!(lo <= a && a <= b && b <= hi)) return fail(p, "needs min <= max within the allowed range");
    return true;
  }

  bool object(const Value& parent, const std::string& path, std::string_view key, const Value*& out) {
    out = parent.find(key);
    return out == nullptr || data::expect_object(*out, path_key(path, key), sink_);
  }

  static bool shift_name(std::string_view s, ShiftPreset& out) {
    constexpr std::string_view names[] = {"steady", "stable", "oscillating", "shifty", "unstable"};
    for (std::size_t i = 0; i < 5; ++i)
      if (s == names[i]) return (out = static_cast<ShiftPreset>(i), true);
    return false;
  }
  static bool puff_name(std::string_view s, PuffPreset& out) {
    constexpr std::string_view names[] = {"none", "light", "standard", "gusty"};
    for (std::size_t i = 0; i < 4; ++i)
      if (s == names[i]) return (out = static_cast<PuffPreset>(i), true);
    return false;
  }

  bool puff_override(const std::string& p, std::string_view key, const Value& v, PuffParams& q) {
    float x = 0.0f;
    if (!read_float_value(v, p, x, sink_)) return false;
    if (!(x >= 0.0f)) return fail(p, "must be >= 0");
    auto count = [&](std::uint32_t& c) {
      if (x != std::floor(x) || x > 64.0f) return fail(p, "a whole number of slots, at most 64");
      c = static_cast<std::uint32_t>(x);
      return true;
    };
    auto life = [&](std::uint32_t& ms) {
      if (x > 3600.0f) return fail(p, "at most 3600 s");
      ms = static_cast<std::uint32_t>(std::lround(static_cast<double>(x) * 1000.0));
      return true;
    };
    if (key == "puff_tile") q.tile = x;
    else if (key == "puff_count") return count(q.puff_count);
    else if (key == "lull_count") return count(q.lull_count);
    else if (key == "puff_diameter_min") q.diameter_min = x;
    else if (key == "puff_diameter_max") q.diameter_max = x;
    else if (key == "puff_strength_min") q.puff_strength_min = x;
    else if (key == "puff_strength_max") q.puff_strength_max = x;
    else if (key == "lull_strength_min") q.lull_strength_min = x;
    else if (key == "lull_strength_max") q.lull_strength_max = x;
    else if (key == "puff_life_min") return life(q.life_min_ms);
    else if (key == "puff_life_max") return life(q.life_max_ms);
    else if (key == "puff_cap_up") q.cap_up = x;
    else if (key == "puff_cap_down") q.cap_down = x;
    else return fail(p, "unknown puff parameter");
    return true;
  }

  bool conditions(const Value& root) {
    const Value* cv = root.find("conditions");
    if (cv == nullptr) return true;
    const std::string p = "$.conditions";
    if (!data::expect_object(*cv, p, sink_)) return false;
    VenueConditions& c = out_.conditions;
    constexpr float kSpeedLo = 2.06f, kSpeedHi = 12.87f;  // the menu's 4 to 25 kn

    const Value* o = nullptr;
    if (!object(*cv, p, "wind", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".wind";
      if (!range(*o, q, "speed", c.speed_min, c.speed_max, kSpeedLo, kSpeedHi)) return false;
      if (!opt(*o, q, "from", c.from, 0.0f, TWO_PI)) return false;
      if (o->find("from") != nullptr && !(c.from < TWO_PI)) return fail(q + ".from", "in [0, 2 pi)");
      if (!opt(*o, q, "from_spread", c.from_spread, 0.0f, 0.349f)) return false;
    }

    if (!object(*cv, p, "shift", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".shift";
      if (const Value* pv = o->find("preset")) {
        if (!pv->is_string() || !shift_name(pv->text, c.shift_preset)) return fail(q + ".preset", "unknown shift preset");
      }
      if (!opt(*o, q, "amplitude", c.shift_amplitude, 0.0f, PI, &c.has_shift_amplitude)) return false;
      if (!opt(*o, q, "hold_max", c.hold_max_s, 0.0f, 3600.0f, &c.has_hold_max)) return false;
      if (!opt(*o, q, "hold_min", c.hold_min_s, 0.0f, 3600.0f, &c.has_hold_min)) return false;
      if (!opt(*o, q, "trend_rate", c.trend_rate, -1.0f, 1.0f)) return false;
      if (!opt(*o, q, "trend_max", c.trend_max, 0.0f, 0.35f)) return false;
      WindSettings w;
      c.local_shift(w);
      if (w.shift_hold_min_ms > w.shift_hold_max_ms) return fail(q + ".hold_min", "needs hold_min <= hold_max");
    }

    if (!object(*cv, p, "oscillation", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".oscillation";
      if (!read_float(*o, q, "amplitude", c.osc_amplitude, sink_)) return false;
      if (!(c.osc_amplitude >= 0.0f && c.osc_amplitude <= 0.087f)) return fail(q + ".amplitude", "in [0, 0.087]");
      if (!read_float(*o, q, "time_scale", c.osc_time_scale, sink_)) return false;
      if (!(c.osc_time_scale > 0.0f)) return fail(q + ".time_scale", "must be > 0");
      c.has_oscillation = true;
    }

    {
      WindSettings w;
      apply_puff_preset(w, c.puff_preset);
      if (!object(*cv, p, "puffs", o)) return false;
      if (o != nullptr) {
        const std::string q = p + ".puffs";
        if (const Value* pv = o->find("preset")) {
          if (!pv->is_string() || !puff_name(pv->text, c.puff_preset)) return fail(q + ".preset", "unknown puff preset");
        }
        apply_puff_preset(w, c.puff_preset);
        for (const auto& [k, v] : o->members) {
          if (k == "preset") continue;
          if (!puff_override(path_key(q, k), k, v, w.puffs)) return false;
        }
        if (w.puffs_enabled) {
          if (const char* why = check_wind_settings(w)) return fail(q, why);
        }
      }
      c.puffs = w.puffs;
      c.puffs_enabled = w.puffs_enabled;
    }

    if (!object(*cv, p, "current", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".current";
      if (!opt(*o, q, "speed", c.current_speed, 0.0f, 10.0f)) return false;
      if (!opt(*o, q, "to", c.current_to, -TWO_PI, 2.0f * TWO_PI)) return false;
    }

    if (!object(*cv, p, "tide", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".tide";
      if (!out_.has_current_field) return fail(q, "a tide needs a current_field");
      if (!read_float(*o, q, "scale", c.tide_scale, sink_)) return false;
      if (!(c.tide_scale >= 0.0f && c.tide_scale <= 100.0f)) return fail(q + ".scale", "must be >= 0");
      std::int64_t per = 0;
      if (!data::read_int(*o, q, "period", per, sink_)) return false;
      if (per <= 0 || per > 4000000) return fail(q + ".period", "a whole number of seconds > 0");
      c.tide_period_s = static_cast<std::uint32_t>(per);
      if (o->find("turn") == nullptr) return fail(q + ".turn", "required");
      if (!range(*o, q, "turn", c.turn_a, c.turn_b, 0.0f, 1.0f)) return false;
      if (!(c.turn_b - c.turn_a <= 0.4f + 1e-6f)) return fail(q + ".turn", "b - a <= 0.4");
      std::int64_t to = 0;
      if (!data::read_int(*o, q, "turn_to", to, sink_)) return false;
      if (to != 1 && to != -1) return fail(q + ".turn_to", "+1 or -1");
      c.turn_to = static_cast<std::int32_t>(to);
      c.has_tide = true;
    }

    if (!object(*cv, p, "sea", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".sea";
      if (!opt(*o, q, "scale", c.sea_scale, 0.0f, 100.0f)) return false;
      if (const Value* sv = o->find("swells")) {
        const std::string sp = q + ".swells";
        if (!sv->is_array() || sv->items.size() > SeaSettings::kMaxSwells) return fail(sp, "at most 4 swells");
        for (std::size_t i = 0; i < sv->items.size(); ++i) {
          const std::string ip = path_index(sp, i);
          if (!data::expect_object(sv->items[i], ip, sink_)) return false;
          WaveTrain w;
          if (!read_float(sv->items[i], ip, "hs", w.hs, sink_) || !read_float(sv->items[i], ip, "tp", w.tp, sink_) ||
              !read_float(sv->items[i], ip, "from", w.from, sink_)) {
            return false;
          }
          if (!(w.hs >= 0.0f)) return fail(ip + ".hs", "must be >= 0");
          if (!(w.tp > 0.0f) && w.hs > 0.0f) return fail(ip + ".tp", "must be > 0 when hs > 0");
          c.swells.push_back(w);
        }
      }
    }

    // random, each key missing widened from the local values (data_format.md §6.7)
    constexpr float kKn4 = 4.0f * 0.514444f;
    c.r_speed_min = std::fmax(c.speed_min - kKn4, kSpeedLo);
    c.r_speed_max = std::fmin(c.speed_max + kKn4, kSpeedHi);
    c.r_from_spread = std::fmin(2.0f * c.from_spread, 0.785f);
    ShiftPreset sp = c.shift_preset;
    if (c.has_shift_amplitude) sp = shift_band(c.shift_amplitude);
    for (int k = static_cast<int>(sp) - 1; k <= static_cast<int>(sp) + 1; ++k)
      if (k >= 0 && k <= 4) c.r_shift.push_back(static_cast<ShiftPreset>(k));
    for (int k = static_cast<int>(c.puff_preset) - 1; k <= static_cast<int>(c.puff_preset) + 1; ++k) {
      if (k < 0 || k > 3) continue;
      if (k == 0 && c.puff_preset != PuffPreset::none) continue;
      c.r_puffs.push_back(static_cast<PuffPreset>(k));
    }
    if (!object(*cv, p, "random", o)) return false;
    if (o != nullptr) {
      const std::string q = p + ".random";
      if (!range(*o, q, "speed", c.r_speed_min, c.r_speed_max, kSpeedLo, kSpeedHi)) return false;
      if (!opt(*o, q, "from_spread", c.r_from_spread, 0.0f, 0.785f)) return false;
      if (const Value* lv = o->find("shift")) {
        if (!lv->is_array() || lv->items.empty()) return fail(q + ".shift", "a non-empty list of shift presets");
        c.r_shift.clear();
        for (std::size_t i = 0; i < lv->items.size(); ++i) {
          ShiftPreset s{};
          if (!lv->items[i].is_string() || !shift_name(lv->items[i].text, s))
            return fail(path_index(q + ".shift", i), "unknown shift preset");
          c.r_shift.push_back(s);
        }
      }
      if (const Value* lv = o->find("puffs")) {
        if (!lv->is_array() || lv->items.empty()) return fail(q + ".puffs", "a non-empty list of puff presets");
        c.r_puffs.clear();
        for (std::size_t i = 0; i < lv->items.size(); ++i) {
          PuffPreset s{};
          if (!lv->items[i].is_string() || !puff_name(lv->items[i].text, s))
            return fail(path_index(q + ".puffs", i), "unknown puff preset");
          c.r_puffs.push_back(s);
        }
      }
      if (!range(*o, q, "tide_scale", c.r_tide_min, c.r_tide_max, 0.0f, 100.0f)) return false;
      if (!range(*o, q, "swell_scale", c.r_swell_min, c.r_swell_max, 0.0f, 100.0f)) return false;
    }
    out_.has_conditions = true;
    return true;
  }

  // ---- §6.8 briefing: the core ignores it but refuses em dashes in player-facing text -----------------------
  bool briefing(const Value& root) {
    const Value* bv = root.find("briefing");
    if (bv == nullptr) return true;
    if (!data::expect_object(*bv, "$.briefing", sink_)) return false;
    for (const char* k : {"tag", "tip"}) {
      const Value* v = bv->find(k);
      if (v != nullptr && (!v->is_string() || has_em_dash(v->text)))
        return fail(path_key("$.briefing", k), "a string without em dashes");
    }
    if (const Value* tv = bv->find("translations")) {
      if (!data::expect_object(*tv, "$.briefing.translations", sink_)) return false;
      for (const auto& [lang, tr] : tv->members) {
        const std::string lp = path_key("$.briefing.translations", lang);
        if (!data::expect_object(tr, lp, sink_)) return false;
        for (const auto& [k, v] : tr.members)
          if (!v.is_string() || has_em_dash(v.text)) return fail(path_key(lp, k), "a string without em dashes");
      }
    }
    return true;
  }

  bool id(const Value& obj, const std::string& path, std::string& out, const std::vector<std::string>& seen) {
    if (!data::read_string(obj, path, "id", out, sink_)) return false;
    if (!data::is_valid_id(out)) return fail(path + ".id", "ids are lowercase [a-z0-9_]");
    for (const std::string& s : seen)
      if (s == out) return fail(path + ".id", "duplicate id \"" + out + "\"");
    return true;
  }

  bool simple(const std::vector<Vec2>& pts, const std::string& path) {
    std::size_t bad = 0;
    if (const char* why = check_simple(pts, bad)) return fail(pts.size() < 3 ? path : path_index(path, bad), why);
    return true;
  }

  // §6.5 land
  bool land(const Value& root) {
    const Value* lv = root.find("land");
    if (lv == nullptr) return true;
    if (!lv->is_array()) return fail("$.land", "expected an array");
    std::vector<std::string> seen;
    for (std::size_t i = 0; i < lv->items.size(); ++i) {
      const Value& e = lv->items[i];
      const std::string p = path_index("$.land", i);
      if (!data::expect_object(e, p, sink_)) return false;
      VenueLand l;
      if (!id(e, p, l.id, seen)) return false;
      const Value* pv = member(e, p, "points", true, sink_);
      if (pv == nullptr || !data::read_points(*pv, p + ".points", l.points, sink_)) return false;
      if (!simple(l.points, p + ".points")) return false;
      if (!(twice_area(l.points) > 0.0)) return fail(p + ".points", "land must be counter-clockwise");
      l.index.build(l.points);
      seen.push_back(l.id);
      out_.land.push_back(std::move(l));
    }
    return true;
  }

  // §6.5 obstacles
  bool obstacles(const Value& root) {
    const Value* ov = root.find("obstacles");
    if (ov == nullptr) return true;
    if (!ov->is_array()) return fail("$.obstacles", "expected an array");
    std::vector<std::string> seen;
    for (std::size_t i = 0; i < ov->items.size(); ++i) {
      const Value& e = ov->items[i];
      const std::string p = path_index("$.obstacles", i);
      if (!data::expect_object(e, p, sink_)) return false;
      VenueObstacle o;
      if (!id(e, p, o.id, seen)) return false;
      const Value* pv = e.find("polygon");
      const Value* cv = e.find("circle");
      if ((pv == nullptr) == (cv == nullptr)) return fail(p, "an obstacle has exactly one of polygon and circle");
      if (pv != nullptr) {
        const std::string pp = p + ".polygon";
        if (!data::read_points(*pv, pp, o.polygon, sink_)) return false;
        if (!simple(o.polygon, pp)) return false;
        const std::size_t n = o.polygon.size();
        for (std::size_t k = 0; k < n; ++k) {
          if (!(orient(o.polygon[k], o.polygon[(k + 1) % n], o.polygon[(k + 2) % n]) > 0.0)) {
            return fail(path_index(pp, (k + 1) % n), "obstacle polygon not strictly convex and counter-clockwise");
          }
        }
      } else {
        const std::string cp = p + ".circle";
        if (!data::expect_object(*cv, cp, sink_)) return false;
        const Value* centre = member(*cv, cp, "c", true, sink_);
        if (centre == nullptr) return false;
        const std::string ccp = cp + ".c";
        if (!centre->is_array() || centre->items.size() != 2) return fail(ccp, "expected an [x, y] pair");
        if (!read_float_value(centre->items[0], path_index(ccp, 0), o.c.x, sink_)) return false;
        if (!read_float_value(centre->items[1], path_index(ccp, 1), o.c.y, sink_)) return false;
        o.is_circle = true;
        if (!read_float(*cv, cp, "r", o.r, sink_)) return false;
        if (!(o.r > 0.0f)) return fail(cp + ".r", "must be > 0");
      }
      seen.push_back(o.id);
      out_.obstacles.push_back(std::move(o));
    }
    return true;
  }
};

}  // namespace

bool parse_venue(std::string_view text, std::string_view file, VenueData& out, LoadError& err) {
  out = VenueData{};
  err = LoadError{};
  ErrorSink sink(err, file);
  const json::ParseResult pr = json::parse(text);
  if (!pr.ok) return sink.fail("", "JSON: " + pr.error);
  VenueReader reader(sink, out);
  if (!reader.read(pr.value)) {
    out = VenueData{};
    return false;
  }
  const auto* bytes = reinterpret_cast<const std::uint8_t*>(text.data());
  out.file_sha256 = to_hex(sha256(std::span<const std::uint8_t>(bytes, text.size())));
  return true;
}

bool load_venue(const std::string& file, VenueData& out, LoadError& err) {
  out = VenueData{};
  std::string text;
  if (!data::read_file(file, text, err)) return false;
  return parse_venue(text, file, out, err);
}

void VenueConditions::local_shift(WindSettings& w) const {
  apply_shift_preset(w, shift_preset);
  if (has_shift_amplitude) w.shift_amplitude = shift_amplitude;
  if (has_hold_max) {
    w.shift_hold_max_ms = static_cast<std::uint32_t>(std::lround(static_cast<double>(hold_max_s) * 1000.0));
    w.shift_hold_min_ms = w.shift_hold_max_ms / 5;
  }
  if (has_hold_min) w.shift_hold_min_ms = static_cast<std::uint32_t>(std::lround(static_cast<double>(hold_min_s) * 1000.0));
}

void apply_venue(const VenueData& v, WindSettings& wind, SeaSettings& sea) {
  wind.venue_wind_field = v.wind_field_ptr();
  wind.venue_current_field = v.current_field_ptr();
  sea.exposure = v.exposure_ptr();
  sea.exposure_default = v.exposure_default;
}

}  // namespace wm
