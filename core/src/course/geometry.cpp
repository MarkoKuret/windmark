#include "course/geometry.h"

#include <cmath>

namespace wm {

float v_len(Vec2 a) { return std::sqrt(a.x * a.x + a.y * a.y); }
float v_dist(Vec2 a, Vec2 b) { return v_len(v_sub(a, b)); }

Vec2 v_unit(Vec2 a, Vec2 fallback) {
  const float l = v_len(a);
  if (!(l >= 1e-6f)) return fallback;
  return {a.x / l, a.y / l};
}

Vec2 place_point(Vec2 b, Vec2 pos, float psi) {
  const SinCos sc = wm_sincos(psi);
  // f = (sin ψ, cos ψ), p = (−cos ψ, sin ψ)
  return {(pos.x + b.x * sc.s) + b.y * (-sc.c), (pos.y + b.x * sc.c) + b.y * sc.s};
}

void place_outline(std::span<const Vec2> body, Vec2 pos, float psi, std::vector<Vec2>& world) {
  const SinCos sc = wm_sincos(psi);
  world.resize(body.size());
  for (std::size_t k = 0; k < body.size(); ++k) {
    const Vec2 b = body[k];
    world[k] = {(pos.x + b.x * sc.s) + b.y * (-sc.c), (pos.y + b.x * sc.c) + b.y * sc.s};
  }
}

float point_segment_dist(Vec2 p, Vec2 a, Vec2 b) {
  const Vec2 ab = v_sub(b, a);
  const Vec2 ap = v_sub(p, a);
  const float l2 = v_dot(ab, ab);
  float t = 0.0f;
  if (l2 > 0.0f) t = clamp(v_dot(ap, ab) / l2, 0.0f, 1.0f);
  const Vec2 q = v_add(a, v_scale(ab, t));
  return v_dist(p, q);
}

bool point_in_polygon(Vec2 p, std::span<const Vec2> poly) {
  bool in = false;
  const std::size_t n = poly.size();
  for (std::size_t i = 0, j = n - 1; i < n; j = i++) {
    const Vec2 a = poly[i], b = poly[j];
    if ((a.y > p.y) != (b.y > p.y)) {
      const float x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x);
      if (p.x < x) in = !in;
    }
  }
  return in;
}

namespace {
float point_polygon_edge_dist2(Vec2 p, std::span<const Vec2> poly, float d2);
}

float point_polygon_edge_dist(Vec2 p, std::span<const Vec2> poly) {
  return std::sqrt(point_polygon_edge_dist2(p, poly, INFINITY));
}

namespace {

// Projection interval of a polygon on an axis.
void project(std::span<const Vec2> p, Vec2 axis, float& lo, float& hi) {
  lo = INFINITY;
  hi = -INFINITY;
  for (const Vec2 v : p) {
    const float d = v_dot(v, axis);
    lo = min(lo, d);
    hi = max(hi, d);
  }
}

bool separated_on_edges(std::span<const Vec2> a, std::span<const Vec2> b) {
  const std::size_t n = a.size();
  for (std::size_t i = 0; i < n; ++i) {
    const Vec2 e = v_sub(a[(i + 1) % n], a[i]);
    const Vec2 axis{-e.y, e.x};
    float alo, ahi, blo, bhi;
    project(a, axis, alo, ahi);
    project(b, axis, blo, bhi);
    if (ahi < blo || bhi < alo) return true;
  }
  return false;
}

bool segments_cross(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  const float o1 = side_left(c, a, b), o2 = side_left(d, a, b);
  const float o3 = side_left(a, c, d), o4 = side_left(b, c, d);
  return ((o1 > 0.0f) != (o2 > 0.0f)) && ((o3 > 0.0f) != (o4 > 0.0f)) && o1 != 0.0f && o2 != 0.0f &&
         o3 != 0.0f && o4 != 0.0f;
}

// The squared distance from p to the segment a-b, the same operations as point_segment_dist: the square root is
// monotonic and correctly rounded, so the square root of the least squared distance is the least distance, bit
// for bit, and only one square root is taken per polygon pair.
float point_segment_dist2(Vec2 p, Vec2 a, Vec2 b) {
  const Vec2 ab = v_sub(b, a);
  const Vec2 ap = v_sub(p, a);
  const float l2 = v_dot(ab, ab);
  float t = 0.0f;
  if (l2 > 0.0f) t = clamp(v_dot(ap, ab) / l2, 0.0f, 1.0f);
  const Vec2 q = v_add(a, v_scale(ab, t));
  const Vec2 r = v_sub(p, q);
  return r.x * r.x + r.y * r.y;
}

float point_polygon_edge_dist2(Vec2 p, std::span<const Vec2> poly, float d2) {
  const std::size_t n = poly.size();
  for (std::size_t i = 0; i < n; ++i) d2 = min(d2, point_segment_dist2(p, poly[i], poly[i + 1 < n ? i + 1 : 0]));
  return d2;
}

float vertex_edge_min(std::span<const Vec2> a, std::span<const Vec2> b) {
  float d2 = INFINITY;
  for (const Vec2 v : a) d2 = point_polygon_edge_dist2(v, b, d2);
  for (const Vec2 v : b) d2 = point_polygon_edge_dist2(v, a, d2);
  return std::sqrt(d2);
}

}  // namespace

