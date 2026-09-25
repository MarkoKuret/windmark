// Plane geometry shared by the course, the race and the rules (race.md §0, rules.md §3.1): vector helpers, the
// side-of-line and signed-angle helpers, hull outlines placed in the world, convex polygon gap and point tests.
// Everything is binary32 in the written order (conventions.md §5); the load-time validators use double copies.
#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "math/wm_math.h"

namespace wm {

inline Vec2 v_add(Vec2 a, Vec2 b) { return {a.x + b.x, a.y + b.y}; }
inline Vec2 v_sub(Vec2 a, Vec2 b) { return {a.x - b.x, a.y - b.y}; }
inline Vec2 v_scale(Vec2 a, float k) { return {a.x * k, a.y * k}; }
inline float v_dot(Vec2 a, Vec2 b) { return a.x * b.x + a.y * b.y; }
// race.md §0: cross(u, v) = u.x·v.y − u.y·v.x.
inline float v_cross(Vec2 a, Vec2 b) { return a.x * b.y - a.y * b.x; }
float v_len(Vec2 a);
float v_dist(Vec2 a, Vec2 b);
// Unit vector; `fallback` when |a| < 1e-6.
Vec2 v_unit(Vec2 a, Vec2 fallback);
inline Vec2 v_mid(Vec2 a, Vec2 b) { return {(a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f}; }

// race.md §0: left(p; a→b) > 0 when p is left of the directed line a→b seen from above.
inline float side_left(Vec2 p, Vec2 a, Vec2 b) { return v_cross(v_sub(b, a), v_sub(p, a)); }
// race.md §0: ang(u → v) > 0 when v is anticlockwise of u.
inline float signed_angle(Vec2 u, Vec2 v) { return wm_atan2(v_cross(u, v), v_dot(u, v)); }

// collisions.md §2.1: body outline (x forward, y port) at pos, heading psi: w = (pos + x·f) + y·p.
void place_outline(std::span<const Vec2> body, Vec2 pos, float psi, std::vector<Vec2>& world);
Vec2 place_point(Vec2 body, Vec2 pos, float psi);

// Distance from p to the segment a-b.
float point_segment_dist(Vec2 p, Vec2 a, Vec2 b);
// Even-odd point in polygon (either orientation).
bool point_in_polygon(Vec2 p, std::span<const Vec2> poly);
// Distance from p to the polygon boundary (0 inside is not implied: callers test inside first).
float point_polygon_edge_dist(Vec2 p, std::span<const Vec2> poly);

// rules.md §3.1: separating-axis intersection of two convex polygons (either orientation).
bool convex_intersect(std::span<const Vec2> a, std::span<const Vec2> b);
// rules.md §3.1: 0 when they intersect, else the minimum vertex-edge distance.
float convex_gap(std::span<const Vec2> a, std::span<const Vec2> b);
// The same gap where only values below `cap` must be exact: the largest separation along a unit edge normal
// (a lower bound of the gap) is returned when it is at least `cap`.
float convex_gap_capped(std::span<const Vec2> a, std::span<const Vec2> b, float cap);
// Gap between a convex polygon and a circle (0 when they overlap).
float convex_circle_gap(std::span<const Vec2> a, Vec2 c, float r);
// Gap between a convex polygon and any polygon (0 when a vertex of either is inside the other or edges cross).
float polygon_gap(std::span<const Vec2> convex, std::span<const Vec2> poly);

}  // namespace wm
