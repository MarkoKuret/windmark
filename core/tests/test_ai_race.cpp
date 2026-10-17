// AI fleet races (ai.md §15 headless acceptance tests). Long: run with `ctest --test-dir core/build -L ai_long`
// or `core/build/tests/windmark_ai_race_tests`.
#include <algorithm>
#include <map>
#include <cstdio>
#include <vector>
#include <cstdlib>
#include <string>

#include "ai_harness.h"
#include "doctest.h"

namespace {

void report(const char* name, const wm_test::AiRaceOutcome& o) {
  std::printf("%s: %u ticks, contacts %d, penalties %d\n", name, o.ticks, o.contacts, o.penalties);
  for (const wm::ResultRow& r : o.results) {
    const wm::AiTelemetry& t = o.tel[static_cast<std::size_t>(r.boat)];
    std::printf("  boat %2d place %2d %-4s t %7.1f  tacks %2d gybes %2d pen %d ocs %d stuck %5.1f gap %5.1f "
                "bad_air %zu start %5.1f\n",
                r.boat, r.place, wm::score_code_name(r.code).data(), static_cast<double>(r.t_finish_us) * 1e-6, t.tacks,
                t.gybes, t.penalties, t.ocs, static_cast<double>(t.stuck_s), static_cast<double>(t.min_gap),
                t.bad_air.size(), static_cast<double>(t.start_delay));
    std::printf("     ");
    for (std::size_t k = 0; k < wm::kAiTacticCount; ++k) {
      if (t.activations[k] != 0) std::printf(" %s:%d", wm::ai_tactic_name(static_cast<wm::AiTactic>(k)), t.activations[k]);
    }
    std::printf("\n");
  }
}

}  // namespace

TEST_CASE("ai dev: one race of 10 Intermediate boats" * doctest::skip(std::getenv("AI_DEV") == nullptr)) {
  wm_test::AiRaceSpec sp;
  sp.seed = std::getenv("AI_SEED") != nullptr ? std::strtoull(std::getenv("AI_SEED"), nullptr, 10) : 1;
  sp.levels.assign(std::getenv("AI_N") != nullptr ? std::strtoul(std::getenv("AI_N"), nullptr, 10) : 10,
                   std::getenv("AI_LEVEL") != nullptr
                       ? static_cast<wm::AiLevel>(std::strtoul(std::getenv("AI_LEVEL"), nullptr, 10))
                       : wm::AiLevel::intermediate);
  if (std::getenv("AI_MIXED") != nullptr) {
    for (std::size_t k = 0; k < sp.levels.size(); ++k) sp.levels[k] = static_cast<wm::AiLevel>(k % 4);
  }
  if (std::getenv("AI_WM12") != nullptr) {
    for (std::size_t k = 0; k < sp.levels.size(); ++k) sp.classes.push_back(k % 2 == 1 ? "wm12" : "wm7");
  }
  if (std::getenv("AI_WIND") != nullptr) sp.wind_kn = std::strtof(std::getenv("AI_WIND"), nullptr);
  if (std::getenv("AI_MATCH") != nullptr) {
    sp.course = &wm_test::ai_match_course();
    sp.levels.assign(2, wm::AiLevel::expert);
    sp.shifts = wm::ShiftPreset::oscillating;
  }
  // AI_CLASS=<id>: every boat of that class (data/perf/<id>.perf.json)
  if (const char* c = std::getenv("AI_CLASS")) sp.classes.assign(sp.levels.size(), c);
  sp.trace = std::getenv("AI_TRACE");
  {
    auto w = wm_test::ai_world(sp);
    std::string why;
    REQUIRE_MESSAGE(w->create_race(sp.course != nullptr ? *sp.course : wm_test::ai_default_course(), why), why);
    for (const wm::ResolvedMark& m : w->course().marks)
      std::printf("mark %d (%.1f, %.1f) r %.1f\n", static_cast<int>(m.type), static_cast<double>(m.pos.x), static_cast<double>(m.pos.y), static_cast<double>(m.radius));
    std::printf("twd %.1f deg, L %.1f\n", static_cast<double>(w->course().twd_c / wm::DEG), static_cast<double>(w->race().boat(0).L));
  }
  const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
  report("dev", o);
  for (const wm::RulesEvent& e : o.rules_events) {
    if (e.kind == wm::RulesEventKind::mark_touch)
      std::printf("  t %.1f touch boat %d mark %d\n", static_cast<double>(e.tick) * 0.05 - static_cast<double>(o.n_gun_s), e.boat, e.mark);
    if (e.kind == wm::RulesEventKind::penalty || e.kind == wm::RulesEventKind::disqualified)
      std::printf("  t %.1f %s boat %d rule %s other %d mark %d\n", static_cast<double>(e.tick) * 0.05 - static_cast<double>(o.n_gun_s),
                  e.kind == wm::RulesEventKind::penalty ? "penalty" : "DSQ", e.boat,
                  std::string(wm::rule_code_str(e.rule)).c_str(), e.other, e.mark);
  }
}

