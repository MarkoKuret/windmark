// Headless sail tests (sails.md §8) on the shipped classes, plus requests, let-fly and luffing (boat.md §7.5).
#include <cmath>
#include <string>
#include <vector>

#include "boat_harness.h"

using namespace wm_test;
using wm::DT;
using wm::SailPhase;
using wm::SailRequest;

namespace {

struct Wm7 {
  const wm::PerfData& p = perf_no_helm_balance("wm7");  // the sail tests sail with the helm centred
  const std::int32_t main = p.main_sail;
  const std::int32_t jib = p.find_sail("jib");
  const std::int32_t kite = p.find_sail("kite");
};

const wm::SailHandling& handling(const wm::PerfData& p, std::int32_t s) {
  return p.sails[static_cast<std::size_t>(s)].handling;
}

// Ticks until `done` holds (checked after each step), -1 if not within `max_s` seconds.
template <typename F>
int ticks_until(Sim& sim, float max_s, F done) {
  const int n = static_cast<int>(max_s / DT);
  for (int i = 1; i <= n; ++i) {
    sim.step();
    if (done()) return i;
  }
  return -1;
}

}  // namespace

// §8.1: at 10 kn TWS, 90 deg TWA, hoisting the spinnaker with the jib up: the spinnaker drives from
// prepare_hoist_time + hoist_time after the request, the jib is down after the sum of all six steps.
TEST_CASE("sails: peel timing") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  sim.place(deg(90.0f), 2.0f, c.jib);
  REQUIRE(sim.boat.sails().front() == c.jib);
  const float tws = sim.s().tws, ta = std::fabs(sim.s().twa);
  const wm::SailHandling& k = handling(c.p, c.kite);
  const wm::SailHandling& j = handling(c.p, c.jib);
  const float t_up = k.prepare_hoist_time.at(tws, ta) + k.hoist_time.at(tws, ta);
  const float t_down = t_up + j.prepare_drop_time.at(tws, ta) + j.drop_time.at(tws, ta);

  REQUIRE(sim.boat.hoist(c.kite) == SailRequest::accepted);
  std::vector<SailPhase> kite_phases, jib_phases;
  int tick_up = -1, tick_down = -1;
  bool slowed = false;
  for (int i = 1; i <= static_cast<int>((t_down + 2.0f) / DT); ++i) {
    sim.step();
    for (const wm::SailPhaseEvent& e : sim.boat.sails().events()) {
      (e.sail == c.kite ? kite_phases : jib_phases).push_back(e.phase);
    }
    if (tick_up < 0 && sim.boat.sails().front() == c.kite) tick_up = i;
    if (tick_down < 0 && sim.boat.sails().sail(static_cast<std::size_t>(c.jib)).phase == SailPhase::down)
      tick_down = i;
    if (sim.boat.outputs().man_coef < 1.0f) slowed = true;
    // Until its `up` step the new sail does not drive: the jib config stays in force.
    if (tick_up < 0) CHECK(sim.boat.sails().front() == c.jib);
  }
  MESSAGE("kite drives after ", tick_up * DT, " s (", t_up, " s), jib down after ", tick_down * DT, " s (", t_down,
          " s)");
  // The change runs on 50 ms ticks: the step completes in the tick that reaches its end time.
  CHECK(tick_up * DT >= t_up - 1e-3f);
  CHECK(tick_up * DT < t_up + DT + 1e-3f);
  CHECK(tick_down * DT >= t_down - 1e-3f);
  CHECK(tick_down * DT < t_down + DT + 1e-3f);
  CHECK(kite_phases == std::vector<SailPhase>{SailPhase::prepare_hoist, SailPhase::hoisting, SailPhase::up});
  CHECK(jib_phases == std::vector<SailPhase>{SailPhase::prepare_drop, SailPhase::dropping, SailPhase::down});
  CHECK(slowed);
  CHECK_FALSE(sim.boat.sails().busy());
}

