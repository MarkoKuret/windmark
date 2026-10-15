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
// heel and pitch by about 1 deg, and the heel changes the speed through heel_speed_factor), and without its helm
// balance (the steady runs sail with the helm centred).
const wm::PerfData& perf_no_wobble(const std::string& cls) {
  static std::map<std::string, wm::PerfData> cache;
  auto it = cache.find(cls);
  if (it == cache.end()) {
    wm::PerfData p = perf_no_helm_balance(cls);
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
  float sway;         // sideways drift at the end (boat.md §6.4): only below the grip speed (a broached polar)
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
  r.sway = s.sway;
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
          if (!(c.polar.at(kn(tws), deg(static_cast<float>(twa_d))) > 0.0f)) continue;  // the config's no-go zone
          const Steady r = run_steady(p, c, tws, deg(static_cast<float>(twa_d)), 120.0f);
          if (r.boom_limited) {
            ++skipped;
            MESSAGE(cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d,
                    ": boom-limited, skipped (heel ", to_deg(-r.phi), " deg, table ", to_deg(-r.heel_target), ")");
            continue;
          }
          ++points;
          const float dv = std::fabs(r.v - r.expect_v) / wm::max(std::fabs(r.expect_v), 0.05f);
          // A boat drifting sideways (a broached speed below the grip speed, boat.md §6.4) feels its drift in the
          // apparent wind, and its heel follows that wind (§5.5): compared on speed only.
          const float dh = r.sway != 0.0f ? 0.0f : std::fabs(r.phi - r.heel_target);
          if (r.sway != 0.0f) {
            MESSAGE(cls, " ", sail_name(p, c.front_sail), " tws ", tws, " twa ", twa_d, ": drifting ", to_kn(-r.sway),
                    " kn at ", to_kn(r.v), " kn, heel ", to_deg(-r.phi), " deg (table ", to_deg(-r.heel_target),
                    "), speed only");
          }
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
    const wm::PerfData& p = perf_no_helm_balance(cls);
    for (const wm::ConfigPerf& c : p.configs) {
      float worst_v = 0.0f, worst_h = 0.0f;
      for (float tws : kTwsSet) {
        for (int twa_d = 30; twa_d <= 180; twa_d += 10) {
          if (!(c.polar.at(kn(tws), deg(static_cast<float>(twa_d))) > 0.0f)) continue;
          const Steady r = run_steady(p, c, tws, deg(static_cast<float>(twa_d)), 120.0f);
          if (r.boom_limited) continue;
          const float dv = (r.v_mean - r.expect_v) / wm::max(std::fabs(r.expect_v), 0.05f);
          const float dh = r.sway != 0.0f ? 0.0f : std::fabs(r.phi_mean - r.heel_target);  // as above
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

// §10.2: at 8 kn TWS on a beam reach with full helm the circle has radius turn_radius_full within 1 % (helm
// balance off: it adds its own turn rate to the circle's).
TEST_CASE("boat: turning circle at full helm") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_yaw_inertia(cls);
    Sim sim(p, 8.0f, 0.0f);
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

// §10.9: yaw inertia. The turn builds toward the radius law's rate over yaw_time after the helm goes over and dies
// away as quickly when it comes back to the centre: no jump either way. Helm balance off, beam reach at 10 kn.
TEST_CASE("boat: yaw inertia") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_helm_balance(cls);
    const float T = p.dynamics.yaw_time;
    REQUIRE(T > 0.1f);
    Sim sim(p, 10.0f, 0.0f);
    sim.place(deg(90.0f), p.config_for(p.start_front_sail)->polar.at(kn(10.0f), deg(90.0f)), p.start_front_sail);
    sim.run(5.0f);
    const float h = -0.3f;  // bear away
    const float t_helm = std::fabs(h) / p.dynamics.helm_rate;  // the rudder's travel
    auto steady = [&] { return std::fabs(sim.s().v / sim.boat.turn_radius(sim.s().h)); };
    sim.boat.set_helm(h);
    sim.step();
    const float first = std::fabs(sim.boat.outputs().turn_rate);
    float t63 = -1.0f, t95 = -1.0f;
    for (int i = 2; i <= static_cast<int>(3.0f / DT); ++i) {
      sim.step();
      const float r = std::fabs(sim.boat.outputs().turn_rate), r_ss = steady();
      if (t63 < 0.0f && r >= 0.63f * r_ss) t63 = static_cast<float>(i) * DT;
      if (t95 < 0.0f && r >= 0.95f * r_ss) t95 = static_cast<float>(i) * DT;
    }
    const float r_on = std::fabs(sim.boat.outputs().turn_rate);
    sim.boat.set_helm(0.0f);
    float t37 = -1.0f, t05 = -1.0f, carried = 0.0f, after_centre = -1.0f;
    for (int i = 1; i <= static_cast<int>(3.0f / DT); ++i) {
      const float psi0 = sim.s().psi;
      sim.step();
      carried += std::fabs(wm::wrap_pi(sim.s().psi - psi0));
      const float r = std::fabs(sim.boat.outputs().turn_rate);
      if (after_centre < 0.0f && sim.s().h == 0.0f) after_centre = r;
      if (t37 < 0.0f && r <= 0.37f * r_on) t37 = static_cast<float>(i) * DT;
      if (t05 < 0.0f && r <= 0.05f * r_on) t05 = static_cast<float>(i) * DT;
    }
    MESSAGE(cls, ": yaw_time ", T, " s; helm ", h, ": first tick ", to_deg(first), " deg/s of ", to_deg(r_on),
            ", 63 % in ", t63, " s, 95 % in ", t95, " s; centred: 37 % in ", t37, " s, 5 % in ", t05, " s, turns on ",
            to_deg(carried), " deg");
    CHECK(first < 0.25f * r_on);                         // no jump when the helm goes over
    CHECK(t63 > 0.0f);
    CHECK(t63 <= T + t_helm + 2.0f * DT);
    CHECK(t95 <= 3.0f * T + t_helm + 2.0f * DT);
    CHECK(after_centre > 0.5f * r_on);                   // no jerk when the helm is back in the centre
    CHECK(t37 <= T + t_helm + 2.0f * DT);
    CHECK(t05 <= 3.0f * T + t_helm + 3.0f * DT);
    CHECK(to_deg(carried) > 0.5f * to_deg(r_on) * T);    // the turn carries on a little
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
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.steer_twa(twa);  // hold close-hauled against the helm balance
    sim.step();
  }
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
// the wind for 30 s; backing the bow off with reversed helm gets it sailing at half its polar speed within 20 s, 17 s
// on the shipped classes (the fall_off table swings the bow away while the boat has no way on, accel_rest gets it
// moving out of the sternway).
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
    CHECK(r.t50 < 17.0f);  // the 20 s target with a 3 s margin
  }
}

namespace {

// Seconds from letting fly on steady close-hauled at `tws` kn until the speed is below `below` (m/s), -1 if not
// within 60 s; helm 0.
float let_fly_time(const wm::PerfData& p, float tws, float below) {
  const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
  const float twa = upwind_twa(c, kn(tws));
  Sim sim(p, tws, 0.0f);
  sim.place(twa, c.polar.at(kn(tws), twa), p.start_front_sail);
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.steer_twa(twa);
    sim.step();
  }
  sim.boat.set_let_fly(true);
  sim.boat.set_helm(0.0f);
  for (int i = 0; i < static_cast<int>(60.0f / DT); ++i) {
    sim.step();
    if (sim.s().v < below) return static_cast<float>(i + 1) * DT;
  }
  return -1.0f;
}

}  // namespace

// §10.6: let fly on close-hauled at 10 kn, the flogging sails and the windage brake the boat: under 1 kn within
// 12 s for an S boat, 20 s for an L boat.
TEST_CASE("boat: let fly slows the boat") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
      const float v0 = c.polar.at(kn(tws), upwind_twa(c, kn(tws)));
      const float t1 = let_fly_time(p, tws, kn(1.0f));
      const float t_half = let_fly_time(p, tws, 0.5f * v0);
      MESSAGE(cls, " ", tws, " kn: let fly from ", to_kn(v0), " kn: half speed in ", t_half, " s, under 1 kn in ",
              t1, " s");
      CHECK(t1 > 0.0f);
      CHECK(t_half < t1);
      // The heavier L boat carries its way about twice as long.
      if (tws == 10.0f && cls == "wm7") CHECK(t1 < 12.0f);
      if (tws == 10.0f && cls == "wm12") CHECK(t1 < 20.0f);
    }
  }
}

