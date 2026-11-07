// The world loop (conventions.md §4.1): a race on the shipped example course and venue, spawning, the signals, the
// collision scene, determinism of the tick checksum, and a joining boat.
#include <cmath>
#include <set>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "course/geometry.h"
#include "doctest.h"
#include "world/world.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;
const std::string kCourses = WINDMARK_COURSES_DIR;

const wm::VenueData& bay() {
  static wm::VenueData v;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/practice_waters.venue.json", v, err), err.message());
    loaded = true;
  }
  return v;
}

const wm::CourseData& example_course() {
  static wm::CourseData c;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_course(kCourses + "/practice_waters/example_wl.course.json", c, err), err.message());
    loaded = true;
  }
  return c;
}

wm::WorldSetup setup(std::uint64_t seed) {
  wm::WorldSetup s;
  s.venue = &bay();
  s.race_seed = seed;
  s.wind.base_speed = wm_test::kn(11.0f);
  s.wind.base_from = 0.3f;
  s.race.free_sailing_s = 10.0f;
  return s;
}

std::unique_ptr<wm::World> make_world(std::uint64_t seed, int boats) {
  auto w = std::make_unique<wm::World>(setup(seed));
  for (int i = 0; i < boats; ++i) {
    wm::BoatEntry e;
    e.perf = &wm_test::perf(i % 3 == 2 ? "wm12" : "wm7");
    REQUIRE(w->add_boat(e) == i);
  }
  std::string err;
  REQUIRE_MESSAGE(w->create_race(example_course(), err), err);
  return w;
}

}  // namespace

// boat.md §2: the weather helm option is the world's, given to every boat it adds; off unless asked for.
TEST_CASE("world: the weather helm option reaches every boat") {
  CHECK_FALSE(wm::WorldSetup().weather_helm);
  for (bool on : {false, true}) {
    wm::WorldSetup s = setup(3);
    s.weather_helm = on;
    wm::World w(s);
    for (int i = 0; i < 2; ++i) {
      wm::BoatEntry e;
      e.perf = &wm_test::perf(i == 0 ? "wm7" : "wm12");
      e.human = i == 0;
      REQUIRE(w.add_boat(e) == i);
      CHECK(w.boat(static_cast<std::size_t>(i)).weather_helm() == on);
    }
  }
}

TEST_CASE("world: a race on the example course") {
  auto w = make_world(7, 8);
  const wm::Race& race = w->race();
  const wm::ResolvedCourse& rc = w->course();
  CHECK(race.state() == wm::RaceState::free_sailing);
  // The course is laid to the median wind at the gun (the base direction plus the trend, 0 here).
  CHECK(rc.twd_c == doctest::Approx(0.3f));
  CHECK(rc.k >= 0.5f);
  CHECK(rc.k <= 2.0f);
  // The collision scene has one entry per mark, in course order (courses.md §2).
  REQUIRE(w->scene().course().size() == rc.marks.size());
  for (std::size_t m = 0; m < rc.marks.size(); ++m) {
    const bool solid = rc.marks[m].type != wm::MarkType::virtual_point;
    CHECK(w->scene().course()[m].solid == solid);
  }
  CHECK(w->scene().land().size() == bay().land.size());

  // Spawned on the pre-start side, on starboard at a close reach, apart from each other.
  std::set<std::pair<float, float>> seen;
  for (std::size_t i = 0; i < w->boat_count(); ++i) {
    const wm::BoatState& s = w->boat(i).state();
    CHECK(race.start_s({s.pos_x, s.pos_y}) < 0.0f);
    CHECK(wm::wrap_pi(s.twd_from - s.psi) == doctest::Approx(100.0f * wm::DEG).epsilon(0.02));
    CHECK(s.v > 0.5f);
    seen.insert({s.pos_x, s.pos_y});
  }
  CHECK(seen.size() == w->boat_count());

  // Sail on to just after the gun with the helm free: the signals come at their ticks.
  std::vector<std::pair<std::uint32_t, wm::SignalKind>> signals;
  const std::uint32_t gun = static_cast<std::uint32_t>(race.n_gun());
  while (w->tick() <= gun) {
    w->step();
    for (const wm::RaceEvent& e : w->events().race) {
      if (e.kind == wm::RaceEventKind::signal) signals.push_back({e.tick, e.signal});
    }
  }
  REQUIRE(signals.size() >= 4);
  CHECK(signals[0] == std::make_pair(gun - 3600u, wm::SignalKind::warning));  // 3-2-1-0 (course default)
  CHECK(signals[1] == std::make_pair(gun - 2400u, wm::SignalKind::prep_up));
  CHECK(signals[2] == std::make_pair(gun - 1200u, wm::SignalKind::prep_down));
  CHECK(signals[3] == std::make_pair(gun, wm::SignalKind::start));
  CHECK(race.state() == wm::RaceState::racing);
  CHECK(race.rules_live());
}

