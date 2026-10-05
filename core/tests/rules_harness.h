// Scripted rules scenarios (rules.md §13): kinematic boats (position, heading, speed and turn rate set by the
// script, no physics) in a uniform wind, a Race on a small course and the Rules engine, stepped in the tick-1
// order of race.md §1. Contact events are injected by the script (the collision step is not run).
#pragma once

#include <cmath>
#include <string>
#include <vector>

#include "race_harness.h"
#include "rules/rules.h"

namespace wm_test {

struct KBoat {
  wm::Vec2 p{0.0f, 0.0f};
  float psi = 0.0f;
  float v = 3.0f;
  float r = 0.0f;  // heading rate, rad/s
  bool ai = false;
  float sprit = 0.0f;  // bowsprit reach in normal position (rules.md §3.2)
};

// Start line y = 0 (x -100..100), windward mark w (0, 1000) to port, a leeward buoy l (0, 300) to port, finish
// line at y = 600.
inline std::string rules_course() {
  return R"({"schema": "windmark.course/1", "id": "t", "name": "T", "venue": "v", "frame": "world",
    "marks": [{"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
              {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
              {"id": "w", "type": "buoy", "at": {"x": 0, "y": 1000}},
              {"id": "l", "type": "buoy", "at": {"x": 0, "y": 300}},
              {"id": "f1", "type": "buoy", "at": {"x": -60, "y": 600}},
              {"id": "f2", "type": "buoy", "at": {"x": 60, "y": 600}}],
    "start": {"ends": ["pin", "rc"]}, "finish": {"ends": ["f1", "f2"]},
    "sequence": [{"mark": "w", "round": "port"}, {"mark": "l", "round": "port"}]})";
}

struct RulesRig {
  wm::ResolvedCourse course;
  wm::Race race;
  wm::Rules rules;
  std::vector<KBoat> b;
  std::vector<wm::RaceBoatInput> rin;
  std::vector<wm::RulesBoatInput> in;
  std::vector<wm::ContactEvent> contacts;  // delivered to the next update
  std::vector<std::uint8_t> pending;
  std::vector<wm::RulesEvent> events;
  std::vector<wm::RaceEvent> race_events;
  std::uint32_t n = 0;
  float tws = 5.0f, twd = 0.0f;

  RulesRig(int boats, const wm::RaceSettings& s = quick_settings(wm::PrepFlag::P), const std::string& json = rules_course(),
           const std::string& cls = "wm7")
      : course(course_from(json)) {
    for (int i = 0; i < boats; ++i) race.add_boat(&perf(cls), true);
    b.resize(static_cast<std::size_t>(boats));
    std::string err;
    REQUIRE_MESSAGE(race.create(course, s, 0, 0.0f, err), err);
    rules.init(race, nullptr);
  }

  // The wind angle and the main boom follow the heading (boom to leeward).
  void inputs() {
    rin.resize(b.size());
    in.resize(b.size());
    for (std::size_t i = 0; i < b.size(); ++i) {
      const float twa = wm::wrap_pi(twd - b[i].psi);
      rin[i].pos = b[i].p;
      rin[i].psi = b[i].psi;
      rin[i].v = b[i].v;
      rin[i].tws = tws;
      rin[i].twd = twd;
      rin[i].main_beta = twa > 0.0f ? -0.4f : 0.4f;
      wm::RulesBoatInput& x = in[i];
      x.pos = b[i].p;
      x.psi = b[i].psi;
      x.v = b[i].v;
      x.turn_rate = b[i].r;
      x.current = {0.0f, 0.0f};
      x.cog = b[i].psi;
      x.sog = b[i].v;
      x.tws = tws;
      x.twd = twd;
      x.main_beta = rin[i].main_beta;
      x.helm = 0.0f;
      x.ai = b[i].ai;
      x.sprit = b[i].sprit;
    }
  }