namespace {

// Seconds for a full-helm 360 (a penalty turn: a tack and a gybe) from steady sailing on starboard at `twa0` (0:
// close-hauled) and `tws` kn, entered at `entry` times the steady speed (a boat slowed by the incident); upwind and
// reaching the boat luffs first, running (from 100 deg) it bears away first, as a sailor does. -1 if the heading
// has not turned through 360 deg within 90 s; `v_min` is the lowest speed on the way.
float penalty_turn(const wm::PerfData& p, float tws, float twa0, float entry, float& v_min) {
  const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
  const float twa = twa0 > 0.0f ? twa0 : upwind_twa(c, kn(tws));
  const float dir = twa < deg(100.0f) ? 1.0f : -1.0f;
  Sim sim(p, tws, 0.0f);
  sim.place(twa, c.polar.at(kn(tws), twa), p.start_front_sail);
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.steer_twa(twa);
    sim.step();
  }
  sim.boat.mutable_state().v = entry * sim.s().v;
  float turned = 0.0f;
  v_min = sim.s().v;
  for (int i = 0; i < static_cast<int>(90.0f / DT); ++i) {
    const float psi0 = sim.s().psi;
    sim.boat.set_helm(dir);  // starboard tack: + = bow to starboard, up into the wind
    sim.step();
    turned += dir * wm::wrap_pi(sim.s().psi - psi0);
    v_min = wm::min(v_min, sim.s().v);
    if (turned >= wm::TWO_PI) return static_cast<float>(i + 1) * DT;
  }
  return -1.0f;
}

}  // namespace