bool convex_intersect(std::span<const Vec2> a, std::span<const Vec2> b) {
  return !separated_on_edges(a, b) && !separated_on_edges(b, a);
}

float convex_gap(std::span<const Vec2> a, std::span<const Vec2> b) {
  if (convex_intersect(a, b)) return 0.0f;
  return vertex_edge_min(a, b);
}

namespace {

// Largest separation of b from a over the unit edge normals of a (either orientation): the gap between the
// projection intervals, a lower bound of the distance between the polygons.
float max_separation(std::span<const Vec2> a, std::span<const Vec2> b) {
  float best = -INFINITY;
  const std::size_t n = a.size();
  for (std::size_t i = 0; i < n; ++i) {
    const Vec2 e = v_sub(a[(i + 1) % n], a[i]);
    const float l = v_len(e);
    if (!(l > 0.0f)) continue;
    const Vec2 axis{-e.y / l, e.x / l};
    float alo, ahi, blo, bhi;
    project(a, axis, alo, ahi);
    project(b, axis, blo, bhi);
    best = max(best, max(blo - ahi, alo - bhi));
  }
  return best;
}

}  // namespace

float convex_gap_capped(std::span<const Vec2> a, std::span<const Vec2> b, float cap) {
  const float s = max(max_separation(a, b), max_separation(b, a));
  if (!(s >= 0.0f)) return 0.0f;  // no separating axis: they intersect
  if (s >= cap) return s;
  return vertex_edge_min(a, b);
}

float convex_circle_gap(std::span<const Vec2> a, Vec2 c, float r) {
  if (point_in_polygon(c, a)) return 0.0f;
  return max(0.0f, point_polygon_edge_dist(c, a) - r);
}

float polygon_gap(std::span<const Vec2> convex, std::span<const Vec2> poly) {
  for (const Vec2 v : convex) {
    if (point_in_polygon(v, poly)) return 0.0f;
  }
  for (const Vec2 v : poly) {
    if (point_in_polygon(v, convex)) return 0.0f;
  }
  const std::size_t n = convex.size(), m = poly.size();
  for (std::size_t i = 0; i < n; ++i) {
    for (std::size_t k = 0; k < m; ++k) {
      if (segments_cross(convex[i], convex[(i + 1) % n], poly[k], poly[(k + 1) % m])) return 0.0f;
    }
  }
  return vertex_edge_min(convex, poly);
}


// ---- placed hulls ----

void place_hull(std::span<const Vec2> body, Vec2 pos, float psi, Hull& out) {
  const SinCos sc = wm_sincos(psi);
  const std::size_t n = body.size() < kMaxOutline ? body.size() : kMaxOutline;
  out.n = static_cast<std::uint32_t>(n);
  out.pos = pos;
  out.s = sc.s;
  out.c = sc.c;
  float x0 = INFINITY, x1 = -INFINITY, y0 = INFINITY, y1 = -INFINITY;
  for (std::size_t k = 0; k < n; ++k) {
    const Vec2 b = body[k];
    out.v[k] = {(pos.x + b.x * sc.s) + b.y * (-sc.c), (pos.y + b.x * sc.c) + b.y * sc.s};
    x0 = min(x0, b.x);
    x1 = max(x1, b.x);
    y0 = min(y0, b.y);
    y1 = max(y1, b.y);
  }
  out.x0 = x0;
  out.x1 = x1;
  out.y0 = y0;
  out.y1 = y1;
  out.axes = false;
}

