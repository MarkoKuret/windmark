// collisions.md. Every formula is written in the spec's order, one rounding per operation (conventions.md §5).
#include "collide/collide.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "boat/boat.h"
#include "data/venue.h"

namespace wm {

namespace {

constexpr float INF = std::numeric_limits<float>::infinity();

inline float dot(Vec2 a, Vec2 b) { return a.x * b.x + a.y * b.y; }
inline Vec2 sub(Vec2 a, Vec2 b) { return {a.x - b.x, a.y - b.y}; }

// Unit outward normal of the counter-clockwise edge a -> b.
inline Vec2 outward(Vec2 a, Vec2 b) {
  const float dx = b.x - a.x;
  const float dy = b.y - a.y;
  const float len = std::sqrt(dx * dx + dy * dy);
  return {dy / len, -dx / len};
}

inline float dist_between(Vec2 a, Vec2 b) {
  const float dx = a.x - b.x;
  const float dy = a.y - b.y;
  return std::sqrt(dx * dx + dy * dy);
}

// Closest point to p on segment a -> b (clamped projection) and its squared distance.
inline float seg_closest(Vec2 p, Vec2 a, Vec2 b, Vec2& q) {
  const float dx = b.x - a.x;
  const float dy = b.y - a.y;
  const float dd = dx * dx + dy * dy;
  float t = dd > 0.0f ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / dd : 0.0f;
  t = clamp(t, 0.0f, 1.0f);
  q = {a.x + dx * t, a.y + dy * t};
  const float ex = p.x - q.x;
  const float ey = p.y - q.y;
  return ex * ex + ey * ey;
}

// Projection interval of a polygon on n.
inline void project(std::span<const Vec2> poly, Vec2 n, float& lo, float& hi) {
  lo = INF;
  hi = -INF;
  for (const Vec2& v : poly) {
    const float d = dot(v, n);
    if (d < lo) lo = d;
    if (d > hi) hi = d;
  }
}

// Vertex with the largest projection on n, lowest index on ties.
inline Vec2 support(std::span<const Vec2> poly, Vec2 n) {
  std::size_t best = 0;
  float bd = dot(poly[0], n);
  for (std::size_t k = 1; k < poly.size(); ++k) {
    const float d = dot(poly[k], n);
    if (d > bd) {
      bd = d;
      best = k;
    }
  }
  return poly[best];
}

// Strictly convex, counter-clockwise, origin strictly inside (the perf outline rule, collisions.md §2.1).
bool valid_outline(std::span<const Vec2> o) {
  const std::size_t n = o.size();
  if (n < 3 || n > 64) return false;
  for (std::size_t i = 0; i < n; ++i) {
    const Vec2 a = o[i];
    const Vec2 b = o[(i + 1) % n];
    const Vec2 e = o[(i + 2) % n];
    const float turn = (b.x - a.x) * (e.y - b.y) - (b.y - a.y) * (e.x - b.x);
    if (!(turn > 0.0f)) return false;
    const float side = (b.x - a.x) * (0.0f - a.y) - (b.y - a.y) * (0.0f - a.x);
    if (!(side > 0.0f)) return false;
  }
  return true;
}

// Margin on bounding tests that only skip work: rounding of world vertices must never skip a real contact.
constexpr float BOUND_MARGIN = 0.01f;

}  // namespace

// ---------------------------------------------------------------------------------------------------------------
// §3.2

bool collide_polygons(std::span<const Vec2> a, Vec2 ca, std::span<const Vec2> b, Vec2 cb, Hit& out) {
  float best = INF;
  Vec2 axis{0.0f, 0.0f};
  bool from_a = true;
  for (int side = 0; side < 2; ++side) {
    const std::span<const Vec2> p = side == 0 ? a : b;
    const std::size_t n = p.size();
    for (std::size_t k = 0; k < n; ++k) {
      const Vec2 nrm = outward(p[k], p[(k + 1) % n]);
      float min_a, max_a, min_b, max_b;
      project(a, nrm, min_a, max_a);
      project(b, nrm, min_b, max_b);
      const float o = min(max_a - min_b, max_b - min_a);
      if (o <= 0.0f) return false;
      if (o < best) {
        best = o;
        axis = nrm;
        from_a = side == 0;
      }
    }
  }
  Vec2 normal = axis;
  if (dot(axis, sub(ca, cb)) < 0.0f) normal = {-axis.x, -axis.y};
  out.depth = best;
  out.normal = normal;
  out.point = from_a ? support(b, normal) : support(a, {-normal.x, -normal.y});
  return true;
}

// §3.3

bool collide_circle_polygon(Vec2 c, float r, std::span<const Vec2> a, Hit& out) {
  const std::size_t n = a.size();
  bool inside = true;
  for (std::size_t k = 0; k < n && inside; ++k) {
    if (dot(sub(c, a[k]), outward(a[k], a[(k + 1) % n])) > 0.0f) inside = false;
  }
  if (inside) {
    std::size_t e = 0;
    float best = INF;
    for (std::size_t k = 0; k < n; ++k) {
      const float d = -dot(sub(c, a[k]), outward(a[k], a[(k + 1) % n]));
      if (d < best) {
        best = d;
        e = k;
      }
    }
    const Vec2 no = outward(a[e], a[(e + 1) % n]);
    out.normal = {-no.x, -no.y};
    out.depth = r + best;
    out.point = c;
    return true;
  }
  Vec2 q{0.0f, 0.0f};
  float best2 = INF;
  for (std::size_t k = 0; k < n; ++k) {
    Vec2 qk;
    const float d2 = seg_closest(c, a[k], a[(k + 1) % n], qk);
    if (d2 < best2) {
      best2 = d2;
      q = qk;
    }
  }
  const float d = dist_between(q, c);
  if (d >= r) return false;
  out.normal = {(q.x - c.x) / d, (q.y - c.y) / d};
  out.depth = r - d;
  out.point = q;
  return true;
}

// ---------------------------------------------------------------------------------------------------------------
// §3.4 land and its band index: the polygon's y range cut into equal bands; each band lists the edges whose y range
// touches it and the vertices inside it. An edge that crosses the horizontal through p is always in p's band, and
// edges outside the bands searched so far are at least (ring - 2) band heights away, so the indexed searches give
// the same results as the full ones.

std::int32_t LandShape::band_of(float y) const {
  if (bands <= 1) return 0;
  const float f = std::floor((y - ymin) / band_h);
  if (!(f >= 0.0f)) return 0;
  if (f >= static_cast<float>(bands - 1)) return bands - 1;
  return static_cast<std::int32_t>(f);
}

void LandShape::build(std::span<const Vec2> pts) {
  points.assign(pts.begin(), pts.end());
  const std::size_t n = points.size();
  xmin = ymin = INF;
  xmax = ymax = -INF;
  for (const Vec2& p : points) {
    xmin = min(xmin, p.x);
    ymin = min(ymin, p.y);
    xmax = max(xmax, p.x);
    ymax = max(ymax, p.y);
  }
  bands = static_cast<std::int32_t>(std::clamp<std::size_t>(n / 8, 1, 1024));
  band_h = (ymax - ymin) / static_cast<float>(bands);
  if (!(band_h > 0.0f)) {
    bands = 1;
    band_h = 0.0f;
  }
  std::vector<std::vector<std::uint32_t>> eb(static_cast<std::size_t>(bands));
  std::vector<std::vector<std::uint32_t>> vb(static_cast<std::size_t>(bands));
  for (std::size_t k = 0; k < n; ++k) {
    const Vec2 a = points[k];
    const Vec2 b = points[(k + 1) % n];
    const std::int32_t k0 = band_of(min(a.y, b.y));
    const std::int32_t k1 = band_of(max(a.y, b.y));
    for (std::int32_t j = k0; j <= k1; ++j) eb[static_cast<std::size_t>(j)].push_back(static_cast<std::uint32_t>(k));
    vb[static_cast<std::size_t>(band_of(a.y))].push_back(static_cast<std::uint32_t>(k));
  }
  edge_start.assign(1, 0);
  vert_start.assign(1, 0);
  edge_ids.clear();
  vert_ids.clear();
  for (std::int32_t j = 0; j < bands; ++j) {
    const auto& e = eb[static_cast<std::size_t>(j)];
    const auto& v = vb[static_cast<std::size_t>(j)];
    edge_ids.insert(edge_ids.end(), e.begin(), e.end());
    vert_ids.insert(vert_ids.end(), v.begin(), v.end());
    edge_start.push_back(static_cast<std::uint32_t>(edge_ids.size()));
    vert_start.push_back(static_cast<std::uint32_t>(vert_ids.size()));
  }
}

namespace {

inline bool edge_crosses(Vec2 a, Vec2 b, Vec2 p) {
  return ((a.y > p.y) != (b.y > p.y)) && (p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y));
}

}  // namespace

