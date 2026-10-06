// Collisions (collisions.md): the shape tests, the pair set and the spec's tests of §7.
#include <cmath>
#include <cstdint>
#include <vector>

#include "boat_harness.h"
#include "collide/collide.h"
#include "data/venue.h"
#include "math/rng.h"

using namespace wm_test;
using wm::ContactEvent;
using wm::ContactKind;
using wm::Vec2;

namespace {

// Several boats of one class in a steady uniform wind with the collision step after the boat steps.
struct World {
  std::vector<wm::Boat> boats;
  std::vector<wm::CollideBoatInput> input;
  wm::BoatEnv env;
  wm::CollisionScene scene;
  wm::Collisions col;
  std::vector<ContactEvent> events;  // every event so far
  std::vector<ContactEvent> last;    // the last step's events
  std::uint64_t tick = 0;

  World(int n, float tws_kn, float wind_from, const std::string& cls = "wm7") {
    boats.resize(static_cast<std::size_t>(n));
    input.resize(static_cast<std::size_t>(n));
    for (int i = 0; i < n; ++i) boats[static_cast<std::size_t>(i)].init(&perf(cls), 1, static_cast<std::uint32_t>(i));
    env.wind_speed = kn(tws_kn);
    env.wind_speed_clean = env.wind_speed;
    env.wind_from = wind_from;
  }
  wm::Boat& b(int i) { return boats[static_cast<std::size_t>(i)]; }
  wm::BoatState& s(int i) { return b(i).mutable_state(); }
  void place(int i, float x, float y, float psi, float v) { b(i).reset(x, y, psi, v, -1, true, env); }
  void collide() {
    last.clear();
    col.step(tick, boats, input, scene, last);
    events.insert(events.end(), last.begin(), last.end());
  }
  void step() {
    for (wm::Boat& x : boats) x.step(env);
    collide();
    ++tick;
  }
  // Heading hold on a true wind angle (as boat_harness.h Sim::steer_twa).
  void steer_twa(int i, float twa_target) {
    const float e = wm::wrap_pi(b(i).state().twa - twa_target);
    b(i).set_helm(wm::clamp(4.0f * e, -0.5f, 0.5f));
  }
  Vec2 ground_v(int i) const {
    const wm::BoatState& st = boats[static_cast<std::size_t>(i)].state();
    const wm::SinCos sc = wm::wm_sincos(st.psi);
    return {st.v * sc.s + st.contact_vx, st.v * sc.c + st.contact_vy};
  }
};

std::vector<Vec2> square(float x0, float y0, float x1, float y1) { return {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}; }

wm::VenueData venue_with_land(std::vector<Vec2> pts) {
  wm::VenueData v;
  wm::VenueLand l;
  l.id = "l";
  l.points = std::move(pts);
  v.land.push_back(std::move(l));
  return v;
}

// A star-shaped land polygon with `n` vertices (counter-clockwise, non-convex).
std::vector<Vec2> star(int n, Vec2 c, float r0, float r1) {
  std::vector<Vec2> p;
  for (int k = 0; k < n; ++k) {
    const float a = wm::TWO_PI * static_cast<float>(k) / static_cast<float>(n);
    const float r = (k % 2 == 0) ? r0 : r1;
    const wm::SinCos sc = wm::wm_sincos(a);
    p.push_back({c.x + r * sc.c, c.y + r * sc.s});
  }
  return p;
}

}  // namespace