namespace {

// The culls below compare lower bounds taken in another frame with distances taken in world coordinates; both
// carry rounding errors of about 1e-7 of the coordinates, so a bound only skips work when it clears by this much.
constexpr float kCull = 0.1f;

// p in the body frame of h.
inline Vec2 to_body(const Hull& h, Vec2 p) {
  const Vec2 d = v_sub(p, h.pos);
  return {d.x * h.s + d.y * h.c, d.y * h.s - d.x * h.c};
}

// Squared distance from p to h's body-frame bounding box (0 inside): a lower bound of the distance to h.
inline float box_dist2(const Hull& h, Vec2 p) {
  const Vec2 l = to_body(h, p);
  const float dx = max(max(h.x0 - l.x, l.x - h.x1), 0.0f);
  const float dy = max(max(h.y0 - l.y, l.y - h.y1), 0.0f);
  return dx * dx + dy * dy;
}

// A side of b's bounding box has every vertex of a beyond it by more than the cull margin.
bool outside_box(const Hull& a, const Hull& b) {
  float lx0 = INFINITY, lx1 = -INFINITY, ly0 = INFINITY, ly1 = -INFINITY;
  for (std::uint32_t k = 0; k < a.n; ++k) {
    const Vec2 l = to_body(b, a.v[k]);
    lx0 = min(lx0, l.x);
    lx1 = max(lx1, l.x);
    ly0 = min(ly0, l.y);
    ly1 = max(ly1, l.y);
  }
  return lx0 > b.x1 + kCull || lx1 < b.x0 - kCull || ly0 > b.y1 + kCull || ly1 < b.y0 - kCull;
}

// Unit edge normals and the hull's own projection on them, the same operations as max_separation.
void ensure_axes(const Hull& h) {
  if (h.axes) return;
  h.axis_ok = 0;
  const std::uint32_t n = h.n;
  for (std::uint32_t i = 0; i < n; ++i) {
    const Vec2 e = v_sub(h.v[i + 1 < n ? i + 1 : 0], h.v[i]);
    const float l = v_len(e);
    if (!(l > 0.0f)) continue;
    const Vec2 axis{-e.y / l, e.x / l};
    float lo = INFINITY, hi = -INFINITY;
    for (std::uint32_t k = 0; k < n; ++k) {
      const float d = v_dot(h.v[k], axis);
      lo = min(lo, d);
      hi = max(hi, d);
    }
    h.ax[i] = axis;
    h.lo[i] = lo;
    h.hi[i] = hi;
    h.axis_ok |= 1u << i;
  }
  h.axes = true;
}

// max_separation(a, b) folded into `best`; stops early (returning true) at an axis that separates by `stop` or
// more.
bool separation(const Hull& a, const Hull& b, float stop, float& best) {
  ensure_axes(a);
  for (std::uint32_t i = 0; i < a.n; ++i) {
    if (((a.axis_ok >> i) & 1u) == 0u) continue;
    const Vec2 axis = a.ax[i];
    float blo = INFINITY, bhi = -INFINITY;
    for (std::uint32_t k = 0; k < b.n; ++k) {
      const float d = v_dot(b.v[k], axis);
      blo = min(blo, d);
      bhi = max(bhi, d);
    }
    const float sep = max(blo - a.hi[i], a.lo[i] - bhi);
    best = max(best, sep);
    if (sep >= stop) return true;
  }
  return false;
}

// vertex_edge_min on placed hulls: the vertices are taken nearest first by their distance to the other hull's
// bounding box, and a vertex whose bound already clears the best distance so far (or `ub`) is skipped. Exact
// below `ub`; `ub` itself when every pair is at least `ub` apart.
float vertex_edge_min(const Hull& a, const Hull& b, float ub) {
  std::array<float, 2 * kMaxOutline> lb2;
  const std::uint32_t na = a.n, nb = b.n;
  std::uint32_t first = 0;
  for (std::uint32_t k = 0; k < na + nb; ++k) {
    lb2[k] = k < na ? box_dist2(b, a.v[k]) : box_dist2(a, b.v[k - na]);
    if (lb2[k] < lb2[first]) first = k;
  }
  float d2 = INFINITY;
  float thr2 = ub < INFINITY ? (ub + kCull) * (ub + kCull) : INFINITY;
  auto visit = [&](std::uint32_t k) {
    if (!(lb2[k] <= thr2)) return;
    const float before = d2;
    d2 = k < na ? point_polygon_edge_dist2(a.v[k], b.pts(), d2) : point_polygon_edge_dist2(b.v[k - na], a.pts(), d2);
    if (d2 < before) {
      const float lim = min(std::sqrt(d2), ub);
      thr2 = (lim + kCull) * (lim + kCull);
    }
  };
  visit(first);
  for (std::uint32_t k = 0; k < na + nb; ++k) {
    if (k != first) visit(k);
  }
  const float d = std::sqrt(d2);
  return d < ub ? d : ub;
}

}  // namespace

float convex_gap(const Hull& a, const Hull& b) {
  if (!outside_box(a, b) && !outside_box(b, a) && convex_intersect(a.pts(), b.pts())) return 0.0f;
  return vertex_edge_min(a, b, INFINITY);
}

float convex_gap_capped(const Hull& a, const Hull& b, float cap) {
  const float stop = cap > 0.0f ? cap : 0.0f;
  float s = -INFINITY;
  if (separation(a, b, stop, s) || separation(b, a, stop, s)) return s;
  if (!(s >= 0.0f)) return 0.0f;  // no separating axis: they intersect
  return vertex_edge_min(a, b, cap);
}

}  // namespace wm
