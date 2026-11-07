// Sideways drift of a stalled boat (boat.md §6.4, §10.11 to §10.13, §10.5 with the boat drifting).
#include <cmath>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "state/checksum.h"

using namespace wm_test;
using wm::DT;

namespace {

const char* kClasses[] = {"wm7", "wm12"};
constexpr float kGripMax = 2.0f;  // DRIFT_GRIP_MAX, boat.md §5.9

// The class with its heading held: no helm balance and no fall-off, so a boat at rest keeps its true wind angle and
// its drift can be compared with the table at that angle.
const wm::PerfData& perf_heading_held(const std::string& cls) {
  static std::map<std::string, std::unique_ptr<wm::PerfData>> cache;
  auto it = cache.find(cls);
  if (it == cache.end()) {
    auto p = std::make_unique<wm::PerfData>(perf_no_helm_balance(cls));
    for (wm::ConfigPerf& c : p->configs) c.fall_off.present = false;
    it = cache.emplace(cls, std::move(p)).first;
  }
  return *it->second;
}

// Sideways ground displacement to starboard of the heading `psi0`, m.
float to_starboard(const Sim& sim, float psi0) {
  return sim.s().pos_x * wm::wm_cos(psi0) - sim.s().pos_y * wm::wm_sin(psi0);
}

struct Stalled {
  float sway, v, t90, sog, cog_off;  // cog_off: cog minus heading, wrapped
};

// At rest at `twa` (wind from starboard), sheets free (let fly, or the manual sheet fully eased), 30 s.
Stalled stall(const wm::PerfData& p, float tws, float twa, float expect, bool let_fly) {
  Sim sim(p, tws, deg(30.0f));
  sim.place(twa, 0.0f, p.start_front_sail, /*auto_trim=*/let_fly);
  if (let_fly) {
    sim.boat.set_let_fly(true);
  } else {
    sim.boat.set_sheet(1.0f);
  }
  Stalled r{0.0f, 0.0f, -1.0f, 0.0f, 0.0f};
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.step();
    if (r.t90 < 0.0f && -sim.s().sway >= 0.9f * expect) r.t90 = static_cast<float>(i + 1) * DT;
  }
  r.sway = sim.s().sway;
  r.v = sim.s().v;
  r.sog = sim.boat.outputs().sog;
  r.cog_off = wm::wrap_pi(sim.boat.outputs().cog - sim.s().psi);
  return r;
}

}  // namespace

// §10.11: let fly (or the sheet eased fully by hand) at rest at 50 deg TWA, the boat stays at rest and drifts to
// leeward at the drift_flog rate, square to its heading, building to 90 % within 15 s.
TEST_CASE("drift: a stalled boat drifts to leeward at the table rate") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_heading_held(cls);
    const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
    REQUIRE(c.drift_flog.present);
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      const float twa = deg(50.0f);
      const float expect = c.drift_flog.table.at(kn(tws), twa);
      for (bool let_fly : {true, false}) {
        CAPTURE(cls);
        CAPTURE(tws);
        CAPTURE(let_fly);
        const Stalled r = stall(p, tws, twa, expect, let_fly);
        if (let_fly) {
          MESSAGE(cls, " ", tws, " kn, let fly at 50 deg: drift ", to_kn(-r.sway), " kn (table ", to_kn(expect),
                  " kn, luffing ", to_kn(c.drift.table.at(kn(tws), twa)), " kn), 90 % in ", r.t90, " s");
        }
        CHECK(std::fabs(r.v) < 1e-6f);
        CHECK(r.sway < 0.0f);  // wind from starboard: to port
        CHECK(-r.sway == doctest::Approx(expect).epsilon(0.01));
        CHECK(r.sog == doctest::Approx(-r.sway).epsilon(0.01));
        CHECK(std::fabs(r.cog_off + deg(90.0f)) < deg(1.0f));  // square to the heading, to leeward
        CHECK(r.t90 > 0.0f);
        CHECK(r.t90 < 20.0f);
        if (tws == 10.0f) {
          CHECK(to_kn(expect) > 0.3f);
          CHECK(to_kn(expect) < 1.0f);
        }
      }
    }
  }
}

