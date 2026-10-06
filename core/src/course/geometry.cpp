#include "course/geometry.h"

#include <algorithm>
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
  // Clearly apart: no separating-axis search, the vertex-edge distance (exact below the cap) is the gap.
  if (cap > 0.0f && (outside_box(a, b) || outside_box(b, a))) return vertex_edge_min(a, b, cap);
  const float stop = cap > 0.0f ? cap : 0.0f;
  float s = -INFINITY;
  if (separation(a, b, stop, s) || separation(b, a, stop, s)) return s;
  if (!(s >= 0.0f)) return 0.0f;  // no separating axis: they intersect
  return vertex_edge_min(a, b, cap);
}


// ---- large polygons (land) ----
//
// The grid: square cells over the polygon's bounding box, about two per edge and at most 256 a side. Cell and row
// lookups clamp to the grid and are monotonic in the coordinate, so a point of an edge always maps into the cell
// range of that edge's bounding box, and a query box grown by R + kSlack visits every edge that comes within R of
// it. The skipped edges are farther than R + kSlack, which is far beyond the rounding of a distance (millimetres
// at venue coordinates), so their computed distance is above R and a minimum found at or below R is the minimum of
// all edges, bit for bit. Searches grow R by doubling until that holds or the whole grid is visited.

namespace {

constexpr float kSlack = 1.0f;  // m

// Calls f(k) for every edge listed in the cells covering the box (an edge may come more than once). True when the
// box covered every cell, so every edge was visited.
template <class F>
bool visit_box(const PolygonIndex& ix, float bx0, float by0, float bx1, float by1, F&& f) {
  const std::int32_t c0 = ix.col_of(bx0), c1 = ix.col_of(bx1), r0 = ix.row_of(by0), r1 = ix.row_of(by1);
  for (std::int32_t r = r0; r <= r1; ++r) {
    for (std::int32_t c = c0; c <= c1; ++c) {
      const std::size_t j = static_cast<std::size_t>(r) * static_cast<std::size_t>(ix.nx) + static_cast<std::size_t>(c);
      for (std::uint32_t i = ix.cell_start[j]; i < ix.cell_start[j + 1]; ++i) f(ix.cell_edges[i]);
    }
  }
  return c0 == 0 && r0 == 0 && c1 == ix.nx - 1 && r1 == ix.ny - 1;
}

// Grows R from one cell until `eval(R)` (which visits the box grown by R + kSlack and returns the least distance
// found) is at most R, or the whole grid was visited.
template <class Eval>
void ring_search(const PolygonIndex& ix, Eval&& eval) {
  float R = ix.cell;
  for (;;) {
    bool all = false;
    const float best = eval(R, all);
    if (best <= R || all) return;
    R *= 2.0f;
  }
}

}  // namespace

std::int32_t PolygonIndex::col_of(float x) const {
  const float f = std::floor((x - x0) / cell);
  if (!(f >= 0.0f)) return 0;
  if (f >= static_cast<float>(nx - 1)) return nx - 1;
  return static_cast<std::int32_t>(f);
}

std::int32_t PolygonIndex::row_of(float y) const {
  const float f = std::floor((y - y0) / cell);
  if (!(f >= 0.0f)) return 0;
  if (f >= static_cast<float>(ny - 1)) return ny - 1;
  return static_cast<std::int32_t>(f);
}

