// The land edge grid (venues.md §4.1): every indexed land query gives the bits of the full query it replaces, on
// a real coastline (the Fremantle venue) and on a fixture built to stress ties and long edges.
#include <bit>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

#include "course/geometry.h"
#include "data/venue.h"
#include "doctest.h"
#include "math/rng.h"

namespace {

using wm::Vec2;

const std::string kData = WINDMARK_DATA_DIR;

std::uint32_t bits(float f) { return std::bit_cast<std::uint32_t>(f); }

// A boat-sized convex outline (counter-clockwise, about 10 m by 3 m).
const std::vector<Vec2> kHull = {{-5.0f, -1.5f}, {3.0f, -1.5f}, {5.0f, 0.0f}, {3.0f, 1.5f}, {-5.0f, 1.5f}};

struct Counts {
  int inside = 0, near = 0, touching = 0;
};

// Points and hulls spread over the polygon's box and its margin, half of them within a few hull lengths of a
// vertex so the coast itself is well covered.
Counts compare(const std::vector<Vec2>& poly, const wm::PolygonIndex& idx, std::uint64_t seed, int count) {
  REQUIRE(idx.usable(poly));
  float x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
  for (const Vec2 v : poly) {
    x0 = wm::min(x0, v.x);
    y0 = wm::min(y0, v.y);
    x1 = wm::max(x1, v.x);
    y1 = wm::max(y1, v.y);
  }
  Counts c;
  std::vector<Vec2> hull;
  for (int i = 0; i < count; ++i) {
    const std::uint64_t k = static_cast<std::uint64_t>(i);
    Vec2 p;
    if (i % 2 == 0) {
      const float m = 0.1f * wm::max(x1 - x0, y1 - y0) + 50.0f;
      p = {wm::rng_range(x0 - m, x1 + m, seed, 0, k), wm::rng_range(y0 - m, y1 + m, seed, 1, k)};
    } else {
      const std::size_t v = static_cast<std::size_t>(wm::rng_range(0.0f, static_cast<float>(poly.size()), seed, 2, k));
      const Vec2 q = poly[v < poly.size() ? v : 0];
      p = {q.x + wm::rng_range(-40.0f, 40.0f, seed, 3, k), q.y + wm::rng_range(-40.0f, 40.0f, seed, 4, k)};
    }
    if (i % 97 == 1) p = poly[static_cast<std::size_t>(i) % poly.size()];  // exactly on a vertex

    const bool in = wm::point_in_polygon(p, poly);
    REQUIRE(wm::point_in_polygon(p, poly, &idx) == in);
    c.inside += in ? 1 : 0;

    const float d = wm::point_polygon_edge_dist(p, poly);
    for (const float cap : {0.0f, 5.0f, 23.7f, 120.0f}) {
      const float dc = wm::point_polygon_edge_dist_capped(p, poly, &idx, cap);
      if (d <= cap) {
        REQUIRE(bits(dc) == bits(d));
      } else {
        REQUIRE(dc > cap);
      }
      CHECK((dc < cap) == (d < cap));
    }
    c.near += d < 30.0f ? 1 : 0;

    const Vec2 np = wm::polygon_nearest_point(p, poly, nullptr, {0.0f, 0.0f});
    const Vec2 ni = wm::polygon_nearest_point(p, poly, &idx, {0.0f, 0.0f});
    REQUIRE(bits(np.x) == bits(ni.x));
    REQUIRE(bits(np.y) == bits(ni.y));

    wm::place_outline(kHull, p, wm::rng_range(0.0f, wm::TWO_PI, seed, 5, k), hull);
    const float g = wm::polygon_gap(hull, poly);
    REQUIRE(bits(wm::polygon_gap(hull, poly, &idx)) == bits(g));
    c.touching += g == 0.0f ? 1 : 0;
  }
  return c;
}

}  // namespace

TEST_CASE("land index: Fremantle's coast gives the full queries' bits") {
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/fremantle.venue.json", v, err), err.message());
  REQUIRE(!v.land.empty());
  Counts all;
  for (std::size_t i = 0; i < v.land.size(); ++i) {
    const wm::VenueLand& l = v.land[i];
    // The rules' bounding circle, computed once at load in the same order.
    wm::Vec2 c{0.0f, 0.0f};
    for (const Vec2 p : l.points) c = wm::v_add(c, p);
    c = wm::v_scale(c, 1.0f / static_cast<float>(l.points.size()));
    float r = 0.0f;
    for (const Vec2 p : l.points) r = wm::max(r, wm::v_dist(p, c));
    CHECK(bits(l.index.centre.x) == bits(c.x));
    CHECK(bits(l.index.centre.y) == bits(c.y));
    CHECK(bits(l.index.radius) == bits(r));
    const Counts k = compare(l.points, l.index, 11 + i, l.points.size() > 100 ? 6000 : 600);
    all.inside += k.inside;
    all.near += k.near;
    all.touching += k.touching;
  }
  // The samples reached every case: inside land, near the shore, hulls on it.
  CHECK(all.inside > 100);
  CHECK(all.near > 100);
  CHECK(all.touching > 100);
}

TEST_CASE("land index: a jagged fixture with ties and long edges") {
  // A 1500-vertex counter-clockwise star around (300, -200) whose spikes alternate between two radii, closed by a
  // few long edges across the grid, so equal edge distances and edges spanning many cells both occur.
  std::vector<Vec2> poly;
  const int n = 1500;
  for (int k = 0; k < n; ++k) {
    const float a = wm::TWO_PI * static_cast<float>(k) / static_cast<float>(n);
    const float r = k % 2 == 0 ? 2000.0f : 1900.0f;
    if (k > 0 && k < 40) continue;  // a wide gap bridged by one long edge
    poly.push_back({300.0f + r * std::cos(a), -200.0f + r * std::sin(a)});
  }
  wm::PolygonIndex idx;
  idx.build(poly);
  const Counts k = compare(poly, idx, 5, 6000);
  CHECK(k.inside > 100);
  CHECK(k.near > 100);
  // The centre is at one of two distances from every spike: many ties, the lowest edge must win.
  const Vec2 centre{300.0f, -200.0f};
  const Vec2 a = wm::polygon_nearest_point(centre, poly, nullptr, centre);
  const Vec2 b = wm::polygon_nearest_point(centre, poly, &idx, centre);
  CHECK(bits(a.x) == bits(b.x));
  CHECK(bits(a.y) == bits(b.y));
  // A stale index (built for another vertex count) falls back to the full queries.
  std::vector<Vec2> fewer(poly.begin(), poly.end() - 1);
  CHECK(!idx.usable(fewer));
  CHECK(wm::point_in_polygon(centre, fewer, &idx) == wm::point_in_polygon(centre, fewer));
}