// The game scene's AI race (game/tests/course_land_test.gd): 6 Expert wm7 boats on the example course in 12 kn from
// 0°, the default shifts, 5 s of free sailing. AI_SEEDS=first,count (default 1,8); AI_N, AI_LEVEL, AI_WIND as above.
// Prints per seed: first mark rounded, mark touches, penalties, DSQ, finished.
TEST_CASE("ai dev: the scene fleet over seeds" * doctest::skip(std::getenv("AI_SCENE") == nullptr)) {
  unsigned long long s0 = 1, ns = 8;
  if (const char* e = std::getenv("AI_SEEDS")) std::sscanf(e, "%llu,%llu", &s0, &ns);
  int tot_round = 0, tot_touch = 0, tot_pen = 0, tot_dsq = 0, tot_fin = 0, tot_boats = 0;
  for (unsigned long long seed = s0; seed < s0 + ns; ++seed) {
    wm_test::AiRaceSpec sp;
    sp.seed = seed;
    sp.wind_kn = std::getenv("AI_WIND") != nullptr ? std::strtof(std::getenv("AI_WIND"), nullptr) : 12.0f;
    sp.wind_from = 0.0f;
    sp.wind_default = true;
    sp.free_sailing_s = 5.0f;
    sp.levels.assign(std::getenv("AI_N") != nullptr ? std::strtoul(std::getenv("AI_N"), nullptr, 10) : 6,
                     std::getenv("AI_LEVEL") != nullptr
                         ? static_cast<wm::AiLevel>(std::strtoul(std::getenv("AI_LEVEL"), nullptr, 10))
                         : wm::AiLevel::expert);
    if (std::getenv("AI_FLEET") != nullptr) {
      // AI_FLEET=1: the ai_races fleet instead (11 kn from 0.3 rad, stable shifts, 10 s free sailing)
      sp.wind_kn = std::getenv("AI_WIND") != nullptr ? std::strtof(std::getenv("AI_WIND"), nullptr) : 11.0f;
      sp.wind_from = 0.3f;
      sp.wind_default = false;
      sp.free_sailing_s = 10.0f;
      const wm::AiLevel lv = sp.levels.front();
      if (std::getenv("AI_N") == nullptr) sp.levels.assign(10, lv);
    }
    if (std::getenv("AI_WM12") != nullptr) {
      for (std::size_t k = 0; k < sp.levels.size(); ++k) sp.classes.push_back(k % 2 == 1 ? "wm12" : "wm7");
    }
    sp.trace = std::getenv("AI_TRACE");
    sp.snap_dir = std::getenv("AI_SNAP");  // a race saved by the game at the gun (boat 0 the player, taken over)
    sp.human0 = sp.snap_dir != nullptr;
    if (sp.snap_dir != nullptr) sp.wind_kn = 12.0f * 0.514444f / wm::KNOT;  // the game's knot
    const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
    int round1 = 0, touch = 0, dsq = 0, fin = 0;
    for (const wm::RaceBoat& b : o.boats) round1 += b.last_rounded >= 1 || b.finished ? 1 : 0;
    for (const wm::ResultRow& r : o.results) {
      fin += r.place > 0 ? 1 : 0;
      dsq += r.code == wm::ScoreCode::DSQ ? 1 : 0;
    }
    if (seed == s0) {
      auto w = wm_test::ai_world(sp);
      std::string why;
      REQUIRE_MESSAGE(w->create_race(wm_test::ai_default_course(), why), why);
      for (const wm::ResolvedMark& m : w->course().marks)
        std::printf("mark type %d (%.1f, %.1f) r %.1f\n", static_cast<int>(m.type), static_cast<double>(m.pos.x),
                    static_cast<double>(m.pos.y), static_cast<double>(m.radius));
    }
    std::printf("seed %2llu:", seed);
    for (const wm::RulesEvent& e : o.rules_events) {
      const double t = static_cast<double>(e.tick) * 0.05 - static_cast<double>(o.n_gun_s);
      if (e.kind == wm::RulesEventKind::mark_touch) {
        ++touch;
        std::printf(" [t%.0f touch b%d m%d]", t, e.boat, e.mark);
      }
      if (e.kind == wm::RulesEventKind::penalty || e.kind == wm::RulesEventKind::disqualified)
        std::printf(" [t%.0f %s b%d %s]", t, e.kind == wm::RulesEventKind::penalty ? "pen" : "DSQ", e.boat,
                    std::string(wm::rule_code_str(e.rule)).c_str());
    }
    std::printf("\n  OCS:");
    for (std::size_t k = 0; k < o.tel.size(); ++k) {
      if (o.tel[k].ocs > 0) std::printf(" b%zu", k);
    }
    std::printf("\n  rounded mark 1 %d/%zu, touches %d, penalties %d, DSQ %d, finished %d\n", round1, o.boats.size(),
                touch, o.penalties, dsq, fin);
    tot_round += round1;
    tot_touch += touch;
    tot_pen += o.penalties;
    tot_dsq += dsq;
    tot_fin += fin;
    tot_boats += static_cast<int>(o.boats.size());
  }
  std::printf("TOTAL %llu seeds, %d boats: rounded mark 1 %d, touches %d, penalties %d, DSQ %d, finished %d\n", ns,
              tot_boats, tot_round, tot_touch, tot_pen, tot_dsq, tot_fin);
}

TEST_CASE("ai dev: fixed helm 360s"* doctest::skip(std::getenv("AI_DEV") == nullptr)) {
  for (const char* cls : {"wm7", "wm12"}) {
    for (const float kn : {6.0f, 11.0f, 16.0f, 22.0f}) {
      for (const float twa0 : {45.0f, 90.0f, 150.0f}) {
        for (const float hs : {0.6f, 0.8f, 1.0f}) {
          for (const float sgn_ : {1.0f, -1.0f}) {
            wm_test::AiRaceSpec sp;
            sp.levels.assign(1, wm::AiLevel::intermediate);
            sp.classes = {cls};
            sp.wind_kn = kn;
            sp.puffs = false;
            sp.shifts = wm::ShiftPreset::steady;
            auto w = wm_test::ai_world(sp);
            std::string why;
            REQUIRE_MESSAGE(w->create_race(sp.course != nullptr ? *sp.course : wm_test::ai_default_course(), why), why);
            const float twd = w->env(0).wind_from_clean;
            const float V = w->boat(0).polar_at(wm_test::kn(kn), twa0 * wm::DEG, w->boat(0).sails().front());
            w->place_boat(0, 0.0f, -600.0f, wm::wrap_2pi(twd - twa0 * wm::DEG), V);
            for (int k = 0; k < 200; ++k) { w->set_helm(0, 0.0f); w->step(); }
            // + helm turns clockwise: from starboard (wind on the right) that is towards the wind.
            float turned = 0.0f, vmin = 1e9f, psi_prev = w->boat(0).state().psi;
            int k = 0;
            for (; k < 1200 && std::fabs(turned) < 2.0f * wm::PI; ++k) {
              w->set_helm(0, sgn_ * hs);
              w->step();
              const float psi = w->boat(0).state().psi;
              turned += wm::wrap_pi(psi - psi_prev);
              psi_prev = psi;
              vmin = wm::min(vmin, w->boat(0).state().v);
            }
            std::printf("%s %4.0f kn twa %4.0f h %+.1f %s: v0 %.2f %s in %5.1f s, vmin %.2f\n", cls,
                        static_cast<double>(kn), static_cast<double>(twa0), static_cast<double>(sgn_ * hs),
                        sgn_ > 0 ? "luff" : "bear", static_cast<double>(w->boat(0).state().v),
                        std::fabs(turned) >= 2.0f * wm::PI ? "done" : "STALL", static_cast<double>(k) * 0.05,
                        static_cast<double>(vmin));
          }
        }
      }
    }
  }
}

