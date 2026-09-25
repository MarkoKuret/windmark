// Shared set-up for the AI tests (ai.md §15): a world on the shipped example venue with AI skippers, the default
// course (the shipped example windward-leeward) or a course given as text, and a run to the close that collects the
// results, the AI telemetry, contacts and penalties.
#pragma once

#include <cstdint>
#include <cstdio>
#include <memory>
#include <span>
#include <string>
#include <vector>

#include "ai/ai.h"
#include "boat_harness.h"
#include "course/course.h"
#include "doctest.h"
#include "world/world.h"

namespace wm_test {

inline const wm::VenueData& ai_venue() {
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

// The default course: the shipped example windward-leeward, two laps.
inline const wm::CourseData& ai_default_course() {
  static wm::CourseData c;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_course(std::string(WINDMARK_COURSES_DIR) + "/example_bay/example_wl.course.json", c, err),
                    err.message());
    loaded = true;
  }
  return c;
}

// A match race on the example venue: windward-leeward, two laps, a 150 m line, a 500 m beat, finish on the start line.
inline const wm::CourseData& ai_match_course() {
  static wm::CourseData c;
  static bool loaded = false;
  if (!loaded) {
    static const char* kText = R"({
  "schema": "windmark.course/1", "id": "test_match", "name": "Test match race", "venue": "example_bay",
  "frame": "wind", "reference": { "x": 0.0, "y": -300.0 },
  "marks": [
    { "id": "rc",  "type": "committee_boat", "at": { "bearing": 1.57079633, "dist": 75, "fixed": true }, "heading": null },
    { "id": "pin", "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 75, "fixed": true } },
    { "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 500, "from": "rc_pin_mid", "fixed": true } },
    { "id": "l",   "type": "buoy", "style": "large", "at": { "bearing": 3.14159265, "dist": 60, "from": "rc_pin_mid", "fixed": true } }
  ],
  "start": { "ends": ["pin", "rc"] },
  "finish": "start",
  "sequence": [ { "mark": "w", "round": "port" }, { "mark": "l", "round": "port" }, { "mark": "w", "round": "port" }, { "mark": "l", "round": "port" } ],
  "race": { "type": "match", "sequence": "match", "prep_flag": "P", "time_limit": 1500 }
})";
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::parse_course(kText, "test_match.course.json", c, err), err.message());
    loaded = true;
  }
  return c;
}

// One beat of 1 nm to a windward mark, then a short run to a finish line below it (ai.md §15 tack count).
inline const wm::CourseData& ai_beat_course() {
  static wm::CourseData c;
  static bool loaded = false;
  if (!loaded) {
    static const char* kText = R"({
  "schema": "windmark.course/1", "id": "test_beat", "name": "Test 1 nm beat", "venue": "example_bay",
  "frame": "wind", "reference": { "x": 0.0, "y": -900.0 },
  "marks": [
    { "id": "rc",  "type": "committee_boat", "at": { "bearing": 1.57079633, "dist": 125, "fixed": true }, "heading": null },
    { "id": "pin", "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 125, "fixed": true } },
    { "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 1852, "from": "rc_pin_mid", "fixed": true } },
    { "id": "fc",  "type": "virtual", "at": { "bearing": 3.14159265, "dist": 200, "from": "w", "fixed": true } },
    { "id": "fa",  "type": "buoy", "at": { "bearing": 1.57079633, "dist": 50, "from": "fc", "fixed": true } },
    { "id": "fb",  "type": "buoy", "at": { "bearing": 4.71238898, "dist": 50, "from": "fc", "fixed": true } }
  ],
  "start": { "ends": ["pin", "rc"] },
  "finish": { "ends": ["fb", "fa"] },
  "sequence": [ { "mark": "w", "round": "port" } ],
  "race": { "type": "fleet", "sequence": "3-2-1-0", "prep_flag": "I", "time_limit": 2400 }
})";
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::parse_course(kText, "test_beat.course.json", c, err), err.message());
    loaded = true;
  }
  return c;
}

struct AiRaceSpec {
  std::uint64_t seed = 1;
  float wind_kn = 11.0f;
  float wind_from = 0.3f;
  wm::ShiftPreset shifts = wm::ShiftPreset::stable;
  bool puffs = true;
  std::vector<wm::AiLevel> levels;  // one AI boat per entry
  std::vector<std::string> classes; // per boat ("wm7" if empty or short)
  bool speed_only = false;
  const wm::CourseData* course = nullptr;  // default course if null
  float free_sailing_s = 10.0f;
  std::uint32_t max_ticks = 60000;
  // Mid-race snapshot round trip: at this tick the world is saved with the AI memory, a new world and a new set
  // of skippers are built from the bytes, and the race continues in them (0: never).
  std::uint32_t reload_at = 0;
  bool keep_checksums = false;
  const char* trace = nullptr;  // development: a CSV of every AI boat every 0.5 s
};

struct AiRaceOutcome {
  std::vector<wm::ResultRow> results;
  std::vector<wm::AiTelemetry> tel;
  std::vector<wm::RaceBoat> boats;
  std::vector<wm::RulesEvent> rules_events;
  std::int32_t contacts = 0;     // boat-boat contact begins
  std::int32_t penalties = 0;
  std::uint32_t ticks = 0;
  std::uint64_t checksum = 0;
  std::vector<std::uint64_t> checksums;  // per tick, if kept
  bool reloaded = false;
  float n_gun_s = 0.0f;
};