// §8.2: cancelling a hoist halfway through `hoisting` brings the sail's progress from 0.5 back to 0 over half the
// hoist time; it ends down and the front sail never changes.
TEST_CASE("sails: cancel a hoist") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  sim.place(deg(90.0f), 2.0f, c.jib);
  const auto& kite = [&]() -> const wm::SailState& { return sim.boat.sails().sail(static_cast<std::size_t>(c.kite)); };
  REQUIRE(sim.boat.hoist(c.kite) == SailRequest::accepted);
  REQUIRE(ticks_until(sim, 20.0f, [&] { return kite().phase == SailPhase::hoisting && kite().progress >= 0.5f; }) > 0);
  const float p0 = kite().progress;
  CHECK(sim.boat.hoist(c.p.find_sail("kite")) == SailRequest::rejected);  // anything but the cancel is rejected
  REQUIRE(sim.boat.hoist(c.jib) == SailRequest::accepted);
  const float hoist = handling(c.p, c.kite).hoist_time.at(sim.s().tws, std::fabs(sim.s().twa));
  float last = p0;
  bool monotonic = true, front_kept = true;
  const int ticks = ticks_until(sim, 20.0f, [&] {
    if (kite().progress > last + 1e-6f) monotonic = false;
    last = kite().progress;
    if (sim.boat.sails().front() != c.jib) front_kept = false;
    return kite().phase == SailPhase::down;
  });
  MESSAGE("cancelled at progress ", p0, ", down after ", ticks * DT, " s (", p0 * hoist, " s expected)");
  CHECK(ticks * DT >= p0 * hoist - 1e-3f);
  CHECK(ticks * DT < p0 * hoist + DT + 1e-3f);
  CHECK(monotonic);
  CHECK(front_kept);
  CHECK(kite().progress == 0.0f);
  CHECK(sim.boat.sails().front() == c.jib);
  CHECK_FALSE(sim.boat.sails().busy());
}

// sails.md §4.2: a lone drop is cancelled by asking for the same sail; it comes back up from where it was.
TEST_CASE("sails: cancel a drop") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  sim.place(deg(60.0f), 2.0f, c.jib);
  const auto& jib = [&]() -> const wm::SailState& { return sim.boat.sails().sail(static_cast<std::size_t>(c.jib)); };
  REQUIRE(sim.boat.drop_front() == SailRequest::accepted);
  REQUIRE(ticks_until(sim, 20.0f, [&] { return jib().phase == SailPhase::dropping && jib().progress >= 0.5f; }) > 0);
  const float p0 = jib().progress;
  REQUIRE(sim.boat.hoist(c.jib) == SailRequest::accepted);
  const float drop = handling(c.p, c.jib).drop_time.at(sim.s().tws, std::fabs(sim.s().twa));
  const int ticks = ticks_until(sim, 20.0f, [&] { return !sim.boat.sails().busy(); });
  MESSAGE("drop cancelled at ", p0, ", up again after ", ticks * DT, " s (", p0 * drop, " s expected)");
  CHECK(ticks * DT >= p0 * drop - 1e-3f);
  CHECK(ticks * DT < p0 * drop + DT + 1e-3f);
  CHECK(jib().phase == SailPhase::up);
  CHECK(sim.boat.sails().front() == c.jib);

  // Cancelling during prepare_drop puts the sail straight back up in the next tick.
  REQUIRE(sim.boat.drop_front() == SailRequest::accepted);
  sim.step();
  REQUIRE(jib().phase == SailPhase::prepare_drop);
  REQUIRE(sim.boat.hoist(c.jib) == SailRequest::accepted);
  sim.step();
  CHECK(jib().phase == SailPhase::up);
  CHECK_FALSE(sim.boat.sails().busy());
}