// §10.8, a penalty turn (rules.md) with the helm hard over: at full speed a full-helm 360 gets round on both classes from
// close-hauled and from a reach at every wind, and from a run too at 10 kn; the other runs and the entries at half
// speed are reported (a slow boat that slams the helm can stall head to wind, as a real one does).
TEST_CASE("boat: full-helm 360") {
  for (const std::string cls : kClasses) {
    for (float tws : {6.0f, 10.0f, 16.0f, 22.0f}) {
      for (float twa0 : {0.0f, deg(90.0f), deg(150.0f)}) {
        for (float entry : {1.0f, 0.5f}) {
          float v_min = 0.0f;
          const float t = penalty_turn(perf(cls), tws, twa0, entry, v_min);
          MESSAGE(cls, " ", tws, " kn, from ", (twa0 > 0.0f ? to_deg(twa0) : 0.0f), " deg (0: close-hauled) at ",
                  entry * 100.0f, " % speed: full-helm 360 in ", t, " s, lowest speed ", to_kn(v_min), " kn");
          if (entry == 1.0f && (twa0 < deg(100.0f) || tws == 10.0f)) CHECK(t > 0.0f);
        }
      }
    }
  }
}

// §10.7: the helm balance. Close-hauled in 12 kn with the start config (the balance point of the class) the boat
// holds its course with the helm centred; a well-balanced boat drifts slowly with the helm centred upwind and on a
// reach in a moderate breeze; on a spinnaker broad reach in a strong breeze it rounds up unless the helm holds it,
// and holding it costs speed through the rudder drag; overpowered (a kite reaching in a gust past its heel limit)
// it broaches, and a full helm at speed catches it.
TEST_CASE("boat: helm balance") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    const wm::ConfigPerf& up = *p.config_for(p.start_front_sail);
    REQUIRE(up.weather_helm.present);
    const float tws_b = 6.0f;  // m/s, the balance breeze of the VPP (about 12 kn)
    const float twa_b = upwind_twa(up, tws_b);
    const float wh_b = up.weather_helm.table.at(tws_b, twa_b);
    MESSAGE(cls, ": helm balance close-hauled at ", to_kn(tws_b), " kn ", to_deg(wh_b), " deg/s");
    CHECK(std::fabs(wh_b) < deg(1.0f));
    Sim sim(p, to_kn(tws_b), 0.0f);
    sim.place(twa_b, up.polar.at(tws_b, twa_b), p.start_front_sail);
    sim.run(30.0f);
    CHECK(std::fabs(sim.s().twa - twa_b) < deg(3.0f));

    // centred-helm drift of the start config: upwind at its VMG angle within 2 deg/s from 6 to 16 kn, reaching
    // within 3 deg/s at 10 kn (the stronger breezes are reported)
    for (float tws : {6.0f, 10.0f, 14.0f, 16.0f}) {
      const float wu = up.weather_helm.table.at(kn(tws), upwind_twa(up, kn(tws)));
      float wr = 0.0f;
      for (float a = 60.0f; a <= 120.0f; a += 5.0f) wr = wm::max(wr, std::fabs(up.weather_helm.table.at(kn(tws), deg(a))));
      MESSAGE(cls, " ", tws, " kn: centred-helm drift upwind ", to_deg(wu), " deg/s, reaching up to ", to_deg(wr), " deg/s");
      CHECK(std::fabs(wu) <= deg(2.0f));
      if (tws <= 10.0f) CHECK(wr <= deg(3.0f));
    }

    // the last front sail is the spinnaker
    const std::int32_t kite = static_cast<std::int32_t>(p.sails.size()) - 1;
    const wm::ConfigPerf& dn = *p.config_for(kite);
    const float twa = deg(130.0f);
    const float wh = dn.weather_helm.table.at(kn(22.0f), twa);
    Sim free_run(p, 22.0f, 0.0f);
    free_run.place(twa, dn.polar.at(kn(22.0f), twa), kite);
    free_run.run(5.0f);
    Sim held(p, 22.0f, 0.0f);
    held.place(twa, dn.polar.at(kn(22.0f), twa), kite);
    const int n = static_cast<int>(30.0f / DT), tail = static_cast<int>(10.0f / DT);
    float twa_m = 0.0f, h_m = 0.0f, v_m = 0.0f;  // means over the last 10 s
    for (int i = 0; i < n; ++i) {
      held.steer_twa(twa, 1.0f, 6.0f);
      held.step();
      if (i >= n - tail) {
        twa_m += held.s().twa / static_cast<float>(tail);
        h_m += held.s().h / static_cast<float>(tail);
        v_m += held.s().v / static_cast<float>(tail);
      }
    }
    MESSAGE(cls, ": kite at 22 kn, 130 deg: helm balance ", to_deg(wh), " deg/s; helm 0 for 5 s: twa ",
            to_deg(free_run.s().twa), " deg; held at ", to_deg(twa_m), " deg: helm ", h_m, ", v ", to_kn(v_m),
            " kn of ", to_kn(dn.polar.at(kn(22.0f), twa)), " kn");
    CHECK(wh > deg(1.5f));
    CHECK(free_run.s().twa < twa - deg(5.0f));
    CHECK(std::fabs(twa_m - twa) < deg(4.0f));
    CHECK(h_m < 0.0f);  // helm to bear away (starboard tack: the bow to port)
    CHECK(v_m < dn.polar.at(kn(22.0f), twa));

    // overpowered: reaching under the kite at 20 kn, a gust of 26 kn lays her over past her heel limit
    for (float helm : {0.0f, -1.0f}) {
      Sim g(p, 20.0f, 0.0f);
      const float twa_r = deg(100.0f);
      g.place(twa_r, dn.polar.at(kn(20.0f), twa_r), kite);
      for (int i = 0; i < static_cast<int>(5.0f / DT); ++i) {
        g.steer_twa(twa_r, 1.0f, 6.0f);
        g.step();
      }
      g.env.wind_speed = kn(26.0f);
      g.env.wind_speed_clean = g.env.wind_speed;
      g.boat.set_helm(helm);
      // the closest she comes to the wind on her own (starboard) tack: a full helm held for 5 s carries a fast boat
      // on round through a gybe, which is the helm turning her, not a broach
      float lo = g.s().twa;
      bool gybed = false;
      for (int i = 0; i < static_cast<int>(5.0f / DT); ++i) {
        g.step();
        gybed = gybed || g.s().twa < 0.0f || g.s().twa > deg(179.0f);
        if (!gybed) lo = wm::min(lo, g.s().twa);
      }
      MESSAGE(cls, ": kite reaching at 100 deg, gust 20 to 26 kn, helm ", helm, ": lowest twa in 5 s ", to_deg(lo),
              " deg");
      if (helm == 0.0f) CHECK(lo < deg(75.0f));  // she broaches
      else CHECK(lo > deg(80.0f));               // a full helm at speed catches it
    }
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

