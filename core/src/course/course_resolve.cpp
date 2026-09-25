// Laying a course for one race (courses.md §3, §4, §6), its geometry checks (§7) and the canonical form (§9).
#include <cmath>
#include <cstdio>
#include <span>

#include "course/course.h"
#include "course/geometry.h"
#include "state/sha256.h"

namespace wm {

namespace {

Vec2 resolve_pos(const CoursePos& p, const std::vector<Vec2>& known, Vec2 reference, float twd_c, float k) {
  if (!p.offset) return p.world;
  Vec2 base = reference;
  if (p.base_a >= 0 && p.base_b >= 0) {
    base = v_mid(known[static_cast<std::size_t>(p.base_a)], known[static_cast<std::size_t>(p.base_b)]);
  } else if (p.base_a >= 0) {
    base = known[static_cast<std::size_t>(p.base_a)];
  }
  const float d = p.fixed ? p.dist : k * p.dist;
  const Vec2 u = dir(wrap_2pi(twd_c + p.bearing));
  return {base.x + d * u.x, base.y + d * u.y};
}

// courses.md §2: the default committee / mark boat outline, the collisions.md §2.1 construction with transom 0.8·B
// and s_m = 0.5 tabulated once as literal fractions (station x / L, half-breadth / B), so no power function runs.
constexpr float kOutlineX[8] = {-0.5f, -0.35f, -0.2f, 0.0f, 0.1f, 0.25f, 0.37f, 0.45f};
constexpr float kOutlineHalf[8] = {0.4f, 0.451f, 0.484f, 0.5f, 0.4724054f, 0.3564127f, 0.2092049f, 0.0863752f};

std::vector<Vec2> boat_outline(float L, float B) {
  std::vector<Vec2> out;
  for (std::size_t i = 0; i < 8; ++i) out.push_back({kOutlineX[i] * L, -(kOutlineHalf[i] * B)});
  out.push_back({0.5f * L, 0.0f});
  for (std::size_t i = 8; i-- > 0;) out.push_back({kOutlineX[i] * L, kOutlineHalf[i] * B});
  return out;
}

}  // namespace

std::vector<Vec2> default_boat_outline(float L, float B) { return boat_outline(L, B); }

namespace {

void fmt(std::string& s, float f) {
  char buf[40];
  std::snprintf(buf, sizeof buf, "%.9g", static_cast<double>(f));
  s += buf;
}

void fmt_pt(std::string& s, Vec2 p) {
  s += '[';
  fmt(s, p.x);
  s += ',';
  fmt(s, p.y);
  s += ']';
}

void fmt_poly(std::string& s, const std::vector<Vec2>& p) {
  s += '[';
  for (std::size_t i = 0; i < p.size(); ++i) {
    if (i > 0) s += ',';
    fmt_pt(s, p[i]);
  }
  s += ']';
}

void quoted(std::string& s, std::string_view v) {
  s += '"';
  for (char c : v) {
    if (c == '"' || c == '\\') s += '\\';
    s += c;
  }
  s += '"';
}

std::string_view step_kind_name(StepKind k) {
  switch (k) {
    case StepKind::start: return "start";
    case StepKind::mark: return "mark";
    case StepKind::gate: return "gate";
    case StepKind::finish: return "finish";
  }
  return "?";
}

}  // namespace

float course_axis(float median_from) { return wrap_2pi(round_half_even(median_from * 100.0f) * 0.01f); }

void resolve_course(const CourseData& c, float twd_c, float k, ResolvedCourse& out) {
  out = ResolvedCourse{};
  out.id = c.id;
  out.venue = c.venue;
  out.frame = c.frame;
  out.twd_c = twd_c;
  out.k = c.frame == CourseFrame::wind ? k : 1.0f;
  out.race = c.race;
  const float kk = out.k;

  std::vector<Vec2> pos;
  for (const CourseMark& m : c.marks) pos.push_back(resolve_pos(m.at, pos, c.reference, twd_c, kk));

  // courses.md §4.2: bias rotates the start line about its midpoint, clockwise for a positive angle.
  if (c.start_bias != 0.0f) {
    const std::size_t ia = static_cast<std::size_t>(c.start_ends[0]), ib = static_cast<std::size_t>(c.start_ends[1]);
    const Vec2 m = v_mid(pos[ia], pos[ib]);
    const SinCos sc = wm_sincos(c.start_bias);
    for (std::size_t i : {ia, ib}) {
      const Vec2 v = v_sub(pos[i], m);
      pos[i] = {m.x + (v.x * sc.c + v.y * sc.s), m.y + (v.y * sc.c - v.x * sc.s)};
    }
  }

  for (std::size_t i = 0; i < c.marks.size(); ++i) {
    const CourseMark& m = c.marks[i];
    ResolvedMark r;
    r.type = m.type;
    r.pos = pos[i];
    r.radius = m.radius;
    r.length = m.length;
    r.beam = m.beam;
    const bool boat = m.type == MarkType::committee_boat || m.type == MarkType::mark_boat;
    r.heading = boat ? (m.head_to_wind ? twd_c : m.heading) : 0.0f;
    out.mark_ids.push_back(m.id);
    out.marks.push_back(r);
    if (m.type == MarkType::virtual_point) continue;
    CourseObject o;
    o.mark = static_cast<std::int32_t>(i);
    o.is_boat = boat;
    o.c = r.pos;
    o.heading = r.heading;
    if (boat) {
      o.outline = m.outline.empty() ? boat_outline(m.length, m.beam) : m.outline;
      place_outline(o.outline, r.pos, r.heading, o.polygon);
      float rr = 0.0f;
      for (const Vec2 v : o.outline) rr = max(rr, v_len(v));
      o.r = rr;
    } else {
      o.r = r.radius;
    }
    out.objects.push_back(std::move(o));
  }

  // Steps and their reference points (race.md §5).
  out.steps = c.expanded;
  for (CourseStep& s : out.steps) {
    const Vec2 a = pos[static_cast<std::size_t>(s.marks[0])];
    s.ref = s.kind == StepKind::mark ? a : v_mid(a, pos[static_cast<std::size_t>(s.marks[1])]);
  }
  const std::size_t n = out.steps.size();
  for (std::size_t i = 1; i + 1 < n; ++i) {
    CourseStep& s = out.steps[i];
    if (s.kind != StepKind::gate) continue;
    // courses.md §4.3: with P the previous reference and m the gate midpoint, the buoy left of P→m is rounded to
    // port.
    if (!s.sides_given) {
      const Vec2 P = out.steps[i - 1].ref;
      const float l0 = side_left(pos[static_cast<std::size_t>(s.marks[0])], P, s.ref);
      s.sides[0] = l0 > 0.0f ? Side::port : Side::starboard;
      s.sides[1] = l0 > 0.0f ? Side::starboard : Side::port;
    }
  }
  // Line orientation: the course side on the left of A→B (race.md §3.3, §6.1).
  {
    CourseStep& s = out.steps.front();
    if (side_left(out.steps[1].ref, pos[static_cast<std::size_t>(s.marks[0])], pos[static_cast<std::size_t>(s.marks[1])]) < 0.0f) {
      std::swap(s.marks[0], s.marks[1]);
    }
    CourseStep& f = out.steps.back();
    if (side_left(out.steps[n - 2].ref, pos[static_cast<std::size_t>(f.marks[0])], pos[static_cast<std::size_t>(f.marks[1])]) < 0.0f) {
      std::swap(f.marks[0], f.marks[1]);
    }
  }
  out.laps = out.steps.back().lap;
  out.legs_per_lap.assign(static_cast<std::size_t>(out.laps), 0);
  for (std::size_t i = 1; i < n; ++i) {
    std::int32_t& l = out.legs_per_lap[static_cast<std::size_t>(out.steps[i].lap - 1)];
    l = l > out.steps[i].leg_in_lap ? l : out.steps[i].leg_in_lap;
  }

  auto poly = [&](const std::vector<CoursePos>& in) {
    std::vector<Vec2> r;
    for (const CoursePos& p : in) r.push_back(resolve_pos(p, pos, c.reference, twd_c, kk));
    return r;
  };
  out.has_boundary = c.has_boundary;
  if (c.has_boundary) out.boundary = poly(c.boundary);
  for (const CourseExclusion& e : c.exclusions) out.exclusions.push_back(poly(e.polygon));
  out.has_spawn = c.has_spawn;
  if (c.has_spawn) out.spawn = poly(c.spawn);
}

// ---- Polar helpers ----

PolarVmg polar_vmg(const PerfData& perf, float tws) {
  PolarVmg r;
  for (const ConfigPerf& cfg : perf.configs) {
    for (std::int32_t i = 0; i <= 360; ++i) {
      const float twa = static_cast<float>(i) * (PI / 360.0f);
      const float v = cfg.polar.at(tws, twa);
      const float c = wm_cos(twa);
      const float up = v * c, down = -(v * c);
      if (up > r.up_speed) {
        r.up_speed = up;
        r.up_twa = twa;
      }
      if (down > r.down_speed) {
        r.down_speed = down;
        r.down_twa = twa;
      }
    }
  }
  return r;
}

float polar_best(const PerfData& perf, float tws, float twa_abs) {
  float best = 0.0f;
  for (const ConfigPerf& cfg : perf.configs) best = max(best, cfg.polar.at(tws, twa_abs));
  return best;
}

float course_scale(const CourseData& c, float twd_c, const PerfData& perf, float tws) {
  if (c.frame != CourseFrame::wind || !(c.race.target_duration > 0.0f)) return 1.0f;
  ResolvedCourse rc;
  resolve_course(c, twd_c, 1.0f, rc);
  const PolarVmg vmg = polar_vmg(perf, tws);
  const Vec2 w = dir(twd_c);
  float t_est = 0.0f;
  for (std::size_t j = 1; j < rc.steps.size(); ++j) {
    const Vec2 d = v_sub(rc.steps[j].ref, rc.steps[j - 1].ref);
    const float len = v_len(d);
    if (!(len > 0.0f)) continue;
    const float along = v_dot(d, w);
    float ell, V;
    if (std::fabs(along) >= 0.707106781f * len) {  // within 45° of the wind axis: beat or run
      ell = std::fabs(along);
      V = along > 0.0f ? vmg.up_speed : vmg.down_speed;
    } else {
      ell = len;
      V = polar_best(perf, tws, std::fabs(wrap_pi(twd_c - compass(d))));
    }
    if (V > 0.0f) t_est = t_est + ell / V;
  }
  if (!(t_est > 0.0f)) return 1.0f;
  return clamp(c.race.target_duration / t_est, 0.5f, 2.0f);
}

// ---- Canonical form (courses.md §9) ----

std::string ResolvedCourse::canonical_json() const {
  std::string s = "{\"area\":{";
  s += "\"boundary\":";
  if (has_boundary) fmt_poly(s, boundary);
  else s += "null";
  s += ",\"exclusions\":[";
  for (std::size_t i = 0; i < exclusions.size(); ++i) {
    if (i > 0) s += ',';
    fmt_poly(s, exclusions[i]);
  }
  s += "],\"spawn\":";
  if (has_spawn) fmt_poly(s, spawn);
  else s += "null";
  s += "},\"id\":";
  quoted(s, id);
  s += ",\"k\":";
  fmt(s, k);
  s += ",\"marks\":[";
  for (std::size_t i = 0; i < marks.size(); ++i) {
    const ResolvedMark& m = marks[i];
    if (i > 0) s += ',';
    s += "{\"beam\":";
    fmt(s, m.beam);
    s += ",\"heading\":";
    fmt(s, m.heading);
    s += ",\"id\":";
    quoted(s, mark_ids[i]);
    s += ",\"length\":";
    fmt(s, m.length);
    s += ",\"radius\":";
    fmt(s, m.radius);
    s += ",\"type\":";
    quoted(s, mark_type_name(m.type));
    s += ",\"x\":";
    fmt(s, m.pos.x);
    s += ",\"y\":";
    fmt(s, m.pos.y);
    s += '}';
  }
  s += "],\"steps\":[";
  for (std::size_t i = 0; i < steps.size(); ++i) {
    const CourseStep& st = steps[i];
    if (i > 0) s += ',';
    s += "{\"gate_mode\":";
    quoted(s, st.gate_mode == GateMode::round ? "round" : "cross");
    s += ",\"kind\":";
    quoted(s, step_kind_name(st.kind));
    s += ",\"lap\":" + std::to_string(st.lap);
    s += ",\"leg\":" + std::to_string(st.leg_in_lap);
    s += ",\"marks\":[" + std::to_string(st.marks[0]) + "," + std::to_string(st.marks[1]) + "]";
    s += ",\"ref\":";
    fmt_pt(s, st.ref);
    s += ",\"sides\":[";
    quoted(s, side_name(st.sides[0]));
    s += ',';
    quoted(s, side_name(st.sides[1]));
    s += "],\"source\":" + std::to_string(st.source_index) + "}";
  }
  s += "],\"twd_c\":";
  fmt(s, twd_c);
  s += ",\"venue\":";
  quoted(s, venue);
  s += '}';
  return s;
}

std::string ResolvedCourse::hash() const {
  const std::string j = canonical_json();
  const auto* b = reinterpret_cast<const std::uint8_t*>(j.data());
  return to_hex(sha256(std::span<const std::uint8_t>(b, j.size())));
}

// ---- Validation (courses.md §7) ----

namespace {

bool segments_intersect(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  const float o1 = side_left(c, a, b), o2 = side_left(d, a, b);
  const float o3 = side_left(a, c, d), o4 = side_left(b, c, d);
  return ((o1 > 0.0f && o2 < 0.0f) || (o1 < 0.0f && o2 > 0.0f)) && ((o3 > 0.0f && o4 < 0.0f) || (o3 < 0.0f && o4 > 0.0f));
}

bool simple_polygon(const std::vector<Vec2>& p) {
  const std::size_t n = p.size();
  if (n < 3) return false;
  for (std::size_t i = 0; i < n; ++i) {
    for (std::size_t k = i + 1; k < n; ++k) {
      if (k == i + 1 || (i == 0 && k == n - 1)) continue;
      if (segments_intersect(p[i], p[(i + 1) % n], p[k], p[(k + 1) % n])) return false;
    }
  }
  return true;
}

// Clearance of a point from the venue's land: negative inside land.
float land_clearance(const VenueData& v, Vec2 p) {
  float d = INFINITY;
  for (const VenueLand& l : v.land) {
    if (point_in_polygon(p, l.points)) return -1.0f;
    d = min(d, point_polygon_edge_dist(p, l.points));
  }
  return d;
}

bool in_bounds(const VenueData& v, Vec2 p) {
  return p.x >= v.bounds[0] && p.y >= v.bounds[1] && p.x <= v.bounds[2] && p.y <= v.bounds[3];
}

std::string num(float f) {
  char buf[32];
  std::snprintf(buf, sizeof buf, "%.1f", static_cast<double>(f));
  return buf;
}

}  // namespace

bool check_resolved_course(const ResolvedCourse& rc, const VenueData& venue, const CourseCheck& chk,
                           std::vector<std::string>& warnings, std::string& error) {
  const float L = chk.L;
  const std::size_t n = rc.steps.size();
  auto warn = [&](const std::string& w) {
    for (const std::string& o : warnings) {
      if (o == w) return;
    }
    warnings.push_back(w);
  };
  for (std::size_t i = 0; i + 1 < n; ++i) {
    if (v_dist(rc.steps[i].ref, rc.steps[i + 1].ref) < 20.0f) {
      error = "steps " + std::to_string(i) + " and " + std::to_string(i + 1) + " are closer than 20 m";
      return false;
    }
  }
  const CourseStep& s0 = rc.start();
  const Vec2 A = rc.end_a(s0), B = rc.end_b(s0);
  if (point_segment_dist(rc.steps[1].ref, A, B) < 100.0f) {
    error = "the first step is less than 100 m from the start line";
    return false;
  }
  const CourseStep& fin = rc.finish();
  if (point_segment_dist(rc.steps[n - 2].ref, rc.end_a(fin), rc.end_b(fin)) < 50.0f) {
    error = "the step before the finish is less than 50 m from the finish line";
    return false;
  }
  for (std::size_t i = 1; i + 1 < n; ++i) {
    const CourseStep& s = rc.steps[i];
    if (s.kind != StepKind::gate) continue;
    const float w = v_dist(rc.marks[static_cast<std::size_t>(s.marks[0])].pos, rc.marks[static_cast<std::size_t>(s.marks[1])].pos);
    if (w < 2.0f * L) {
      error = "gate of step " + std::to_string(i) + " is " + num(w) + " m wide, below 2 hull lengths";
      return false;
    }
    if (w < 3.0f * L || w > 20.0f * L) {
      warn("gate of step " + std::to_string(i) + " is " + num(w / L) + " hull lengths wide (3 to 20 expected)");
    }
  }
  const float line_len = v_dist(A, B);
  const float want = max(8.0f * L, 1.2f * L * static_cast<float>(chk.max_boats));
  if (line_len < want) warn("start line is " + num(line_len) + " m, shorter than " + num(want) + " m");

  // Marks and line ends on water with 2 L clearance, inside the bounds.
  auto is_line_end = [&](std::int32_t m) {
    return m == s0.marks[0] || m == s0.marks[1] || m == fin.marks[0] || m == fin.marks[1];
  };
  for (std::size_t i = 0; i < rc.marks.size(); ++i) {
    const ResolvedMark& m = rc.marks[i];
    if (m.type == MarkType::virtual_point && !is_line_end(static_cast<std::int32_t>(i))) continue;
    if (!in_bounds(venue, m.pos)) {
      error = "mark \"" + rc.mark_ids[i] + "\" is outside the venue bounds";
      return false;
    }
    if (land_clearance(venue, m.pos) < 2.0f * L) {
      error = "mark \"" + rc.mark_ids[i] + "\" is on land or within 2 hull lengths of it";
      return false;
    }
  }
  if (rc.has_spawn) {
    for (const Vec2 p : rc.spawn) {
      if (!in_bounds(venue, p) || land_clearance(venue, p) < 2.0f * L) {
        error = "the spawn polygon is outside the bounds, on land or within 2 hull lengths of it";
        return false;
      }
    }
    for (const VenueLand& l : venue.land) {
      for (const Vec2 p : l.points) {
        if (point_in_polygon(p, rc.spawn)) {
          error = "the spawn polygon contains land";
          return false;
        }
      }
    }
  }
  for (std::size_t i = 0; i + 1 < n; ++i) {
    for (const VenueLand& l : venue.land) {
      const std::size_t m = l.points.size();
      for (std::size_t k = 0; k < m; ++k) {
        if (segments_intersect(rc.steps[i].ref, rc.steps[i + 1].ref, l.points[k], l.points[(k + 1) % m])) {
          warn("leg " + std::to_string(i + 1) + " crosses land \"" + l.id + "\"");
          k = m;
        }
      }
    }
  }
  if (rc.has_boundary) {
    if (!simple_polygon(rc.boundary)) {
      error = "the boundary polygon is not simple";
      return false;
    }
    for (std::size_t i = 0; i < rc.marks.size(); ++i) {
      const Vec2 p = rc.marks[i].pos;
      if (!point_in_polygon(p, rc.boundary) || point_polygon_edge_dist(p, rc.boundary) < 3.0f * L) {
        error = "mark \"" + rc.mark_ids[i] + "\" is not inside the boundary with 3 hull lengths of margin";
        return false;
      }
    }
  }
  // "finish": "start" is checked through the finish line's own orientation: the step before the finish must lie
  // on the pre-start side of the start line.
  const bool same_line = (fin.marks[0] == s0.marks[0] && fin.marks[1] == s0.marks[1]) ||
                         (fin.marks[0] == s0.marks[1] && fin.marks[1] == s0.marks[0]);
  if (same_line && !(side_left(rc.steps[n - 2].ref, A, B) < 0.0f)) {
    error = "finishing on the start line needs the last step on the pre-start side";
    return false;
  }
  return true;
}

bool validate_course(const CourseData& c, const VenueData& venue, const CourseCheck& chk,
                     std::vector<std::string>& warnings, LoadError& err) {
  err = LoadError{};
  ErrorSink sink(err, c.id + ".course.json");
  if (c.venue != venue.id) return sink.fail("$.venue", "course is for venue \"" + c.venue + "\", not \"" + venue.id + "\"");
  const std::int32_t axes = c.frame == CourseFrame::wind ? 36 : 1;
  for (std::int32_t a = 0; a < axes; ++a) {
    const float axis = static_cast<float>(a) * 0.174532925f;  // π/18
    ResolvedCourse rc;
    resolve_course(c, axis, 1.0f, rc);
    std::string why;
    if (!check_resolved_course(rc, venue, chk, warnings, why)) {
      if (c.frame == CourseFrame::wind) why = "with the wind from " + std::to_string(a * 10) + " degrees: " + why;
      return sink.fail("$", why);
    }
  }
  return true;
}

}  // namespace wm