  void step() {
    inputs();
    rules.pending_flags(pending);
    race.progress(n, rin, pending, twd);
    rules.update(n, race, in, contacts);
    for (const auto& [boat, why] : rules.dsq()) {
      (void)why;
      race.disqualify(boat, n);
    }
    race.rank(n, rin);
    for (const wm::RulesEvent& e : rules.events()) events.push_back(e);
    rules.clear_events();
    for (const wm::RaceEvent& e : race.events()) race_events.push_back(e);
    race.clear_events();
    contacts.clear();
    for (KBoat& k : b) {
      k.psi = wm::wrap_2pi(k.psi + k.r * wm::DT);
      const wm::Vec2 d = wm::dir(k.psi);
      k.p = {k.p.x + k.v * d.x * wm::DT, k.p.y + k.v * d.y * wm::DT};
    }
    ++n;
  }
  void run(float seconds) {
    const int k = static_cast<int>(std::lround(seconds / wm::DT));
    for (int i = 0; i < k; ++i) step();
  }
  std::uint32_t gun() const { return static_cast<std::uint32_t>(race.n_gun()); }
  // Runs to the preparatory signal plus one tick: rules are live, nobody has started.
  void to_prep() {
    const std::vector<KBoat> keep = b;
    for (KBoat& k : b) {
      k.v = 0.0f;
      k.r = 0.0f;
    }
    while (!race.rules_live()) step();
    b = keep;
  }
  // Starts every boat at the gun by moving it across the line, then places it at `at` with heading `psi`.
  void start_at(const std::vector<KBoat>& at) {
    // Wait below the line in the same formation (relations do not jump when the boats are moved).
    float ymax = -INFINITY;
    for (const KBoat& k : at) ymax = std::fmax(ymax, k.p.y);
    for (std::size_t i = 0; i < b.size(); ++i) {
      b[i] = {{at[i].p.x, at[i].p.y - ymax - 20.0f}, at[i].psi, 0.0f, 0.0f, b[i].ai};
    }
    while (n <= gun()) step();
    for (std::size_t i = 0; i < b.size(); ++i) {
      const bool ai = b[i].ai;
      b[i] = at[i];
      b[i].ai = ai;
      // The jump crosses the line through the band (x stays within the line for the crossing point).
    }
    step();
    for (std::size_t i = 0; i < b.size(); ++i) REQUIRE_MESSAGE(race.boat(i).started, "boat ", i, " did not start");
  }
  void touch(std::int32_t boat, wm::ContactKind kind, std::int32_t other, float closing = 0.5f) {
    wm::ContactEvent e{};
    e.tick = n;
    e.boat = boat;
    e.other_kind = kind;
    e.other = other;
    e.closing_speed = closing;
    e.begin = true;
    contacts.push_back(e);
  }
  int penalties(std::int32_t boat, wm::RuleCode rule = wm::RuleCode::none) const {
    int c = 0;
    for (const wm::RulesEvent& e : events) {
      if (e.kind == wm::RulesEventKind::penalty && e.boat == boat && (rule == wm::RuleCode::none || e.rule == rule)) ++c;
    }
    return c;
  }
  int count(wm::RulesEventKind k, std::int32_t boat = -1) const {
    int c = 0;
    for (const wm::RulesEvent& e : events) {
      if (e.kind == k && (boat < 0 || e.boat == boat)) ++c;
    }
    return c;
  }
  wm::KcState max_kc(std::int32_t i, std::int32_t j) const { return kc_seen[static_cast<std::size_t>(i * 8 + j)]; }
  std::vector<wm::KcState> kc_seen = std::vector<wm::KcState>(64, wm::KcState::clear);
  // Steps and records the worst keep-clear state of every pair.
  void watch_step() {
    step();
    for (const wm::PairRecord& r : rules.pairs()) {
      wm::KcState& s = kc_seen[static_cast<std::size_t>(r.i * 8 + r.j)];
      if (static_cast<int>(r.kc_state) > static_cast<int>(s)) s = r.kc_state;
    }
  }
  void watch(float seconds) {
    const int k = static_cast<int>(std::lround(seconds / wm::DT));
    for (int i = 0; i < k; ++i) watch_step();
  }
};

inline void dump(const RulesRig& rig) {
  for (const wm::RulesEvent& e : rig.events) {
    MESSAGE("t ", e.tick, " kind ", static_cast<int>(e.kind), " boat ", e.boat, " other ", e.other, " rule ",
            std::string(wm::rule_code_str(e.rule)), " contact ", e.contact);
  }
}

inline float heading_for(float twd, float twa) { return wm::wrap_2pi(twd - twa); }

}  // namespace wm_test