// sails.md §4.2: requests that do not apply are rejected and change nothing.
TEST_CASE("sails: rejected requests") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  sim.place(deg(90.0f), 2.0f, c.jib);
  CHECK(sim.boat.hoist(c.jib) == SailRequest::rejected);   // already up
  CHECK(sim.boat.hoist(c.main) == SailRequest::rejected);  // the main is never hoisted
  CHECK(sim.boat.hoist(-1) == SailRequest::rejected);
  CHECK(sim.boat.hoist(99) == SailRequest::rejected);
  CHECK_FALSE(sim.boat.sails().busy());
  REQUIRE(sim.boat.hoist(c.kite) == SailRequest::accepted);
  CHECK(sim.boat.drop_front() == SailRequest::rejected);   // busy
  CHECK(sim.boat.hoist(c.kite) == SailRequest::rejected);  // busy, not a cancel
  CHECK(sim.boat.sails().queue_len() == 6);

  Sim bare("wm7", 10.0f, 0.0f);
  bare.place(deg(90.0f), 2.0f, -1);
  CHECK(bare.boat.drop_front() == SailRequest::rejected);  // nothing to drop
  REQUIRE(bare.boat.hoist(c.jib) == SailRequest::accepted);
  CHECK(bare.boat.sails().queue_len() == 3);               // no old sail to peel
  CHECK(bare.boat.sails().front() == -1);
}

// sails.md §4.2: with no front sail up, drop_front() cancels a first hoist (there is no hoist(F) to ask for).
TEST_CASE("sails: cancel a first hoist") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  sim.place(deg(90.0f), 2.0f, -1);
  const auto& jib = [&]() -> const wm::SailState& { return sim.boat.sails().sail(static_cast<std::size_t>(c.jib)); };
  REQUIRE(sim.boat.hoist(c.jib) == SailRequest::accepted);
  REQUIRE(ticks_until(sim, 20.0f, [&] { return jib().phase == SailPhase::hoisting && jib().progress >= 0.5f; }) > 0);
  const float p0 = jib().progress;
  REQUIRE(sim.boat.drop_front() == SailRequest::accepted);
  const float hoist = handling(c.p, c.jib).hoist_time.at(sim.s().tws, std::fabs(sim.s().twa));
  const int ticks = ticks_until(sim, 20.0f, [&] { return jib().phase == SailPhase::down; });
  MESSAGE("first hoist cancelled at ", p0, ", down after ", ticks * DT, " s (", p0 * hoist, " s expected)");
  CHECK(ticks * DT >= p0 * hoist - 1e-3f);
  CHECK(ticks * DT < p0 * hoist + DT + 1e-3f);
  CHECK(sim.boat.sails().front() == -1);
  CHECK_FALSE(sim.boat.sails().busy());

  // Cancelled during prepare_hoist: down in the next tick, never driving.
  REQUIRE(sim.boat.hoist(c.jib) == SailRequest::accepted);
  sim.step();
  REQUIRE(jib().phase == SailPhase::prepare_hoist);
  REQUIRE(sim.boat.drop_front() == SailRequest::accepted);
  sim.step();
  CHECK(jib().phase == SailPhase::down);
  CHECK(sim.boat.sails().front() == -1);
  CHECK_FALSE(sim.boat.sails().busy());
}

// §8.3: in a tack the sails swing to the new side within 2 s and, with auto-trim, their trim error returns within
// 1 deg of 0.
TEST_CASE("sails: tack swings the sails across") {
  const Wm7 c;
  const wm::PerfData& p = c.p;
  Sim sim(p, 10.0f, 0.0f);
  const float twa = deg(42.0f);
  sim.place(twa, 2.5f, c.jib);
  sim.run(20.0f);
  const auto side_ok = [&](std::int32_t s) {
    const float b = sim.boat.sails().sail(static_cast<std::size_t>(s)).beta;
    return wm::sgn(b) == -wm::sgn(sim.s().awa) && std::fabs(b) > deg(1.0f);
  };
  int flip = -1, jib_across = -1, main_across = -1;
  bool turning = true;
  for (int i = 1; i <= static_cast<int>(40.0f / DT); ++i) {
    if (turning) {
      sim.boat.set_helm(0.5f);
      if (sim.s().twa < -(twa - deg(8.0f))) turning = false;
    } else {
      sim.steer_twa(-twa);
    }
    sim.step();
    if (flip < 0 && sim.s().awa < 0.0f) flip = i;
    if (flip > 0 && jib_across < 0 && side_ok(c.jib)) jib_across = i;
    if (flip > 0 && main_across < 0 && side_ok(c.main)) main_across = i;
  }
  REQUIRE(flip > 0);
  const float t_jib = (jib_across - flip) * DT, t_main = (main_across - flip) * DT;
  const float eps_jib = sim.boat.sails().output(static_cast<std::size_t>(c.jib)).trim_error;
  const float eps_main = sim.boat.sails().output(static_cast<std::size_t>(c.main)).trim_error;
  MESSAGE("jib across ", t_jib, " s, main across ", t_main, " s after the wind crossed the bow; eps jib ",
          to_deg(eps_jib), " deg, main ", to_deg(eps_main), " deg");
  CHECK(jib_across > 0);
  CHECK(main_across > 0);
  CHECK(t_jib <= 2.0f);
  CHECK(t_main <= 2.0f);
  CHECK(std::fabs(eps_jib) <= deg(1.0f));
  CHECK(std::fabs(eps_main) <= deg(1.0f));
}

