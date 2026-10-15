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

#include <algorithm>
#include <chrono>
#include <cmath>
#include <map>

#include "ai/ai.h"
#include "boat_harness.h"
#include "race/conditions.h"
#include "course/course.h"
#include "doctest.h"
#include "world/world.h"

namespace wm_test {

inline const wm::VenueData& ai_venue() {
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

// A shipped venue by id (data/venues/<id>.venue.json), loaded once.
inline const wm::VenueData& venue_by_id(const std::string& id) {
  static std::map<std::string, std::unique_ptr<wm::VenueData>> cache;
  auto it = cache.find(id);
  if (it == cache.end()) {
    auto v = std::make_unique<wm::VenueData>();
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(std::string(WINDMARK_DATA_DIR) + "/venues/" + id + ".venue.json", *v, err),
                    err.message());
    it = cache.emplace(id, std::move(v)).first;
  }
  return *it->second;
}

// A shipped course by its path under the courses directory without the extension (e.g. "solent/cowes_wl").
inline const wm::CourseData& course_by_path(const std::string& rel) {
  static std::map<std::string, std::unique_ptr<wm::CourseData>> cache;
  auto it = cache.find(rel);
  if (it == cache.end()) {
    auto c = std::make_unique<wm::CourseData>();
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_course(std::string(WINDMARK_COURSES_DIR) + "/" + rel + ".course.json", *c, err),
                    err.message());
    it = cache.emplace(rel, std::move(c)).first;
  }
  return *it->second;
}

// The default course: the shipped example windward-leeward, two laps.
inline const wm::CourseData& ai_default_course() {
  static wm::CourseData c;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_course(std::string(WINDMARK_COURSES_DIR) + "/practice_waters/example_wl.course.json", c, err),
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
  "schema": "windmark.course/1", "id": "test_match", "name": "Test match race", "venue": "practice_waters",
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
  "schema": "windmark.course/1", "id": "test_beat", "name": "Test 1 nm beat", "venue": "practice_waters",
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
  bool wind_default = false;  // the wind.md default shifts (no preset), as the game's scene uses
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
  // Development: boat 0 a human entry (the game scene's player), and the race resumed from a world snapshot and the
  // skippers' block saved by the game (`<snap_dir>/world.bin`, `<snap_dir>/ai.bin`) instead of created.
  bool human0 = false;
  const char* snap_dir = nullptr;
  // Another venue (null: the example venue) and its own conditions for the race seed (race.md §2.1, local mode)
  // instead of wind_kn / wind_from / shifts. `tide`: the tide factor at the gun forced to flood (+1), ebb (-1) or
  // slack (0, turning to flood) instead of the drawn phase; NaN keeps the draw.
  const wm::VenueData* venue = nullptr;
  bool local_weather = false;
  float tide = NAN;
  bool no_current = false;  // the venue's conditions without any current (a reference for the tide's cost)
  bool time_ai = false;     // development: time the skippers' step every tick (AiRaceOutcome::ai_us_*)
};

inline std::vector<std::uint8_t> read_bytes(const std::string& path) {
  std::vector<std::uint8_t> b;
  if (std::FILE* f = std::fopen(path.c_str(), "rb")) {
    std::uint8_t buf[65536];
    for (std::size_t n; (n = std::fread(buf, 1, sizeof buf, f)) > 0;) b.insert(b.end(), buf, buf + n);
    std::fclose(f);
  }
  return b;
}

