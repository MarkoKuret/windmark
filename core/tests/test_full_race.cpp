// A full race headless (race.md §12, WM-009): the shipped example venue, a one-lap windward-leeward course, six
// scripted boats with the shipped wm7 and wm12 files, from the spawn to the results. Scripted misbehaviour gives
// an OCS-I start, a port-tack boat sailing blindly through the fleet before the start and a boat sailing out of
// the race area, so the race has penalties and penalty turns. The same seed reproduces the same results and the
// same final state checksum.
#include <string>
#include <vector>

#include "boat_harness.h"
#include "doctest.h"
#include "pilot.h"
#include "world/world.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;

const char* kCourse = R"({
  "schema": "windmark.course/1", "id": "test_wl_1", "name": "Test windward-leeward, 1 lap", "venue": "example_bay",
  "frame": "wind", "reference": { "x": 0.0, "y": -300.0 },
  "marks": [
    { "id": "rc",  "type": "committee_boat", "at": { "bearing": 1.57079633, "dist": 90, "fixed": true } },
    { "id": "pin", "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 90, "fixed": true } },
    { "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 320, "from": "rc_pin_mid", "fixed": true } },
    { "id": "gc",  "type": "virtual", "at": { "bearing": 3.14159265, "dist": 90, "from": "rc_pin_mid", "fixed": true } },
    { "id": "g1",  "type": "buoy", "at": { "bearing": 1.57079633, "dist": 30, "from": "gc", "fixed": true } },
    { "id": "g2",  "type": "buoy", "at": { "bearing": 4.71238898, "dist": 30, "from": "gc", "fixed": true } }
  ],
  "start": { "ends": ["pin", "rc"] },
  "finish": "start",
  "sequence": [ { "mark": "w", "round": "port" }, { "gate": ["g1", "g2"] } ],
  "area": { "boundary": [ { "x": -900, "y": -1100 }, { "x": 900, "y": -1100 }, { "x": 900, "y": 700 }, { "x": -900, "y": 700 } ],
            "exclusions": [ { "id": "lane", "polygon": [ { "x": 220, "y": -420 }, { "x": 420, "y": -420 },
                                                        { "x": 420, "y": -150 }, { "x": 220, "y": -150 } ] } ] },
  "race": { "type": "fleet", "sequence": "3-2-1-0", "prep_flag": "I", "time_limit": 1500 }
})";

struct Outcome {
  std::vector<wm::ResultRow> results;
  std::uint64_t checksum = 0;
  std::uint32_t ticks = 0;
  std::vector<wm::RulesEvent> rules_events;
  std::vector<wm::RaceEvent> race_events;
};

Outcome run_race(std::uint64_t seed) {
  static wm::VenueData venue;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/example_bay.venue.json", venue, err), err.message());
    loaded = true;
  }
  wm::CourseData course;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_course(kCourse, "test_wl_1.course.json", course, err), err.message());

  wm::WorldSetup s;
  s.venue = &venue;
  s.race_seed = seed;
  s.wind.base_speed = wm_test::kn(11.0f);
  s.wind.base_from = 0.2f;
  wm::apply_shift_preset(s.wind, wm::ShiftPreset::stable);
  s.race.free_sailing_s = 10.0f;
  wm::World w(s);
  const int n = 6;
  for (int i = 0; i < n; ++i) {
    wm::BoatEntry e;
    e.perf = &wm_test::perf(i == 5 ? "wm12" : "wm7");
    REQUIRE(w.add_boat(e) == i);
  }
  std::string why;
  REQUIRE_MESSAGE(w.create_race(course, why), why);

  wm_test::Pilot pilot(static_cast<std::size_t>(n));
  pilot.boat(1).early = true;
  pilot.boat(2).rogue_port = true;
  pilot.boat(3).leave_bounds_at = 20.0f;
  pilot.boat(3).exclusion = {245.0f, -250.0f};
  w.set_controller([&pilot](wm::World& world) { pilot(world); });

  Outcome o;
  for (int k = 0; k < 60000 && w.race().state() != wm::RaceState::closed; ++k) {
    w.step();
    for (const wm::RulesEvent& e : w.events().rules) o.rules_events.push_back(e);
    for (const wm::RaceEvent& e : w.events().race) o.race_events.push_back(e);
  }
  o.results = w.race().results();
  o.checksum = w.checksum();
  o.ticks = w.tick();
  return o;
}

int count(const Outcome& o, wm::RulesEventKind k) {
  int c = 0;
  for (const wm::RulesEvent& e : o.rules_events) c += e.kind == k ? 1 : 0;
  return c;
}

}  // namespace

TEST_CASE("full race: a headless race with penalties, and determinism") {
  const Outcome a = run_race(20260925);
  REQUIRE(!a.results.empty());
  MESSAGE("race closed after ", a.ticks, " ticks (", static_cast<float>(a.ticks) * wm::DT, " s)");
  for (const wm::ResultRow& r : a.results) {
    MESSAGE("boat ", r.boat, " place ", r.place, " ", std::string(wm::score_code_name(r.code)), " points ", r.points,
            " t ", static_cast<double>(r.t_finish_us) * 1e-6);
  }
  for (const wm::RulesEvent& e : a.rules_events) {
    if (e.kind == wm::RulesEventKind::penalty || e.kind == wm::RulesEventKind::penalty_served ||
        e.kind == wm::RulesEventKind::disqualified) {
      const char* what = e.kind == wm::RulesEventKind::penalty
                             ? "penalty"
                             : (e.kind == wm::RulesEventKind::penalty_served ? "served" : "disqualified");
      MESSAGE("tick ", e.tick, " ", what, " boat ", e.boat, " rule ", std::string(wm::rule_code_str(e.rule)), " other ",
              e.other);
    }
  }
  // Every boat finished or scored.
  CHECK(a.results.size() == 6);
  for (const wm::ResultRow& r : a.results) CHECK((r.place > 0 || r.code != wm::ScoreCode::none));
  // Penalties were given and turns were taken.
  CHECK(count(a, wm::RulesEventKind::penalty) >= 2);
  CHECK(count(a, wm::RulesEventKind::penalty_served) >= 1);
  bool boundary = false, ocs_i = false, returned = false;
  for (const wm::RulesEvent& e : a.rules_events) boundary = boundary || (e.kind == wm::RulesEventKind::penalty && e.rule == wm::RuleCode::si_boundary);
  for (const wm::RaceEvent& e : a.race_events) {
    ocs_i = ocs_i || (e.kind == wm::RaceEventKind::boat_ocs && e.boat == 1 && e.flag == wm::PrepFlag::I);
    returned = returned || (e.kind == wm::RaceEventKind::boat_returned && e.boat == 1);
  }
  CHECK(boundary);
  CHECK(ocs_i);
  CHECK(returned);

  // The same seed: the same results table and final state.
  const Outcome b = run_race(20260925);
  CHECK(b.ticks == a.ticks);
  CHECK(b.checksum == a.checksum);
  REQUIRE(b.results.size() == a.results.size());
  for (std::size_t i = 0; i < a.results.size(); ++i) {
    CHECK(b.results[i].boat == a.results[i].boat);
    CHECK(b.results[i].code == a.results[i].code);
    CHECK(b.results[i].points == a.results[i].points);
    CHECK(b.results[i].t_finish_us == a.results[i].t_finish_us);
  }
}