bool land_contains(const LandShape& land, Vec2 p, bool use_index) {
  const std::size_t n = land.points.size();
  if (n < 3) return false;
  std::uint32_t count = 0;
  if (!use_index) {
    for (std::size_t k = 0; k < n; ++k) count += edge_crosses(land.points[k], land.points[(k + 1) % n], p) ? 1 : 0;
  } else {
    if (p.y < land.ymin || p.y > land.ymax) return false;
    const std::size_t j = static_cast<std::size_t>(land.band_of(p.y));
    for (std::uint32_t i = land.edge_start[j]; i < land.edge_start[j + 1]; ++i) {
      const std::uint32_t k = land.edge_ids[i];
      count += edge_crosses(land.points[k], land.points[(k + 1) % n], p) ? 1 : 0;
    }
  }
  return (count & 1u) != 0;
}

float land_nearest_edge(const LandShape& land, Vec2 p, bool use_index, std::uint32_t& edge) {
  const std::size_t n = land.points.size();
  float best = INF;
  std::uint32_t best_k = 0;
  auto test = [&](std::uint32_t k) {
    Vec2 q;
    const float d2 = seg_closest(p, land.points[k], land.points[(k + 1) % n], q);
    if (d2 < best || (d2 == best && k < best_k)) {
      best = d2;
      best_k = k;
    }
  };
  if (!use_index || land.bands <= 1) {
    for (std::size_t k = 0; k < n; ++k) test(static_cast<std::uint32_t>(k));
  } else {
    const std::int32_t kp = land.band_of(p.y);
    for (std::int32_t ring = 0;; ++ring) {
      const std::int32_t lo = kp - ring;
      const std::int32_t hi = kp + ring;
      if (lo < 0 && hi >= land.bands) break;
      if (ring >= 2) {
        const float lb = static_cast<float>(ring - 2) * land.band_h;
        if (lb * lb > best) break;
      }
      auto scan = [&](std::int32_t j) {
        const std::size_t js = static_cast<std::size_t>(j);
        for (std::uint32_t i = land.edge_start[js]; i < land.edge_start[js + 1]; ++i) test(land.edge_ids[i]);
      };
      if (ring == 0) {
        scan(kp);
        continue;
      }
      if (lo >= 0) scan(lo);
      if (hi < land.bands) scan(hi);
    }
  }
  edge = best_k;
  return best;
}