TEST_CASE("collide: polygon and circle shape tests") {
  const std::vector<Vec2> a = square(0, 0, 2, 2);
  wm::Hit h;
  // B overlaps A by 0.25 from the right.
  const std::vector<Vec2> b = square(1.75f, 0.5f, 3.75f, 1.5f);
  REQUIRE(wm::collide_polygons(a, {1, 1}, b, {2.75f, 1}, h));
  CHECK(h.depth == doctest::Approx(0.25f));
  CHECK(h.normal.x == doctest::Approx(-1.0f));  // from B toward A
  CHECK(h.normal.y == doctest::Approx(0.0f));
  CHECK(h.point.x == doctest::Approx(1.75f));  // the B vertex deepest inside A
  const std::vector<Vec2> far = square(2.5f, 0, 3, 1);
  CHECK_FALSE(wm::collide_polygons(a, {1, 1}, far, {2.75f, 0.5f}, h));
  // Touching exactly is no contact (o <= 0).
  const std::vector<Vec2> touch = square(2, 0, 3, 1);
  CHECK_FALSE(wm::collide_polygons(a, {1, 1}, touch, {2.5f, 0.5f}, h));

  // Circle outside, near the top edge.
  REQUIRE(wm::collide_circle_polygon({1.0f, 2.5f}, 0.8f, a, h));
  CHECK(h.depth == doctest::Approx(0.3f));
  CHECK(h.normal.y == doctest::Approx(-1.0f));
  CHECK(h.point.y == doctest::Approx(2.0f));
  CHECK_FALSE(wm::collide_circle_polygon({1.0f, 3.0f}, 0.8f, a, h));
  // Circle centre inside, nearest the right edge.
  REQUIRE(wm::collide_circle_polygon({1.8f, 1.0f}, 0.8f, a, h));
  CHECK(h.depth == doctest::Approx(1.0f));
  CHECK(h.normal.x == doctest::Approx(-1.0f));
}

TEST_CASE("collide: land containment and the band index match the full tests") {
  wm::LandShape land;
  land.build(star(240, {100, 50}, 80, 50));
  CHECK(land.bands > 1);
  CHECK(wm::land_contains(land, {100, 50}, true));
  CHECK_FALSE(wm::land_contains(land, {300, 50}, true));
  const std::vector<Vec2>& hull = perf("wm7").dynamics.collision.outline;
  float r_hull = 0.0f;
  for (const Vec2& v : hull) r_hull = std::fmax(r_hull, std::sqrt(v.x * v.x + v.y * v.y));
  int found = 0;
  std::vector<Vec2> w;
  for (std::uint64_t i = 0; i < 4000; ++i) {
    const Vec2 p{wm::rng_range(0.0f, 200.0f, 99, 0, i), wm::rng_range(-50.0f, 150.0f, 99, 1, i)};
    std::uint32_t e1 = 0, e2 = 0;
    const float d1 = wm::land_nearest_edge(land, p, true, e1);
    const float d2 = wm::land_nearest_edge(land, p, false, e2);
    REQUIRE(d1 == d2);
    REQUIRE(e1 == e2);
    REQUIRE(wm::land_contains(land, p, true) == wm::land_contains(land, p, false));
    wm::outline_to_world(hull, p, wm::rng_range(0.0f, wm::TWO_PI, 99, 2, i), w);
    wm::Hit h1, h2;
    const bool c1 = wm::collide_boat_land(w, p, r_hull, land, true, h1);
    const bool c2 = wm::collide_boat_land(w, p, r_hull, land, false, h2);
    REQUIRE(c1 == c2);
    if (c1) {
      ++found;
      CHECK(h1.depth == h2.depth);
      CHECK(h1.normal.x == h2.normal.x);
      CHECK(h1.normal.y == h2.normal.y);
      CHECK(h1.point.x == h2.point.x);
      CHECK(h1.point.y == h2.point.y);
    }
  }
  CHECK(found > 20);
}