namespace {

struct LetFlyRun {
  float v0 = 0.0f, v5 = 0.0f, v10 = 0.0f;
  float worst_over = -1.0f;  // largest |beta| beyond the sail's fully eased angle (sheet_max, heel limit)
  float ts1 = 1.0f;          // trim_speed in the first tick of let fly
};

// Steady at `twa` in 10 kn under `front`, then let fly holding the heading: speed at 0, 5 and 10 s and how far any
// sail went beyond its fully eased angle.
LetFlyRun let_fly_run(const wm::PerfData& p, std::int32_t front, float twa) {
  const wm::ConfigPerf& c = *p.config_for(front);
  Sim sim(p, 10.0f, 0.0f);
  sim.place(twa, c.polar.at(kn(10.0f), twa), front);
  for (int i = 0; i < static_cast<int>(30.0f / DT); ++i) {
    sim.steer_twa(twa);
    sim.step();
  }
  LetFlyRun r;
  r.v0 = sim.s().v;
  sim.boat.set_let_fly(true);
  for (int i = 1; i <= static_cast<int>(10.0f / DT); ++i) {
    sim.steer_twa(twa);
    sim.step();
    for (std::size_t k = 0; k < p.sails.size(); ++k) {
      const wm::SailPerf& sp = p.sails[k];
      const float lim = sp.sheet_max_by_heel.present
                            ? wm::min(sp.sheet_max, sp.sheet_max_by_heel.table.at(std::fabs(sim.s().phi)))
                            : sp.sheet_max;
      r.worst_over = wm::max(r.worst_over, std::fabs(sim.boat.sails().sail(k).beta) - lim);
    }
    if (i == 1) r.ts1 = sim.boat.outputs().trim_speed;
    if (i == static_cast<int>(5.0f / DT)) r.v5 = sim.s().v;
  }
  r.v10 = sim.s().v;
  return r;
}

}  // namespace