bool collide_boat_land(std::span<const Vec2> a, Vec2 pos, float r_hull, const LandShape& land, bool use_index,
                       Hit& out) {
  const std::size_t nl = land.points.size();
  const std::size_t na = a.size();
  if (nl < 3) return false;
  const float reach = r_hull + BOUND_MARGIN;
  if (use_index &&
      (pos.x + reach < land.xmin || pos.x - reach > land.xmax || pos.y + reach < land.ymin ||
       pos.y - reach > land.ymax)) {
    return false;
  }
  bool found = false;
  float best = 0.0f;
  // (a) hull vertices inside the land.
  for (std::size_t k = 0; k < na; ++k) {
    const Vec2 w = a[k];
    if (!land_contains(land, w, use_index)) continue;
    std::uint32_t e = 0;
    const float depth = std::sqrt(land_nearest_edge(land, w, use_index, e));
    if (depth > best) {
      best = depth;
      found = true;
      const Vec2 no = outward(land.points[e], land.points[(e + 1) % nl]);
      out.depth = depth;
      out.normal = no;
      out.point = w;
    }
  }
  // (b) land vertices strictly inside the hull, ascending index.
  auto test_vertex = [&](std::uint32_t qi) {
    const Vec2 q = land.points[qi];
    std::size_t e = 0;
    float dmin = INF;
    for (std::size_t k = 0; k < na; ++k) {
      const float d = -dot(sub(q, a[k]), outward(a[k], a[(k + 1) % na]));
      if (!(d > 0.0f)) return;
      if (d < dmin) {
        dmin = d;
        e = k;
      }
    }
    if (dmin > best) {
      best = dmin;
      found = true;
      const Vec2 no = outward(a[e], a[(e + 1) % na]);
      out.depth = dmin;
      out.normal = {-no.x, -no.y};
      out.point = q;
    }
  };
  if (!use_index) {
    for (std::size_t k = 0; k < nl; ++k) test_vertex(static_cast<std::uint32_t>(k));
  } else {
    std::vector<std::uint32_t> ids;
    const std::int32_t j0 = land.band_of(pos.y - reach);
    const std::int32_t j1 = land.band_of(pos.y + reach);
    for (std::int32_t j = j0; j <= j1; ++j) {
      const std::size_t js = static_cast<std::size_t>(j);
      for (std::uint32_t i = land.vert_start[js]; i < land.vert_start[js + 1]; ++i) {
        const Vec2 q = land.points[land.vert_ids[i]];
        if (std::fabs(q.x - pos.x) <= reach && std::fabs(q.y - pos.y) <= reach) ids.push_back(land.vert_ids[i]);
      }
    }
    std::sort(ids.begin(), ids.end());
    for (std::uint32_t qi : ids) test_vertex(qi);
  }
  return found;
}

