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

class VenueReader {
 public:
  VenueReader(ErrorSink& sink, VenueData& out) : sink_(sink), out_(out) {}

  bool read(const Value& root) {
    if (!data::check_schema(root, "windmark.venue", 1, sink_)) return false;
    return header(root) && wind_field(root) && current_field(root) && exposure(root) && land(root) &&
           obstacles(root);
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

void apply_venue(const VenueData& v, WindSettings& wind, SeaSettings& sea) {
  wind.venue_wind_field = v.wind_field_ptr();
  wind.venue_current_field = v.current_field_ptr();
  sea.exposure = v.exposure_ptr();
  sea.exposure_default = v.exposure_default;
}

}  // namespace wm