TEST_CASE("world: same seed, same ticks; another seed, another race") {
  auto a = make_world(11, 5), b = make_world(11, 5), c = make_world(12, 5);
  bool same = true, differ = false;
  for (int k = 0; k < 1500; ++k) {
    const float h = 0.3f * wm::wm_sin(static_cast<float>(k) * 0.01f);
    for (auto* w : {a.get(), b.get(), c.get()}) {
      for (std::int32_t i = 0; i < 5; ++i) w->set_helm(i, i % 2 == 0 ? h : -h);
    }
    a->step();
    b->step();
    c->step();
    const std::uint64_t ca = a->checksum(), cb = b->checksum(), cc = c->checksum();
    same = same && ca == cb;
    differ = differ || ca != cc;
  }
  CHECK(same);
  CHECK(differ);
  CHECK(a->checksum() == b->checksum());
}

TEST_CASE("world: a boat joining before the preparatory signal takes a free slot") {
  auto w = make_world(3, 4);
  for (int k = 0; k < 100; ++k) w->step();
  wm::BoatEntry e;
  e.perf = &wm_test::perf("wm7");
  const std::int32_t j = w->add_boat(e);
  REQUIRE(j == 4);
  const wm::BoatState& s = w->boat(4).state();
  CHECK(w->race().start_s({s.pos_x, s.pos_y}) < 0.0f);
  for (std::size_t i = 0; i < 4; ++i) {
    const wm::BoatState& o = w->boat(i).state();
    CHECK(wm::v_dist({s.pos_x, s.pos_y}, {o.pos_x, o.pos_y}) >= 3.0f * w->race().L_max());
  }
  CHECK(w->rules().boat_count() == 5);
  // After the preparatory signal the race takes no more boats.
  while (!w->race().rules_live()) w->step();
  CHECK(w->add_boat(e) == -1);
}

TEST_CASE("world: free sail lays the course without a race") {
  auto w = std::make_unique<wm::World>(setup(5));
  wm::BoatEntry e;
  e.perf = &wm_test::perf("wm7");
  REQUIRE(w->add_boat(e) == 0);
  CHECK_FALSE(w->course_laid());
  std::string err;
  REQUIRE_MESSAGE(w->lay_course(example_course(), err), err);
  CHECK(w->course_laid());
  CHECK_FALSE(w->race_created());
  const wm::ResolvedCourse& rc = w->course();
  // courses.md §6.4: the axis on the median wind now (the base direction, no trend here), scaled as in a race.
  CHECK(rc.twd_c == doctest::Approx(0.3f));
  CHECK(rc.k >= 0.5f);
  CHECK(rc.k <= 2.0f);
  REQUIRE(w->scene().course().size() == rc.marks.size());
  for (std::size_t m = 0; m < rc.marks.size(); ++m) {
    CHECK(w->scene().course()[m].solid == (rc.marks[m].type != wm::MarkType::virtual_point));
  }
  // Placed on the pre-start side near the line's middle, on starboard at a close reach.
  const wm::Vec2 A = rc.end_a(rc.start()), B = rc.end_b(rc.start());
  const wm::BoatState& s = w->boat(0).state();
  const wm::Vec2 c{s.pos_x, s.pos_y};
  const wm::Vec2 d = wm::v_unit(wm::v_sub(B, A), {1.0f, 0.0f});
  const float side = d.x * (c.y - A.y) - d.y * (c.x - A.x);  // > 0 on the course side (left of A->B)
  CHECK(side < 0.0f);
  CHECK(wm::v_dist(c, wm::v_mid(A, B)) < 0.25f * wm::v_dist(A, B) + 10.0f * 7.2f);
  CHECK(wm::wrap_pi(s.twd_from - s.psi) == doctest::Approx(100.0f * wm::DEG).epsilon(0.02));
  // Only once; a free sailing world: place_boat works and the boat sails with no race events.
  CHECK_FALSE(w->lay_course(example_course(), err));
  CHECK(w->place_boat(0, c, s.psi));
  for (int k = 0; k < 200; ++k) {
    w->step();
    CHECK(w->events().race.empty());
    CHECK(w->events().rules.empty());
  }
  // The marks are solid: a boat put on a buoy touches it.
  std::size_t buoy = 0;
  while (rc.marks[buoy].type != wm::MarkType::buoy) ++buoy;
  const wm::Vec2 m = rc.marks[buoy].pos;
  w->place_boat(0, m.x, m.y - 6.0f, 0.0f, 2.0f);
  bool touched = false;
  for (int k = 0; k < 100 && !touched; ++k) {
    w->step();
    for (const wm::ContactEvent& ce : w->events().contacts) {
      touched = touched || (ce.other_kind == wm::ContactKind::mark && ce.other == static_cast<std::int32_t>(buoy));
    }
  }
  CHECK(touched);
  // A race may still be created on it; it lays the course again for the race.
  REQUIRE_MESSAGE(w->create_race(example_course(), err), err);
  CHECK(w->race_created());
  CHECK(w->course_laid());
}