// §8.4: in a gybe the asymmetric spinnaker goes round the bow: its angle passes through +-pi and settles on the new
// side, never through 0. The main swings across the stern.
TEST_CASE("sails: asymmetric spinnaker gybe") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 12.0f, 0.0f);
  const float twa = deg(145.0f);
  sim.place(twa, c.p.config_for(c.kite)->polar.at(kn(12.0f), twa), c.kite);
  sim.run(20.0f);
  const auto beta = [&](std::int32_t s) { return sim.boat.sails().sail(static_cast<std::size_t>(s)).beta; };
  const float start_side = wm::sgn(beta(c.kite));
  float min_abs = 10.0f, max_abs = 0.0f;
  bool crossed_forward = false, crossed_aft = false;
  float prev = beta(c.kite);
  bool gybing = true;
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    if (gybing) {
      sim.boat.set_helm(-0.4f);  // bear away through dead downwind onto port
      if (sim.s().twa < 0.0f && sim.s().twa > -twa - deg(5.0f)) gybing = false;
    } else {
      sim.steer_twa(-twa, 0.4f);
    }
    sim.step();
    const float b = beta(c.kite);
    if (wm::sgn(b) != wm::sgn(prev)) {
      if (std::fabs(b) > wm::HALF_PI) crossed_forward = true;
      else crossed_aft = true;
    }
    min_abs = wm::min(min_abs, std::fabs(b));
    max_abs = wm::max(max_abs, std::fabs(b));
    prev = b;
  }
  const float eps = sim.boat.sails().output(static_cast<std::size_t>(c.kite)).trim_error;
  MESSAGE("kite: largest |beta| ", to_deg(max_abs), " deg, smallest ", to_deg(min_abs), " deg, final eps ",
          to_deg(eps), " deg");
  CHECK(crossed_forward);
  CHECK_FALSE(crossed_aft);
  CHECK(max_abs > deg(170.0f));
  CHECK(wm::sgn(beta(c.kite)) == -start_side);
  CHECK(wm::sgn(beta(c.kite)) == -wm::sgn(sim.s().awa));
  CHECK(std::fabs(eps) <= deg(1.0f));
  CHECK(wm::sgn(beta(c.main)) == -wm::sgn(sim.s().awa));
}

