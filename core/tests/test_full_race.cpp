// A full race headless (race.md §12, WM-009): the shipped example venue, a one-lap windward-leeward course, six
// scripted boats with the shipped wm7 and wm12 files, from the spawn to the results. Scripted misbehaviour gives
// an OCS-I start, a port-tack boat sailing blindly through the fleet before the start and a boat sailing out of
// the race area, so the race has penalties and penalty turns. The same seed reproduces the same results and the
// same final state checksum.
#include <string>
#include <vector>

#include "doctest.h"
#include "full_race.h"

namespace {

struct Outcome {
  std::vector<wm::ResultRow> results;
  std::uint64_t checksum = 0;
  std::uint32_t ticks = 0;
  std::vector<wm::RulesEvent> rules_events;
  std::vector<wm::RaceEvent> race_events;
};

Outcome run_race(std::uint64_t seed) {
  auto w = wm_test::full_race_world(seed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });

  Outcome o;
  for (int k = 0; k < 60000 && w->race().state() != wm::RaceState::closed; ++k) {
    w->step();
    for (const wm::RulesEvent& e : w->events().rules) o.rules_events.push_back(e);
    for (const wm::RaceEvent& e : w->events().race) o.race_events.push_back(e);
  }
  o.results = w->race().results();
  o.checksum = w->checksum();
  o.ticks = w->tick();
  return o;
}

int count(const Outcome& o, wm::RulesEventKind k) {
  int c = 0;
  for (const wm::RulesEvent& e : o.rules_events) c += e.kind == k ? 1 : 0;
  return c;
}

}  // namespace

TEST_CASE("full race: a headless race with penalties, and determinism" * doctest::test_suite("long")) {
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
