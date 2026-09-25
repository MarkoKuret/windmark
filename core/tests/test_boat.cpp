// Headless boat tests (boat.md §10) on the shipped classes.
#include <cmath>
#include <map>
#include <cstdio>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "state/checksum.h"

using namespace wm_test;
using wm::DEG;
using wm::DT;

namespace {

const char* kClasses[] = {"wm7", "wm12"};

std::string sail_name(const wm::PerfData& p, std::int32_t i) { return i < 0 ? "main only" : p.sails[static_cast<std::size_t>(i)].id; }


// The class with the attitude wobble switched off, so the steady state is exactly the tables' (the wobble moves
// heel and pitch by about 1 deg, and the heel changes the speed through heel_speed_factor).
const wm::PerfData& perf_no_wobble(const std::string& cls) {
  static std::map<std::string, wm::PerfData> cache;
  auto it = cache.find(cls);
  if (it == cache.end()) {
    wm::PerfData p = perf(cls);
    p.dynamics.wobble_heel = 0.0f;
    p.dynamics.wobble_pitch = 0.0f;
    it = cache.emplace(cls, std::move(p)).first;
  }
  return it->second;
}

// A steady run: placed at the table speed at `twa`, helm 0, flat water, auto-trim, for `seconds`.
struct Steady {
  float v, v_mean, phi, phi_mean, expect_v, heel_target, surf_mean;
  bool boom_limited;  // the main cannot reach its optimum at the table heel (sheet_max_by_heel)
};

Steady run_steady(const wm::PerfData& p, const wm::ConfigPerf& c, float tws_kn, float twa, float seconds) {
  wm::Boat boat;
  boat.init(&p, 7, 0);
  wm::BoatEnv env;
  env.wind_speed = kn(tws_kn);
  env.wind_speed_clean = env.wind_speed;
  env.wind_from = deg(200.0f);
  boat.reset(0.0f, 0.0f, wm::wrap_2pi(env.wind_from - twa), c.polar.at(env.wind_speed, twa), c.front_sail, true,
             env);
  const int n = static_cast<int>(seconds / DT);
  const int tail = 200;  // mean over the last 10 s, several wobble periods
  double phi_sum = 0.0, surf_sum = 0.0, v_sum = 0.0;
  for (int i = 0; i < n; ++i) {
    boat.step(env);
    if (i >= n - tail) {
      phi_sum += static_cast<double>(boat.state().phi);
      surf_sum += static_cast<double>(boat.outputs().surf_coef);
      v_sum += static_cast<double>(boat.state().v);
    }
  }
  const wm::BoatState& s = boat.state();
  Steady r{};
  r.v = s.v;
  r.phi = s.phi;
  r.phi_mean = static_cast<float>(phi_sum / tail);
  r.surf_mean = static_cast<float>(surf_sum / tail);
  r.v_mean = static_cast<float>(v_sum / tail);
  const float ta = std::fabs(s.twa);
  r.expect_v = c.polar.at(s.tws, ta) * p.dynamics.heel_speed_factor.at(std::fabs(s.phi));
  r.heel_target = -wm::sgn(s.twa) * wm::clamp(c.heel.at(s.tws, ta), 0.0f, p.dynamics.heel_max);
  const wm::SailPerf& main = p.sails[static_cast<std::size_t>(p.main_sail)];
  if (c.front_sail < 0 && main.sheet_max_by_heel.present) {
    const float m_opt = wm::clamp(c.optimal_main.at(s.tws, std::fabs(s.awa)), main.sheet_min, main.sheet_max);
    r.boom_limited = m_opt > main.sheet_max_by_heel.table.at(std::fabs(r.heel_target)) + deg(0.1f);
  }
  return r;
}

const float kTwsSet[] = {4, 6, 8, 10, 12, 16, 20, 25};

}  // namespace

