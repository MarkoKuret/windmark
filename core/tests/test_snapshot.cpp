// World snapshots (conventions.md §9.1, race.md §13, rules.md §14): the full race of test_full_race.cpp saved at
// several ticks, loaded into a new world and continued gives the same checksum every tick, the same events and the
// same results as the unbroken run; a load re-saves to the same bytes; damaged or foreign snapshots are rejected;
// a race with a joined boat is rebuilt as it was.
#include <algorithm>
#include <string>
#include <vector>

#include "doctest.h"
#include "full_race.h"

namespace {

constexpr std::uint64_t kSeed = 20260925;

struct SavePoint {
  std::string what;
  std::uint32_t tick = 0;  // the world's tick() when saved (the next tick to run)
  std::vector<std::uint8_t> bytes;
  wm_test::Pilot pilot{0};
};

struct Run {
  std::vector<std::uint64_t> sums;  // sums[t] = checksum after the step that made tick() == t (sums[0] unused)
  std::vector<wm::RulesEvent> rules_events;
  std::vector<wm::RaceEvent> race_events;
  std::vector<wm::ResultRow> results;
  std::uint32_t end = 0;
};

bool same(const wm::RulesEvent& a, const wm::RulesEvent& b) {
  return a.kind == b.kind && a.tick == b.tick && a.boat == b.boat && a.other == b.other && a.rule == b.rule &&
         a.count == b.count && a.contact == b.contact && a.mark == b.mark && a.deadline == b.deadline;
}

bool same(const wm::RaceEvent& a, const wm::RaceEvent& b) {
  return a.kind == b.kind && a.tick == b.tick && a.boat == b.boat && a.signal == b.signal && a.flag == b.flag &&
         a.step == b.step && a.buoy == b.buoy && a.t == b.t && a.t_us == b.t_us && a.place == b.place &&
         a.block == b.block && a.ghost == b.ghost && a.value == b.value;
}

// Steps `w` to the close of the race, appending to `run` (sums indexed by tick).
void run_to_close(wm::World& w, Run& run, const std::function<void(wm::World&)>& after_step = {}) {
  for (int k = 0; k < 60000 && w.race().state() != wm::RaceState::closed; ++k) {
    const std::uint64_t c = w.step();
    if (run.sums.size() <= w.tick()) run.sums.resize(w.tick() + 1, 0);
    run.sums[w.tick()] = c;
    for (const wm::RulesEvent& e : w.events().rules) run.rules_events.push_back(e);
    for (const wm::RaceEvent& e : w.events().race) run.race_events.push_back(e);
    if (after_step) after_step(w);
  }
  run.results = w.race().results();
  run.end = w.tick();
}

bool any_penalty_turn(const wm::World& w) {
  for (std::size_t i = 0; i < w.boat_count(); ++i) {
    if (w.rules().boat(i).turning_for_penalty) return true;
  }
  return false;
}

bool any_pending(const wm::World& w) {
  for (std::size_t i = 0; i < w.boat_count(); ++i) {
    if (w.rules().penalty_pending(i)) return true;
  }
  return false;
}

bool busy_pair(const wm::World& w) {
  for (const wm::PairRecord& p : w.rules().pairs()) {
    if (p.kc_state != wm::KcState::clear || p.room_entitled >= 0) return true;
  }
  return false;
}

bool any_finished(const wm::World& w) {
  for (std::size_t i = 0; i < w.boat_count(); ++i) {
    if (w.race().boat(i).finished) return true;
  }
  return false;
}

}  // namespace

