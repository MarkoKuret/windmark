// The full AI race determinism test (WM-033, ROADMAP phase 2 gate): a headless race of the AI fleet of
// ai_fleet_race.h with collisions and the racing rules, from the spawn to the close, run twice with the same seed:
// the same checksum every tick (conventions.md §9) and the same results. A long test (doctest suite `long`).
// The second-architecture run is tools/cross_arch_check.sh: the same race through windmark_race_trace on an arm64
// and an x86_64 build, per-tick checksums compared.
#include <string>
#include <vector>

#include "ai_fleet_race.h"
#include "doctest.h"

namespace {

struct FleetRun {
  std::vector<std::uint64_t> sums;  // per tick, in step order
  std::vector<wm::ResultRow> results;
  std::int32_t contacts = 0;        // boat-boat contact begins
  std::int32_t penalties = 0;
  std::int32_t rules_events = 0;
  bool closed = false;
};

FleetRun run_fleet(const wm_test::AiFleetRace& data, std::uint64_t seed, int boats) {
  FleetRun r;
  wm::AiSkippers ai;
  std::string why;
  std::unique_ptr<wm::World> w = data.world(seed, boats, ai, why);
  REQUIRE_MESSAGE(w != nullptr, why);
  w->set_controller([&ai](wm::World& world) { ai.step(world); });
  for (int k = 0; k < 80000 && w->race().state() != wm::RaceState::closed; ++k) {
    r.sums.push_back(w->step());
    for (const wm::ContactEvent& e : w->events().contacts) {
      if (e.begin && e.other_kind == wm::ContactKind::boat && e.boat < e.other) ++r.contacts;
    }
    for (const wm::RulesEvent& e : w->events().rules) {
      ++r.rules_events;
      if (e.kind == wm::RulesEventKind::penalty) ++r.penalties;
    }
  }
  r.closed = w->race().state() == wm::RaceState::closed;
  r.results = w->race().results();
  return r;
}

}  // namespace

TEST_CASE("full AI race: a fleet with collisions and rules races to the close, the same every tick" *
          doctest::test_suite("long")) {
  wm_test::AiFleetRace data;
  std::string why;
  REQUIRE_MESSAGE(data.load(why), why);
  constexpr int kBoats = 10;
  const FleetRun a = run_fleet(data, 33, kBoats);
  MESSAGE("AI fleet race: ", a.sums.size(), " ticks, ", a.contacts, " boat contacts, ", a.penalties, " penalties, ",
          a.rules_events, " rules events");
  REQUIRE(a.closed);
  REQUIRE(a.results.size() == kBoats);
  int finished = 0;
  for (const wm::ResultRow& r : a.results) {
    CHECK((r.place > 0 || r.code != wm::ScoreCode::none));
    finished += r.place > 0 ? 1 : 0;
  }
  CHECK(finished >= kBoats * 8 / 10);
  // The collisions and the rules are in play.
  CHECK(a.contacts >= 1);
  CHECK(a.penalties >= 1);

  const FleetRun b = run_fleet(data, 33, kBoats);
  REQUIRE(b.sums.size() == a.sums.size());
  std::size_t first_diff = a.sums.size();
  for (std::size_t k = 0; k < a.sums.size() && first_diff == a.sums.size(); ++k) {
    if (a.sums[k] != b.sums[k]) first_diff = k;
  }
  CHECK_MESSAGE(first_diff == a.sums.size(), "checksums differ from step ", first_diff + 1);
  REQUIRE(b.results.size() == a.results.size());
  for (std::size_t k = 0; k < a.results.size(); ++k) {
    CHECK(b.results[k].boat == a.results[k].boat);
    CHECK(b.results[k].place == a.results[k].place);
    CHECK(b.results[k].code == a.results[k].code);
    CHECK(b.results[k].t_finish_us == a.results[k].t_finish_us);
  }
  CHECK(b.contacts == a.contacts);
  CHECK(b.penalties == a.penalties);
}