// ---- ai.md §15 acceptance runs --------------------------------------------------------------------------------------

namespace {

struct FleetStats {
  int boats = 0, finished = 0, dsq = 0, races = 0;
  int penalties = 0, contacts = 0, ocs = 0, started = 0;
  int late = 0;  // penalties not taken in time (rules.md §9.4)
  double start_delay = 0.0, stuck = 0.0, stuck_max = 0.0;
  int bad_air = 0, bad_air_known = 0, bad_air_better = 0;
  double d_at = 0.0, d_after = 0.0;
  int tacks = 0;
  void add(const wm_test::AiRaceOutcome& o) {
    ++races;
    contacts += o.contacts;
    for (const wm::RulesEvent& e : o.rules_events) {
      if (e.kind == wm::RulesEventKind::penalty_late ||
          (e.kind == wm::RulesEventKind::disqualified && e.rule == wm::RuleCode::late))
        ++late;
    }
    for (const wm::ResultRow& r : o.results) {
      ++boats;
      if (r.place > 0) ++finished;
      if (r.code == wm::ScoreCode::DSQ) ++dsq;
    }
    for (const wm::AiTelemetry& t : o.tel) {
      penalties += t.penalties;
      ocs += t.ocs;
      tacks += t.tacks;
      if (t.start_delay >= 0.0f) {
        ++started;
        start_delay += static_cast<double>(t.start_delay);
      }
      stuck += static_cast<double>(t.stuck_s);
      stuck_max = std::max(stuck_max, static_cast<double>(t.stuck_s));
      for (const wm::AiBadAirRecord& b : t.bad_air) {
        ++bad_air;
        if (b.d_after >= 0.0f) {
          ++bad_air_known;
          d_at += static_cast<double>(b.d_at);
          d_after += static_cast<double>(b.d_after);
          if (b.d_after < b.d_at) ++bad_air_better;
        }
      }
    }
  }
  double per_boat(double v) const { return boats > 0 ? v / boats : 0.0; }
  void print(const char* name) const {
    std::printf("%s: %d races, finished %d/%d (DSQ %d), penalties/boat %.2f, late %d, contacts/race %.2f, OCS %d/%d, "
                "start delay %.1f s, stuck/boat %.1f s (max %.1f), bad air/boat %.2f (deficit %.3f -> %.3f 20 s later, "
                "%d/%d lower), tacks/boat %.1f\n",
                name, races, finished, boats, dsq, per_boat(penalties), late, races > 0 ? double(contacts) / races : 0.0,
                ocs, boats, started > 0 ? start_delay / started : 0.0, per_boat(stuck), stuck_max,
                per_boat(bad_air), bad_air_known > 0 ? d_at / bad_air_known : 0.0,
                bad_air_known > 0 ? d_after / bad_air_known : 0.0, bad_air_better, bad_air_known, per_boat(tacks));
  }
};

FleetStats fleet(std::vector<wm::AiLevel> levels, std::initializer_list<std::uint64_t> seeds, const char* name,
                 const wm::CourseData* course = nullptr, bool speed_only = false) {
  FleetStats st;
  for (const std::uint64_t seed : seeds) {
    wm_test::AiRaceSpec sp;
    sp.seed = seed;
    sp.levels = levels;
    sp.course = course;
    sp.speed_only = speed_only;
    st.add(wm_test::run_ai_race(sp));
  }
  st.print(name);
  return st;
}

}  // namespace

TEST_CASE("ai race: ten Intermediate boats on the default course, five seeds (ai.md §15)") {
  const FleetStats s = fleet(std::vector<wm::AiLevel>(10, wm::AiLevel::intermediate), {1, 2, 3, 4, 5}, "intermediate");
  // Measured targets of this implementation (ai.md §15 records the spec's targets and the gaps).
  CHECK(s.finished >= s.boats * 8 / 10);
  CHECK(s.per_boat(s.penalties) <= 1.3);
  CHECK(double(s.contacts) / s.races <= 6.0);
  CHECK(s.stuck_max <= 60.0);
  // Bad air triggers, and the boats that trigger are in less of it 20 s later. The count follows how bunched the
  // fleet leaves the line: since boats parked before the start drift to leeward (boat.md §6.4) these five seeds
  // give 1.1 triggers/boat (2.5 before); seeds 6 to 20 give 2.1 (2.5 before).
  CHECK(s.per_boat(s.bad_air) >= 1.0);
  CHECK(s.d_after < s.d_at);
}