void outline_to_world(std::span<const Vec2> body, Vec2 pos, float psi, std::vector<Vec2>& world) {
  const SinCos sc = wm_sincos(psi);
  const Vec2 f{sc.s, sc.c};
  const Vec2 p{-sc.c, sc.s};
  world.resize(body.size());
  for (std::size_t k = 0; k < body.size(); ++k) {
    const Vec2 b = body[k];
    world[k] = {(pos.x + b.x * f.x) + b.y * p.x, (pos.y + b.x * f.y) + b.y * p.y};
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Scene

void CollisionScene::clear() {
  course_.clear();
  obstacles_.clear();
  land_.clear();
}

std::int32_t CollisionScene::add_mark(Vec2 centre, float radius) {
  if (!(radius >= 0.8f)) return -1;
  CourseShape s;
  s.kind = ContactKind::mark;
  s.pos = centre;
  s.radius = radius;
  course_.push_back(std::move(s));
  return static_cast<std::int32_t>(course_.size() - 1);
}

std::int32_t CollisionScene::add_course_circle(Vec2 centre, float radius) {
  if (!(radius >= 0.8f)) return -1;
  CourseShape s;
  s.kind = ContactKind::course_object;
  s.pos = centre;
  s.radius = radius;
  course_.push_back(std::move(s));
  return static_cast<std::int32_t>(course_.size() - 1);
}

std::int32_t CollisionScene::add_course_polygon(Vec2 pos, float heading, std::span<const Vec2> outline_body) {
  if (!valid_outline(outline_body)) return -1;
  CourseShape s;
  s.kind = ContactKind::course_object;
  s.is_circle = false;
  s.pos = pos;
  s.heading = heading;
  float r = 0.0f;
  for (const Vec2& v : outline_body) r = max(r, std::sqrt(v.x * v.x + v.y * v.y));
  s.radius = r;
  outline_to_world(outline_body, pos, heading, s.world);
  course_.push_back(std::move(s));
  return static_cast<std::int32_t>(course_.size() - 1);
}

std::int32_t CollisionScene::add_virtual() {
  CourseShape s;
  s.solid = false;
  course_.push_back(std::move(s));
  return static_cast<std::int32_t>(course_.size() - 1);
}

void CollisionScene::set_venue(const VenueData& venue) {
  obstacles_.clear();
  land_.clear();
  for (const VenueObstacle& o : venue.obstacles) {
    ObstacleShape s;
    s.is_circle = o.is_circle;
    if (o.is_circle) {
      s.centre = o.c;
      s.radius = o.r;
    } else {
      s.polygon = o.polygon;
      float sx = 0.0f, sy = 0.0f;
      for (const Vec2& v : o.polygon) {
        sx = sx + v.x;
        sy = sy + v.y;
      }
      const float n = static_cast<float>(o.polygon.size());
      s.centre = {sx / n, sy / n};
      float r = 0.0f;
      for (const Vec2& v : o.polygon) r = max(r, dist_between(v, s.centre));
      s.radius = r;
    }
    obstacles_.push_back(std::move(s));
  }
  for (const VenueLand& l : venue.land) {
    LandShape s;
    s.build(l.points);
    land_.push_back(std::move(s));
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Step

std::uint64_t Collisions::pair_key(std::int32_t boat, ContactKind kind, std::int32_t other) {
  return (static_cast<std::uint64_t>(static_cast<std::uint32_t>(boat)) << 36) |
         (static_cast<std::uint64_t>(kind) << 32) | static_cast<std::uint64_t>(static_cast<std::uint32_t>(other));
}

namespace {

struct Contact {
  std::int32_t a;
  ContactKind kind;
  std::int32_t other;
  Hit hit;
};

inline bool by_key(const ContactPair& a, const ContactPair& b) { return a.key < b.key; }

struct BoatInfo {
  Vec2 pos;
  float psi;
  Vec2 f;
  float r_hull, mass, inertia;
};

}  // namespace

void Collisions::step(std::uint64_t tick, std::span<Boat> boats, std::span<const CollideBoatInput> input,
                      const CollisionScene& scene, std::vector<ContactEvent>& events) {
  const std::size_t nb = boats.size();
  world_.resize(nb);
  std::vector<BoatInfo> info(nb);
  for (std::size_t i = 0; i < nb; ++i) {
    const BoatState& s = boats[i].state();
    const CollisionShape& cs = boats[i].perf().dynamics.collision;
    BoatInfo& b = info[i];
    b.pos = {s.pos_x, s.pos_y};
    b.psi = s.psi;
    const SinCos sc = wm_sincos(s.psi);
    b.f = {sc.s, sc.c};
    float r = 0.0f;
    for (const Vec2& v : cs.outline) r = max(r, std::sqrt(v.x * v.x + v.y * v.y));
    b.r_hull = r;
    b.mass = cs.mass;
    b.inertia = cs.mass * (cs.yaw_gyration * cs.yaw_gyration);
    if (input[i].collides) outline_to_world(cs.outline, b.pos, s.psi, world_[i]);
  }

  // §3.1 detection, all on the positions after the boat steps.
  std::vector<Contact> list;
  Hit h;
  for (std::size_t i = 0; i < nb; ++i) {
    if (!input[i].collides) continue;
    for (std::size_t j = i + 1; j < nb; ++j) {
      if (!input[j].collides) continue;
      if (!(dist_between(info[i].pos, info[j].pos) < info[i].r_hull + info[j].r_hull)) continue;
      if (collide_polygons(world_[i], info[i].pos, world_[j], info[j].pos, h)) {
        list.push_back({static_cast<std::int32_t>(i), ContactKind::boat, static_cast<std::int32_t>(j), h});
      }
    }
  }
  const auto& course = scene.course();
  for (std::size_t i = 0; i < nb; ++i) {
    if (!input[i].collides) continue;
    for (std::size_t k = 0; k < course.size(); ++k) {
      const CourseShape& c = course[k];
      if (!c.solid) continue;
      if (!(dist_between(info[i].pos, c.pos) < info[i].r_hull + c.radius)) continue;
      const bool hit = c.is_circle ? collide_circle_polygon(c.pos, c.radius, world_[i], h)
                                   : collide_polygons(world_[i], info[i].pos, c.world, c.pos, h);
      if (hit) list.push_back({static_cast<std::int32_t>(i), c.kind, static_cast<std::int32_t>(k), h});
    }
  }
  const auto& obstacles = scene.obstacles();
  const auto& land = scene.land();
  for (std::size_t i = 0; i < nb; ++i) {
    if (!input[i].collides) continue;
    for (std::size_t k = 0; k < obstacles.size(); ++k) {
      const ObstacleShape& o = obstacles[k];
      if (!(dist_between(info[i].pos, o.centre) < info[i].r_hull + o.radius)) continue;
      const bool hit = o.is_circle ? collide_circle_polygon(o.centre, o.radius, world_[i], h)
                                   : collide_polygons(world_[i], info[i].pos, o.polygon, o.centre, h);
      if (hit) list.push_back({static_cast<std::int32_t>(i), ContactKind::obstacle, static_cast<std::int32_t>(k), h});
    }
    for (std::size_t k = 0; k < land.size(); ++k) {
      if (collide_boat_land(world_[i], info[i].pos, info[i].r_hull, land[k], true, h)) {
        list.push_back({static_cast<std::int32_t>(i), ContactKind::land, static_cast<std::int32_t>(k), h});
      }
    }
  }

  // §4 response, one pass in list order.
  using C = CollideConst;
  std::vector<std::uint64_t> next;
  next.reserve(list.size());
  for (const Contact& c : list) {
    const bool bb = c.kind == ContactKind::boat;
    BoatState& A = boats[static_cast<std::size_t>(c.a)].mutable_state();
    const BoatInfo& ia = info[static_cast<std::size_t>(c.a)];
    const Vec2 n = c.hit.normal;
    const float corr = min(max(c.hit.depth - C::SLOP, 0.0f) * C::PUSH, C::PUSH_MAX);

    // 4.2 inputs (ground velocities before this contact's impulse).
    const CollideBoatInput& in_a = input[static_cast<std::size_t>(c.a)];
    // Ground velocity: along the heading, the sideways drift (`sway` to starboard, f = (fx, fy) -> (fy, -fx)),
    // the current, the contact velocity (§4.2, boat.md §5.10).
    Vec2 vr{((A.v * ia.f.x + A.sway * ia.f.y) + in_a.current.x) + A.contact_vx,
            ((A.v * ia.f.y - A.sway * ia.f.x) + in_a.current.y) + A.contact_vy};
    float inv = 1.0f / ia.mass;
    BoatState* B = nullptr;
    const BoatInfo* ib = nullptr;
    if (bb) {
      B = &boats[static_cast<std::size_t>(c.other)].mutable_state();
      ib = &info[static_cast<std::size_t>(c.other)];
      const CollideBoatInput& in_b = input[static_cast<std::size_t>(c.other)];
      const Vec2 vb{((B->v * ib->f.x + B->sway * ib->f.y) + in_b.current.x) + B->contact_vx,
                    ((B->v * ib->f.y - B->sway * ib->f.x) + in_b.current.y) + B->contact_vy};
      vr = {vr.x - vb.x, vr.y - vb.y};
      inv = inv + 1.0f / ib->mass;
    }

    // 4.1 separate
    if (bb) {
      const float msum = ia.mass + ib->mass;
      const float sa = (corr * ib->mass) / msum;
      const float sb = (corr * ia.mass) / msum;
      A.pos_x = A.pos_x + n.x * sa;
      A.pos_y = A.pos_y + n.y * sa;
      B->pos_x = B->pos_x - n.x * sb;
      B->pos_y = B->pos_y - n.y * sb;
    } else {
      A.pos_x = A.pos_x + n.x * corr;
      A.pos_y = A.pos_y + n.y * corr;
    }

    // 4.2 impulse
    const float vn = dot(vr, n);
    float j = 0.0f;
    if (vn < 0.0f) {
      const float e = bb ? C::REST_BOAT
                         : (c.kind == ContactKind::mark || c.kind == ContactKind::course_object ? C::REST_MARK
                                                                                               : C::REST_FIXED);
      const float mu = bb ? C::FRICTION_BOAT : C::FRICTION_FIXED;
      j = (-(1.0f + e) * vn) / inv;
      const Vec2 t{-n.y, n.x};
      const float vt = dot(vr, t);
      const float jt = clamp(-vt / inv, -(mu * j), mu * j);
      const Vec2 J{n.x * j + t.x * jt, n.y * j + t.y * jt};
      auto apply = [&](BoatState& s, const BoatInfo& bi, Vec2 imp) {
        const Vec2 dV{imp.x / bi.mass, imp.y / bi.mass};
        const float dv = dot(dV, bi.f);
        s.v = s.v + dv;
        s.contact_vx = s.contact_vx + (dV.x - bi.f.x * dv);
        s.contact_vy = s.contact_vy + (dV.y - bi.f.y * dv);
        const Vec2 r{c.hit.point.x - bi.pos.x, c.hit.point.y - bi.pos.y};
        const float torque = r.x * imp.y - r.y * imp.x;
        s.contact_yaw_rate = clamp(s.contact_yaw_rate - torque / bi.inertia, -C::YAW_KICK_MAX, C::YAW_KICK_MAX);
      };
      apply(A, ia, J);
      if (bb) apply(*B, *ib, {-J.x, -J.y});
    }

    // §5 event
    const std::uint64_t key = pair_key(c.a, c.kind, c.other);
    ContactEvent ev;
    ev.tick = tick;
    ev.boat = c.a;
    ev.other_kind = c.kind;
    ev.other = c.other;
    ev.point = c.hit.point;
    ev.normal = n;
    ev.depth = c.hit.depth;
    ev.closing_speed = max(0.0f, -vn);
    ev.impulse = j;
    ev.begin = !std::binary_search(pairs_.begin(), pairs_.end(), ContactPair{key, 0}, by_key);
    events.push_back(ev);
    next.push_back(key);
  }
  // §6: the pairs touched now get age 0, the others age by one tick and leave after CONTACT_GAP ticks.
  std::sort(next.begin(), next.end());
  next.erase(std::unique(next.begin(), next.end()), next.end());
  std::vector<ContactPair> merged;
  merged.reserve(pairs_.size() + next.size());
  std::size_t a = 0, b = 0;
  while (a < pairs_.size() || b < next.size()) {
    if (b < next.size() && (a == pairs_.size() || next[b] <= pairs_[a].key)) {
      if (a < pairs_.size() && pairs_[a].key == next[b]) ++a;
      merged.push_back({next[b], 0});
      ++b;
    } else {
      const std::uint8_t age = static_cast<std::uint8_t>(pairs_[a].age + 1);
      if (age < C::CONTACT_GAP) merged.push_back({pairs_[a].key, age});
      ++a;
    }
  }
  pairs_ = std::move(merged);
}

void Collisions::save(SnapshotWriter& w) const {
  w.put_u32(static_cast<std::uint32_t>(pairs_.size()));
  for (const ContactPair& p : pairs_) {
    w.put_u64(p.key);
    w.put_u8(p.age);
  }
}

bool Collisions::load(SnapshotReader& r) {
  const std::uint32_t n = r.get_u32();
  std::vector<ContactPair> pairs;
  for (std::uint32_t i = 0; i < n && !r.failed(); ++i) {
    ContactPair p;
    p.key = r.get_u64();
    p.age = r.get_u8();
    pairs.push_back(p);
  }
  if (r.failed()) return false;
  for (std::size_t i = 0; i < pairs.size(); ++i) {
    if (pairs[i].age >= CollideConst::CONTACT_GAP) return false;
    if (i > 0 && !(pairs[i - 1].key < pairs[i].key)) return false;
  }
  pairs_ = std::move(pairs);
  return true;
}

}  // namespace wm