inline std::unique_ptr<wm::World> ai_world(const AiRaceSpec& sp) {
  wm::WorldSetup s;
  s.venue = &ai_venue();
  s.race_seed = sp.seed;
  s.wind.base_speed = kn(sp.wind_kn);
  s.wind.base_from = sp.wind_from;
  wm::apply_shift_preset(s.wind, sp.shifts);
  s.wind.puffs_enabled = sp.puffs;
  s.race.free_sailing_s = sp.free_sailing_s;
  auto w = std::make_unique<wm::World>(s);
  for (std::size_t i = 0; i < sp.levels.size(); ++i) {
    const std::string cls = i < sp.classes.size() ? sp.classes[i] : std::string("wm7");
    wm::BoatEntry e = wm::ai_entry(&perf(cls), sp.levels[i]);
    if (sp.speed_only) e.performance_scale = wm::ai_level_params(sp.levels[i], true).performance_scale;
    REQUIRE(w->add_boat(e) == static_cast<std::int32_t>(i));
  }
  return w;
}

inline void ai_add_all(wm::AiSkippers& ai, const AiRaceSpec& sp) {
  for (std::size_t i = 0; i < sp.levels.size(); ++i) ai.add(static_cast<std::int32_t>(i), sp.levels[i], sp.speed_only);
}

inline AiRaceOutcome run_ai_race(const AiRaceSpec& sp) {
  const wm::CourseData& course = sp.course != nullptr ? *sp.course : ai_default_course();
  auto w = ai_world(sp);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(course, why), why);
  auto ai = std::make_unique<wm::AiSkippers>();
  ai_add_all(*ai, sp);
  wm::AiSkippers* aip = ai.get();
  w->set_controller([aip](wm::World& world) { aip->step(world); });
  AiRaceOutcome o;
  std::FILE* tf = sp.trace != nullptr ? std::fopen(sp.trace, "w") : nullptr;
  if (tf != nullptr) std::fprintf(tf, "t,i,x,y,psi,v,twa,tws,tact,man,psit,next,rank,pend,d,leg,helm,letfly,phi,phid,tr,sx,sy,ax,ay\n");
  for (std::uint32_t k = 0; k < sp.max_ticks && w->race().state() != wm::RaceState::closed; ++k) {
    if (sp.reload_at != 0 && w->tick() == sp.reload_at) {
      // The world snapshot and the skippers' own block (ai.md §16), each as its own bytes.
      wm::SnapshotWriter sw, sa;
      w->save(sw);
      ai->save(sa, *w);
      auto w2 = ai_world(sp);
      auto ai2 = std::make_unique<wm::AiSkippers>();
      REQUIRE_MESSAGE(w2->load(sw.bytes(), &course, why), why);
      REQUIRE_MESSAGE(ai2->load(sa.bytes(), *w2, why), why);
      w = std::move(w2);
      ai = std::move(ai2);
      aip = ai.get();
      w->set_controller([aip](wm::World& world) { aip->step(world); });
      o.reloaded = true;
    }
    if (tf != nullptr && w->race_created() && w->tick() % 10u == 0u) {
      for (std::size_t i = 0; i < w->boat_count(); ++i) {
        const wm::BoatState& bs = w->boat(i).state();
        const wm::AiDebug& d = ai->debug(static_cast<std::int32_t>(i));
        std::fprintf(tf, "%.1f,%zu,%.1f,%.1f,%.1f,%.2f,%.1f,%.2f,%d,%d,%.1f,%d,%d,%zu,%.3f,%d,%.2f,%d,%.0f,%.0f,%.1f,%.1f,%.1f,%.1f,%.1f\n",
                     static_cast<double>(w->race().race_time(w->tick())), i, static_cast<double>(bs.pos_x),
                     static_cast<double>(bs.pos_y), static_cast<double>(bs.psi / wm::DEG), static_cast<double>(bs.v),
                     static_cast<double>(wm::wrap_pi(w->env(i).wind_from_clean - bs.psi) / wm::DEG),
                     static_cast<double>(w->env(i).wind_speed), static_cast<int>(d.tactic), d.manoeuvre,
                     static_cast<double>(d.psi_target / wm::DEG), w->race().boat(i).next, w->race().boat(i).rank,
                     w->rules().boat(i).pending.size(), static_cast<double>(d.d), d.leg,
                     static_cast<double>(bs.h), w->boat(i).controls().let_fly ? 1 : 0,
                     static_cast<double>(w->race().boat(i).phi[0] / wm::DEG),
                     static_cast<double>(w->race().boat(i).phi_done[0] / wm::DEG),
                     static_cast<double>(w->boat(i).outputs().turn_rate / wm::DEG), static_cast<double>(d.spot.x),
                     static_cast<double>(d.spot.y), static_cast<double>(d.aim.x), static_cast<double>(d.aim.y));
      }
    }
    const std::uint64_t c = w->step();
    if (sp.keep_checksums) o.checksums.push_back(c);
    for (const wm::ContactEvent& e : w->events().contacts) {
      if (e.begin && e.other_kind == wm::ContactKind::boat && e.boat < e.other) ++o.contacts;
    }
    for (const wm::RulesEvent& e : w->events().rules) {
      if (e.kind == wm::RulesEventKind::penalty) ++o.penalties;
      o.rules_events.push_back(e);
    }
  }
  if (tf != nullptr) std::fclose(tf);
  o.results = w->race().results();
  o.ticks = w->tick();
  o.n_gun_s = -w->race().race_time(0);
  o.checksum = w->checksum();
  for (std::size_t i = 0; i < w->boat_count(); ++i) {
    o.tel.push_back(ai->telemetry(static_cast<std::int32_t>(i)));
    o.boats.push_back(w->race().boat(i));
  }
  return o;
}

}  // namespace wm_test