TEST_CASE("ai race: a fleet completes races at every level (ai.md §13)") {
  for (const wm::AiLevel l : {wm::AiLevel::easy, wm::AiLevel::intermediate, wm::AiLevel::expert, wm::AiLevel::pro}) {
    const std::string name = std::string("level ") + std::to_string(static_cast<int>(l));
    const FleetStats s = fleet(std::vector<wm::AiLevel>(10, l), {21, 22}, name.c_str());
    CAPTURE(static_cast<int>(l));
    CHECK(s.finished >= s.boats * 7 / 10);
    CHECK(s.ocs <= s.boats / 5);
  }
}

TEST_CASE("ai race: level separation in a mixed fleet and with speed-only levels (ai.md §13, §15)") {
  // Mixed: 3 boats per level would need 12; 8 boats, 2 per level, 8 seeds (3 seeds was noise).
  std::vector<wm::AiLevel> mixed;
  for (int k = 0; k < 8; ++k) mixed.push_back(static_cast<wm::AiLevel>(k % 4));
  double place[4] = {0, 0, 0, 0}, time_sum[4] = {0, 0, 0, 0};
  int n[4] = {0, 0, 0, 0}, nt[4] = {0, 0, 0, 0};
  for (const bool speed_only : {false, true}) {
    for (int k = 0; k < 4; ++k) place[k] = time_sum[k] = n[k] = nt[k] = 0;
    for (const std::uint64_t seed : {31u, 32u, 33u, 34u, 35u, 36u, 37u, 38u}) {
      wm_test::AiRaceSpec sp;
      sp.seed = seed;
      sp.levels = mixed;
      sp.speed_only = speed_only;
      const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
      for (const wm::ResultRow& r : o.results) {
        const int lv = r.boat % 4;
        place[lv] += r.place > 0 ? r.place : 9;
        ++n[lv];
        if (r.place > 0) {
          time_sum[lv] += static_cast<double>(r.t_finish_us) * 1e-6;
          ++nt[lv];
        }
      }
    }
    std::printf("%s: mean place by level %.2f %.2f %.2f %.2f; mean finish time %.1f %.1f %.1f %.1f\n",
                speed_only ? "speed only" : "mixed", place[0] / n[0], place[1] / n[1], place[2] / n[2], place[3] / n[3],
                nt[0] ? time_sum[0] / nt[0] : 0.0, nt[1] ? time_sum[1] / nt[1] : 0.0, nt[2] ? time_sum[2] / nt[2] : 0.0,
                nt[3] ? time_sum[3] / nt[3] : 0.0);
    // Easy is behind Pro on average.
    CHECK(place[0] / n[0] > place[3] / n[3]);
  }
}

TEST_CASE("ai race: tacks on a 1 nm beat (ai.md §15)") {
  const FleetStats s = fleet(std::vector<wm::AiLevel>(10, wm::AiLevel::intermediate), {41, 42}, "1 nm beat",
                             &wm_test::ai_beat_course());
  CHECK(s.per_boat(s.tacks) >= 3.0);
  CHECK(s.per_boat(s.tacks) <= 14.0);
}

TEST_CASE("ai race: the match race leader covers (ai.md §9, §15)") {
  int covered = 0;
  for (const std::uint64_t seed : {1u, 2u, 3u, 4u, 5u}) {
    wm_test::AiRaceSpec sp;
    sp.seed = seed;
    sp.levels = {wm::AiLevel::expert, wm::AiLevel::expert};
    sp.course = &wm_test::ai_match_course();
    sp.shifts = wm::ShiftPreset::oscillating;
    const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
    const int c = o.tel[0].activations[static_cast<std::size_t>(wm::AiTactic::Cover)] +
                  o.tel[1].activations[static_cast<std::size_t>(wm::AiTactic::Cover)];
    std::printf("match seed %llu: cover activations %d, penalties %d, contacts %d, finished %d %d\n",
                static_cast<unsigned long long>(seed), c, o.penalties, o.contacts, o.results[0].place,
                o.results[1].place);
    if (c >= 1) ++covered;
    CHECK(o.results[0].place + o.results[1].place == 3);
  }
  CHECK(covered == 5);
}

// A tidal venue (WM-111): ten Intermediate boats at the Solent on its own conditions, the tide forced to a strong
// flood, a strong ebb and slack, two seeds each. The fleet finishes, nobody is pinned for long, the windward marks
// are not overstood, and in the flood (foul upwind, weaker towards the shore on the left) the beats lean further
// left than in the ebb (fair upwind, strongest mid-channel).
TEST_CASE("ai race: a fleet races the Solent tide (ai.md §4.3, §4.7, §6.5)") {
  double side[3] = {0.0, 0.0, 0.0};
  const char* name[3] = {"flood", "ebb", "slack"};
  const float tide[3] = {1.0f, -1.0f, 0.0f};
  for (int k = 0; k < 3; ++k) {
    FleetStats st;
    wm_test::ApproachStats ap;
    for (const std::uint64_t seed : {1u, 2u}) {
      wm_test::AiRaceSpec sp;
      sp.seed = seed;
      sp.venue = &wm_test::venue_by_id("solent");
      sp.course = &wm_test::course_by_path("solent/cowes_wl");
      sp.local_weather = true;
      sp.tide = tide[k];
      sp.levels.assign(10, wm::AiLevel::intermediate);
      const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
      st.add(o);
      ap.approaches += o.approach.approaches;
      ap.overstand_s += o.approach.overstand_s;
      ap.overstood += o.approach.overstood;
      ap.side_sum += o.approach.side_sum;
      ap.side_n += o.approach.side_n;
    }
    const std::string label = std::string("solent ") + name[k];
    st.print(label.c_str());
    side[k] = ap.side_n > 0 ? ap.side_sum / ap.side_n : 0.0;
    std::printf("%s: %d windward approaches, overstood %.1f s each, %d over 10 s; beats' mean side %+.0f m\n",
                label.c_str(), ap.approaches, ap.approaches > 0 ? ap.overstand_s / ap.approaches : 0.0, ap.overstood,
                side[k]);
    CAPTURE(label);
    CHECK(st.finished >= st.boats * 8 / 10);
    CHECK(st.stuck_max <= 60.0);
    CHECK(ap.approaches >= 30);
    CHECK(ap.overstood * 5 <= ap.approaches);
    CHECK(ap.overstand_s <= 8.0 * ap.approaches);
  }
  CHECK(side[0] > side[1]);
}