void PolygonIndex::build(std::span<const Vec2> poly) {
  *this = PolygonIndex{};
  const std::size_t m = poly.size();
  if (m < 3) return;
  Vec2 c{0.0f, 0.0f};
  for (const Vec2 v : poly) c = v_add(c, v);
  c = v_scale(c, 1.0f / static_cast<float>(m));
  float r = 0.0f;
  for (const Vec2 v : poly) r = max(r, v_dist(v, c));
  centre = c;
  radius = r;

  float xmin = INFINITY, ymin = INFINITY, xmax = -INFINITY, ymax = -INFINITY;
  for (const Vec2 v : poly) {
    xmin = min(xmin, v.x);
    ymin = min(ymin, v.y);
    xmax = max(xmax, v.x);
    ymax = max(ymax, v.y);
  }
  if (!(xmin <= xmax && ymin <= ymax)) return;  // not finite: no index, the full queries run
  const double w = static_cast<double>(xmax) - static_cast<double>(xmin);
  const double h = static_cast<double>(ymax) - static_cast<double>(ymin);
  double s = std::sqrt(std::max(w * h, 1.0) / (2.0 * static_cast<double>(m)));
  s = std::max({s, std::max(w, h) / 256.0, 1.0});
  x0 = xmin;
  y0 = ymin;
  cell = static_cast<float>(s);
  nx = static_cast<std::int32_t>(std::clamp(std::ceil(w / s), 1.0, 256.0));
  ny = static_cast<std::int32_t>(std::clamp(std::ceil(h / s), 1.0, 256.0));

  // Cells: those of the edge's bounding box the edge's line comes near (a generous pad; the outer cells reach out
  // to infinity, as the clamped lookups do).
  std::vector<std::vector<std::uint32_t>> cells(static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny));
  std::vector<std::vector<std::uint32_t>> rows(static_cast<std::size_t>(ny));
  const double cs = static_cast<double>(cell), gx = static_cast<double>(x0), gy = static_cast<double>(y0);
  const double pad = 0.01 * cs + 1.0;
  for (std::size_t k = 0; k < m; ++k) {
    const Vec2 a = poly[k], b = poly[k + 1 < m ? k + 1 : 0];
    const std::int32_t c0 = col_of(min(a.x, b.x)), c1 = col_of(max(a.x, b.x));
    const std::int32_t r0 = row_of(min(a.y, b.y)), r1 = row_of(max(a.y, b.y));
    for (std::int32_t rr = r0; rr <= r1; ++rr) {
      rows[static_cast<std::size_t>(rr)].push_back(static_cast<std::uint32_t>(k));
    }
    const double ax = static_cast<double>(a.x), ay = static_cast<double>(a.y);
    const double ex = static_cast<double>(b.x) - ax, ey = static_cast<double>(b.y) - ay;
    auto near_line = [&](std::int32_t cc, std::int32_t rr) {
      if (cc == 0 || cc == nx - 1 || rr == 0 || rr == ny - 1) return true;
      const double lx = gx + cc * cs - pad, hx = gx + (cc + 1) * cs + pad;
      const double ly = gy + rr * cs - pad, hy = gy + (rr + 1) * cs + pad;
      int pos = 0, neg = 0;
      for (const double px : {lx, hx}) {
        for (const double py : {ly, hy}) {
          const double side = ex * (py - ay) - ey * (px - ax);
          pos += side >= 0.0 ? 1 : 0;
          neg += side <= 0.0 ? 1 : 0;
        }
      }
      return pos > 0 && neg > 0;
    };
    bool any = false;
    for (int pass = 0; pass < 2 && !any; ++pass) {
      for (std::int32_t rr = r0; rr <= r1; ++rr) {
        for (std::int32_t cc = c0; cc <= c1; ++cc) {
          if (pass == 0 && !near_line(cc, rr)) continue;
          cells[static_cast<std::size_t>(rr) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(cc)].push_back(
              static_cast<std::uint32_t>(k));
          any = true;
        }
      }
    }
  }
  cell_start.assign(1, 0);
  for (const auto& v : cells) {
    cell_edges.insert(cell_edges.end(), v.begin(), v.end());
    cell_start.push_back(static_cast<std::uint32_t>(cell_edges.size()));
  }
  row_start.assign(1, 0);
  for (const auto& v : rows) {
    row_edges.insert(row_edges.end(), v.begin(), v.end());
    row_start.push_back(static_cast<std::uint32_t>(row_edges.size()));
  }
  n = static_cast<std::uint32_t>(m);
}

bool point_in_polygon(Vec2 p, std::span<const Vec2> poly, const PolygonIndex* idx) {
  if (idx == nullptr || !idx->usable(poly)) return point_in_polygon(p, poly);
  // Only an edge whose y range holds p.y can cross the horizontal through p, and each sits once in that row; the
  // crossing test is point_in_polygon's own (a = poly[i], b = poly[j], j = i − 1), so the parity is the same.
  const std::size_t n = poly.size();
  const std::size_t r = static_cast<std::size_t>(idx->row_of(p.y));
  bool in = false;
  for (std::uint32_t q = idx->row_start[r]; q < idx->row_start[r + 1]; ++q) {
    const std::size_t j = idx->row_edges[q];
    const std::size_t i = j + 1 < n ? j + 1 : 0;
    const Vec2 a = poly[i], b = poly[j];
    if ((a.y > p.y) != (b.y > p.y)) {
      const float x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x);
      if (p.x < x) in = !in;
    }
  }
  return in;
}