// §10.1 as written: every config, TWS 4..25 kn, TWA 30..180 deg, auto-trim, flat water, no shadows, helm 0.
// After 120 s the speed is polar * heel_speed_factor(heel) within 0.5 % and the heel is the heel target within
// 0.2 deg. Run without the wobble, which is not part of the tables. Points where the main-only config's boom limit
// stops the main short of its optimum at the table heel are reported and skipped: there the boat over-sheets,
// heels more and rounds into a heel of its own (a data consistency question for the VPP).
TEST_CASE("boat: steady polar and heel match the tables") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_wobble(cls);
    for (const wm::ConfigPerf& c : p.configs) {
      int points = 0, skipped = 0;
      float worst_v = 0.0f, worst_h = 0.0f;
      for (float tws : kTwsSet) {
        for (int twa_d = 30; twa_d <= 180; twa_d += 10) {
          const Steady r = run_steady(p, c, tws, deg(static_cast<float>(twa_d)), 120.0f);
          if (r.boom_limited) {
            ++skipped;
            MESSAGE(cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d,
                    ": boom-limited, skipped (heel ", to_deg(-r.phi), " deg, table ", to_deg(-r.heel_target), ")");
            continue;
          }
          ++points;
          const float dv = std::fabs(r.v - r.expect_v) / wm::max(std::fabs(r.expect_v), 0.05f);
          const float dh = std::fabs(r.phi - r.heel_target);
          worst_v = wm::max(worst_v, dv);
          worst_h = wm::max(worst_h, dh);
          CHECK_MESSAGE(dv <= 0.005f, cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d, ": v ",
                        to_kn(r.v), " kn, expected ", to_kn(r.expect_v), " kn");
          CHECK_MESSAGE(dh <= deg(0.2f), cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d,
                        ": heel ", to_deg(r.phi), " deg, target ", to_deg(r.heel_target), " deg");
        }
      }
      MESSAGE(cls, " ", sail_name(p, c.front_sail), ": ", points, " points, ", skipped, " boom-limited, worst speed ",
              worst_v * 100.0f, " %, worst heel ", to_deg(worst_h), " deg");
    }
  }
}

// §10.1 with the class wobble: the mean heel stays on the table within 0.2 deg. Surfing follows the wave pitch
// only (boat.md §5.8), so the wobble reaches the speed only through the heel it adds (heel_speed_factor, trim of
// the boom-limited main); that offset is reported and bounded at 1.5 %.
TEST_CASE("boat: steady state with the attitude wobble") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    for (const wm::ConfigPerf& c : p.configs) {
      float worst_v = 0.0f, worst_h = 0.0f;
      for (float tws : kTwsSet) {
        for (int twa_d = 30; twa_d <= 180; twa_d += 10) {
          const Steady r = run_steady(p, c, tws, deg(static_cast<float>(twa_d)), 120.0f);
          if (r.boom_limited) continue;
          const float dv = (r.v_mean - r.expect_v) / wm::max(std::fabs(r.expect_v), 0.05f);
          const float dh = std::fabs(r.phi_mean - r.heel_target);
          if (std::fabs(dv) > std::fabs(worst_v)) worst_v = dv;
          worst_h = wm::max(worst_h, dh);
          CHECK_MESSAGE(dh <= deg(0.2f), cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d,
                        ": mean heel ", to_deg(r.phi_mean), " deg, target ", to_deg(r.heel_target), " deg");
          CHECK_MESSAGE(std::fabs(dv) <= 0.015f, cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d,
                        ": mean v ", to_kn(r.v_mean), " kn, table ", to_kn(r.expect_v), " kn");
        }
      }
      MESSAGE(cls, " ", sail_name(p, c.front_sail), ": worst mean heel error ", to_deg(worst_h),
              " deg, largest mean speed offset from the wobble ", worst_v * 100.0f, " %");
    }
  }
}

namespace {

// Radius of the circle through three points.
float circumradius(float ax, float ay, float bx, float by, float cx, float cy) {
  const float a = std::hypot(bx - cx, by - cy);
  const float b = std::hypot(ax - cx, ay - cy);
  const float c = std::hypot(ax - bx, ay - by);
  const float cross = std::fabs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax));
  return (a * b * c) / (2.0f * cross);
}

// Best close-hauled angle of a config: the TWA of the largest VMG between 25 and 60 deg.
float upwind_twa(const wm::ConfigPerf& c, float tws) {
  float best = deg(40.0f), best_vmg = -1.0f;
  for (int i = 250; i <= 600; ++i) {
    const float twa = deg(static_cast<float>(i) * 0.1f);
    const float vmg = c.polar.at(tws, twa) * wm::wm_cos(twa);
    if (vmg > best_vmg) {
      best_vmg = vmg;
      best = twa;
    }
  }
  return best;
}

}  // namespace