TEST_CASE("ai race: an AI race reproduces, and saved mid-race it continues identically (race.md §12)") {
  wm_test::AiRaceSpec sp;
  sp.seed = 9;
  sp.levels = std::vector<wm::AiLevel>(10, wm::AiLevel::intermediate);
  sp.keep_checksums = true;
  const wm_test::AiRaceOutcome a = wm_test::run_ai_race(sp);
  const wm_test::AiRaceOutcome b = wm_test::run_ai_race(sp);
  sp.reload_at = 3800u + 5000u;  // on the first beat, 250 s after the gun
  const wm_test::AiRaceOutcome c = wm_test::run_ai_race(sp);
  REQUIRE(c.reloaded);
  CHECK(a.checksums == b.checksums);
  CHECK(a.checksums == c.checksums);
  REQUIRE(a.results.size() == c.results.size());
  for (std::size_t k = 0; k < a.results.size(); ++k) {
    CHECK(a.results[k].boat == c.results[k].boat);
    CHECK(a.results[k].t_finish_us == c.results[k].t_finish_us);
  }
}

// A venue's own conditions (race.md §2.1, local mode) over seeds (WM-111): AI_VENUE=solent (fremantle, trieste, garda,
// practice_waters), AI_COURSE (default the venue's windward-leeward), AI_TIDE=flood|ebb|slack (default the drawn
// phase), AI_SEEDS=first,count (default 1,6), AI_N (default 10), AI_LEVEL (default Intermediate), AI_MIXED.
// Prints per seed the finishes, DSQs, winner time, penalties, contacts, stuck time and the windward approaches.
TEST_CASE("ai dev: a venue's fleet over seeds" * doctest::skip(std::getenv("AI_VENUE") == nullptr)) {
  const std::string venue = std::getenv("AI_VENUE");
  std::string course = venue + "/";
  if (const char* c = std::getenv("AI_COURSE")) course = c;
  else if (venue == "solent") course += "cowes_wl";
  else if (venue == "fremantle") course += "gage_roads_wl";
  else if (venue == "trieste") course += "barcola_wl";
  else if (venue == "garda") course += "garda_wl";
  else course += "example_wl";
  unsigned long long s0 = 1, ns = 6;
  if (const char* e = std::getenv("AI_SEEDS")) std::sscanf(e, "%llu,%llu", &s0, &ns);
  float tide = NAN;
  if (const char* e = std::getenv("AI_TIDE")) {
    const std::string t = e;
    tide = t == "flood" ? 1.0f : (t == "ebb" ? -1.0f : (t == "slack" ? 0.0f : NAN));
  }
  const std::size_t n = std::getenv("AI_N") != nullptr ? std::strtoul(std::getenv("AI_N"), nullptr, 10) : 10;
  const wm::AiLevel lv = std::getenv("AI_LEVEL") != nullptr
                             ? static_cast<wm::AiLevel>(std::strtoul(std::getenv("AI_LEVEL"), nullptr, 10))
                             : wm::AiLevel::intermediate;
  FleetStats st;
  wm_test::ApproachStats ap;
  std::map<std::string, int> rules_tally;
  double lv_place[4] = {0, 0, 0, 0};
  int lv_n[4] = {0, 0, 0, 0};
  double win_sum = 0.0, mean_sum = 0.0;
  int wins = 0;
  for (unsigned long long seed = s0; seed < s0 + ns; ++seed) {
    wm_test::AiRaceSpec sp;
    sp.seed = seed;
    sp.venue = &wm_test::venue_by_id(venue);
    sp.course = &wm_test::course_by_path(course);
    sp.local_weather = true;
    sp.tide = tide;
    sp.no_current = std::getenv("AI_TIDE") != nullptr && std::string(std::getenv("AI_TIDE")) == "none";
    sp.levels.assign(n, lv);
    if (std::getenv("AI_MIXED") != nullptr) {
      for (std::size_t k = 0; k < n; ++k) sp.levels[k] = static_cast<wm::AiLevel>(k % 4);
    }
    if (std::getenv("AI_WM12") != nullptr) {
      for (std::size_t k = 0; k < n; ++k) sp.classes.push_back(k % 2 == 1 ? "wm12" : "wm7");
    }
    sp.trace = std::getenv("AI_TRACE");
    if (sp.trace != nullptr) {
      auto w = wm_test::ai_world(sp);
      std::string why;
      REQUIRE_MESSAGE(w->create_race(*sp.course, why), why);
      for (const wm::ResolvedMark& m : w->course().marks)
        std::printf("mark type %d (%.1f, %.1f) r %.1f\n", static_cast<int>(m.type), static_cast<double>(m.pos.x),
                    static_cast<double>(m.pos.y), static_cast<double>(m.radius));
      std::printf("twd %.1f deg, wind %.1f kn\n", static_cast<double>(w->course().twd_c / wm::DEG),
                  static_cast<double>(w->wind().settings().base_speed / wm::KNOT));
    }
    const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
    st.add(o);
    for (const wm::RulesEvent& e : o.rules_events) {
      if (e.kind == wm::RulesEventKind::penalty) ++rules_tally["pen " + std::string(wm::rule_code_str(e.rule))];
      if (e.kind == wm::RulesEventKind::disqualified) ++rules_tally["DSQ " + std::string(wm::rule_code_str(e.rule))];
      if (e.kind == wm::RulesEventKind::mark_touch) ++rules_tally["touch"];
    }
    if (std::getenv("AI_OCS") != nullptr) {
      for (const wm::RaceEvent& e : o.ocs_events)
        std::printf("  OCS t %.1f boat %d flag %d\n", static_cast<double>(e.tick) * 0.05 - static_cast<double>(o.n_gun_s),
                    e.boat, static_cast<int>(e.flag));
    }
    int fin = 0, dsq = 0;
    double win = 0.0, mean = 0.0;
    for (const wm::ResultRow& r : o.results) {
      const int lvk = static_cast<int>(sp.levels[static_cast<std::size_t>(r.boat)]);
      lv_place[lvk] += r.place > 0 ? r.place : static_cast<double>(n) + 1.0;
      ++lv_n[lvk];
      if (r.place > 0) {
        ++fin;
        mean += static_cast<double>(r.t_finish_us) * 1e-6;
        if (r.place == 1) win = static_cast<double>(r.t_finish_us) * 1e-6;
      }
      dsq += r.code == wm::ScoreCode::DSQ ? 1 : 0;
    }
    double stuck = 0.0;
    int ocs = 0;
    for (const wm::AiTelemetry& t : o.tel) {
      stuck = std::max(stuck, static_cast<double>(t.stuck_s));
      ocs += t.ocs;
    }
    if (win > 0.0) {
      win_sum += win;
      mean_sum += mean / fin;
      ++wins;
    }
    ap.approaches += o.approach.approaches;
    ap.overstand_s += o.approach.overstand_s;
    ap.overstand_m += o.approach.overstand_m;
    ap.overstood += o.approach.overstood;
    ap.near_tacks += o.approach.near_tacks;
    ap.side_sum += o.approach.side_sum;
    ap.side_n += o.approach.side_n;
    std::printf("seed %3llu tide %+.2f: finished %2d/%zu DSQ %d winner %6.1f s mean %6.1f s pen %d contacts %d "
                "stuck max %5.1f s ocs %d | approaches %d overstood %.1f s/app (%d > 10 s) near tacks %d side %+.1f ostot %.1f\n",
                seed, static_cast<double>(o.tide_at_gun), fin, o.results.size(), dsq, win, fin > 0 ? mean / fin : 0.0,
                o.penalties, o.contacts, stuck, ocs, o.approach.approaches,
                o.approach.approaches > 0 ? o.approach.overstand_s / o.approach.approaches : 0.0, o.approach.overstood,
                o.approach.near_tacks, o.approach.side_n > 0 ? o.approach.side_sum / o.approach.side_n : 0.0,
                o.approach.overstand_s);
  }
  st.print(venue.c_str());
  std::printf("LEVELS mean place");
  for (int k = 0; k < 4; ++k) std::printf(" %.2f", lv_n[k] > 0 ? lv_place[k] / lv_n[k] : 0.0);
  std::printf("\n");
  std::printf("RULES");
  for (const auto& [k, v] : rules_tally) std::printf(" [%s %d]", k.c_str(), v);
  std::printf("\n");
  std::printf("TOTAL %s: winner mean %.1f s, finishers' mean %.1f s; approaches %d, overstood %.1f s/app, %.0f m/app, %d > 10 s (%.0f %%), "
              "near tacks %.2f/app; beats' mean side %+.1f m (+ left)\n",
              venue.c_str(), wins > 0 ? win_sum / wins : 0.0, wins > 0 ? mean_sum / wins : 0.0, ap.approaches,
              ap.approaches > 0 ? ap.overstand_s / ap.approaches : 0.0,
              ap.approaches > 0 ? ap.overstand_m / ap.approaches : 0.0, ap.overstood,
              ap.approaches > 0 ? 100.0 * ap.overstood / ap.approaches : 0.0,
              ap.approaches > 0 ? double(ap.near_tacks) / ap.approaches : 0.0,
              ap.side_n > 0 ? ap.side_sum / ap.side_n : 0.0);
}


