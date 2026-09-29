// AI skippers (ai.md): level parameters, polar tables, a lone boat sailing the course, the snapshot of the
// skippers' memory, the finished-boat autopilot and projected finishes, and the scenario tests of §15 on boats
// placed on the course. The long fleet races are in test_ai_race.cpp (ctest label ai_long).
#include <algorithm>
#include <cmath>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "ai/ai_polar.h"
#include "ai_harness.h"
#include "course/geometry.h"
#include "doctest.h"
#include "state/checksum.h"

namespace {

using wm_test::deg;
using wm_test::kn;

// A world on the example venue with the default course, AI boats where `ai` is set and scripted boats (human
// entries that hold a heading) elsewhere, run to just after the gun, every boat started.
struct Scenario {
  std::unique_ptr<wm::World> w;
  wm::AiSkippers ai;
  std::vector<bool> is_ai;
  std::vector<float> hold;  // scripted boats: heading to hold

  explicit Scenario(const std::vector<bool>& ai_mask, float wind_kn = 11.0f, std::uint64_t seed = 5) : is_ai(ai_mask) {
    wm::WorldSetup s;
    s.venue = &wm_test::ai_venue();
    s.race_seed = seed;
    s.wind.base_speed = kn(wind_kn);
    s.wind.base_from = 0.3f;
    wm::apply_shift_preset(s.wind, wm::ShiftPreset::steady);
    s.wind.puffs_enabled = false;
    s.race.free_sailing_s = 10.0f;
    w = std::make_unique<wm::World>(s);
    for (std::size_t i = 0; i < ai_mask.size(); ++i) {
      wm::BoatEntry e = ai_mask[i] ? wm::ai_entry(&wm_test::perf("wm7"), wm::AiLevel::intermediate) : wm::BoatEntry{};
      if (!ai_mask[i]) e.perf = &wm_test::perf("wm7");
      REQUIRE(w->add_boat(e) == static_cast<std::int32_t>(i));
      if (ai_mask[i]) ai.add(static_cast<std::int32_t>(i), wm::AiLevel::intermediate);
    }
    hold.assign(ai_mask.size(), 0.0f);
    std::string why;
    REQUIRE_MESSAGE(w->create_race(wm_test::ai_default_course(), why), why);
    // To the gun with the boats held 3 L behind the line (no controller yet), then every boat put just over the
    // line in the band: the race sees the crossing and starts her.
    const wm::ResolvedCourse& co = w->course();
    const wm::Vec2 A = co.end_a(co.start()), B = co.end_b(co.start());
    auto on_line = [&](std::size_t i, float off) {
      const float u = 0.2f + 0.6f * static_cast<float>(i) / static_cast<float>(is_ai.size());
      return wm::v_add(wm::v_add(A, wm::v_scale(wm::v_sub(B, A), u)), wm::v_scale(up(), off));
    };
    bool seen = false;  // one race tick at or after the gun has seen them behind the line (race.md §4.2)
    while (!seen) {
      seen = w->race().after_gun(w->tick());
      for (std::size_t i = 0; i < is_ai.size(); ++i) {
        const wm::Vec2 p = on_line(i, -25.0f);
        w->place_boat(static_cast<std::int32_t>(i), p.x, p.y, twd(), 0.0f);
      }
      w->step();
    }
    for (std::size_t i = 0; i < is_ai.size(); ++i) {
      const wm::Vec2 p = on_line(i, 5.0f);
      w->place_boat(static_cast<std::int32_t>(i), p.x, p.y, twd(), 1.0f);
    }
    for (std::size_t i = 0; i < is_ai.size(); ++i) w->set_let_fly(static_cast<std::int32_t>(i), false);
    w->step();
    for (std::size_t i = 0; i < is_ai.size(); ++i) {
      const wm::RaceBoat& rb = w->race().boat(i);
      CAPTURE(rb.ocs);
      CAPTURE(rb.ocs_i);
      CAPTURE(rb.pre_seen);
      CAPTURE(rb.came_near);
      CAPTURE(w->race().start_s(rb.c));
      CAPTURE(static_cast<int>(w->race().state()));
      REQUIRE(rb.started);
    }
    w->set_controller([this](wm::World& world) { control(world); });
  }

