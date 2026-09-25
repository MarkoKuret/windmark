// AI fleet races (ai.md §15 headless acceptance tests). Long: run with `ctest --test-dir core/build -L ai_long`
// or `core/build/tests/windmark_ai_race_tests`.
#include <cstdio>
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

TEST_CASE("ai dev: fixed helm 360s" * doctest::skip(std::getenv("AI_DEV") == nullptr)) {
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
