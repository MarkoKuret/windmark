// World snapshots (conventions.md §9.1, race.md §13, rules.md §14): the full race of test_full_race.cpp saved at
// several ticks, loaded into a new world and continued gives the same checksum every tick, the same events and the
// same results as the unbroken run (a long test); a load re-saves to the same bytes and restores the sail outputs;
// damaged or foreign snapshots are rejected and leave the world as it was; a world is reset and loaded repeatedly;
// the tick checksum is the hash of the snapshot body; a race with a joined boat is rebuilt as it was.
#include <algorithm>
#include <cstring>
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

TEST_CASE("snapshot: a full race saved mid-race and loaded continues bit for bit" * doctest::test_suite("long")) {
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

namespace {

bool same_bits(float a, float b) { return std::memcmp(&a, &b, sizeof a) == 0; }

// Every boat's per-sail outputs (sails.md §7) and her let_fly_drive (boat.md §9, which reads m_opt).
struct SailOutputs {
  std::vector<std::vector<wm::SailOutput>> sails;
  std::vector<float> let_fly_drive;
};

SailOutputs sail_outputs(const wm::World& w) {
  SailOutputs o;
  for (std::size_t i = 0; i < w.boat_count(); ++i) {
    const wm::Sails& s = w.boat(i).sails();
    o.sails.emplace_back();
    for (std::size_t k = 0; k < s.sail_count(); ++k) o.sails.back().push_back(s.output(k));
    o.let_fly_drive.push_back(w.boat(i).let_fly_drive());
  }
  return o;
}

bool same(const SailOutputs& a, const SailOutputs& b) {
  if (a.sails.size() != b.sails.size()) return false;
  for (std::size_t i = 0; i < a.sails.size(); ++i) {
    if (a.sails[i].size() != b.sails[i].size() || !same_bits(a.let_fly_drive[i], b.let_fly_drive[i])) return false;
    for (std::size_t k = 0; k < a.sails[i].size(); ++k) {
      const wm::SailOutput& x = a.sails[i][k];
      const wm::SailOutput& y = b.sails[i][k];
      if (!same_bits(x.k_h, y.k_h) || !same_bits(x.m_opt, y.m_opt) || !same_bits(x.beta_opt, y.beta_opt) ||
          !same_bits(x.beta_t, y.beta_t) || !same_bits(x.trim_error, y.trim_error) ||
          !same_bits(x.luff_shiver, y.luff_shiver) || x.motion != y.motion || x.backed != y.backed) {
        return false;
      }
    }
  }
  return true;
}

}  // namespace

TEST_CASE("snapshot: the tick checksum is FNV-1a 64 of the tick index and the snapshot body") {
  auto w = wm_test::full_race_world(kSeed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  while (w->tick() < 300) w->step();
  wm::SnapshotWriter sw;
  w->save(sw);
  // conventions.md §9.1 header: magic, version, tick, seed, created, n_created, entries at creation, venue id,
  // course id, then the entry list (a count and 19 bytes per boat); the body follows.
  const std::size_t header = 4 + 4 + 4 + 8 + 1 + 4 + 4 + 8 + 8 + 4 + 19 * w->boat_count();
  REQUIRE(sw.bytes().size() > header);
  std::vector<std::uint8_t> hashed{static_cast<std::uint8_t>(w->tick()), static_cast<std::uint8_t>(w->tick() >> 8),
                                   static_cast<std::uint8_t>(w->tick() >> 16),
                                   static_cast<std::uint8_t>(w->tick() >> 24)};
  hashed.insert(hashed.end(), sw.bytes().begin() + static_cast<std::ptrdiff_t>(header), sw.bytes().end());
  CHECK(w->checksum() == wm::fnv1a64(hashed));
  // A hashing writer keeps no bytes.
  wm::Fnv1a64 h;
  wm::SnapshotWriter hw(h);
  w->save(hw);
  CHECK(hw.bytes().empty());
  CHECK(h.value() == wm::fnv1a64(sw.bytes()));
}

TEST_CASE("snapshot: damaged or foreign snapshots are rejected; a world is reset and loaded again and again") {
  // The reference run: saves at two ticks (in the sequence, and after the gun with the rules live), the checksum of
  // every tick, and the sail outputs at the later save.
  auto w = wm_test::full_race_world(kSeed);
  std::string why;
  REQUIRE_MESSAGE(w->create_race(wm_test::full_race_course(), why), why);
  wm_test::Pilot pilot = wm_test::full_race_pilot();
  w->set_controller([&pilot](wm::World& world) { pilot(world); });
  const std::uint32_t gun = static_cast<std::uint32_t>(w->race().n_gun());
  const std::uint32_t ta = gun - 600, tb = gun + 300, run = 100;
  std::vector<std::uint64_t> sums(tb + run + 1, 0);
  std::vector<std::uint8_t> a, b;
  wm_test::Pilot pa{0}, pb{0};
  SailOutputs outs_b;
  while (w->tick() < tb + run) {
    if (w->tick() == ta || w->tick() == tb) {
      wm::SnapshotWriter sw;
      w->save(sw);
      (w->tick() == ta ? a : b) = sw.bytes();
      (w->tick() == ta ? pa : pb) = pilot;
      if (w->tick() == tb) outs_b = sail_outputs(*w);
    }
    const std::uint64_t c = w->step();
    sums[w->tick()] = c;
  }
  const wm::CourseData* course = &wm_test::full_race_course();

  // Damaged or foreign snapshots, into new worlds.
  std::vector<std::uint8_t> cut(b.begin(), b.end() - 3);
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(cut, course, why));
  std::vector<std::uint8_t> longer = b;
  longer.push_back(0);
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(longer, course, why));
  CHECK(why == "bytes left over after the snapshot");
  CHECK_FALSE(wm_test::full_race_world(kSeed + 1)->load(b, course, why));
  CHECK_FALSE(wm_test::full_race_world(kSeed, 5)->load(b, course, why));
  CHECK_FALSE(wm_test::full_race_world(kSeed)->load(b, nullptr, why));

  // A world that has raced a while on its own, and its twin that is never loaded.
  auto u = wm_test::full_race_world(kSeed);
  REQUIRE_MESSAGE(u->create_race(*course, why), why);
  wm_test::Pilot p = wm_test::full_race_pilot();
  u->set_controller([&p](wm::World& world) { p(world); });
  auto twin = wm_test::full_race_world(kSeed);
  REQUIRE_MESSAGE(twin->create_race(*course, why), why);
  wm_test::Pilot pt = wm_test::full_race_pilot();
  twin->set_controller([&pt](wm::World& world) { pt(world); });
  while (u->tick() < 700) {
    u->step();
    twin->step();
  }

  // Failed loads leave it as it was: same tick and checksum, and it steps on as its twin does.
  const std::uint64_t before = u->checksum();
  CHECK_FALSE(u->load(cut, course, why));
  CHECK_FALSE(u->load(b, nullptr, why));
  CHECK_FALSE(u->load(longer, course, why));
  CHECK(u->tick() == 700);
  CHECK(u->checksum() == before);
  CHECK(u->race_created());
  bool same_sums = true;
  for (int k = 0; k < 50; ++k) same_sums = same_sums && u->step() == twin->step();
  CHECK(same_sums);

  // Then it takes the later save, the earlier one, and the later one again; each continues bit for bit. The loaded
  // world re-saves to the same bytes and has the sail outputs of the saved tick (a new world's differ).
  auto continues = [&](const std::vector<std::uint8_t>& bytes, std::uint32_t t, const wm_test::Pilot& saved) {
    REQUIRE_MESSAGE(u->load(bytes, course, why), why);
    CHECK(u->tick() == t);
    CHECK(u->checksum() == sums[t]);
    wm::SnapshotWriter again;
    u->save(again);
    CHECK(again.bytes() == bytes);
    if (t == tb) CHECK(same(sail_outputs(*u), outs_b));
    p = saved;
    bool ok = true;
    for (std::uint32_t k = 1; k <= run; ++k) ok = ok && u->step() == sums[t + k];
    CHECK(ok);
  };
  continues(b, tb, pb);
  continues(a, ta, pa);
  continues(b, tb, pb);
  CHECK_FALSE(same(sail_outputs(*twin), outs_b));

  // A reset world is a new one: no race, tick 0, and it creates the race and runs as a new world does.
  u->reset();
  CHECK(u->tick() == 0);
  CHECK_FALSE(u->race_created());
  auto fresh = wm_test::full_race_world(kSeed);
  CHECK(u->checksum() == fresh->checksum());
  REQUIRE_MESSAGE(u->create_race(*course, why), why);
  REQUIRE_MESSAGE(fresh->create_race(*course, why), why);
  p = wm_test::full_race_pilot();
  wm_test::Pilot pf = wm_test::full_race_pilot();
  fresh->set_controller([&pf](wm::World& world) { pf(world); });
  same_sums = true;
  for (int k = 0; k < 100; ++k) same_sums = same_sums && u->step() == fresh->step();
  CHECK(same_sums);
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
  for (int k = 0; k < 1000; ++k) same_sums = same_sums && w->step() == v->step();
  CHECK(same_sums);
}