// §8.5: with the manual sheet fixed, turning from 45 to 90 deg AWA over-sheets the sails (eps < 0) and the speed
// falls below the polar by the trim_speed factor.
TEST_CASE("sails: manual sheet over-sheeted on a reach") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  const wm::ConfigPerf& cfg = *c.p.config_for(c.jib);
  // Sheet so that the jib sits at its optimum at 45 deg AWA.
  const wm::SailPerf& js = c.p.sails[static_cast<std::size_t>(c.jib)];
  const float u = (cfg.optimal_front.at(kn(10.0f), deg(45.0f)) - js.sheet_min) / (js.sheet_max - js.sheet_min);
  sim.place(deg(60.0f), 2.5f, c.jib, /*auto_trim=*/false);
  sim.boat.set_sheet(u);
  // Steer to 45 deg AWA, then to 90 deg AWA.
  for (float target_awa : {45.0f, 90.0f}) {
    for (int i = 0; i < static_cast<int>(60.0f / DT); ++i) {
      const float e = wm::wrap_pi(sim.s().awa - deg(target_awa));
      sim.boat.set_helm(wm::clamp(2.0f * e, -0.3f, 0.3f));
      sim.step();
    }
    const float eps = sim.boat.sails().driving_trim_error();
    const wm::BoatOutputs& o = sim.boat.outputs();
    MESSAGE("AWA ", to_deg(sim.s().awa), " deg: eps ", to_deg(eps), " deg, trim_speed ", o.trim_speed, ", v ",
            to_kn(sim.s().v), " kn, polar ", to_kn(o.polar_speed), " kn");
    if (target_awa == 45.0f) {
      CHECK(std::fabs(eps) <= deg(1.0f));
    } else {
      CHECK(eps < -deg(5.0f));
      CHECK(o.trim_speed < 0.99f);
      const float expect = o.polar_speed * o.trim_speed * o.heel_coef;
      CHECK(sim.s().v == doctest::Approx(expect).epsilon(0.03));
      CHECK(sim.s().v < 0.99f * o.polar_speed);
    }
  }
}

// boat.md §7.5: eased past the optimum the sails luff and lose drive; let-fly runs every sheet out to fully eased,
// on a reach that is the wind line: the drive goes to zero at once and the boat slows along the deceleration law;
// released, it sails again.
TEST_CASE("sails: luffing and let-fly") {
  const Wm7 c;
  Sim sim(perf_no_helm_balance("wm7"), 10.0f, 0.0f);
  const float twa = deg(70.0f);
  const float v0 = c.p.config_for(c.jib)->polar.at(kn(10.0f), twa);
  sim.place(twa, v0, c.jib, /*auto_trim=*/false);
  sim.boat.set_sheet(1.0f);  // fully eased
  sim.run(40.0f);
  const float eps_luff = sim.boat.sails().driving_trim_error();
  MESSAGE("eased: eps ", to_deg(eps_luff), " deg, trim_speed ", sim.boat.outputs().trim_speed, ", v ",
          to_kn(sim.s().v), " kn of ", to_kn(v0));
  CHECK(eps_luff > deg(5.0f));
  CHECK(sim.s().v < 0.9f * v0);

  sim.boat.set_auto_trim(true);
  sim.run(40.0f);
  const float v_trim = sim.s().v;
  CHECK(v_trim == doctest::Approx(v0).epsilon(0.03));

  // sails.md §5.3: let fly runs the sheet out to fully eased; at speed the apparent wind lies inside the jib's
  // fully eased angle (68 deg), so the wind line holds the sail there and it flogs. The drive goes at once.
  sim.boat.set_let_fly(true);
  sim.step();
  CHECK(sim.boat.outputs().trim_speed == 0.0f);
  sim.run(2.0f);
  const std::size_t j = static_cast<std::size_t>(c.jib);
  const wm::SailOutput& jo = sim.boat.sails().output(j);
  const float off_line = std::fabs(sim.boat.sails().sail(j).beta + sim.s().awa);
  const wm::BoatOutputs& o = sim.boat.outputs();
  MESSAGE("let fly 2 s: jib ", to_deg(off_line), " deg off the wind line, eps ", to_deg(jo.trim_error),
          " deg, shiver ", jo.luff_shiver, ", trim_speed ", o.trim_speed, ", v ", to_kn(sim.s().v), " kn of ",
          to_kn(v_trim));
  CHECK(off_line < deg(1.0f));
  CHECK(jo.luff_shiver > 0.9f);
  CHECK(jo.trim_error > deg(5.0f));
  // sails.md §6: no drive with the sail on the wind line (the apparent wind is forward of the beam); the boat
  // coasts down along the deceleration law and the flogging sails brake it (boat.md §5.8).
  CHECK(o.trim_speed == 0.0f);
  CHECK(o.target_speed == 0.0f);
  // Slowed down the apparent wind swings aft of the fully eased angle: the sail stays there, never beyond it,
  // and draws a little (the table's value for that trim).
  sim.run(18.0f);
  const float lim = c.p.sails[j].sheet_max;
  MESSAGE("let fly 20 s: jib at ", to_deg(std::fabs(sim.boat.sails().sail(j).beta)), " deg (fully eased ",
          to_deg(lim), "), awa ", to_deg(std::fabs(sim.s().awa)), ", trim_speed ", o.trim_speed, ", v ",
          to_kn(sim.s().v), " kn");
  CHECK(std::fabs(sim.boat.sails().sail(j).beta) <= lim + 1e-5f);
  CHECK(o.trim_speed < 0.25f);
  CHECK(sim.s().v < 0.6f * v_trim);
  CHECK(sim.s().v >= 0.0f);

  sim.boat.set_let_fly(false);
  sim.run(40.0f);
  CHECK(sim.s().v > 0.8f * v_trim);
}