// §7 test 1. Pointed bows meeting stem to stem touch along a bow edge, so the contact normal is oblique; the
// restitution acts on the closing speed along it, and the equal masses share the loss equally.
TEST_CASE("collide: head-on at 3 m/s, equal masses") {
  World wd(2, 10.0f, wm::HALF_PI);
  const float stem = 3.455f;
  wd.place(0, 0.0f, 0.0f, 0.0f, 3.0f);
  wd.place(1, 0.0f, 2.0f * stem - 0.1f, wm::PI, 3.0f);
  const Vec2 va = wd.ground_v(0), vb = wd.ground_v(1);
  wd.collide();
  REQUIRE(wd.last.size() == 1);
  const ContactEvent& ev = wd.last[0];
  CHECK(ev.other_kind == ContactKind::boat);
  CHECK(ev.boat == 0);
  CHECK(ev.other == 1);
  CHECK(ev.begin);
  const Vec2 n = ev.normal;
  const float vn0 = (va.x - vb.x) * n.x + (va.y - vb.y) * n.y;
  REQUIRE(vn0 < -1.0f);
  CHECK(ev.closing_speed == doctest::Approx(-vn0));
  const Vec2 va1 = wd.ground_v(0), vb1 = wd.ground_v(1);
  const float vn1 = (va1.x - vb1.x) * n.x + (va1.y - vb1.y) * n.y;
  CHECK(vn1 == doctest::Approx(-0.2f * vn0).epsilon(1e-4));  // closing speed 0.2x, now opening
  const float dva = 3.0f - wd.b(0).state().v;
  const float dvb = 3.0f - wd.b(1).state().v;
  CHECK(dva > 0.3f);
  CHECK(dva == doctest::Approx(dvb).epsilon(1e-4));
  // Momentum is kept (equal masses: the sum of the ground velocities).
  CHECK((va1.x + vb1.x) == doctest::Approx(va.x + vb.x).epsilon(1e-4));
  CHECK((va1.y + vb1.y) == doctest::Approx(va.y + vb.y).epsilon(1e-4));
  // Pushed apart equally.
  const float da = std::hypot(wd.b(0).state().pos_x, wd.b(0).state().pos_y);
  const float db = std::hypot(wd.b(1).state().pos_x, wd.b(1).state().pos_y - (2.0f * stem - 0.1f));
  CHECK(da > 0.0f);
  CHECK(da == doctest::Approx(db));
}

// §7 test 2
TEST_CASE("collide: T-bone pushes and spins the struck boat, both decay") {
  World wd(2, 10.0f, wm::HALF_PI);
  wd.place(0, 0.0f, 0.0f, 0.0f, 0.0f);  // struck, heading north, at rest
  // Striker heading east, its stem 0.08 m inside the struck boat's port side at body x = 1 m.
  wd.place(1, -0.915f - 3.455f + 0.08f, 1.0f, wm::HALF_PI, 3.0f);
  wd.b(0).set_let_fly(true);
  wd.collide();
  REQUIRE(wd.last.size() == 1);
  CHECK(wd.last[0].begin);
  const wm::BoatState& s0 = wd.b(0).state();
  const float cv0 = s0.contact_vx;
  const float yaw0 = s0.contact_yaw_rate;
  CHECK(cv0 > 0.5f);                          // pushed east (the push direction)
  CHECK(std::fabs(s0.contact_vy) < 0.1f * cv0);
  CHECK(yaw0 > 0.0f);                         // bow turned toward the push (clockwise)
  CHECK(wd.b(1).state().v < 1.5f);            // the rammer lost most of its forward speed
  // Head to wind the rammer coasts on (boat.md §5.8) and would push again as the struck boat's contact velocity
  // decays; stop it so the decay itself is measured.
  wd.s(1).v = 0.0f;
  // 1.1 s = 22 ticks
  float cv_peak = cv0, yaw_peak = yaw0;
  for (int k = 0; k < 22; ++k) {
    wd.step();
    cv_peak = std::fmax(cv_peak, wd.b(0).state().contact_vx);
    yaw_peak = std::fmax(yaw_peak, wd.b(0).state().contact_yaw_rate);
  }
  CHECK(cv_peak == cv0);
  CHECK(yaw_peak == yaw0);
  const wm::BoatState& s1 = wd.b(0).state();
  CHECK(std::hypot(s1.contact_vx, s1.contact_vy) < 0.1f * cv0);
  CHECK(std::fabs(s1.contact_yaw_rate) < 0.1f * yaw0);
}