TEST_CASE("snapshot: a full race saved mid-race and loaded continues bit for bit") {
  // The unbroken run, saving at the first tick of each situation.
  auto w = wm_test::full_race_world(kSeed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  const std::uint32_t gun = static_cast<std::uint32_t>(w->race().n_gun());

  std::vector<SavePoint> saves;
  std::vector<std::string> taken;
  auto save_once = [&](const std::string& what, bool when) {
    if (!when || std::find(taken.begin(), taken.end(), what) != taken.end()) return;
    taken.push_back(what);
    SavePoint sp;
    sp.what = what;
    sp.tick = w->tick();
    wm::SnapshotWriter sw;
    w->save(sw);
    sp.bytes = sw.bytes();
    sp.pilot = pilot;
    saves.push_back(std::move(sp));
  };
  Run a;
  run_to_close(*w, a, [&](wm::World& x) {
    const std::uint32_t t = x.tick();
    save_once("free sailing", t == 100);
    save_once("sequence, before the preparatory signal", t + 3000 == gun);
    save_once("sequence, rules live", t + 600 == gun);
    save_once("just after the gun", t == gun + 20);
    save_once("a pair under a keep-clear or room obligation", t > gun && busy_pair(x));
    save_once("a penalty pending", any_pending(x));
    save_once("a penalty turn in progress", any_penalty_turn(x));
    save_once("after the first finish", any_finished(x));
    save_once("closing", x.race().state() == wm::RaceState::closing && t % 100 == 0);
  });
  REQUIRE(a.results.size() == 6);
  MESSAGE("race closed after ", a.end, " ticks; ", saves.size(), " save points");
  CHECK(saves.size() == 9);

  for (const SavePoint& sp : saves) {
    CAPTURE(sp.what);
    CAPTURE(sp.tick);
    MESSAGE("save at tick ", sp.tick, " (", sp.what, "): ", sp.bytes.size(), " bytes");
    auto v = wm_test::full_race_world(kSeed);
    REQUIRE_MESSAGE(v->load(sp.bytes, &wm_test::full_race_course(), why), why);
    CHECK(v->tick() == sp.tick);
    CHECK(v->checksum() == a.sums[sp.tick]);
    // The loaded world saves to the same bytes.
    wm::SnapshotWriter again;
    v->save(again);
    CHECK(again.bytes() == sp.bytes);

    wm_test::Pilot p = sp.pilot;
    v->set_controller([&p](wm::World& world) { p(world); });
    Run b;
    run_to_close(*v, b);
    REQUIRE(b.end == a.end);
    std::uint32_t first_bad = 0;
    for (std::uint32_t t = sp.tick + 1; t <= a.end && first_bad == 0; ++t) {
      if (b.sums[t] != a.sums[t]) first_bad = t;
    }
    CHECK_MESSAGE(first_bad == 0, "checksums differ from tick ", first_bad);
    std::vector<wm::RulesEvent> ra;
    for (const wm::RulesEvent& e : a.rules_events) {
      if (e.tick >= sp.tick) ra.push_back(e);
    }
    std::vector<wm::RaceEvent> ca;
    for (const wm::RaceEvent& e : a.race_events) {
      if (e.tick >= sp.tick) ca.push_back(e);
    }
    REQUIRE(b.rules_events.size() == ra.size());
    for (std::size_t k = 0; k < ra.size(); ++k) CHECK(same(b.rules_events[k], ra[k]));
    REQUIRE(b.race_events.size() == ca.size());
    for (std::size_t k = 0; k < ca.size(); ++k) CHECK(same(b.race_events[k], ca[k]));
    REQUIRE(b.results.size() == a.results.size());
    for (std::size_t k = 0; k < a.results.size(); ++k) {
      CHECK(b.results[k].boat == a.results[k].boat);
      CHECK(b.results[k].place == a.results[k].place);
      CHECK(b.results[k].code == a.results[k].code);
      CHECK(b.results[k].points == a.results[k].points);
      CHECK(b.results[k].t_finish_us == a.results[k].t_finish_us);
      CHECK(b.results[k].projected == a.results[k].projected);
    }
  }
}

TEST_CASE("snapshot: the checksum covers the race and rules state") {
  auto w = wm_test::full_race_world(kSeed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  const std::uint32_t gun = static_cast<std::uint32_t>(w->race().n_gun());
  while (w->tick() < gun + 200) w->step();
  wm::SnapshotWriter sw;
  w->save(sw);
  const std::uint64_t base = w->checksum();
  // Retiring a boat changes the race state only (the boat steps come later): the checksum after the next step
  // differs from the run without it, although the boats' first step is the same.
  auto u = wm_test::full_race_world(kSeed), v = wm_test::full_race_world(kSeed);
  REQUIRE_MESSAGE(u->load(sw.bytes(), &wm_test::full_race_course(), why), why);
  REQUIRE_MESSAGE(v->load(sw.bytes(), &wm_test::full_race_course(), why), why);
  CHECK(u->checksum() == base);
  v->retire(4);
  CHECK(v->checksum() != base);  // the queued control is state too
  const std::uint64_t cu = u->step(), cv = v->step();
  CHECK(cu != cv);
  CHECK(v->race().boat(4).retired);
}

TEST_CASE("snapshot: damaged or foreign snapshots are rejected") {
  auto w = wm_test::full_race_world(kSeed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  while (w->tick() < 5000) w->step();
  wm::SnapshotWriter sw;
  w->save(sw);
  const std::vector<std::uint8_t>& good = sw.bytes();

  std::vector<std::uint8_t> cut(good.begin(), good.end() - 3);
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(cut, &wm_test::full_race_course(), why));
  std::vector<std::uint8_t> longer = good;
  longer.push_back(0);
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(longer, &wm_test::full_race_course(), why));
  CHECK(why == "bytes left over after the snapshot");
  CHECK_FALSE(wm_test::full_race_world(kSeed + 1)->load(good, &wm_test::full_race_course(), why));
  CHECK_FALSE(wm_test::full_race_world(kSeed, 5)->load(good, &wm_test::full_race_course(), why));
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(good, nullptr, why));
  // A world that has run already cannot take a snapshot.
  CHECK_FALSE(w->load(good, &wm_test::full_race_course(), why));
  CHECK(wm_test::full_race_world(kSeed)->load(good, &wm_test::full_race_course(), why));
}

TEST_CASE("snapshot: a race with a joined boat is rebuilt as it was") {
  // Five entries at creation; the sixth (the longer wm12) joins in free sailing.
  auto w = wm_test::full_race_world(kSeed, 5);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  while (w->tick() < 60) w->step();
  wm::BoatEntry e;
  e.perf = &wm_test::perf("wm12");
  REQUIRE(w->add_boat(e) == 5);
  while (w->tick() < 1500) w->step();
  wm::SnapshotWriter sw;
  w->save(sw);
  wm_test::Pilot p = pilot;

  auto v = wm_test::full_race_world(kSeed, 6);  // every entry, in index order
  REQUIRE_MESSAGE(v->load(sw.bytes(), &wm_test::full_race_course(), why), why);
  v->set_controller([&p](wm::World& world) { p(world); });
  CHECK(v->checksum() == w->checksum());
  CHECK(v->race().L_max() == w->race().L_max());
  CHECK(v->course().k == w->course().k);
  bool same_sums = true;
  for (int k = 0; k < 3000; ++k) same_sums = same_sums && w->step() == v->step();
  CHECK(same_sums);
}
