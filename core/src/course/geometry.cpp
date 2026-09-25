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

float point_polygon_edge_dist(Vec2 p, std::span<const Vec2> poly) {
  float d = INFINITY;
  const std::size_t n = poly.size();
  for (std::size_t i = 0; i < n; ++i) d = min(d, point_segment_dist(p, poly[i], poly[(i + 1) % n]));
  return d;
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

float vertex_edge_min(std::span<const Vec2> a, std::span<const Vec2> b) {
  float d = INFINITY;
  for (const Vec2 v : a) d = min(d, point_polygon_edge_dist(v, b));
  for (const Vec2 v : b) d = min(d, point_polygon_edge_dist(v, a));
  return d;
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

}  // namespace wm