// §7 test 3
TEST_CASE("collide: sailing into land at 45 deg slides along it for 30 s") {
  World wd(1, 12.0f, 7.0f * wm::QUARTER_PI);  // wind from the north-west
  wm::VenueData v = venue_with_land(square(50.0f, -2000.0f, 2000.0f, 2000.0f));
  wd.scene.set_venue(v);
  wd.place(0, 44.0f, 0.0f, wm::QUARTER_PI, 3.0f);  // heading north-east: 45 deg to the shore
  int first = -1;
  float y_first = 0.0f, max_x = -1e9f;
  int contacts = 0;
  std::vector<Vec2> w;
  const int ticks = 800;  // 40 s
  for (int k = 0; k < ticks; ++k) {
    wd.steer_twa(0, -wm::HALF_PI);
    wd.step();
    if (!wd.last.empty()) {
      ++contacts;
      CHECK(wd.last[0].other_kind == ContactKind::land);
      if (first < 0) {
        first = k;
        y_first = wd.b(0).state().pos_y;
      }
    }
    const wm::BoatState& st = wd.b(0).state();
    wm::outline_to_world(perf("wm7").dynamics.collision.outline, {st.pos_x, st.pos_y}, st.psi, w);
    for (const Vec2& p : w) max_x = std::fmax(max_x, p.x);
    CHECK(st.pos_x < 50.0f);
  }
  REQUIRE(first >= 0);
  REQUIRE(first < ticks - 600);  // at least 30 s against the shore
  CHECK(contacts > 100);
  CHECK(max_x < 50.5f);  // never more than half a metre in
  const float slid = wd.b(0).state().pos_y - y_first;
  MESSAGE("first contact tick ", first, ", contacts ", contacts, ", slid ", slid, " m, deepest x ", max_x);
  CHECK(slid > 5.0f);  // it keeps moving along the shore
}

// §7 test 4
TEST_CASE("collide: passing 0.5 m inside a mark's radius gives exactly one begin") {
  World wd(1, 10.0f, wm::HALF_PI);  // beam reach heading north
  const float half_beam = 1.25f;    // wm7 maximum half-beam
  wd.place(0, 0.0f, -30.0f, 0.0f, 3.0f);
  for (int k = 0; k < 100; ++k) {
    wd.steer_twa(0, wm::HALF_PI);
    wd.step();
  }
  // The mark 10 m ahead on the boat's present track, its centre so that the hull's widest point passes 0.5 m
  // inside the radius on the starboard side.
  REQUIRE(wd.scene.add_virtual() == 0);
  const wm::BoatState& s0 = wd.b(0).state();
  const wm::SinCos sc = wm::wm_sincos(s0.psi);
  const float off = half_beam + 0.8f - 0.5f;
  REQUIRE(wd.scene.add_mark({s0.pos_x + 10.0f * sc.s + off * sc.c, s0.pos_y + 10.0f * sc.c - off * sc.s}, 0.8f) == 1);
  const wm::Vec2 start{s0.pos_x, s0.pos_y};
  for (int k = 0; k < 200; ++k) {
    wd.steer_twa(0, wm::HALF_PI);
    wd.step();
  }
  int begins = 0, touches = 0;
  float deepest = 0.0f;
  for (const ContactEvent& e : wd.events) {
    CHECK(e.other_kind == ContactKind::mark);
    CHECK(e.other == 1);
    ++touches;
    begins += e.begin ? 1 : 0;
    deepest = std::fmax(deepest, e.depth);
  }
  MESSAGE("touches ", touches, ", deepest ", deepest, " m");
  CHECK(touches >= 1);
  CHECK(begins == 1);
  CHECK(std::hypot(wd.b(0).state().pos_x - start.x, wd.b(0).state().pos_y - start.y) > 20.0f);  // went past
}