// §10.11: in irons the boat is carried to leeward while it gathers sternway; let fly there, it falls off and lies
// drifting to leeward. The fall-off and the helm balance are on.
TEST_CASE("drift: in irons and lying let fly") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    {
      Sim sim(p, 10.0f, deg(30.0f));
      sim.place(deg(15.0f), 0.0f, p.start_front_sail);
      const float psi0 = sim.s().psi;
      float windward = 0.0f, v_min = 0.0f;
      for (int i = 0; i < static_cast<int>(10.0f / DT); ++i) {
        sim.step();
        windward = wm::max(windward, sim.s().sway * wm::sgn(sim.s().twa));  // + = to windward
        v_min = wm::min(v_min, sim.s().v);
      }
      const float lee = -to_starboard(sim, psi0);
      MESSAGE(cls, " in irons at 15 deg, 10 kn: ", lee, " m to leeward in 10 s, sternway ", to_kn(-v_min), " kn");
      CHECK(windward <= 0.0f);
      CHECK(lee > 0.3f);
      CHECK(v_min < 0.0f);
    }
    {
      Sim sim(p, 10.0f, deg(30.0f));
      sim.place(deg(15.0f), 0.0f, p.start_front_sail);
      sim.boat.set_let_fly(true);
      sim.run(60.0f);
      const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
      const float ta = std::fabs(sim.s().twa);
      const float table = c.drift_flog.table.at(sim.s().tws, ta);
      MESSAGE(cls, " let fly in irons, after 60 s: twa ", to_deg(ta), " deg, v ", to_kn(sim.s().v), " kn, drift ",
              to_kn(-sim.s().sway), " kn (table there ", to_kn(table), " kn)");
      const float lee = -wm::wrap_pi(sim.boat.outputs().cog - sim.s().psi) * wm::sgn(sim.s().twa);
      MESSAGE("  ground track ", to_deg(lee), " deg to leeward of the heading");
      CHECK(ta > deg(45.0f));                                   // fallen off
      CHECK(to_kn(-sim.s().sway * wm::sgn(sim.s().twa)) > 0.05f);  // drifting to leeward
      CHECK(lee > deg(5.0f));
    }
  }
}

// §10.12: sheeting in from the stalled drift, the boat gathers way and the drift is gone before the speed reaches
// DRIFT_GRIP_MAX; sailing at speed it is exactly 0, steady and through tacks.
TEST_CASE("drift: fades out as the boat gathers way") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_heading_held(cls);
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      CAPTURE(cls);
      CAPTURE(tws);
      Sim sim(p, tws, deg(30.0f));
      sim.place(deg(60.0f), 0.0f, p.start_front_sail);
      sim.boat.set_let_fly(true);
      sim.run(30.0f);
      const float drift0 = -sim.s().sway;
      sim.boat.set_let_fly(false);
      float sway_fast = 0.0f;  // largest drift at or above DRIFT_GRIP_MAX
      float t_fast = -1.0f, t_zero = -1.0f;
      for (int i = 0; i < static_cast<int>(60.0f / DT); ++i) {
        sim.step();
        const float t = static_cast<float>(i + 1) * DT;
        if (std::fabs(sim.s().v) >= kGripMax) {
          if (t_fast < 0.0f) t_fast = t;
          sway_fast = wm::max(sway_fast, std::fabs(sim.s().sway));
        }
        if (sim.s().sway != 0.0f) t_zero = -1.0f;
        else if (t_zero < 0.0f) t_zero = t;
      }
      MESSAGE(cls, " ", tws, " kn: drift ", to_kn(drift0), " kn at rest; from ", to_kn(kGripMax), " kn at most ",
              to_kn(sway_fast), " kn, 0 ", t_zero - t_fast, " s after; then ", to_kn(sim.s().v), " kn");
      CHECK(drift0 > 0.0f);
      CHECK(t_fast > 0.0f);
      CHECK(to_kn(sway_fast) < 0.05f);
      CHECK(t_zero > 0.0f);
      CHECK(t_zero - t_fast < 5.0f);
      CHECK(sim.s().sway == 0.0f);
    }
  }

  // Steady sailing on every config: never a drift.
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_helm_balance(cls);
    for (const wm::ConfigPerf& c : p.configs) {
      for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
        for (float twa_d : {45.0f, 90.0f, 150.0f}) {
          const float twa = deg(twa_d);
          const float v0 = c.polar.at(kn(tws), twa);
          if (!(v0 >= kGripMax)) continue;
          Sim sim(p, tws, deg(200.0f));
          sim.place(twa, v0, c.front_sail);
          bool none = true;
          for (int i = 0; i < static_cast<int>(60.0f / DT); ++i) {
            sim.step();
            if (sim.s().sway != 0.0f) none = false;
          }
          CAPTURE(cls);
          CAPTURE(tws);
          CAPTURE(twa_d);
          CHECK(none);
        }
      }
    }
  }

  // Tacks (boat.md §10.3 set-up): the drift is 0 whenever the speed is at or above DRIFT_GRIP_MAX.
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      for (float helm : {0.5f, 1.0f}) {
        Sim sim(p, tws, 0.0f);
        const float twa = deg(42.0f);
        sim.place(twa, c.polar.at(kn(tws), twa), p.start_front_sail);
        for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
          sim.steer_twa(twa);
          sim.step();
        }
        float sway_max = 0.0f;
        bool ok = true;
        bool turning = true;
        for (int i = 0; i < static_cast<int>(40.0f / DT); ++i) {
          if (turning && sim.s().twa < -twa) turning = false;
          if (turning) {
            sim.boat.set_helm(-helm);
          } else {
            sim.steer_twa(-twa);
          }
          sim.step();
          sway_max = wm::max(sway_max, std::fabs(sim.s().sway));
          if (std::fabs(sim.s().v) >= kGripMax && sim.s().sway != 0.0f) ok = false;
        }
        MESSAGE(cls, " ", tws, " kn tack, helm ", helm, ": largest drift ", to_kn(sway_max), " kn");
        CAPTURE(cls);
        CAPTURE(tws);
        CAPTURE(helm);
        CHECK(ok);
      }
    }
  }
}

