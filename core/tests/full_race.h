// The full-race set-up shared by the full-race and snapshot tests (race.md §12, WM-009): the shipped example venue,
// a one-lap windward-leeward course, six scripted boats of the shipped wm7 and wm12 files, and a pilot with
// scripted misbehaviour (an OCS-I start, a port-tack boat sailing blindly through the fleet before the start, a
// boat sailing out of the race area) so the race has penalties and penalty turns.
#pragma once

#include <memory>
#include <string>

#include "boat_harness.h"
#include "doctest.h"
#include "pilot.h"
#include "world/world.h"

namespace wm_test {

inline const char* kFullRaceCourse = R"({
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

inline const wm::VenueData& full_race_venue() {
  static wm::VenueData venue;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(std::string(WINDMARK_DATA_DIR) + "/venues/example_bay.venue.json", venue, err),
                    err.message());
    loaded = true;
  }
  return venue;
}

inline const wm::CourseData& full_race_course() {
  static wm::CourseData course;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::parse_course(kFullRaceCourse, "test_wl_1.course.json", course, err), err.message());
    loaded = true;
  }
  return course;
}

constexpr int kFullRaceBoats = 6;

// The world with its first `boats` boats added, before the race is created.
inline std::unique_ptr<wm::World> full_race_world(std::uint64_t seed, int boats = kFullRaceBoats) {
  wm::WorldSetup s;
  s.venue = &full_race_venue();
  s.race_seed = seed;
  s.wind.base_speed = kn(11.0f);
  s.wind.base_from = 0.2f;
  wm::apply_shift_preset(s.wind, wm::ShiftPreset::stable);
  s.race.free_sailing_s = 10.0f;
  auto w = std::make_unique<wm::World>(s);
  for (int i = 0; i < boats; ++i) {
    wm::BoatEntry e;
    e.perf = &perf(i == 5 ? "wm12" : "wm7");
    REQUIRE(w->add_boat(e) == i);
  }
  return w;
}

inline Pilot full_race_pilot() {
  Pilot pilot(static_cast<std::size_t>(kFullRaceBoats));
  pilot.boat(1).early = true;
  pilot.boat(2).rogue_port = true;
  pilot.boat(3).leave_bounds_at = 20.0f;
  pilot.boat(3).exclusion = {245.0f, -250.0f};
  return pilot;
}

}  // namespace wm_test