  float twd() const { return w->course().twd_c; }
  wm::Vec2 up() const { return wm::dir(twd()); }                 // towards the wind
  wm::Vec2 right() const { return {up().y, -up().x}; }           // to the right looking upwind
  // A point of the first beat: `along` metres up the wind from the line's middle, `side` metres to the right.
  wm::Vec2 beat_point(float along, float side) const {
    const wm::ResolvedCourse& co = w->course();
    const wm::Vec2 mid = wm::v_mid(co.end_a(co.start()), co.end_b(co.start()));
    return wm::v_add(wm::v_add(mid, wm::v_scale(up(), along)), wm::v_scale(right(), side));
  }
  // Close-hauled headings (the AI's θ_up) on starboard (twa > 0) and port.
  float close_hauled(float tack) const {
    const wm::AiPolar pol(wm_test::perf("wm7"));
    return wm::wrap_2pi(twd() - tack * pol.theta_up(w->env(0).wind_speed_clean));
  }
  void place(std::size_t i, wm::Vec2 p, float psi) {
    const float V = w->boat(i).polar_at(w->env(i).wind_speed_clean, wm::wrap_pi(twd() - psi), w->boat(i).sails().front());
    w->place_boat(static_cast<std::int32_t>(i), p.x, p.y, psi, V);
    hold[i] = psi;
  }

  void control(wm::World& world) {
    ai.step(world);
    for (std::size_t i = 0; i < is_ai.size(); ++i) {
      if (is_ai[i]) continue;
      const float e = wm::wrap_pi(hold[i] - world.boat(i).state().psi);
      world.set_helm(static_cast<std::int32_t>(i), wm::clamp(2.5f * e, -0.6f, 0.6f));
      world.set_let_fly(static_cast<std::int32_t>(i), false);
    }
  }

  // Runs for `s` seconds; `each` is called after every step.
  void run(float s, const std::function<void()>& each = {}) {
    const std::uint32_t n = static_cast<std::uint32_t>(s / wm::DT);
    for (std::uint32_t k = 0; k < n; ++k) {
      w->step();
      if (each) each();
    }
  }
  std::int32_t penalties(std::int32_t boat) const { return w->rules().boat(static_cast<std::size_t>(boat)).received; }
};

float hull_gap(const wm::World& w, std::size_t i, std::size_t j) {
  for (const wm::PairRecord& p : w.rules().pairs()) {
    if ((p.i == static_cast<std::int32_t>(i) && p.j == static_cast<std::int32_t>(j)) ||
        (p.i == static_cast<std::int32_t>(j) && p.j == static_cast<std::int32_t>(i))) {
      return p.gap;
    }
  }
  return 1e9f;
}

bool on_port(const wm::World& w, std::size_t i) {
  return wm::wrap_pi(w.env(i).wind_from_clean - w.boat(i).state().psi) < 0.0f;
}

}  // namespace

TEST_CASE("ai: level parameters (ai.md §13)") {
  const wm::AiLevelParams e = wm::ai_level_params(wm::AiLevel::easy);
  const wm::AiLevelParams i = wm::ai_level_params(wm::AiLevel::intermediate);
  const wm::AiLevelParams x = wm::ai_level_params(wm::AiLevel::expert);
  const wm::AiLevelParams p = wm::ai_level_params(wm::AiLevel::pro);
  CHECK(e.performance_scale == 0.90f);
  CHECK(i.performance_scale == 1.00f);
  CHECK(x.performance_scale == 1.025f);
  CHECK(p.performance_scale == 1.04f);
  CHECK(e.t_final == 35.0f);
  CHECK(p.t_final == 22.0f);
  CHECK(!e.shifts);
  CHECK(p.h_up == doctest::Approx(5.0f * wm::DEG));
  CHECK(x.r_read == 250.0f);
  CHECK(e.cover == wm::AiCover::none);
  CHECK(i.cover == wm::AiCover::match_only);
  CHECK(p.cover == wm::AiCover::all);
  // "Speed only": Intermediate decisions, the level's performance scale.
  const wm::AiLevelParams so = wm::ai_level_params(wm::AiLevel::pro, true);
  CHECK(so.performance_scale == 1.04f);
  CHECK(so.t_final == i.t_final);
  CHECK(so.h_up == i.h_up);
  const wm::BoatEntry be = wm::ai_entry(&wm_test::perf("wm7"), wm::AiLevel::expert);
  CHECK(!be.human);
  CHECK(be.ai);
  CHECK(be.performance_scale == 1.025f);
}