// sails.md §5.5: a symmetric spinnaker is re-set, not sheeted: its angle is its target at once (the class files
// carry only asymmetric kites, so the wm7 kite is relabelled for this check).
TEST_CASE("sails: symmetric spinnaker swaps sides at once") {
  wm::PerfData p = perf("wm7");
  const std::int32_t kite = p.find_sail("kite");
  p.sails[static_cast<std::size_t>(kite)].type = wm::SailType::spinnaker_sym;
  Sim sim(p, 12.0f, 0.0f);
  sim.place(deg(150.0f), 3.0f, kite);
  sim.run(5.0f);
  const float before = sim.boat.sails().sail(static_cast<std::size_t>(kite)).beta;
  wm::BoatState& s = sim.boat.mutable_state();
  s.psi = wm::wrap_2pi(s.psi - deg(60.0f));  // TWA 150 -> 210 = -150: wind now on the other side
  sim.step();
  const float after = sim.boat.sails().sail(static_cast<std::size_t>(kite)).beta;
  CHECK(wm::sgn(before) == -wm::sgn(after));
  CHECK(std::fabs(sim.boat.sails().output(static_cast<std::size_t>(kite)).trim_error) < deg(0.01f));
}

// sails.md §6: every config's trim_heel is 0 where the driving sail lies on the wind line (eps = |awa| - m_opt, at
// least 0.5 deg past the optimum), and trim_speed too with the apparent wind forward of the beam, at any wind and
// angle the core can look them up at, not only on the table's grid. Abaft the beam trim_speed holds the let-fly
// share of the polar (the windage pushes the boat along), below 1.
TEST_CASE("sails: trim tables are 0 on the wind line") {
  for (const std::string cls : {"wm7", "wm12"}) {
    const wm::PerfData& p = perf(cls);
    for (const wm::ConfigPerf& c : p.configs) {
      const std::int32_t drive = c.front_sail >= 0 ? c.front_sail : p.main_sail;
      const wm::SailPerf& sp = p.sails[static_cast<std::size_t>(drive)];
      const wm::Table& opt = c.front_sail >= 0 ? c.optimal_front : c.optimal_main;
      REQUIRE(c.trim_speed.present);
      REQUIRE(c.trim_heel.present);
      float worst_s = 0.0f, worst_h = 0.0f, worst_push = 0.0f;
      for (int it = 1; it <= 80; ++it) {
        const float tws = 0.25f * static_cast<float>(it);
        for (int ia = 30; ia <= 1800; ++ia) {
          const float aa = deg(0.1f * static_cast<float>(ia));
          const float m_opt = wm::clamp(opt.at(tws, aa), sp.sheet_min, sp.sheet_max);
          // Within the first trim-error step (0.5 deg) of the optimum the sail is at its optimum, which there lies
          // on the wind line (no-go and broached cells): the factor is 1 at eps = 0 by definition.
          const float e = aa - m_opt;
          if (e < deg(0.5f)) continue;
          const float ts = c.trim_speed.table.at(tws, aa, e);
          if (aa <= wm::HALF_PI) {
            worst_s = wm::max(worst_s, ts);
          } else {
            worst_push = wm::max(worst_push, ts);
          }
          worst_h = wm::max(worst_h, c.trim_heel.table.at(tws, aa, e));
        }
      }
      MESSAGE(cls, " ", (c.front_sail < 0 ? std::string("main only") : sp.id), ": largest trim_speed ", worst_s,
              " (let-fly push abaft the beam ", worst_push, "), trim_heel ", worst_h, " on the wind line");
      CHECK(worst_s == 0.0f);
      CHECK(worst_push < 1.0f);
      CHECK(worst_h == 0.0f);
    }
  }
}