// sails.md §5.3, §8.8: let fly holds every sail at its fully eased angle, never beyond it; the drive is the trim
// table's there, at once. Upwind the sails luff and the boat coasts down; running, the eased sails still drive.
TEST_CASE("boat: let fly upwind and downwind") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf(cls);
    const std::int32_t kite = p.find_sail(cls == "wm7" ? "kite" : "a2");
    const float up = upwind_twa(*p.config_for(p.start_front_sail), kn(10.0f));
    struct Case {
      const char* name;
      std::int32_t front;
      float twa;
    };
    for (const Case& k : {Case{"upwind jib", p.start_front_sail, up}, Case{"jib 60", p.start_front_sail, deg(60.0f)},
                          Case{"jib 90", p.start_front_sail, deg(90.0f)}, Case{"jib 120", p.start_front_sail, deg(120.0f)},
                          Case{"jib 150", p.start_front_sail, deg(150.0f)}, Case{"kite 90", kite, deg(90.0f)},
                          Case{"kite 120", kite, deg(120.0f)}, Case{"kite 150", kite, deg(150.0f)}}) {
      const LetFlyRun r = let_fly_run(p, k.front, k.twa);
      MESSAGE(cls, " ", std::string(k.name), ": let fly from ", to_kn(r.v0), " kn: ", to_kn(r.v5), " kn after 5 s, ",
              to_kn(r.v10), " kn after 10 s; largest sail angle beyond fully eased ", to_deg(r.worst_over),
              " deg; trim_speed in the first tick ", r.ts1);
      CHECK(r.worst_over <= 1e-5f);
      if (k.twa == up) {
        CHECK(r.ts1 == 0.0f);  // the drive goes at once, not as the sail swings out
        CHECK(r.v10 < 0.5f * r.v0);
      }
      if (k.twa >= deg(150.0f)) CHECK(r.v10 > 0.8f * r.v0);  // running, the fully eased sails still draw
    }
  }
}

