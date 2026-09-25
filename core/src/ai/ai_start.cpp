// The start (ai.md §5): free sailing, line analysis, setup point, hovering, the go decision, the final approach,
// the launch, OCS returns and the match race entry.
#include <cmath>

#include "ai/ai_steps.h"
#include "math/rng.h"

namespace wm::ai_detail {

namespace {

struct Line {
  Vec2 A, B, u, n;  // n: towards the course side
  float len;
};

Line start_line(AC& x) {
  const CourseStep& st = x.course.start();
  Line l;
  l.A = x.course.end_a(st);
  l.B = x.course.end_b(st);
  l.len = max(1.0f, v_dist(l.A, l.B));
  l.u = v_unit(v_sub(l.B, l.A), {1.0f, 0.0f});
  l.n = left_of(l.u);
  return l;
}

float draw(AC& x, AB& a, RngStream s) {
  const std::uint64_t k = s == RngStream::ai_first ? a.k16++ : a.k17++;
  const std::uint64_t index = (static_cast<std::uint64_t>(static_cast<std::uint32_t>(a.i)) << 32) | k;
  return rng_unit(x.race.settings().race_seed, s, index);
}

float approach_heading(const Me& m) { return heading_for(m.twd, m.theta_up + 8.0f * DEG); }

// §5.2 line analysis and the target spot.
void choose_spot(AC& x, AB& a, const Me& m, const Line& l) {
  if (!a.drawn) {
    a.drawn = true;
    a.spread_r = draw(x, a, RngStream::ai_first);
    a.e_start = rng_range(a.P.e_start_lo, a.P.e_start_hi, x.race.settings().race_seed, RngStream::ai_first,
                          (static_cast<std::uint64_t>(static_cast<std::uint32_t>(a.i)) << 32) | a.k16++);
  }
  const Vec2 w = dir(a.twd_ref);
  const float beta = wrap_pi(compass(l.n) - a.twd_ref);
  // The spot is chosen once, again at -75 s (the mean wind is known better by then), and after that only when the
  // bias changes by more than 5°.
  const bool final_choice = x.created && x.race.state() == RaceState::sequence && x.t_race >= -75.0f;
  if (a.spot_fixed && std::fabs(wrap_pi(beta - a.spot_beta)) <= 5.0f * DEG &&
      (a.phase != StartPhase::free || !final_choice)) {
    return;
  }
  if (final_choice) a.phase = StartPhase::hover;
  const float du = v_dot(v_sub(l.B, l.A), w);
  const bool significant = std::fabs(du) > max(m.L, 0.05f * l.len);
  float u = 0.5f;
  if (x.race.race_type() == RaceType::match) {
    u = a.i == 0 ? 0.62f : 0.38f;
  } else if (significant) {
    u = du > 0.0f ? 0.85f : 0.15f;
  }
  u = clamp(u + a.P.spread * (a.spread_r - 0.5f), 0.05f, 0.95f);
  // Crowding: another AI's spot within 2 L moves this one 2 L on, away from the favoured end (towards the other
  // end when there is no room left on that side). Spots are taken in boat order, so the result is deterministic.
  const float step = 2.0f * m.L / l.len;
  float away = (significant && du < 0.0f) ? 1.0f : -1.0f;
  if (!significant) away = a.spread_r < 0.5f ? -1.0f : 1.0f;
  for (std::int32_t tries = 0; tries < 60; ++tries) {
    bool clash = false;
    for (const auto& o : *x.ai) {
      if (o->i == a.i || !o->drawn || !o->active || o->autopilot_only) continue;
      if (x.created && !x.race.racing(static_cast<std::size_t>(o->i)) && x.race.rules_live()) continue;
      if (std::fabs(o->spot_u - u) < step * 0.999f) clash = true;
    }
    if (!clash) break;
    float nu = u + away * step;
    if (nu < 0.05f || nu > 0.95f) {
      away = -away;
      nu = clamp(u + away * step, 0.05f, 0.95f);
    }
    u = nu;
  }
  a.spot_u = u;
  a.spot_fixed = true;
  a.spot_beta = beta;
}

Vec2 spot_point(const AB& a, const Line& l, float back) {
  return v_sub(v_add(l.A, v_scale(v_sub(l.B, l.A), a.spot_u)), v_scale(l.n, back));
}

// §5.7 OCS returns and the start after the gun.
void return_and_start(AC& x, AB& a, const Me& m, const Line& l) {
  const float s = v_dot(v_sub(m.c, l.A), l.n);
  const float u = v_dot(v_sub(m.c, l.A), l.u) / l.len;
  a.tactic = AiTactic::Start;
  if (m.rb.ocs_i) {
    // Around the nearer end (race.md §4.3): to the course side beyond the end, then across the extension to the
    // pre-start side. A boat that came back through the line crosses it again first.
    const bool a_near = u < 0.5f;
    const Vec2 end = a_near ? l.A : l.B;
    const Vec2 out = a_near ? v_scale(l.u, -1.0f) : l.u;
    const Vec2 wide = v_add(end, v_scale(out, 1.5f * m.L + m.B));
    const Vec2 p1 = v_add(wide, v_scale(l.n, 1.0f * m.L));
    const Vec2 p2 = v_sub(wide, v_scale(l.n, 2.5f * m.L));
    const float beyond = v_dot(v_sub(m.c, end), out);  // > 0: outside the end
    if (a.ret_stage == 0 && s > 0.3f * m.L && beyond > 0.5f * m.L) a.ret_stage = 1;
    if (a.ret_stage == 1 && s < -0.5f * m.L && beyond < -1.0f * m.L) a.ret_stage = 0;  // came back through the band
    sail_to_point(x, a, m, a.ret_stage == 0 ? p1 : p2);
    return;
  }
  if (m.rb.ocs || (s > -0.5f * m.L && x.race.returning(static_cast<std::size_t>(a.i)))) {
    // Back to the pre-start side, 2 L behind the line: bear away and gybe round (never tack).
    const Vec2 p = v_sub(m.c, v_scale(l.n, s + 2.0f * m.L));
    sail_to_point(x, a, m, p);
    return;
  }
  a.ret_stage = 0;
  // Behind the line: go and start, through the band.
  if (u > 0.05f && u < 0.95f) {
    beat_run(x, a, m, x.course.steps[1].ref, true, 0.0f, false);
    const float twa = wrap_pi(m.twd - a.psi_target);
    const Vec2 f = dir(a.psi_target);
    // Heading away from the line on this tack: take the other.
    if (v_dot(f, l.n) <= 0.1f) a.psi_target = heading_for(m.twd, -sgn(twa) * m.theta_up);
  } else {
    sail_to_point(x, a, m, v_add(spot_point(a, l, 0.0f), v_scale(l.n, 2.0f * m.L)));
  }
}

}  // namespace

float time_to_spot(const AB& a, const Me& m, Vec2 spot, float psi_app) {
  const float v0 = max(0.0f, m.s.v);
  const float turn_radius = m.b.perf().dynamics.turn_radius_full;
  float t = v0 > 0.05f ? std::fabs(wrap_pi(psi_app - m.s.psi)) / (v0 / turn_radius) : 8.0f;
  t = min(t, 8.0f);
  const float th_a = m.theta_up + 8.0f * DEG;
  const float tws = max(0.5f, m.tws);
  const std::int32_t front = m.b.sails().front();
  const float V = m.b.polar_at(tws, th_a, front) * m.scale;
  const float acc = m.b.accel_at(tws, th_a, front);
  const Vec2 bow = v_add(m.c, v_scale(dir(m.s.psi), 0.5f * m.L));
  const float d_path = v_dist(bow, spot);
  float v = v0, xx = 0.0f;
  for (std::int32_t k = 0; k < 1200 && xx < d_path; ++k) {
    const float aa = v < V ? acc : 0.0f;
    v = min(v + aa * 0.1f, max(V, v0 < V ? V : v0));
    xx = xx + v * 0.1f;
    t = t + 0.1f;
  }
  (void)a;
  return t;
}

// §5.4 staying near S: sail back to it when more than 2 L away (slowing on the way in), else park on starboard
// close-hauled with the sails let fly. The way back never tacks (sail_to_point turns through a gybe).
void hover(AC& x, AB& a, const Me& m, Vec2 S) {
  const float d = v_dist(m.c, S);
  const float V = polar_speed(a, m, 60.0f * DEG);
  if (d > 3.0f * m.L) a.loop = true;
  if (d < 1.0f * m.L) a.loop = false;
  if (a.loop) {
    sail_to_point(x, a, m, S);
    // Arrive slowly.
    if (d < 5.0f * m.L && m.s.v > 0.6f * V) a.let_fly = true;
    return;
  }
  a.psi_target = heading_for(m.twd, 50.0f * DEG);
  if (m.tack < 0.0f) a.turn_dir = 1;  // port: back to starboard by bearing away
  a.let_fly = m.tack > 0.0f;
  a.hover_fly = a.let_fly;
}

void free_sailing(AC& x, AB& a, const Me& m) {
  // Near the own setup point, a little farther back (§5.1): each boat has its own, so the fleet does not bunch.
  const Line l = start_line(x);
  choose_spot(x, a, m, l);
  const Vec2 spot = spot_point(a, l, 0.3f * m.L);
  const float d_back = m.v_up * a.P.t_final;
  hover(x, a, m, v_sub(spot, v_scale(dir(approach_heading(m)), 1.2f * d_back)));
  a.tactic = AiTactic::Start;
}

void prestart(AC& x, AB& a, const Me& m) {
  const Line l = start_line(x);
  const float t = x.t_race;
  a.tactic = AiTactic::Start;
  const bool match = x.race.race_type() == RaceType::match;
  const Vec2 bow = v_add(m.c, v_scale(dir(m.s.psi), 0.5f * m.L));
  const float s_bow = v_dot(v_sub(bow, l.A), l.n);
  // §5.8 match race entry.
  if (match && a.i < 2 && a.match_stage < 3) {
    const Vec2 end = a.i == 0 ? l.B : l.A;
    const Vec2 out = a.i == 0 ? l.u : v_scale(l.u, -1.0f);
    if (t < -240.0f) {
      hover(x, a, m, v_sub(v_add(end, v_scale(out, 6.0f * m.L)), v_scale(l.n, 2.0f * m.L)));
      return;
    }
    const float ue = a.i == 0 ? 0.85f : 0.15f;
    const Vec2 q = v_add(l.A, v_scale(v_sub(l.B, l.A), ue));
    if (a.match_stage == 0) a.match_stage = 1;
    if (a.match_stage == 1) {
      sail_to_point(x, a, m, v_add(q, v_scale(l.n, 2.0f * m.L)));
      if (s_bow > 1.0f * m.L) a.match_stage = 2;
      return;
    }
    if (a.match_stage == 2) {
      sail_to_point(x, a, m, v_sub(q, v_scale(l.n, 3.0f * m.L)));
      if (v_dot(v_sub(m.c, l.A), l.n) < -1.5f * m.L) a.match_stage = 3;
      return;
    }
  }
  choose_spot(x, a, m, l);
  const Vec2 spot = spot_point(a, l, 0.3f * m.L);
  a.dbg.spot = spot;
  const float psi_app = approach_heading(m);
  const float d_back = m.v_up * a.P.t_final;
  const Vec2 S = v_sub(spot, v_scale(dir(psi_app), d_back));
  // Over the line before the gun: back to the pre-start side at once.
  if (v_dot(v_sub(m.c, l.A), l.n) > -0.5f * m.L && s_bow > -0.1f * m.L && !a.go) {
    sail_to_point(x, a, m, v_sub(m.c, v_scale(l.n, s_bow + 3.0f * m.L)));
    return;
  }
  if (!a.go) {
    if (t >= -75.0f) {
      const float t_run = time_to_spot(a, m, spot, psi_app);
      if (-t <= t_run + 1.0f + a.e_start) {
        a.go = true;
        a.loop = false;
      }
    }
    if (!a.go) {
      hover(x, a, m, S);
      return;
    }
  }
  // §5.6 final approach on starboard towards the spot.
  const float brg = bearing(m.c, spot);
  float psi = psi_app;
  const float twa_brg = wrap_pi(m.twd - brg);
  if (twa_brg >= m.theta_up + 2.0f * DEG && twa_brg < 120.0f * DEG && v_dist(m.c, spot) > 2.0f * m.L) psi = brg;
  const float t_run = time_to_spot(a, m, spot, psi_app);
  const float want = (-t) + a.e_start;  // arrival time wanted, from now
  const float early = want - t_run;
  if (early > 1.0f) {
    a.let_fly = true;
    if (early > 4.0f) psi = heading_for(m.twd, 45.0f * DEG);
  } else if (early < -1.0f) {
    psi = heading_for(m.twd, max(m.theta_up + 16.0f * DEG, twa_brg));
  }
  // Brake: at the present speed the bow would reach the line before the gun. The stopping distance with the
  // sails let fly is about 2.5 s of the present speed.
  const Vec2 vel = v_add(v_scale(dir(m.s.psi), max(0.0f, m.s.v)), m.cur);
  const float v_n = max(0.05f, v_dot(vel, l.n));
  const float D = max(0.0f, -s_bow);
  if (t < -0.3f && D < v_n * 2.5f + 0.5f * m.L && D / v_n < -t - 0.3f) {
    psi = heading_for(m.twd, 40.0f * DEG);
    a.let_fly = true;
  }
  // Keep starboard: a boat on port turns back the bear-away way.
  if (m.tack < 0.0f) a.turn_dir = 1;
  a.psi_target = psi;
}

void after_gun(AC& x, AB& a, const Me& m) {
  const Line l = start_line(x);
  return_and_start(x, a, m, l);
}

}  // namespace wm::ai_detail