// Development probe (AI_PIN=t_race, AI_PIN_B=boat, AI_REL=kind as the sweep, AI_SEED): the race run to race time t,
// then boat b sailed with fixed controls for 60 s (the others on their last controls); prints where she gets to.
TEST_CASE("ai dev: pinned probe" * doctest::skip(std::getenv("AI_PIN") == nullptr)) {
  wm_test::AiRaceSpec sp;
  sp.seed = std::getenv("AI_SEED") != nullptr ? std::strtoull(std::getenv("AI_SEED"), nullptr, 10) : 5;
  const std::string kind = std::getenv("AI_REL") != nullptr ? std::getenv("AI_REL") : "match7";
  const float winds[4] = {8.0f, 11.0f, 15.0f, 19.0f};
  sp.wind_kn = winds[sp.seed % 4];
  if (kind == "match7" || kind == "match12") {
    sp.course = &wm_test::ai_match_course();
    sp.levels.assign(2, wm::AiLevel::expert);
    sp.shifts = wm::ShiftPreset::oscillating;
    if (kind == "match12") sp.classes = {"wm12", "wm12"};
  } else if (kind == "big") {
    sp.levels.assign(16, wm::AiLevel::intermediate);
  } else {
    for (int k = 0; k < 10; ++k) {
      sp.levels.push_back(static_cast<wm::AiLevel>(k % 4));
      sp.classes.push_back(kind == "fleet12" ? "wm12" : (kind == "mixed" && k % 2 == 1 ? "wm12" : "wm7"));
    }
  }
  const wm::CourseData& course = sp.course != nullptr ? *sp.course : wm_test::ai_default_course();
  const std::int32_t bi = std::getenv("AI_PIN_B") != nullptr ? std::atoi(std::getenv("AI_PIN_B")) : 0;
  const float t_at = std::strtof(std::getenv("AI_PIN"), nullptr);
  auto w = wm_test::ai_world(sp);
  std::string why;
  REQUIRE(w->create_race(course, why));
  auto ai = std::make_unique<wm::AiSkippers>();
  wm_test::ai_add_all(*ai, sp);
  wm::AiSkippers* aip = ai.get();
  w->set_controller([aip](wm::World& world) { aip->step(world); });
  while (w->race().race_time(w->tick()) < t_at) w->step();
  wm::SnapshotWriter sw;
  w->save(sw);
  const std::size_t b = static_cast<std::size_t>(bi);
  const wm::BoatState s0 = w->boat(b).state();
  std::printf("at t %.1f: boat %d (%.2f, %.2f) psi %.1f v %.2f twa %.1f\n", static_cast<double>(t_at), bi,
              static_cast<double>(s0.pos_x), static_cast<double>(s0.pos_y), static_cast<double>(s0.psi / wm::DEG),
              static_cast<double>(s0.v), static_cast<double>(wm::wrap_pi(w->env(b).wind_from_clean - s0.psi) / wm::DEG));
  if (const char* seqs = std::getenv("AI_PIN_SEQ")) {
    // "mode,helm,seconds;...|..." : mode 0 sails drawing, 1 let fly; sequences separated by |
    const std::string all = seqs;
    std::size_t sa = 0;
    while (sa < all.size()) {
    std::size_t se = all.find('|', sa);
    if (se == std::string::npos) se = all.size();
    auto w2 = wm_test::ai_world(sp);
    REQUIRE(w2->load(sw.bytes(), &course, why));
    std::string q = all.substr(sa, se - sa);
    sa = se + 1;
    std::size_t at = 0;
    while (at < q.size()) {
      std::size_t e = q.find(';', at);
      if (e == std::string::npos) e = q.size();
      int mode = 0;
      float h = 0.0f, secs = 0.0f;
      std::sscanf(q.substr(at, e - at).c_str(), "%d,%f,%f", &mode, &h, &secs);
      for (int k = 0; k < static_cast<int>(secs * 20.0f); ++k) {
        w2->set_helm(bi, h);
        w2->set_let_fly(bi, mode == 1);
        w2->set_auto_trim(bi, true);
        w2->step();
      }
      const wm::BoatState& s = w2->boat(b).state();
      std::printf("  seq %d,%+.1f,%.0f: (%.2f, %.2f) psi %.1f v %.2f moved %.1f\n", mode, static_cast<double>(h),
                  static_cast<double>(secs), static_cast<double>(s.pos_x), static_cast<double>(s.pos_y),
                  static_cast<double>(s.psi / wm::DEG), static_cast<double>(s.v),
                  static_cast<double>(std::hypot(s.pos_x - s0.pos_x, s.pos_y - s0.pos_y)));
      at = e + 1;
    }
    const wm::BoatState& s = w2->boat(b).state();
    std::printf("RESULT %s moved %.1f\n", q.c_str(), static_cast<double>(std::hypot(s.pos_x - s0.pos_x, s.pos_y - s0.pos_y)));
    }
    return;
  }
  for (const int mode : {0, 1, 2, 3}) {  // sails drawing, let fly, sheet hard in, sheet free
    for (const float h : {-1.0f, -0.5f, 0.0f, 0.5f, 1.0f}) {
      auto w2 = wm_test::ai_world(sp);
      REQUIRE(w2->load(sw.bytes(), &course, why));
      float vmax = -9.0f;
      for (int k = 0; k < 1200; ++k) {
        w2->set_helm(bi, h);
        w2->set_let_fly(bi, mode == 1);
        w2->set_auto_trim(bi, mode <= 1);
        if (mode == 2) w2->set_sheet(bi, 0.0f);
        if (mode == 3) w2->set_sheet(bi, 1.0f);
        w2->step();
        vmax = std::max(vmax, w2->boat(b).state().v);
      }
      const wm::BoatState& s = w2->boat(b).state();
      std::printf("  mode %d helm %+.1f: (%.2f, %.2f) psi %.1f v %.2f vmax %.2f moved %.1f\n", mode, static_cast<double>(h),
                  static_cast<double>(s.pos_x), static_cast<double>(s.pos_y), static_cast<double>(s.psi / wm::DEG),
                  static_cast<double>(s.v), static_cast<double>(vmax),
                  static_cast<double>(std::hypot(s.pos_x - s0.pos_x, s.pos_y - s0.pos_y)));
    }
  }
}