// boat.md §6.2, §7.5: on a reach, sheeting the sails hard in stalls them and heels the boat more than trimmed.
TEST_CASE("boat: over-sheeting on a reach heels the boat more") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_helm_balance(cls);
    const std::int32_t front = p.start_front_sail;
    for (float tws : {10.0f, 16.0f}) {
      const float twa = deg(90.0f);
      Sim sim(p, tws, 0.0f);
      sim.place(twa, p.config_for(front)->polar.at(kn(tws), twa), front);
      for (int i = 0; i < static_cast<int>(40.0f / DT); ++i) {
        sim.steer_twa(twa);
        sim.step();
      }
      const float v0 = sim.s().v, h0 = std::fabs(sim.s().phi);
      sim.boat.set_auto_trim(false);
      sim.boat.set_sheet(0.0f);  // fully sheeted in
      float h_max = 0.0f, h10 = 0.0f;
      std::string trace;
      for (int i = 1; i <= static_cast<int>(40.0f / DT); ++i) {
        sim.steer_twa(twa);
        sim.step();
        h_max = wm::max(h_max, std::fabs(sim.s().phi));
        if (i == static_cast<int>(10.0f / DT)) h10 = h_max;
        if (i % static_cast<int>(5.0f / DT) == 0)
          trace += " " + std::to_string(static_cast<int>(std::lround(to_deg(std::fabs(sim.s().phi))))) + "/" +
                   std::to_string(to_kn(sim.s().v)).substr(0, 3);
      }
      const float v1 = sim.s().v, h1 = std::fabs(sim.s().phi);
      MESSAGE(cls, " ", tws, " kn, 90 deg: trimmed ", to_kn(v0), " kn heel ", to_deg(h0), " deg; sheeted in ",
              to_kn(v1), " kn heel ", to_deg(h1), " deg (largest ", to_deg(h_max), "), trim_heel ",
              sim.boat.outputs().trim_heel, ", trim_speed ", sim.boat.outputs().trim_speed, "; every 5 s deg/kn",
              trace);
      CHECK(h10 > h0 + deg(2.0f));  // the stalled sails lay her over while she still carries her speed
      CHECK(h1 > h0 - deg(1.5f));   // slowed, the heel follows her apparent wind down, not far below trimmed
    }
  }
}

// boat.md §5.6: on flat water a steadily heeled boat sits at the shipped classes' heel_rise and heel_trim for its
// heel (both tables come from the generator's free-floating hull), and upright at neither.
TEST_CASE("boat: heeled hull rises and trims") {
  for (const std::string cls : kClasses) {
    const wm::PerfData& p = perf_no_wobble(cls);
    const wm::Dynamics& d = p.dynamics;
    REQUIRE(d.heel_rise.present);
    REQUIRE(d.heel_trim.present);
    Sim sim(p, 16.0f, 0.0f);
    sim.place(deg(60.0f), 3.0f, p.start_front_sail);
    for (int i = 0; i < 1200; ++i) {
      sim.steer_twa(deg(60.0f));
      sim.step();
    }
    const wm::BoatState& s = sim.boat.state();
    const float rise = d.heel_rise.table.at(std::fabs(s.phi));
    const float trim = d.heel_trim.table.at(std::fabs(s.phi));
    MESSAGE(cls, ": heel ", to_deg(std::fabs(s.phi)), " deg, z ", s.z, " m (table ", rise, "), pitch ",
            to_deg(s.theta), " deg (table ", to_deg(trim), ")");
    CHECK(to_deg(std::fabs(s.phi)) > 10.0f);
    CHECK(rise > 0.01f);
    CHECK(trim < 0.0f);  // bow down: the immersed leeward quarter lifts the stern
    CHECK(std::fabs(s.z - rise) < 0.002f);
    CHECK(std::fabs(s.theta - trim) < deg(0.05f));
    CHECK(d.heel_rise.table.at(0.0f) == 0.0f);
    CHECK(d.heel_trim.table.at(0.0f) == 0.0f);
  }
}