TEST_CASE("ai: polar tables (ai.md §3.1)") {
  for (const char* cls : {"wm7", "wm12"}) {
    const wm::PerfData& perf = wm_test::perf(cls);
    const wm::AiPolar pol(perf);
    for (const float k : {6.0f, 11.0f, 16.0f, 22.0f}) {
      const float tws = kn(k);
      CAPTURE(cls);
      CAPTURE(k);
      CHECK(pol.theta_up(tws) > deg(25.0f));
      CHECK(pol.theta_up(tws) < deg(60.0f));
      CHECK(pol.theta_dn(tws) > deg(120.0f));
      CHECK(pol.theta_dn(tws) <= deg(180.0f));
      CHECK(pol.v_up(tws) > 0.5f);
      CHECK(pol.vmg_up(tws) == doctest::Approx(pol.v_up(tws) * std::cos(pol.theta_up(tws))).epsilon(0.02));
      // The optimum is an optimum: 5° either side gives less VMG.
      const float th = pol.theta_up(tws);
      CHECK(pol.speed(tws, th + deg(5.0f)) * std::cos(th + deg(5.0f)) <= pol.vmg_up(tws) + 1e-4f);
      CHECK(pol.speed(tws, th - deg(5.0f)) * std::cos(th - deg(5.0f)) <= pol.vmg_up(tws) + 1e-4f);
      const std::int32_t s = pol.best_sail(tws, deg(150.0f));
      CHECK(s >= -1);
      CHECK(pol.speed_with(tws, deg(150.0f), s) == doctest::Approx(pol.speed(tws, deg(150.0f))));
    }
  }
}

TEST_CASE("ai: a lone boat sails the default course clean") {
  wm_test::AiRaceSpec sp;
  sp.seed = 1;
  sp.levels = {wm::AiLevel::intermediate};
  const wm_test::AiRaceOutcome o = wm_test::run_ai_race(sp);
  REQUIRE(o.results.size() == 1);
  CHECK(o.results[0].place == 1);
  CHECK(o.penalties == 0);
  CHECK(o.contacts == 0);
  const wm::AiTelemetry& t = o.tel[0];
  MESSAGE("lone boat: finish ", static_cast<double>(o.results[0].t_finish_us) * 1e-6, " s, start delay ", t.start_delay,
          " s, tacks ", t.tacks, ", gybes ", t.gybes);
  CHECK(t.start_delay >= 0.0f);
  CHECK(t.start_delay < 8.0f);
  CHECK(t.stuck_s == 0.0f);
  // Two beats of about 0.2 nm: a handful of tacks, not dozens.
  CHECK(t.tacks >= 2);
  CHECK(t.tacks <= 14);
}

TEST_CASE("ai: the skippers' memory saved mid-race and reloaded continues identically (ai.md §16)") {
  wm_test::AiRaceSpec sp;
  sp.seed = 11;
  sp.levels = {wm::AiLevel::easy, wm::AiLevel::intermediate, wm::AiLevel::expert, wm::AiLevel::pro};
  const wm::CourseData& course = wm_test::ai_default_course();
  // Saved in the start sequence (-100 s) and on the first beat (+90 s) of one unbroken run; each save is loaded into
  // a new world with new skippers and compared with the unbroken run for 1500 ticks.
  const std::uint32_t n_gun = static_cast<std::uint32_t>(10.0f / wm::DT) + 3600u;
  const std::uint32_t at[2] = {n_gun - 2000u, n_gun + 1800u};
  const std::uint32_t len = 1500u;
  auto w = wm_test::ai_world(sp);
  std::string why;
  REQUIRE(w->create_race(course, why));
  wm::AiSkippers ai;
  wm_test::ai_add_all(ai, sp);
  w->set_controller([&ai](wm::World& world) { ai.step(world); });
  std::vector<std::uint64_t> sums(at[1] + len + 1, 0);
  std::vector<std::uint8_t> world_bytes[2], ai_bytes[2];
  while (w->tick() < at[1] + len && w->race().state() != wm::RaceState::closed) {
    for (int k = 0; k < 2; ++k) {
      if (w->tick() != at[k]) continue;
      wm::SnapshotWriter sw, sa;
      w->save(sw);
      ai.save(sa, *w);
      world_bytes[k] = sw.bytes();
      ai_bytes[k] = sa.bytes();
    }
    const std::uint64_t c = w->step();
    sums[w->tick()] = c;
  }
  REQUIRE(w->tick() == at[1] + len);
  for (int k = 0; k < 2; ++k) {
    CAPTURE(at[k]);
    auto w2 = wm_test::ai_world(sp);
    wm::AiSkippers ai2;
    REQUIRE_MESSAGE(w2->load(world_bytes[k], &course, why), why);
    REQUIRE_MESSAGE(ai2.load(ai_bytes[k], *w2, why), why);
    // Saving the loaded skippers gives the same bytes.
    wm::SnapshotWriter sa2;
    ai2.save(sa2, *w2);
    CHECK(sa2.bytes() == ai_bytes[k]);
    w2->set_controller([&ai2](wm::World& world) { ai2.step(world); });
    std::uint32_t first_diff = 0;
    while (w2->tick() < at[k] + len) {
      const std::uint64_t c = w2->step();
      if (c != sums[w2->tick()] && first_diff == 0) first_diff = w2->tick();
    }
    CHECK(first_diff == 0);
  }
}