// §5.1, §5.2: behind the jib the main trims to the jib's leech flow: close-hauled in light and medium air the boom
// is on the centreline (within the traveller's few degrees either side); the manual sheet hard in puts it on the
// centreline or to windward, never aback. With the kite set the main follows the apparent wind inside the kite.
TEST_CASE("sails: main on the centreline upwind, inside the kite downwind") {
  for (const char* cls : {"wm7", "wm12"}) {
    const wm::PerfData& p = perf_no_helm_balance(cls);
    const std::int32_t main = p.main_sail;
    const std::int32_t jib = p.find_sail("jib");
    const std::int32_t kite = p.find_sail(std::string(cls) == "wm7" ? "kite" : "a2");
    const std::size_t mi = static_cast<std::size_t>(main);
    const float windward = -p.sails[mi].sheet_min;
    CHECK(windward > 0.0f);
    for (float tws : {6.0f, 10.0f}) {
      Sim sim(p, tws, 0.0f);
      const float twa = deg(43.0f);
      sim.place(twa, p.config_for(jib)->polar.at(kn(tws), twa), jib);
      for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
        sim.steer_twa(twa);
        sim.step();
      }
      const float side = -wm::sgn(sim.s().awa);
      const float m = side * sim.boat.sails().sail(mi).beta;  // + to leeward
      MESSAGE(std::string(cls), " ", tws, " kn close-hauled: AWA ", to_deg(std::fabs(sim.s().awa)), " deg, main ", to_deg(m),
              " deg, jib ", to_deg(side * sim.boat.sails().sail(static_cast<std::size_t>(jib)).beta), " deg");
      CHECK(m >= -windward - 1e-4f);
      CHECK(m <= deg(3.0f));
      CHECK_FALSE(sim.boat.sails().output(mi).backed);
      // the manual sheet hard in: the main on the centreline or to windward
      sim.boat.set_auto_trim(false);
      sim.boat.set_sheet(0.0f);
      for (int i = 0; i < static_cast<int>(10.0f / DT); ++i) {
        sim.steer_twa(twa);
        sim.step();
      }
      const float mm = side * sim.boat.sails().sail(mi).beta;
      MESSAGE("  sheet hard in: main ", to_deg(mm), " deg");
      CHECK(mm <= 1e-4f);
      CHECK(mm >= -windward - 1e-4f);
      CHECK_FALSE(sim.boat.sails().output(mi).backed);
    }
    Sim sim(p, 10.0f, 0.0f);
    const float twa = deg(135.0f);
    sim.place(twa, p.config_for(kite)->polar.at(kn(10.0f), twa), kite);
    for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
      sim.steer_twa(twa);
      sim.step();
    }
    const float side = -wm::sgn(sim.s().awa);
    const float m = side * sim.boat.sails().sail(mi).beta;
    const float k = side * sim.boat.sails().sail(static_cast<std::size_t>(kite)).beta;
    MESSAGE(std::string(cls), " kite at 135 deg TWA: AWA ", to_deg(std::fabs(sim.s().awa)), " deg, main ", to_deg(m),
            " deg, kite ", to_deg(k), " deg");
    CHECK(m > deg(15.0f));
    CHECK(m < k);
  }
}