float point_polygon_edge_dist_capped(Vec2 p, std::span<const Vec2> poly, const PolygonIndex* idx, float cap) {
  if (idx == nullptr || !idx->usable(poly) || !(cap >= 0.0f && cap < 1e7f)) return point_polygon_edge_dist(p, poly);
  const std::size_t n = poly.size();
  const float g = cap + kSlack;
  float d2 = INFINITY;
  visit_box(*idx, p.x - g, p.y - g, p.x + g, p.y + g,
            [&](std::uint32_t k) { d2 = min(d2, point_segment_dist2(p, poly[k], poly[k + 1 < n ? k + 1 : 0])); });
  return std::sqrt(d2);
}

float polygon_gap(std::span<const Vec2> convex, std::span<const Vec2> poly, const PolygonIndex* idx) {
  if (idx == nullptr || !idx->usable(poly) || convex.empty()) return polygon_gap(convex, poly);
  for (const Vec2 v : convex) {
    if (point_in_polygon(v, poly, idx)) return 0.0f;
  }
  float bx0 = INFINITY, by0 = INFINITY, bx1 = -INFINITY, by1 = -INFINITY;
  for (const Vec2 v : convex) {
    bx0 = min(bx0, v.x);
    by0 = min(by0, v.y);
    bx1 = max(bx1, v.x);
    by1 = max(by1, v.y);
  }
  if (!(bx0 <= bx1 && by0 <= by1)) return polygon_gap(convex, poly);
  const std::size_t n = convex.size(), m = poly.size();
  // A polygon vertex inside the convex one, or crossing edges: only edges within the convex one's box (and a metre)
  // can do either; each vertex k is tested through edge k.
  bool touch = false;
  visit_box(*idx, bx0 - kSlack, by0 - kSlack, bx1 + kSlack, by1 + kSlack, [&](std::uint32_t k) {
    if (touch) return;
    const Vec2 c = poly[k], d = poly[(k + 1) % m];
    if (point_in_polygon(c, convex)) touch = true;
    for (std::size_t i = 0; i < n && !touch; ++i) {
      if (segments_cross(convex[i], convex[(i + 1) % n], c, d)) touch = true;
    }
  });
  if (touch) return 0.0f;
  // vertex_edge_min(convex, poly): convex vertices to the polygon's edges, and the polygon's vertices to the convex
  // edges; vertex k comes with edge k.
  float d2 = INFINITY;
  ring_search(*idx, [&](float R, bool& all) {
    d2 = INFINITY;
    const float g = R + kSlack;
    all = visit_box(*idx, bx0 - g, by0 - g, bx1 + g, by1 + g, [&](std::uint32_t k) {
      const Vec2 a = poly[k], b = poly[k + 1 < m ? k + 1 : 0];
      for (const Vec2 v : convex) d2 = min(d2, point_segment_dist2(v, a, b));
      d2 = point_polygon_edge_dist2(a, convex, d2);
    });
    return std::sqrt(d2);
  });
  return std::sqrt(d2);
}

namespace {

// The clamped projection of p on edge a-b and its distance, in the written order of polygon_nearest_point.
inline float edge_point(Vec2 p, Vec2 a, Vec2 b, Vec2& x) {
  const Vec2 ab = v_sub(b, a);
  const float l2 = v_dot(ab, ab);
  const float t = l2 > 0.0f ? clamp(v_dot(v_sub(p, a), ab) / l2, 0.0f, 1.0f) : 0.0f;
  x = v_add(a, v_scale(ab, t));
  return v_dist(p, x);
}

}  // namespace

Vec2 polygon_nearest_point(Vec2 p, std::span<const Vec2> poly, const PolygonIndex* idx, Vec2 fallback) {
  const std::size_t m = poly.size();
  Vec2 best = fallback;
  float bd = INFINITY;
  if (idx == nullptr || !idx->usable(poly)) {
    for (std::size_t k = 0; k < m; ++k) {
      Vec2 x;
      const float d = edge_point(p, poly[k], poly[(k + 1) % m], x);
      if (d < bd) {
        bd = d;
        best = x;
      }
    }
    return best;
  }
  ring_search(*idx, [&](float R, bool& all) {
    best = fallback;
    bd = INFINITY;
    std::uint32_t bk = 0;
    const float g = R + kSlack;
    all = visit_box(*idx, p.x - g, p.y - g, p.x + g, p.y + g, [&](std::uint32_t k) {
      Vec2 x;
      const float d = edge_point(p, poly[k], poly[(k + 1) % m], x);
      if (d < bd || (d == bd && k < bk)) {  // the full scan keeps the first (lowest) edge of equal distance
        bd = d;
        bk = k;
        best = x;
      }
    });
    return bd;
  });
  return best;
}

}  // namespace wm
