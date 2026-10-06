// The full-race set-up shared by the full-race and snapshot tests (race.md §12, WM-009): the shipped example venue,
// a one-lap windward-leeward course, six scripted boats of the shipped wm7 and wm12 files, and a pilot with
// scripted misbehaviour (an OCS-I start, a port-tack boat sailing blindly through the fleet before the start, a
// boat sailing out of the race area) so the race has penalties and penalty turns.
#pragma once

#include <memory>
#include <string>

#include "boat_harness.h"
#include "doctest.h"
#include "full_race_course.h"
#include "pilot.h"
#include "world/world.h"

namespace wm_test {

inline const wm::VenueData& full_race_venue() {
  static wm::VenueData venue;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(std::string(WINDMARK_DATA_DIR) + "/venues/practice_waters.venue.json", venue, err),
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