TEST_CASE("ai: the memory block is checked against the world") {
  wm_test::AiRaceSpec sp;
  sp.seed = 3;
  sp.levels = {wm::AiLevel::intermediate, wm::AiLevel::intermediate};
  auto w = wm_test::ai_world(sp);
  std::string why;
  REQUIRE(w->create_race(wm_test::ai_default_course(), why));
  wm::AiSkippers ai;
  wm_test::ai_add_all(ai, sp);
  w->set_controller([&ai](wm::World& world) { ai.step(world); });
  for (int k = 0; k < 400; ++k) w->step();
  wm::SnapshotWriter sa;
  ai.save(sa, *w);
  const std::vector<std::uint8_t>& bytes = sa.bytes();
  {
    wm::AiSkippers b;
    CHECK(b.load(bytes, *w, why));
    CHECK(b.has(0));
    CHECK(b.has(1));
  }
  {
    wm::AiSkippers b;
    const std::vector<std::uint8_t> cut(bytes.begin(), bytes.end() - 3);
    CHECK(!b.load(cut, *w, why));
  }
  {
    wm::AiSkippers b;
    std::vector<std::uint8_t> more = bytes;
    more.push_back(0);
    CHECK(!b.load(more, *w, why));
  }
  {
    // A block of another tick.
    w->step();
    wm::AiSkippers b;
    CHECK(!b.load(bytes, *w, why));
  }
}