// §7 test 5
TEST_CASE("collide: rotating a land polygon's vertex list keeps contacts and depths") {
  // A concave island (an L).
  const std::vector<Vec2> base = {{0, 0}, {40, 0}, {40, 15}, {15, 15}, {15, 40}, {0, 40}};
  const std::vector<Vec2>& hull = perf("wm7").dynamics.collision.outline;
  float r_hull = 0.0f;
  for (const Vec2& v : hull) r_hull = std::fmax(r_hull, std::sqrt(v.x * v.x + v.y * v.y));
  std::vector<wm::LandShape> rot(base.size());
  for (std::size_t s = 0; s < base.size(); ++s) {
    std::vector<Vec2> p;
    for (std::size_t k = 0; k < base.size(); ++k) p.push_back(base[(k + s) % base.size()]);
    rot[s].build(p);
  }
  int found = 0;
  std::vector<Vec2> w;
  for (std::uint64_t i = 0; i < 3000; ++i) {
    const Vec2 p{wm::rng_range(-5.0f, 45.0f, 7, 0, i), wm::rng_range(-5.0f, 45.0f, 7, 1, i)};
    wm::outline_to_world(hull, p, wm::rng_range(0.0f, wm::TWO_PI, 7, 2, i), w);
    wm::Hit h0;
    const bool c0 = wm::collide_boat_land(w, p, r_hull, rot[0], true, h0);
    found += c0 ? 1 : 0;
    for (std::size_t s = 1; s < rot.size(); ++s) {
      wm::Hit h;
      REQUIRE(wm::collide_boat_land(w, p, r_hull, rot[s], true, h) == c0);
      if (c0) REQUIRE(h.depth == h0.depth);
    }
  }
  CHECK(found > 100);
}