// §10.2: at 8 kn TWS on a beam reach with full helm the circle has radius turn_radius_full within 1 %.
TEST_CASE("boat: turning circle at full helm") {
  for (const std::string cls : kClasses) {
    Sim sim(cls, 8.0f, 0.0f);
    const wm::PerfData& p = perf(cls);
    sim.place(deg(90.0f), p.config_for(p.start_front_sail)->polar.at(kn(8.0f), deg(90.0f)), p.start_front_sail);
    sim.boat.set_helm(-1.0f);  // bear away from the beam reach: the boat keeps its way into the turn
    while (sim.s().h > -1.0f) sim.step();
    std::vector<wm::Vec2> pts;
    for (int i = 0; i < 12; ++i) {
      pts.push_back({sim.s().pos_x, sim.s().pos_y});
      sim.step();
    }
    REQUIRE(sim.s().v > 0.5f);
    const float r = circumradius(pts[0].x, pts[0].y, pts[5].x, pts[5].y, pts[11].x, pts[11].y);
    MESSAGE(cls, ": radius ", r, " m, turn_radius_full ", p.dynamics.turn_radius_full, " m, speed ", to_kn(sim.s().v),
            " kn");
    CHECK(std::fabs(r - p.dynamics.turn_radius_full) <= 0.01f * p.dynamics.turn_radius_full);
    CHECK(sim.boat.turn_radius(1.0f) == doctest::Approx(p.dynamics.turn_radius_full));
  }
}

namespace {

struct TackResult {
  bool completed;       // the bow reached the new close-hauled angle within 60 s
  float time_to_90;     // s from the helm going over until the speed is back to 90 %, -1 if never
  float distance_lost;  // m of upwind progress against a boat that kept sailing close-hauled for 60 s
};

// §10.3: from steady close-hauled on starboard at `tws` kn, tack with helm `helm` onto port close-hauled.
TackResult tack(const wm::PerfData& p, float tws, float helm) {
  const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
  const float twa = upwind_twa(c, kn(tws));
  Sim sim(p, tws, 0.0f);  // wind from the north: upwind progress is +y
  sim.place(twa, c.polar.at(kn(tws), twa), p.start_front_sail);
  sim.run(30.0f);
  const float v_steady = sim.s().v;
  const float y0 = sim.s().pos_y;
  const float vmg = v_steady * wm::wm_cos(twa);
  bool turning = true;
  float t90 = -1.0f;
  const int n = static_cast<int>(60.0f / DT);
  for (int i = 0; i < n; ++i) {
    if (turning) {
      sim.boat.set_helm(helm);
      // Straighten up once the bow is within a few degrees of the new close-hauled angle.
      if (sim.s().twa < -(twa - deg(8.0f))) turning = false;
    } else {
      sim.steer_twa(-twa, helm);
    }
    sim.step();
    if (t90 < 0.0f && !turning && sim.s().v >= 0.9f * v_steady) t90 = static_cast<float>(i + 1) * DT;
  }
  return {!turning, t90, vmg * 60.0f - (sim.s().pos_y - y0)};
}

}  // namespace

// §10.3: a tack at 10 kn with helm 0.5 gets an S boat back to 90 % speed within 12 s; boat.md §7.2: a slammed
// full-helm tack costs more than a smooth one. On the shipped classes at handling 1.0; the other wind speeds are
// reported (the class targets are for 10 kn).
TEST_CASE("boat: tack on the shipped classes") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      const TackResult r = tack(p, tws, 0.5f);
      const TackResult hard = tack(p, tws, 1.0f);
      MESSAGE(cls, " ", tws, " kn: helm 0.5 back to 90 % in ", r.time_to_90, " s, ", r.distance_lost, " m lost (",
              r.distance_lost / p.dynamics.loa, " lengths); full helm ", hard.time_to_90, " s, ", hard.distance_lost,
              " m (", hard.distance_lost / p.dynamics.loa, " lengths)");
      CHECK_MESSAGE(r.completed, cls, " ", tws, " kn: helm 0.5 does not get round");
      CHECK_MESSAGE(hard.completed, cls, " ", tws, " kn: full helm does not get round");
      CHECK(r.time_to_90 > 0.0f);
      CHECK(r.distance_lost > 0.0f);
      CHECK_MESSAGE(hard.distance_lost > r.distance_lost, cls, " ", tws, " kn: full-helm tack is not slower");
      if (cls == "wm7" && tws == 10.0f) CHECK(r.time_to_90 < 12.0f);
    }
  }
}