// Windward approaches (WM-111): on every beat to a mark, from the boat's last tack to the mark, the time sailed more
// than 10° freer than her own close-hauled angle on that leg (overstanding: the median water TWA of the leg) while
// farther than 3 L from the mark, and the tacks made within 5 L of the mark (understanding: a short tack to lay it).
struct ApproachStats {
  int approaches = 0;
  double overstand_s = 0.0;
  int overstood = 0;  // approaches with more than 10 s overstood
  int near_tacks = 0;
  double overstand_m = 0.0;  // distance sailed while overstood
  // The fleet's side on the beats: the mean lateral offset from the line from the last mark to the next (m, + to
  // the left looking upwind), over every boat and second on a beat.
  double side_sum = 0.0;
  int side_n = 0;
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
  ApproachStats approach;
  std::vector<wm::RaceEvent> ocs_events;  // boat_ocs
  float tide_at_gun = 0.0f;  // the tide factor at the gun (wind.md §7, without the scale)
  // time_ai: the skippers' step, µs per tick, from the warning signal on (sum, ticks, worst tick)
  double ai_us_sum = 0.0, ai_us_max = 0.0;
  std::uint32_t ai_ticks = 0;
  std::vector<float> ai_us;  // every timed tick
  // Per boat: time pinned on a course object, obstacle or land (in contact within the last second, under 0.3 m/s
  // over the ground, racing), in total and the longest spell.
  std::vector<float> pinned_s, pinned_max;
};

