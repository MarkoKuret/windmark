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