TEST_CASE("ai: projected finishes when the human retires (race.md §7.2) and the finished-boat autopilot (§6.2)") {
  // Three AI boats and one human entry sailed by an AI (take_over): the human retires once the AI boats have
  // started, the race closes at once and the AI boats still racing get projected finishes.
  wm_test::AiRaceSpec sp;
  sp.seed = 7;
  sp.levels = {wm::AiLevel::pro, wm::AiLevel::intermediate, wm::AiLevel::easy};
  auto w = wm_test::ai_world(sp);
  wm::BoatEntry human;
  human.perf = &wm_test::perf("wm7");
  REQUIRE(w->add_boat(human) == 3);
  std::string why;
  REQUIRE(w->create_race(wm_test::ai_default_course(), why));
  wm::AiSkippers ai;
  wm_test::ai_add_all(ai, sp);
  ai.take_over(3);
  w->set_controller([&ai](wm::World& world) { ai.step(world); });
  bool retired = false;
  for (int k = 0; k < 40000 && w->race().state() != wm::RaceState::closed; ++k) {
    w->step();
    const wm::Race& r = w->race();
    if (!retired && r.boat(0).started && r.boat(1).started && r.boat(2).started && r.race_time(w->tick()) > 120.0f) {
      w->retire(3);
      retired = true;
    }
  }
  REQUIRE(w->race().state() == wm::RaceState::closed);
  int projected = 0;
  for (const wm::ResultRow& r : w->race().results()) {
    if (r.projected) {
      ++projected;
      CHECK(r.place >= 1);
      CHECK(static_cast<double>(r.t_finish_us) * 1e-6 >= 120.0);
    }
  }
  CHECK(projected == 3);

  // The autopilot: a lone AI boat that finished goes 5 L beyond the line and 2·(1 + 1)·L along it and stops.
  wm_test::AiRaceSpec one;
  one.seed = 1;
  one.levels = {wm::AiLevel::intermediate};
  auto w1 = wm_test::ai_world(one);
  REQUIRE(w1->create_race(wm_test::ai_default_course(), why));
  wm::AiSkippers ai1;
  wm_test::ai_add_all(ai1, one);
  w1->set_controller([&ai1](wm::World& world) { ai1.step(world); });
  std::uint32_t finished_at = 0;
  for (int k = 0; k < 40000; ++k) {
    w1->step();
    if (finished_at == 0 && w1->race().boat(0).finished) finished_at = w1->tick();
    if (finished_at != 0 && w1->tick() > finished_at + 1200u) break;
  }
  REQUIRE(finished_at != 0);
  const wm::BoatState& s = w1->boat(0).state();
  const float L = w1->race().boat(0).L;
  const wm::ResolvedCourse& co = w1->course();
  const float beyond = w1->race().finish_s({s.pos_x, s.pos_y});
  const wm::Vec2 fmid = wm::v_mid(co.end_a(co.finish()), co.end_b(co.finish()));
  // 5 L beyond and 4 L along: about 6.4 L from the middle of the line.
  const float from_mid = wm::v_dist(fmid, {s.pos_x, s.pos_y});
  CHECK(from_mid > 4.0f * L);
  CHECK(from_mid < 9.0f * L);
  MESSAGE("finished boat 60 s later: ", beyond / L, " L beyond the line, speed ", s.v);
  CHECK(beyond > 3.0f * L);
  CHECK(beyond < 8.0f * L);
  CHECK(s.v < 1.5f);
}

TEST_CASE("ai scenario: a port boat ducks a starboard boat (ai.md §15)") {
  // Boat 0 (AI) on port, boat 1 (scripted) on starboard, on a collision course 45 m from the crossing.
  Scenario sc({true, false});
  const float stbd = sc.close_hauled(1.0f), port = sc.close_hauled(-1.0f);
  const wm::Vec2 X = sc.beat_point(150.0f, 0.0f);  // where the tracks cross
  sc.place(0, wm::v_sub(X, wm::v_scale(wm::dir(port), 45.0f)), port);
  sc.place(1, wm::v_sub(X, wm::v_scale(wm::dir(stbd), 45.0f)), stbd);
  float gmin = 1e9f;
  bool avoided = false;
  sc.run(30.0f, [&]() {
    gmin = std::min(gmin, hull_gap(*sc.w, 0, 1));
    if (sc.ai.debug(0).tactic == wm::AiTactic::KeepClear) avoided = true;
  });
  MESSAGE("duck: min gap ", gmin, " m, penalties ", sc.penalties(0));
  CHECK(avoided);
  CHECK(sc.penalties(0) == 0);
  CHECK(sc.penalties(1) == 0);
  CHECK(gmin > 0.5f);
}

TEST_CASE("ai scenario: the right-of-way boat holds her course while a give-way boat ducks (ai.md §7.4)") {
  // Boat 0 (AI) on starboard, boat 1 (scripted) on port aimed to pass well astern of her.
  Scenario sc({true, false});
  const float stbd = sc.close_hauled(1.0f), port = sc.close_hauled(-1.0f);
  const wm::Vec2 X = sc.beat_point(150.0f, 0.0f);
  sc.place(0, wm::v_sub(X, wm::v_scale(wm::dir(stbd), 40.0f)), stbd);
  sc.place(1, wm::v_sub(wm::v_sub(X, wm::v_scale(wm::dir(stbd), 55.0f)), wm::v_scale(wm::dir(port), 40.0f)), port);
  float max_dev = 0.0f;
  sc.run(25.0f, [&]() {
    const float d = std::fabs(wm::wrap_pi(sc.w->boat(0).state().psi - stbd));
    max_dev = std::max(max_dev, d);
  });
  MESSAGE("hold course: largest heading change ", max_dev / wm::DEG, " deg");
  CHECK(sc.penalties(0) == 0);
  CHECK(max_dev < deg(12.0f));
}

