// The AI fleet race of the full determinism test (WM-033, test_ai.cpp) and of the per-tick checksum tool
// (tools/race_trace.cpp): the shipped example venue and its windward-leeward course (two laps), 11 kn from 0.3 rad
// with oscillating shifts and puffs, 10 s of free sailing, and a fleet of AI skippers of every level in turn, every
// third boat a wm12 and the others wm7, so the race has starts, mark roundings, collisions and penalties between
// two classes. Without doctest, so tools can use it too.
#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "ai/ai.h"
#include "course/course.h"
#include "data/perf.h"
#include "data/venue.h"
#include "world/world.h"

namespace wm_test {

struct AiFleetRace {
  wm::VenueData venue;
  wm::PerfData wm7, wm12;
  wm::CourseData course;

  // From WINDMARK_DATA_DIR and WINDMARK_COURSES_DIR; false with the reason.
  bool load(std::string& error) {
    wm::LoadError err;
    const std::string data = WINDMARK_DATA_DIR;
    if (!wm::load_venue(data + "/venues/practice_waters.venue.json", venue, err) ||
        !wm::load_perf(data + "/perf/wm7.perf.json", wm7, err) ||
        !wm::load_perf(data + "/perf/wm12.perf.json", wm12, err) ||
        !wm::load_course(std::string(WINDMARK_COURSES_DIR) + "/practice_waters/example_wl.course.json", course, err)) {
      error = err.message();
      return false;
    }
    return true;
  }

  static wm::AiLevel level(int i) { return static_cast<wm::AiLevel>(i % 4); }

  // The world with the race created and every boat given to `ai`; null with the reason on failure. The caller
  // installs the controller.
  std::unique_ptr<wm::World> world(std::uint64_t seed, int boats, wm::AiSkippers& ai, std::string& error) const {
    wm::WorldSetup s;
    s.venue = &venue;
    s.race_seed = seed;
    s.wind.base_speed = 11.0f * wm::KNOT;
    s.wind.base_from = 0.3f;
    wm::apply_shift_preset(s.wind, wm::ShiftPreset::oscillating);
    s.race.free_sailing_s = 10.0f;
    auto w = std::make_unique<wm::World>(s);
    for (int i = 0; i < boats; ++i) {
      if (w->add_boat(wm::ai_entry(i % 3 == 2 ? &wm12 : &wm7, level(i))) != i) {
        error = "add_boat failed";
        return nullptr;
      }
    }
    if (!w->create_race(course, error)) return nullptr;
    for (int i = 0; i < boats; ++i) ai.add(i, level(i));
    return w;
  }
};

}  // namespace wm_test