// §10.5 with the boat drifting: two runs give the same checksums every tick, and a run split through a snapshot
// save and load while the drift is building gives the same checksums as the unbroken run.
TEST_CASE("drift: determinism and snapshot round trip while drifting") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    auto make = [&]() {
      auto sim = std::make_unique<Sim>(p, 14.0f, deg(10.0f), 0xD21F7);
      sim->place(deg(25.0f), 0.0f, p.start_front_sail);
      sim->boat.set_let_fly(true);
      return sim;
    };
    auto sum = [](const Sim& s) {
      wm::SnapshotWriter w;
      s.boat.save(w);
      const std::vector<std::vector<std::uint8_t>> snaps{w.bytes()};
      return wm::tick_checksum(s.tick, snaps);
    };
    auto script = [](Sim& s) {
      if (s.tick == 500) s.boat.set_let_fly(false);  // sheets in: gathers way, the drift fades
      if (s.tick == 900) s.boat.set_let_fly(true);   // and stalls again
    };
    const int n = 1600;
    auto a = make();
    auto b = make();
    std::vector<std::uint64_t> sums;
    bool same = true;
    for (int i = 0; i < n; ++i) {
      script(*a);
      script(*b);
      a->step();
      b->step();
      if (sum(*a) != sum(*b)) same = false;
      sums.push_back(sum(*a));
    }
    CHECK(same);

    auto c = make();
    for (int i = 0; i < 100; ++i) {
      script(*c);
      c->step();
    }
    CHECK(c->s().sway != 0.0f);  // split while drifting
    wm::SnapshotWriter w;
    c->boat.save(w);
    wm::Boat fresh;
    fresh.init(&p, 0xD21F7, 0);
    fresh.set_weather_helm(c->boat.weather_helm());  // the world's option, not part of the snapshot (boat.md §2)
    wm::SnapshotReader r(w.bytes());
    REQUIRE(fresh.load(r));
    CHECK(r.at_end());
    c->boat = fresh;
    CHECK(sum(*c) == sums[99]);
    bool split_same = true;
    for (int i = 100; i < n; ++i) {
      script(*c);
      c->step();
      if (sum(*c) != sums[static_cast<std::size_t>(i)]) split_same = false;
    }
    CHECK(split_same);
  }
}

// §10.13: with full leeway switched on (data only) a close-hauled boat at speed makes leeway v*tan(leeway); the
// shipped files have it off and make none.
TEST_CASE("drift: full leeway switch") {
  for (const std::string cls : kClasses) {
    wm::PerfData p = perf_no_helm_balance(cls);
    CHECK(!p.dynamics.full_leeway);
    const float lw = 0.1f;
    p.dynamics.full_leeway = true;
    for (wm::ConfigPerf& c : p.configs) {
      c.leeway.present = true;
      c.leeway.table = wm::Table({{wm::Quantity::tws, {0.0f, 20.6f}}, {wm::Quantity::twa_abs, {0.0f, wm::PI}}},
                                 wm::Unit::rad, {lw, lw, lw, lw});
    }
    const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
    const float twa = deg(45.0f);
    Sim sim(p, 10.0f, deg(200.0f));
    sim.place(twa, c.polar.at(kn(10.0f), twa), p.start_front_sail);
    sim.run(60.0f);
    const float expect = -(sim.s().v * (wm::wm_sin(lw * sim.boat.outputs().trim_heel) /
                                        wm::wm_cos(lw * sim.boat.outputs().trim_heel)));
    MESSAGE(cls, " full leeway: v ", to_kn(sim.s().v), " kn, sway ", to_kn(sim.s().sway), " kn, cog off heading ",
            to_deg(wm::wrap_pi(sim.boat.outputs().cog - sim.s().psi)), " deg");
    CHECK(sim.s().sway == doctest::Approx(expect).epsilon(0.01));
    CHECK(wm::wrap_pi(sim.boat.outputs().cog - sim.s().psi) < -deg(4.0f));

    Sim off(perf_no_helm_balance(cls), 10.0f, deg(200.0f));
    off.place(twa, c.polar.at(kn(10.0f), twa), p.start_front_sail);
    off.run(60.0f);
    CHECK(off.s().sway == 0.0f);
  }
}
