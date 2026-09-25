// A scripted skipper for the world and full-race tests (not the computer skipper of ai.md): heading hold with
// tacks on the laylines, orbit-style mark rounding, a timed start, returning around an end when over early,
// penalty turns, and a few scripted misbehaviours that produce penalties. Deterministic: it reads only the world
// state and uses the wm_* functions.
#pragma once

#include <cmath>
#include <vector>

#include "course/course.h"
#include "course/geometry.h"
#include "math/wm_math.h"
#include "world/world.h"

namespace wm_test {

struct PilotBoat {
  // Scripted behaviour
  bool early = false;         // goes over the line in the last minute (OCS-I under the I flag)
  bool rogue_port = false;    // gybes onto port at -1:30 and sails blindly along the line for 40 s
  float leave_bounds_at = -1; // race time at which she sails into the exclusion zone (< 0: never)
  wm::Vec2 exclusion{0.0f, 0.0f};  // a point inside it
  // State
  enum class Mode : std::uint8_t { prestart, returning, racing, penalty, done } mode = Mode::prestart;
  int ret_stage = 0;
  std::int8_t tack = 1;       // pilot's tack for beating
  float out_time = 0.0f;
  float slow_time = 0.0f;     // seconds below 0.4 m/s
  float unstick_until = -1e9f;
  float turn_dir = 1.0f;      // +1: turning to starboard
  float penalty_started = -1.0f;
};

class Pilot {
 public:
  explicit Pilot(std::size_t boats) : b_(boats) {}
  PilotBoat& boat(std::size_t i) { return b_[i]; }

  void operator()(wm::World& w) {
    const wm::Race& race = w.race();
    const float t = race.race_time(w.tick());
    for (std::size_t i = 0; i < w.boat_count(); ++i) steer(w, i, t);
  }

 private:
  std::vector<PilotBoat> b_;

  static float heading_error(float want, float psi) { return wm::wrap_pi(want - psi); }

  // Proportional heading hold; with sternway the rudder works backwards, so the helm is reversed.
  void helm_to(wm::World& w, std::size_t i, float want, float limit = 0.6f) {
    const float e = heading_error(want, w.boat(i).state().psi);
    const float h = wm::clamp(2.5f * e, -limit, limit);
    w.set_helm(static_cast<std::int32_t>(i), w.boat(i).state().v < 0.0f ? -h : h);
  }

  // Sail towards `target`, beating on laylines when it is upwind, around course objects in the way (`skip`: the
  // mark being rounded).
  void sail_to(wm::World& w, std::size_t i, wm::Vec2 target, std::int32_t skip = -1) {
    PilotBoat& pb = b_[i];
    const wm::Boat& bt = w.boat(i);
    const wm::BoatState& s = bt.state();
    {
      const wm::Vec2 c0{s.pos_x, s.pos_y};
      const wm::Vec2 d = wm::v_sub(target, c0);
      const float len = wm::v_len(d);
      for (const wm::CourseObject& o : w.course().objects) {
        if (o.mark == skip || !(len > 1.0f)) continue;
        const float ahead = wm::v_dot(wm::v_sub(o.c, c0), d) / len;
        if (ahead <= 0.0f || ahead > len || ahead > 80.0f) continue;
        const float clear = o.r + 12.0f;
        if (wm::point_segment_dist(o.c, c0, target) >= clear) continue;
        const wm::Vec2 u = wm::v_scale(d, 1.0f / len);
        const wm::Vec2 right{u.y, -u.x};
        const float side = wm::side_left(o.c, c0, target) > 0.0f ? 1.0f : -1.0f;  // object left: pass right
        target = wm::v_add(o.c, wm::v_scale(right, side * (o.r + 16.0f)));
        break;
      }
    }
    const wm::EnvAtBoat& env = w.env(i);
    const float twd = env.wind_from_clean;
    const wm::Vec2 c{s.pos_x, s.pos_y};
    const float beta = wm::compass(wm::v_sub(target, c));
    const float twa_t = wm::wrap_pi(twd - beta);  // > 0: target on the starboard-tack side
    const wm::PolarVmg vmg = wm::polar_vmg(bt.perf(), env.wind_speed_clean > 0.5f ? env.wind_speed_clean : 4.0f);
    const float th = vmg.up_twa + 3.0f * wm::DEG;
    const float cur_twa = wm::wrap_pi(twd - s.psi);
    if (std::fabs(twa_t) < th) {
      // Beating: hold the tack until the target is on the other tack's layline.
      if (std::fabs(cur_twa) < wm::HALF_PI) pb.tack = cur_twa >= 0.0f ? 1 : -1;
      if (pb.tack == 1 && twa_t <= -(th - 6.0f * wm::DEG)) pb.tack = -1;
      if (pb.tack == -1 && twa_t >= th - 6.0f * wm::DEG) pb.tack = 1;
      const float want = wm::wrap_2pi(twd - static_cast<float>(pb.tack) * th);
      const bool tacking = (cur_twa >= 0.0f ? 1 : -1) != pb.tack && std::fabs(cur_twa) < wm::HALF_PI;
      helm_to(w, i, want, tacking ? 0.7f : 0.6f);
      return;
    }
    // Keep off dead downwind a little so the boom does not slam across.
    float want = beta;
    if (std::fabs(twa_t) > 170.0f * wm::DEG) want = wm::wrap_2pi(twd - (twa_t >= 0.0f ? 1.0f : -1.0f) * 170.0f * wm::DEG);
    helm_to(w, i, want);
  }