namespace {

struct IronsResult {
  float v_after;    // speed after 30 s head to wind
  float worst_twa;  // largest |twa| in those 30 s
  float t50;        // s from reversing the helm until half the polar speed, -1 if not within 20 s
};

IronsResult irons(const wm::PerfData& p) {
  Sim sim(p, 10.0f, deg(30.0f));
  sim.place(0.0f, 0.0f, p.start_front_sail);
  IronsResult r{0.0f, 0.0f, -1.0f};
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.step();
    r.worst_twa = wm::max(r.worst_twa, std::fabs(sim.s().twa));
  }
  r.v_after = sim.s().v;
  // Back the bow off: with sternway, helm to starboard swings the bow to port (wind onto the starboard side);
  // once moving ahead, bear away to a reach.
  bool backing = true;
  for (int i = 0; i < static_cast<int>(20.0f / DT); ++i) {
    if (backing && (sim.s().v > 0.0f || sim.s().twa > deg(70.0f))) backing = false;
    if (backing) {
      sim.boat.set_helm(1.0f);
    } else {
      sim.steer_twa(deg(80.0f));
    }
    sim.step();
    const float polar = sim.boat.outputs().polar_speed;
    if (r.t50 < 0.0f && polar > 0.0f && sim.s().v >= 0.5f * polar) r.t50 = static_cast<float>(i + 1) * DT;
  }
  return r;
}

}  // namespace

// §10.4: head to wind at rest with the helm centred the boat gathers sternway and the bow stays within 15 deg of
// the wind for 30 s; backing the bow off with reversed helm gets it sailing at half its polar speed within 20 s
// (the fall_off table swings the bow away while the boat has no way on).
TEST_CASE("boat: in irons and recovery") {
  for (const std::string cls : kClasses) {
    const wm::ConfigPerf& c = *perf(cls).config_for(perf(cls).start_front_sail);
    CHECK(c.fall_off.present);
    const IronsResult r = irons(perf(cls));
    MESSAGE(cls, ": after 30 s in irons v ", to_kn(r.v_after), " kn, largest |twa| ", to_deg(r.worst_twa),
            " deg; 50 % of polar speed ", r.t50, " s after reversing the helm");
    CHECK(r.v_after < -0.05f);
    CHECK(r.worst_twa < deg(15.0f));
    CHECK(r.t50 > 0.0f);
  }
}

// boat.md §8: in a calm the wind directions keep their last values and the boat coasts down along the
// deceleration law; §5.1: the polar sees the wind over the water, so a current is felt as wind.
TEST_CASE("boat: calm, current and invalid commands") {
  const wm::PerfData& p = perf("wm7");
  Sim sim("wm7", 10.0f, deg(90.0f));
  sim.place(deg(90.0f), 3.0f, p.start_front_sail);
  const float twd = sim.s().twd_from;
  sim.env.wind_speed = 0.0f;
  sim.env.wind_speed_clean = 0.0f;
  float prev = sim.s().v;
  bool monotonic = true;
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.step();
    if (sim.s().v > prev) monotonic = false;
    prev = sim.s().v;
  }
  CHECK(sim.s().twd_from == twd);
  CHECK(monotonic);
  CHECK(sim.s().v >= 0.0f);
  CHECK(sim.s().v < 0.3f);

  // A current of 1 m/s toward the north in a calm: the boat drifts with the water and feels 1 m/s of true wind
  // from the north (the air over the water).
  Sim cur("wm7", 0.0f, 0.0f);
  cur.env.current_y = 1.0f;
  cur.place(0.0f, 0.0f, -1);
  cur.run(10.0f);
  CHECK(cur.s().tws == doctest::Approx(1.0f));
  CHECK(wm::angle_diff(cur.s().twd_from, 0.0f) == doctest::Approx(0.0f).epsilon(1e-4));
  // Head to that wind it drifts astern through the water, so it makes a little less than the current's 10 m.
  CHECK(cur.s().v < 0.0f);
  CHECK(cur.s().pos_y > 8.0f);
  CHECK(cur.s().pos_y < 10.0f);

  // Commands are clamped on write; NaN is the neutral value.
  sim.boat.set_helm(5.0f);
  CHECK(sim.boat.controls().h_cmd == 1.0f);
  sim.boat.set_helm(std::nanf(""));
  CHECK(sim.boat.controls().h_cmd == 0.0f);
  sim.boat.set_sheet(0.4f);
  sim.boat.set_sheet(std::nanf(""));
  CHECK(sim.boat.controls().sheet_cmd == 0.4f);
  sim.boat.set_sheet(-3.0f);
  CHECK(sim.boat.controls().sheet_cmd == 0.0f);
  sim.boat.set_performance_scale(std::nanf(""));
  CHECK(sim.boat.controls().performance_scale == 1.0f);
  sim.boat.set_performance_scale(9.0f);
  CHECK(sim.boat.controls().performance_scale == 2.0f);
}