inline std::unique_ptr<wm::World> ai_world(const AiRaceSpec& sp) {
  wm::WorldSetup s;
  s.venue = sp.venue != nullptr ? sp.venue : &ai_venue();
  s.race_seed = sp.seed;
  s.wind.base_speed = kn(sp.wind_kn);
  s.wind.base_from = sp.wind_from;
  if (!sp.wind_default) wm::apply_shift_preset(s.wind, sp.shifts);
  s.wind.puffs_enabled = sp.puffs;
  s.race.free_sailing_s = sp.free_sailing_s;
  if (sp.local_weather) {
    const wm::CourseData& course = sp.course != nullptr ? *sp.course : ai_default_course();
    const wm::RaceTiming timing = wm::race_timing(s.race, &course);
    wm::WeatherChoice c;
    std::string error;
    REQUIRE_MESSAGE(wm::resolve_weather(*s.venue, c, sp.seed, timing, s.wind, s.sea_settings, error), error);
    if (!std::isnan(sp.tide) && s.wind.tide_period_ms > 0) {
      // cos(2π (t_gun + phase) / P) = tide at the gun: flood 0, ebb P/2, slack 3P/4 (turning to flood).
      const std::uint64_t P = s.wind.tide_period_ms;
      const std::uint64_t at = sp.tide > 0.5f ? 0u : (sp.tide < -0.5f ? P / 2u : (3u * P) / 4u);
      s.wind.tide_phase_ms = static_cast<std::uint32_t>((at + P - (timing.t_gun_ms % P)) % P);
    }
    if (sp.no_current) {
      s.wind.tide_scale = 0.0f;
      s.wind.current_speed = 0.0f;
    }
  }
  auto w = std::make_unique<wm::World>(s);
  for (std::size_t i = 0; i < sp.levels.size(); ++i) {
    const std::string cls = i < sp.classes.size() ? sp.classes[i] : std::string("wm7");
    wm::BoatEntry e = wm::ai_entry(&perf(cls), sp.levels[i]);
    if (i == 0 && sp.human0) {
      e = wm::BoatEntry{};
      e.perf = &perf(cls);
      e.human = true;
    }
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
  auto ai = std::make_unique<wm::AiSkippers>();
  if (sp.snap_dir != nullptr) {
    const std::vector<std::uint8_t> wb = read_bytes(std::string(sp.snap_dir) + "/world.bin");
    const std::vector<std::uint8_t> ab = read_bytes(std::string(sp.snap_dir) + "/ai.bin");
    REQUIRE_MESSAGE(w->load(wb, &course, why), why);
    REQUIRE_MESSAGE(ai->load(ab, *w, why), why);
  } else {
    REQUIRE_MESSAGE(w->create_race(course, why), why);
    ai_add_all(*ai, sp);
  }
  wm::AiSkippers* aip = ai.get();
  AiRaceOutcome o;
  auto controller = [&aip, &o, &sp](wm::World& world) {
    if (!sp.time_ai) {
      aip->step(world);
      return;
    }
    const auto t0 = std::chrono::steady_clock::now();
    aip->step(world);
    const double us = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count();
    if (world.race_created() && world.race().state() != wm::RaceState::free_sailing &&
        world.race().state() != wm::RaceState::created) {
      o.ai_us_sum += us;
      o.ai_us_max = std::max(o.ai_us_max, us);
      ++o.ai_ticks;
      o.ai_us.push_back(static_cast<float>(us));
    }
  };
  w->set_controller(controller);
  std::FILE* tf = sp.trace != nullptr ? std::fopen(sp.trace, "w") : nullptr;
  // Approach tracking (ApproachStats).
  struct Track {
    std::int32_t step = -1;
    bool beat = false;
    std::vector<float> twa;  // |water TWA| samples of the leg, 1 Hz
    float med = 0.0f;
    std::int8_t tack = 0;
    double free_s = 0.0, free_m = 0.0;  // since the last tack
    int near_tacks = 0;
  };
  std::vector<Track> trk;
  std::vector<std::uint32_t> pin_seen;
  std::vector<float> pin_run;
  auto close_approach = [&](Track& t) {
    if (!t.beat || t.twa.empty()) return;
    ++o.approach.approaches;
    o.approach.overstand_s += t.free_s;
    o.approach.overstand_m += t.free_m;
    if (t.free_s > 10.0) ++o.approach.overstood;
    o.approach.near_tacks += t.near_tacks;
  };
  if (tf != nullptr) std::fprintf(tf, "t,i,x,y,psi,v,twa,tws,tact,man,psit,next,rank,pend,d,leg,helm,letfly,phi,phid,tr,sx,sy,ax,ay,why,pw,dl\n");
  for (std::uint32_t k = 0; k < sp.max_ticks && w->race().state() != wm::RaceState::closed &&
                          w->race().state() != wm::RaceState::abandoned;
       ++k) {
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
      w->set_controller(controller);
      o.reloaded = true;
    }
    if (tf != nullptr && w->race_created() && w->tick() % 10u == 0u) {
      for (std::size_t i = 0; i < w->boat_count(); ++i) {
        const wm::BoatState& bs = w->boat(i).state();
        const wm::AiDebug& d = ai->debug(static_cast<std::int32_t>(i));
        std::fprintf(tf, "%.1f,%zu,%.1f,%.1f,%.1f,%.2f,%.1f,%.2f,%d,%d,%.1f,%d,%d,%zu,%.3f,%d,%.2f,%d,%.0f,%.0f,%.1f,%.1f,%.1f,%.1f,%.1f,%d,%d,%.0f\n",
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
                     static_cast<double>(d.spot.y), static_cast<double>(d.aim.x), static_cast<double>(d.aim.y), static_cast<int>(d.man_why), d.pen_wait,
                     static_cast<double>(w->rules().boat(i).deadline_s));
      }
    }
    w->step();
    if (sp.keep_checksums) o.checksums.push_back(w->checksum());
    if (w->race_created() && w->race().after_gun(w->tick())) {
      if (o.tide_at_gun == 0.0f) {
        const wm::WindSettings& ws = w->wind().settings();
        const float ph = static_cast<float>((static_cast<std::uint64_t>(w->tick()) * 50u + ws.tide_phase_ms) %
                                            ws.tide_period_ms) / static_cast<float>(ws.tide_period_ms);
        o.tide_at_gun = std::cos(wm::TWO_PI * ph) + 1e-6f;
      }
      trk.resize(w->boat_count());
      const wm::ResolvedCourse& co = w->course();
      const wm::Vec2 wax = wm::dir(co.twd_c);
      for (std::size_t i = 0; i < w->boat_count(); ++i) {
        const wm::RaceBoat& rb = w->race().boat(i);
        Track& t = trk[i];
        if (!rb.started || rb.finished || rb.ghost) {
          if (t.step >= 0 && (rb.finished || rb.ghost)) t.beat = false;
          continue;
        }
        if (rb.next != t.step) {
          if (t.step >= 0 && rb.next > t.step) close_approach(t);
          t = Track{};
          t.step = rb.next;
          const wm::CourseStep& st = co.steps[static_cast<std::size_t>(rb.next)];
          if (st.kind == wm::StepKind::mark && rb.next > 0) {
            const wm::Vec2 d = wm::v_sub(st.ref, co.steps[static_cast<std::size_t>(rb.next - 1)].ref);
            t.beat = wm::v_dot(d, wax) > 0.8f * wm::v_len(d);
          }
        }
        if (!t.beat) continue;
        const wm::BoatState& bs = w->boat(i).state();
        const float twa = bs.twa;  // water relative (boat.md §5.1)
        const std::int8_t tk = static_cast<std::int8_t>(twa >= 0.0f ? 1 : -1);
        const wm::Vec2 M = co.marks[static_cast<std::size_t>(co.steps[static_cast<std::size_t>(t.step)].marks[0])].pos;
        const float dm = wm::v_dist(rb.c, M);
        if (std::fabs(twa) < wm::HALF_PI && t.tack != 0 && tk != t.tack) {
          t.free_s = 0.0;
          t.free_m = 0.0;
          if (dm < 5.0f * rb.L) ++t.near_tacks;
        }
        if (std::fabs(twa) < wm::HALF_PI) t.tack = tk;
        if (w->tick() % 20u == 0u) {
          const wm::Vec2 P0 = co.steps[static_cast<std::size_t>(t.step - 1)].ref;
          const wm::Vec2 ax = wm::v_unit(wm::v_sub(M, P0), wax);
          o.approach.side_sum += static_cast<double>(wm::v_cross(ax, wm::v_sub(rb.c, P0)));
          ++o.approach.side_n;
        }
        if (w->tick() % 20u == 0u && std::fabs(twa) < wm::HALF_PI &&
            bs.v > 0.5f * w->boat(i).polar_at(bs.tws, twa, w->boat(i).sails().front())) {
          t.twa.push_back(std::fabs(twa));
          std::vector<float> c = t.twa;
          std::nth_element(c.begin(), c.begin() + static_cast<std::ptrdiff_t>(c.size() / 2), c.end());
          t.med = c[c.size() / 2];
        }
        if (t.twa.size() >= 10 && dm > 3.0f * rb.L) {
          if (std::fabs(twa) > t.med + 10.0f * wm::DEG && std::fabs(twa) < wm::HALF_PI + 0.35f) {
            t.free_s += 0.05;
            t.free_m += 0.05 * static_cast<double>(bs.v);
          }
        }
      }
    }
    for (const wm::ContactEvent& e : w->events().contacts) {
      if (e.begin && e.other_kind == wm::ContactKind::boat && e.boat < e.other) ++o.contacts;
    }
    if (w->race_created()) {
      const std::size_t nb = w->boat_count();
      if (o.pinned_s.size() != nb) {
        o.pinned_s.assign(nb, 0.0f);
        o.pinned_max.assign(nb, 0.0f);
        pin_seen.assign(nb, 0u);
        pin_run.assign(nb, 0.0f);
      }
      for (const wm::ContactEvent& e : w->last_contacts()) {
        if (e.other_kind != wm::ContactKind::boat && e.boat >= 0 && static_cast<std::size_t>(e.boat) < nb)
          pin_seen[static_cast<std::size_t>(e.boat)] = w->tick();
      }
      for (std::size_t i = 0; i < nb; ++i) {
        const wm::RaceBoat& rb = w->race().boat(i);
        const bool racing = rb.started && !rb.finished && !rb.ghost;
        if (racing && pin_seen[i] != 0u && w->tick() - pin_seen[i] < 20u && w->boat(i).outputs().sog < 0.3f) {
          o.pinned_s[i] += 0.05f;
          pin_run[i] += 0.05f;
          o.pinned_max[i] = std::max(o.pinned_max[i], pin_run[i]);
        } else {
          pin_run[i] = 0.0f;
        }
      }
    }
    for (const wm::RaceEvent& e : w->events().race) {
      if (e.kind == wm::RaceEventKind::boat_ocs) o.ocs_events.push_back(e);
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