// Development reliability sweep (WM-130): AI_REL=fleet7|fleet12|mixed|match7|match12|big|bigmix over AI_SEEDS=first,count.
// fleet7 / fleet12: 10 boats of one class, levels mixed (boat k at level k mod 4); mixed: 10 boats, wm7 and wm12
// alternating, levels mixed; match7 / match12: two Expert boats on the match course, oscillating shifts; big: 16
// Intermediate wm7 boats; bigmix: 16 boats, levels and classes mixed. The wind cycles 8, 11, 15, 19 kn over the seeds. One line per race: finished, DNF, DSQ,
// the longest stuck time, contacts, penalties, mark touches and the skippers' cost (µs per tick, mean and worst).
TEST_CASE("ai dev: reliability sweep" * doctest::skip(std::getenv("AI_REL") == nullptr)) {
  const std::string kind = std::getenv("AI_REL");
  unsigned long long s0 = 1, ns = 8;
  if (const char* e = std::getenv("AI_SEEDS")) std::sscanf(e, "%llu,%llu", &s0, &ns);
  int t_fin = 0, t_boats = 0, t_dnf = 0, t_dsq = 0, t_con = 0, t_pen = 0, t_touch = 0, t_stuck60 = 0;
  double t_stuck_max = 0.0, t_us = 0.0, t_us_max = 0.0;
  std::uint32_t t_ticks = 0;
  std::vector<float> t_all_us;
  for (unsigned long long seed = s0; seed < s0 + ns; ++seed) {
    wm_test::AiRaceSpec sp;
    sp.seed = seed;
    sp.time_ai = true;
    const float winds[4] = {8.0f, 11.0f, 15.0f, 19.0f};
    sp.wind_kn = winds[seed % 4];
    if (kind == "match7" || kind == "match12") {
      sp.course = &wm_test::ai_match_course();
      sp.levels.assign(2, wm::AiLevel::expert);
      sp.shifts = wm::ShiftPreset::oscillating;
      if (kind == "match12") sp.classes = {"wm12", "wm12"};
    } else if (kind == "big") {
      sp.levels.assign(16, wm::AiLevel::intermediate);
    } else if (kind == "bigmix") {
      for (int k = 0; k < 16; ++k) {
        sp.levels.push_back(static_cast<wm::AiLevel>(k % 4));
        sp.classes.push_back(k % 2 == 1 ? "wm12" : "wm7");
      }
    } else {
      for (int k = 0; k < 10; ++k) {
        sp.levels.push_back(static_cast<wm::AiLevel>(k % 4));
        sp.classes.push_back(kind == "fleet12" ? "wm12" : (kind == "mixed" && k % 2 == 1 ? "wm12" : "wm7"));
      }
    }
    sp.trace = std::getenv("AI_TRACE");
    if (sp.trace != nullptr) {
      auto w = wm_test::ai_world(sp);
      std::string why;
      REQUIRE_MESSAGE(w->create_race(sp.course != nullptr ? *sp.course : wm_test::ai_default_course(), why), why);
      for (const wm::ResolvedMark& m : w->course().marks)
        std::printf("MARK %d %.1f %.1f %.1f\n", static_cast<int>(m.type), static_cast<double>(m.pos.x),
                    static_cast<double>(m.pos.y), static_cast<double>(m.radius));
    }
    const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
    int fin = 0, dnf = 0, dsq = 0, touch = 0;
    double stuck = 0.0;
    std::string who;
    for (const wm::ResultRow& r : o.results) {
      fin += r.place > 0 ? 1 : 0;
      dsq += r.code == wm::ScoreCode::DSQ ? 1 : 0;
      if (r.place <= 0 && r.code != wm::ScoreCode::DSQ) {
        ++dnf;
        who += " dnf:b" + std::to_string(r.boat);
      }
    }
    double pinned = 0.0, pinned_tot = 0.0;
    for (std::size_t k = 0; k < o.pinned_max.size(); ++k) {
      pinned = std::max(pinned, static_cast<double>(o.pinned_max[k]));
      pinned_tot += static_cast<double>(o.pinned_s[k]);
      if (o.pinned_max[k] > 30.0f) who += " pinned:b" + std::to_string(k) + "=" + std::to_string(static_cast<int>(o.pinned_max[k]));
    }
    for (std::size_t k = 0; k < o.tel.size(); ++k) {
      stuck = std::max(stuck, static_cast<double>(o.tel[k].stuck_s));
      if (o.tel[k].stuck_s > 60.0f) {
        ++t_stuck60;
        who += " stuck:b" + std::to_string(k) + "=" + std::to_string(static_cast<int>(o.tel[k].stuck_s));
      }
    }
    for (const wm::RulesEvent& e : o.rules_events) {
      touch += e.kind == wm::RulesEventKind::mark_touch ? 1 : 0;
      if (sp.trace != nullptr && e.kind == wm::RulesEventKind::mark_touch)
        std::printf("TOUCH t %.1f boat %d mark %d\n", static_cast<double>(e.tick) * 0.05 - static_cast<double>(o.n_gun_s),
                    e.boat, e.mark);
      if (e.kind == wm::RulesEventKind::disqualified)
        who += " dsq:b" + std::to_string(e.boat) + ":" + std::string(wm::rule_code_str(e.rule));
    }
    const double us = o.ai_ticks > 0 ? o.ai_us_sum / o.ai_ticks : 0.0;
    std::printf("REL %s seed %3llu wind %2.0f: fin %2d/%zu dnf %d dsq %d stuck %6.1f pinned %6.1f pintot %6.1f contacts %2d pen %2d touch %2d "
                "ai us %6.1f max %7.1f%s\n",
                kind.c_str(), seed, static_cast<double>(sp.wind_kn), fin, o.results.size(), dnf, dsq, stuck, pinned,
                pinned_tot, o.contacts, o.penalties, touch, us, o.ai_us_max, who.c_str());
    t_fin += fin;
    t_boats += static_cast<int>(o.results.size());
    t_dnf += dnf;
    t_dsq += dsq;
    t_con += o.contacts;
    t_pen += o.penalties;
    t_touch += touch;
    t_stuck_max = std::max(t_stuck_max, stuck);
    t_us += o.ai_us_sum;
    t_ticks += o.ai_ticks;
    t_us_max = std::max(t_us_max, o.ai_us_max);
    t_all_us.insert(t_all_us.end(), o.ai_us.begin(), o.ai_us.end());
  }
  std::sort(t_all_us.begin(), t_all_us.end());
  if (!t_all_us.empty()) {
    auto pct = [&](double q) { return static_cast<double>(t_all_us[static_cast<std::size_t>(q * static_cast<double>(t_all_us.size() - 1))]); };
    std::printf("RELCOST %s %zu ticks: mean %.1f us, p50 %.1f, p99 %.1f, p99.9 %.1f, max %.1f\n", kind.c_str(),
                t_all_us.size(), t_us / static_cast<double>(t_ticks), pct(0.5), pct(0.99), pct(0.999), t_us_max);
  }
  std::printf("RELTOTAL %s %llu races: fin %d/%d dnf %d dsq %d stuck>60 %d (max %.1f) contacts %d pen %d touch %d "
              "ai us %.1f max %.1f\n",
              kind.c_str(), ns, t_fin, t_boats, t_dnf, t_dsq, t_stuck60, t_stuck_max, t_con, t_pen, t_touch,
              t_ticks > 0 ? t_us / t_ticks : 0.0, t_us_max);
}