TEST_CASE("ai scenario: no tack into the path of a starboard boat within 3 L (ai.md §7.3)") {
  // Boat 0 (AI) on starboard far to the right of the course (past the corridor, so she wants to tack); boat 1
  // (scripted) on starboard 2 L to windward and a little astern: a tack onto port would cross her bow.
  Scenario sc({true, false});
  const float stbd = sc.close_hauled(1.0f);
  const wm::Vec2 P0 = sc.beat_point(200.0f, 140.0f);
  sc.place(0, P0, stbd);
  const float L = sc.w->race().boat(0).L;
  const wm::Vec2 wind_side{wm::dir(stbd).y, -wm::dir(stbd).x};  // starboard: the wind comes from the right
  sc.place(1, wm::v_sub(wm::v_add(P0, wm::v_scale(wind_side, 2.0f * L)), wm::v_scale(wm::dir(stbd), 0.5f * L)), stbd);
  bool tacked_close = false;
  sc.run(20.0f, [&]() {
    if (on_port(*sc.w, 0) && hull_gap(*sc.w, 0, 1) < 3.0f * L) tacked_close = true;
  });
  CHECK(!tacked_close);
  CHECK(sc.penalties(0) == 0);
}

TEST_CASE("ai scenario: out of a boat's shadow on a beat by tacking (ai.md §8)") {
  // Boat 1 (scripted) on starboard; boat 0 (AI) 2.5 L straight downwind of her, same heading.
  Scenario sc({true, false});
  const float stbd = sc.close_hauled(1.0f);
  const wm::Vec2 S = sc.beat_point(200.0f, -40.0f);
  sc.place(1, S, stbd);
  sc.run(1.0f);
  const float L = sc.w->race().boat(0).L;
  // In her blanket: 2.5 L down her apparent wind (wind_shadow.md §4).
  const wm::Vec2 Sb{sc.w->boat(1).state().pos_x, sc.w->boat(1).state().pos_y};
  sc.place(0, wm::v_sub(Sb, wm::v_scale(wm::dir(sc.w->boat(1).state().awd_from), 2.5f * L)), stbd);
  bool bad = false, tacked = false;
  float d_at = 0.0f, d_end = 0.0f;
  sc.run(30.0f, [&]() {
    if (!bad && sc.ai.debug(0).tactic == wm::AiTactic::BadAir) {
      bad = true;
      d_at = sc.ai.debug(0).d;
    }
    if (bad && on_port(*sc.w, 0)) tacked = true;
    d_end = sc.ai.debug(0).d;
  });
  MESSAGE("shadow, tack: deficit at the trigger ", d_at, ", 30 s after placing ", d_end);
  CHECK(bad);
  CHECK(tacked);
  CHECK(d_end < d_at);
  CHECK(sc.penalties(0) == 0);
}

TEST_CASE("ai scenario: out of a boat's shadow by footing when a boat on the other tack blocks the tack (ai.md §8)") {
  // As above, plus boat 2 (scripted) on port on the AI's windward hip, so a tack would have to duck her.
  Scenario sc({true, false, false});
  const float stbd = sc.close_hauled(1.0f), port = sc.close_hauled(-1.0f);
  const wm::Vec2 S = sc.beat_point(200.0f, -40.0f);
  sc.place(1, S, stbd);
  sc.run(1.0f);
  const float L = sc.w->race().boat(0).L;
  const wm::Vec2 Sb{sc.w->boat(1).state().pos_x, sc.w->boat(1).state().pos_y};
  const wm::Vec2 P0 = wm::v_sub(Sb, wm::v_scale(wm::dir(sc.w->boat(1).state().awd_from), 2.5f * L));
  sc.place(0, P0, stbd);
  const wm::Vec2 wind_side{wm::dir(stbd).y, -wm::dir(stbd).x};
  sc.place(2, wm::v_sub(wm::v_add(P0, wm::v_scale(wind_side, 2.5f * L)), wm::v_scale(wm::dir(stbd), 1.5f * L)), port);
  bool bad = false, tacked_early = false;
  float t = 0.0f;
  sc.run(12.0f, [&]() {
    t += wm::DT;
    if (sc.ai.debug(0).tactic == wm::AiTactic::BadAir) bad = true;
    if (t < 8.0f && on_port(*sc.w, 0)) tacked_early = true;
  });
  CHECK(bad);
  CHECK(!tacked_early);
  CHECK(sc.penalties(0) == 0);
}