TEST_CASE("collide: detection order, kinds, collides flag and the pair state") {
  World wd(3, 10.0f, wm::HALF_PI);
  REQUIRE(wd.scene.add_mark({10.0f, 0.0f}, 0.8f) == 0);
  const std::vector<Vec2>& hull = perf("wm7").dynamics.collision.outline;
  REQUIRE(wd.scene.add_course_polygon({-20.0f, 0.0f}, 0.0f, hull) == 1);
  CHECK(wd.scene.add_mark({0, 0}, 0.5f) == -1);
  wm::VenueData v = venue_with_land(square(-5.0f, 30.0f, 5.0f, 40.0f));
  wm::VenueObstacle rock;
  rock.is_circle = true;
  rock.c = {0.0f, -30.0f};
  rock.r = 2.0f;
  v.obstacles.push_back(rock);
  wd.scene.set_venue(v);

  // Boat 2 touches the mark; boat 1 overlaps the committee boat and the rock is touched by boat 0; boats 0 and
  // 2 touch each other side by side; boat 1 also sits in the land.
  wd.place(0, 0.0f, -27.5f, 0.0f, 0.0f);
  wd.place(1, -20.0f, 2.0f, 0.0f, 0.0f);
  wd.place(2, 9.0f, 0.0f, 0.0f, 0.0f);
  wd.collide();
  REQUIRE(wd.last.size() == 3);
  // Marks and course objects for every boat come before any obstacle.
  CHECK(wd.last[0].boat == 1);
  CHECK(wd.last[0].other_kind == ContactKind::course_object);
  CHECK(wd.last[0].other == 1);
  CHECK(wd.last[1].boat == 2);
  CHECK(wd.last[1].other_kind == ContactKind::mark);
  CHECK(wd.last[1].other == 0);
  CHECK(wd.last[2].boat == 0);
  CHECK(wd.last[2].other_kind == ContactKind::obstacle);
  CHECK(wd.last[2].other == 0);
  // Collected in order: boat pairs, then marks and course objects per boat, then obstacles and land per boat.
  wd.place(0, 7.0f, -1.0f, 0.0f, 0.0f);  // now beside boat 2
  wd.place(1, 0.0f, 33.0f, 0.0f, 0.0f);  // in the land
  wd.collide();
  REQUIRE(wd.last.size() == 3);
  CHECK((wd.last[0].other_kind == ContactKind::boat && wd.last[0].boat == 0 && wd.last[0].other == 2));
  CHECK(wd.last[0].begin);
  CHECK((wd.last[1].other_kind == ContactKind::mark && wd.last[1].boat == 2 && !wd.last[1].begin));
  CHECK((wd.last[2].other_kind == ContactKind::land && wd.last[2].boat == 1 && wd.last[2].begin));
  for (const ContactEvent& e : wd.last) CHECK(e.impulse == 0.0f);  // nothing was moving
  // The course-object pair of the first step is kept (age 1) until CONTACT_GAP ticks pass.
  REQUIRE(wd.col.pairs().size() == 5);
  for (std::size_t k = 1; k < wd.col.pairs().size(); ++k) CHECK(wd.col.pairs()[k - 1].key < wd.col.pairs()[k].key);
  int aged = 0;
  for (const wm::ContactPair& p : wd.col.pairs()) aged += p.age == 1 ? 1 : 0;
  CHECK(aged == 2);  // boat 1 with the committee boat, boat 0 with the rock

  // Snapshot round trip.
  wm::SnapshotWriter wr;
  wd.col.save(wr);
  CHECK(wr.bytes().size() == 4 + 5 * 9);
  wm::Collisions other;
  wm::SnapshotReader rd(wr.bytes());
  REQUIRE(other.load(rd));
  CHECK(rd.at_end());
  CHECK(other.pairs() == wd.col.pairs());

  // A boat that does not collide takes part in nothing.
  wd.input[1].collides = false;
  wd.collide();
  for (const ContactEvent& e : wd.last) CHECK(e.boat != 1);
  CHECK(wd.last.size() == 2);

  // Out of contact for CONTACT_GAP ticks: the pairs leave and the next touch begins again.
  wd.input[1].collides = true;
  wd.place(0, 100.0f, 0.0f, 0.0f, 0.0f);
  wd.place(1, 200.0f, 0.0f, 0.0f, 0.0f);
  wd.place(2, 300.0f, 0.0f, 0.0f, 0.0f);
  for (int k = 0; k < wm::CollideConst::CONTACT_GAP - 1; ++k) wd.collide();
  CHECK(wd.col.pairs().size() == 2);  // the two pairs of the last touching step, age CONTACT_GAP - 1
  wd.collide();
  CHECK(wd.col.pairs().empty());
  wd.place(2, 9.0f, 0.0f, 0.0f, 0.0f);
  wd.collide();
  REQUIRE(wd.last.size() == 1);
  CHECK(wd.last[0].begin);
}

TEST_CASE("collide: the venue's obstacles and land from the example venue") {
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_venue(std::string(WINDMARK_DATA_DIR) + "/venues/practice_waters.venue.json", v, err),
                  err.message());
  World wd(1, 10.0f, wm::HALF_PI);
  wd.scene.set_venue(v);
  REQUIRE(wd.scene.obstacles().size() == v.obstacles.size());
  REQUIRE(wd.scene.land().size() == v.land.size());
  wd.place(0, 0.0f, 1990.0f - 3.455f + 0.1f, 0.0f, 2.0f);  // bow 0.1 m into the pier
  wd.collide();
  REQUIRE(wd.last.size() == 1);
  CHECK(wd.last[0].other_kind == ContactKind::obstacle);
  CHECK(wd.last[0].other == 0);
  CHECK(wd.last[0].normal.y == doctest::Approx(-1.0f));
  CHECK(wd.last[0].closing_speed == doctest::Approx(2.0f));
  CHECK(wd.b(0).state().v == doctest::Approx(2.0f - 1.1f * 2.0f));  // restitution 0.1 on a fixed object
}