  // Orbit a mark in the rounding direction at radius r: aim 50 degrees ahead on the circle.
  void orbit(wm::World& w, std::size_t i, wm::Vec2 M, wm::Side side, float r, std::int32_t mark) {
    const wm::BoatState& s = w.boat(i).state();
    const float a = wm::wm_atan2(s.pos_y - M.y, s.pos_x - M.x);
    const float sgn = side == wm::Side::port ? 1.0f : -1.0f;
    const float at = a + sgn * 50.0f * wm::DEG;
    const wm::SinCos sc = wm::wm_sincos(at);
    sail_to(w, i, {M.x + r * sc.c, M.y + r * sc.s}, mark);
  }

  void steer(wm::World& w, std::size_t i, float t) {
    PilotBoat& pb = b_[i];
    const wm::Race& race = w.race();
    const wm::RaceBoat& rb = race.boat(i);
    const wm::ResolvedCourse& course = race.course();
    const wm::BoatState& s = w.boat(i).state();
    const wm::Vec2 c{s.pos_x, s.pos_y};
    const float twd = w.env(i).wind_from_clean;
    const wm::Vec2 A = course.end_a(course.start()), B = course.end_b(course.start());
    const wm::Vec2 mid = wm::v_mid(A, B);
    const wm::Vec2 u = wm::v_unit(wm::v_sub(B, A), {1.0f, 0.0f});
    const wm::Vec2 up{-u.y, u.x};  // towards the course side

    if (rb.ghost || rb.finished) {
      pb.mode = PilotBoat::Mode::done;
      // Sail on, away from the line.
      helm_to(w, i, wm::compass(up));
      return;
    }
    // Stuck (pinned or in irons) for 6 s: bear away onto a reach for 8 s.
    pb.slow_time = s.v < 0.4f ? pb.slow_time + wm::DT : 0.0f;
    if (pb.slow_time > 6.0f && pb.mode != PilotBoat::Mode::penalty) {
      pb.unstick_until = t + 8.0f;
      pb.slow_time = 0.0f;
    }
    if (t < pb.unstick_until) {
      const float twa = wm::wrap_pi(twd - s.psi);
      helm_to(w, i, wm::wrap_2pi(twd - (twa >= 0.0f ? 1.0f : -1.0f) * 120.0f * wm::DEG), 0.8f);
      return;
    }
    // Scripted: into the exclusion zone until she has been out of bounds for 16 s (courses.md §5.1).
    if (pb.leave_bounds_at >= 0.0f && t >= pb.leave_bounds_at && rb.started && pb.out_time < 16.0f) {
      if (w.rules().boat(i).out_of_bounds) pb.out_time += wm::DT;
      sail_to(w, i, pb.exclusion);
      return;
    }
    // Penalty turns (rules.md §9.3), outside the zones of the next mark and the last one rounded; not while
    // returning to start.
    const wm::BoatRules& br = w.rules().boat(i);
    const bool starting_early = pb.early && t >= -60.0f && !rb.started;
    if (!br.pending.empty() && pb.mode != PilotBoat::Mode::returning && !starting_early) {
      bool in_zone = false;
      for (const std::int32_t k : {rb.next, rb.last_rounded}) {
        if (k <= 0 || k >= static_cast<std::int32_t>(course.steps.size()) - 1) continue;
        const wm::CourseStep& z = course.steps[static_cast<std::size_t>(k)];
        for (const std::int32_t m : {z.marks[0], z.marks[1]}) {
          const float zone = 5.0f * w.boat(i).perf().dynamics.loa;  // the 3 L zone and a margin
          if (m >= 0 && wm::v_dist(c, course.marks[static_cast<std::size_t>(m)].pos) < zone) in_zone = true;
        }
      }
      // Start a turn only with way on and clear of course objects; once turning, keep turning.
      bool clear = s.v > 1.2f;
      for (const wm::CourseObject& o : course.objects) clear = clear && wm::v_dist(c, o.c) > 25.0f;
      if ((!in_zone && clear) || pb.mode == PilotBoat::Mode::penalty) {
        if (pb.mode != PilotBoat::Mode::penalty) {
          pb.mode = PilotBoat::Mode::penalty;
          pb.penalty_started = t;
          // Upwind or reaching: luff through the tack first while she is fast; running: gybe first.
          const float twa0 = wm::wrap_pi(twd - s.psi);
          const float toward_wind = twa0 >= 0.0f ? 1.0f : -1.0f;
          pb.turn_dir = std::fabs(twa0) < 100.0f * wm::DEG ? toward_wind : -toward_wind;
        }
        // A steady turn at helm 0.6 (a full helm bleeds the speed she needs through the tack). A turn that stalls
        // (under 0.3 m/s for 6 s, or 50 s without being served) is abandoned; she sails on and tries again.
        const bool stalled = s.v < 0.3f && pb.slow_time > 6.0f;
        if (t - pb.penalty_started < 50.0f && !stalled) {
          w.set_helm(static_cast<std::int32_t>(i), 0.6f * pb.turn_dir);
          return;
        }
        pb.mode = rb.started ? PilotBoat::Mode::racing : PilotBoat::Mode::prestart;
      }
    }
    if (pb.mode == PilotBoat::Mode::penalty) pb.mode = rb.started ? PilotBoat::Mode::racing : PilotBoat::Mode::prestart;

    if (!rb.started && !rb.ocs_scored) {
      const bool after_gun = t >= 0.0f;
      if (after_gun && (rb.ocs || rb.ocs_i || race.returning(i))) {
        // Return: for OCS-I around the nearer end (race.md §4.3), else straight back below the line.
        pb.mode = PilotBoat::Mode::returning;
        const bool a_near = wm::v_dist(c, A) < wm::v_dist(c, B);
        const wm::Vec2 end = a_near ? A : B;
        const wm::Vec2 out = a_near ? wm::Vec2{-u.x, -u.y} : u;
        if (rb.ocs_i) {
          const wm::Vec2 p1 = wm::v_add(wm::v_add(end, wm::v_scale(out, 25.0f)), wm::v_scale(up, 10.0f));
          const wm::Vec2 p2 = wm::v_sub(wm::v_add(end, wm::v_scale(out, 25.0f)), wm::v_scale(up, 20.0f));
          if (pb.ret_stage == 0 && wm::v_dist(c, p1) < 12.0f) pb.ret_stage = 1;
          sail_to(w, i, pb.ret_stage == 0 ? p1 : p2);
        } else {
          sail_to(w, i, wm::v_sub(c, wm::v_scale(up, 30.0f)));
        }
        return;
      }
      if (after_gun) {
        // Behind the line after the gun: go and start.
        pb.mode = PilotBoat::Mode::prestart;
        sail_to(w, i, wm::v_add(wm::v_add(mid, wm::v_scale(u, 18.0f * (static_cast<float>(i % 5) - 2.0f))),
                                wm::v_scale(up, 40.0f)));
        return;
      }
      // Before the gun: beam-reach legs of 15 s around the boat's slot below the line, then a timed approach.
      const wm::Vec2 slot = wm::v_add(mid, wm::v_scale(u, 18.0f * (static_cast<float>(i % 5) - 2.0f)));
      const wm::Vec2 box = wm::v_sub(slot, wm::v_scale(up, 40.0f));
      if (pb.rogue_port && t >= -90.0f && t < -50.0f) {
        helm_to(w, i, wm::wrap_2pi(twd + 100.0f * wm::DEG));  // port tack reach, eyes closed
        return;
      }
      if (pb.early && t >= -40.0f) {
        sail_to(w, i, wm::v_add(slot, wm::v_scale(up, 30.0f)));
        return;
      }
      if (t < -60.0f) {
        if (wm::v_dist(c, box) > 50.0f) {
          sail_to(w, i, box);
        } else {
          const bool west = static_cast<std::int64_t>(std::floor((t + 10000.0f) / 15.0f)) % 2 == 0;
          helm_to(w, i, wm::wrap_2pi(twd + (west ? -90.0f : 90.0f) * wm::DEG));
        }
        return;
      }
      const wm::Vec2 go = wm::v_add(slot, wm::v_scale(up, 20.0f));
      const float d = wm::point_segment_dist(c, A, B);
      const float v = s.v > 1.0f ? s.v : 1.0f;
      if (d / v >= -t - 4.0f) {
        sail_to(w, i, go);  // time to go
      } else if (race.start_s(c) > -30.0f) {
        helm_to(w, i, wm::wrap_2pi(twd - 30.0f * wm::DEG), 0.4f);  // close to the line and early: luff and wait
      } else {
        sail_to(w, i, wm::v_sub(slot, wm::v_scale(up, 25.0f)));
      }
      return;
    }

    pb.mode = PilotBoat::Mode::racing;
    const wm::CourseStep& st = course.steps[static_cast<std::size_t>(rb.next)];
    if (st.kind == wm::StepKind::finish) {
      const wm::Vec2 fa = course.end_a(st), fb = course.end_b(st);
      const wm::Vec2 fm = wm::v_mid(fa, fb);
      const wm::Vec2 fu = wm::v_unit(wm::v_sub(fb, fa), {1.0f, 0.0f});
      const wm::Vec2 beyond{fu.y, -fu.x};  // right of A→B: away from the course side
      sail_to(w, i, wm::v_add(fm, wm::v_scale(beyond, 40.0f)));
      return;
    }
    // Gate: the buoy rounded to port; mark: the mark. Far: aim for the rounding side; near: orbit.
    std::size_t k = 0;
    if (st.kind == wm::StepKind::gate && st.sides[1] == wm::Side::port) k = 1;
    const wm::Vec2 M = course.marks[static_cast<std::size_t>(st.marks[k])].pos;
    const wm::Side side = st.sides[k];
    const float r = 14.0f;
    if (wm::v_dist(c, M) < 45.0f) {
      orbit(w, i, M, side, r, st.marks[k]);
    } else {
      const wm::Vec2 dm = wm::v_unit(wm::v_sub(M, c), {0.0f, 1.0f});
      const float sgn = side == wm::Side::port ? 1.0f : -1.0f;
      const wm::Vec2 right{dm.y, -dm.x};
      sail_to(w, i, wm::v_add(M, wm::v_scale(right, sgn * r)), st.marks[k]);
    }
  }
};

}  // namespace wm_test
