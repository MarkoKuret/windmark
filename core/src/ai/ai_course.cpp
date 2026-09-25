// Sailing the course (ai.md §4, §6, §7.6, §8, §9, §10) and the decision dispatch.
#include <cmath>

#include "ai/ai_predict.h"
#include "ai/ai_steps.h"
#include "math/rng.h"

namespace wm::ai_detail {

namespace {

constexpr float kPenaltyHelm = 0.8f;  // §7.6

// The tack (manoeuvre) duration constants of §4.3, scaled for longer boats.
float t_manoeuvre(const Me& m, bool tack) { return (tack ? 6.0f : 5.0f) * (0.5f * (1.0f + m.L / 10.0f)); }

bool is_zone(AC& x, const Me& m, std::int32_t step) {
  const ResolvedCourse& co = x.course;
  if (step <= 0 || step >= static_cast<std::int32_t>(co.steps.size()) - 1) return false;
  const CourseStep& st = co.steps[static_cast<std::size_t>(step)];
  const float Z = x.race.zone_lengths() * m.L;
  for (const std::int32_t k : {st.marks[0], st.marks[1]}) {
    if (k >= 0 && v_dist(m.c, co.marks[static_cast<std::size_t>(k)].pos) < Z + m.L) return true;
  }
  return false;
}

// A mark or gate buoy target of the current step.
struct MarkTarget {
  bool is_mark = false;
  std::int32_t mark = -1;
  Vec2 M{0.0f, 0.0f};
  float sigma = 1.0f;  // +1 port rounding (anticlockwise), -1 starboard
  float rho = 0.0f;
  float phi = 0.0f, phi_done = 1.0f;  // the race's winding around this buoy and its target (race.md §5.1)
};

float rounding_radius(AC& x, AB& a, const Me& m, std::int32_t mark) {
  const ResolvedMark& rm = x.course.marks[static_cast<std::size_t>(mark)];
  std::int32_t n_in = 0;
  for (const PairRecord* p : x.pairs_of[static_cast<std::size_t>(a.i)]) {
    if (p->room_giver == a.i && p->room_mark == mark && p->room_entitled >= 0) ++n_in;
  }
  return ((rm.radius + 0.5f * m.B) + a.P.c_lvl * m.B) + static_cast<float>(n_in) * (m.B + 1.0f);
}

// §6.3 gate choice.
std::int32_t choose_gate(AC& x, AB& a, const Me& m, const CourseStep& st, std::int32_t step) {
  const ResolvedCourse& co = x.course;
  const Vec2 G0 = co.marks[static_cast<std::size_t>(st.marks[0])].pos;
  const Vec2 G1 = co.marks[static_cast<std::size_t>(st.marks[1])].pos;
  const float d_line = point_segment_dist(m.c, G0, G1);
  auto crowd = [&](Vec2 G, float r) {
    std::int32_t n = 0;
    for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
      if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
      const RaceBoat& o = x.race.boat(j);
      if (o.next == step && v_dist(o.c, G) < r) ++n;
    }
    return n;
  };
  if (a.gate_step == step && d_line < 8.0f * m.L) {
    const Vec2 Gk = a.gate_buoy == 0 ? G0 : G1;
    if (crowd(Gk, 3.0f * m.L) < 3) return a.gate_buoy;
  }
  float best = 1e30f;
  std::int32_t pick = 0;
  const float V = max(0.5f, m.v_dn);
  for (std::int32_t k = 0; k < 2; ++k) {
    const Vec2 G = k == 0 ? G0 : G1;
    const float rho = rounding_radius(x, a, m, st.marks[k]);
    const float d = v_dist(m.c, G);
    const float tan_d = d > rho ? std::sqrt(d * d - rho * rho) : 0.0f;
    float score = tan_d / V + 2.0f * static_cast<float>(crowd(G, 4.0f * m.L));
    // The next leg a beat: prefer the buoy that leaves the boat on the lifted tack. Rounding the buoy with the
    // rounding direction σ leaves the boat heading away on the tack whose bow turns the same way.
    const std::int32_t nstep = step + 1;
    if (nstep < static_cast<std::int32_t>(co.steps.size())) {
      const Vec2 N = co.steps[static_cast<std::size_t>(nstep)].ref;
      const float thN = std::fabs(wrap_pi(m.twd - bearing(G, N)));
      if (thN < m.theta_up + 3.0f * DEG) {
        const float sigma = st.sides[k] == Side::port ? 1.0f : -1.0f;
        // A port rounding (anticlockwise) out of a run turns the bow through the wind's left: the boat leaves on
        // starboard when the next mark is up and to the left of the buoy... read from the exit heading instead.
        const float opt_s = heading_for(m.twd, m.theta_up), opt_p = heading_for(m.twd, -m.theta_up);
        const float tan_heading = wrap_2pi(bearing(G, m.c) - sigma * HALF_PI);
        const float rs = sigma * wrap_pi(tan_heading - opt_s), rp = sigma * wrap_pi(tan_heading - opt_p);
        const float exit_tack = (rs >= 0.0f && (rp < 0.0f || rs <= rp)) ? 1.0f : -1.0f;
        const bool lifted = (exit_tack > 0.0f && a.shift >= 3.0f * DEG) || (exit_tack < 0.0f && a.shift <= -3.0f * DEG);
        if (lifted) score = score - 3.0f;
      }
    }
    if (score < best) {
      best = score;
      pick = k;
    }
  }
  a.gate_step = step;
  a.gate_buoy = pick;
  return pick;
}

MarkTarget mark_target(AC& x, AB& a, const Me& m) {
  MarkTarget t;
  const std::int32_t step = m.rb.next;
  const CourseStep& st = x.course.steps[static_cast<std::size_t>(step)];
  if (st.kind == StepKind::mark) {
    t.is_mark = true;
    t.mark = st.marks[0];
    t.sigma = st.sides[0] == Side::port ? 1.0f : -1.0f;
    t.phi = m.rb.phi[0];
    t.phi_done = m.rb.phi_done[0];
  } else if (st.kind == StepKind::gate) {
    const std::int32_t k = choose_gate(x, a, m, st, step);
    t.is_mark = true;
    t.mark = st.marks[k];
    t.sigma = st.sides[k] == Side::port ? 1.0f : -1.0f;
    t.phi = m.rb.phi[k];
    t.phi_done = m.rb.phi_done[k];
  } else {
    return t;
  }
  t.M = x.course.marks[static_cast<std::size_t>(t.mark)].pos;
  t.rho = rounding_radius(x, a, m, t.mark);
  return t;
}

// The target point after this step (for the exit heading and the sail plan).
Vec2 next_ref(AC& x, const Me& m) {
  const std::size_t k = static_cast<std::size_t>(m.rb.next) + 1;
  if (k < x.course.steps.size()) return x.course.steps[k].ref;
  return x.course.steps.back().ref;
}

// The exit heading of a rounding (§6.1): the VMG heading of the next leg if it is a beat or a run (the one reached
// first in the rounding direction), else the direct course.
float exit_heading(AC& x, const Me& m, const MarkTarget& t, float psi_tan) {
  const Vec2 N = next_ref(x, m);
  const float bN = bearing(t.M, N);
  const float thN = std::fabs(wrap_pi(m.twd - bN));
  float o1, o2;
  if (thN < m.theta_up + 3.0f * DEG) {
    o1 = heading_for(m.twd, m.theta_up);
    o2 = heading_for(m.twd, -m.theta_up);
  } else if (thN > m.theta_dn - 3.0f * DEG) {
    o1 = heading_for(m.twd, m.theta_dn);
    o2 = heading_for(m.twd, -m.theta_dn);
  } else {
    return bN;
  }
  // Remaining turn in the rounding direction (a port rounding turns anticlockwise: the heading decreases).
  const float r1 = t.sigma * wrap_pi(psi_tan - o1), r2 = t.sigma * wrap_pi(psi_tan - o2);
  if (r1 >= -0.3f && (r2 < -0.3f || r1 <= r2)) return o1;
  if (r2 >= -0.3f) return o2;
  return std::fabs(wrap_pi(o1 - bN)) < std::fabs(wrap_pi(o2 - bN)) ? o1 : o2;
}

// The point to pass a mark at on a beat or a run (the circle's side of the approach).
Vec2 pass_point(const MarkTarget& t, Vec2 d, float margin) {
  const Vec2 off = t.sigma > 0.0f ? right_of(d) : left_of(d);
  return v_add(t.M, v_scale(off, t.rho + margin));
}

// §6.1 inside the rounding circle's reach: orbit the circle in the rounding direction, aiming a little ahead on it,
// and leave on the exit heading once the rounding is nearly complete. The race's winding angle says how far round
// the boat is: a boat that came in on the wrong side is behind (φ small or negative) and simply orbits on, which
// takes her back the way she came and round, the way the winding test counts it.
bool round_mark(AC& x, AB& a, const Me& m, const MarkTarget& t) {
  a.round_mark = t.mark;
  a.tactic = AiTactic::Rounding;
  if (a.man == Man::tack) {
    // A tack in progress keeps its target (the new tack's close-hauled heading).
    a.psi_target = heading_for(m.twd, static_cast<float>(a.man_to) * m.theta_up);
    return true;
  }
  const float alpha = bearing(t.M, m.c);
  const float dist = v_dist(m.c, t.M);
  const float rem = t.phi_done - t.phi;  // winding still to go
  const float psi_tan = wrap_2pi(alpha - t.sigma * HALF_PI);
  // Guide: outside the circle the tangent point ahead in the rounding direction, inside it a point 55° ahead.
  Vec2 guide;
  if (dist > 1.15f * t.rho) {
    const float g = std::acos(clamp(t.rho / dist, -1.0f, 1.0f));
    guide = v_add(t.M, v_scale(dir(wrap_2pi(alpha - t.sigma * g)), t.rho));
  } else {
    guide = v_add(t.M, v_scale(dir(wrap_2pi(alpha - t.sigma * 55.0f * DEG)), t.rho));
  }
  float psi = bearing(m.c, guide);
  const float psi_exit = exit_heading(x, m, t, psi_tan);
  // Nearly round: leave on the exit heading once the guide has turned past it.
  if (rem < 70.0f * DEG && t.sigma * wrap_pi(psi - psi_exit) <= 0.0f) psi = psi_exit;
  a.tactic = AiTactic::Rounding;
  a.dbg.aim = guide;
  float twa = wrap_pi(m.twd - psi);
  if (std::fabs(twa) < m.theta_up) {
    // Upwind of close-hauled: this tack if it carries round (moves in the rounding direction and passes the mark on
    // the required side by the circle's radius, or the mark is already behind), else beat to the guide point on
    // its laylines, so the tack comes where the other tack clears the mark.
    const float pc = heading_for(m.twd, m.tack * m.theta_up);
    const Vec2 to_m = v_sub(t.M, m.c);
    const bool clears = t.sigma * v_cross(dir(pc), to_m) >= 0.9f * t.rho || v_dot(dir(pc), to_m) < 0.0f;
    if ((v_dot(dir(pc), dir(psi_tan)) > 0.0f && clears) || a.man != Man::straight || dist <= 1.15f * t.rho) {
      a.psi_target = pc;
      return true;
    }
    // Beat to the pass point the approach uses (the upwind side by the circle and a half length), so a boat that
    // cannot lay the mark tacks away early and comes back on the layline, not at the mark.
    const Vec2 pp = pass_point(t, dir(a.twd_f), 0.5f * m.L);
    beat_run(x, a, m, pp, true, 0.0f, false);
    a.dbg.aim = pp;
    a.tactic = AiTactic::Rounding;
    return true;
  }
  if (a.man == Man::straight && sgn(twa) != m.tack) {
    // The other tack: a tack if the shorter turn passes head to wind and the boat has way on, else the turn goes
    // round the other way (through a gybe).
    const float e = wrap_pi(psi - m.s.psi);
    const float twa_mid = wrap_pi(m.twd - (m.s.psi + 0.5f * e));
    if (std::fabs(twa_mid) < HALF_PI) {
      if (m.s.v >= 0.6f * polar_speed(a, m, std::fabs(m.twa)) && request_tack(x, a, m, AiTactic::Rounding, true)) {
        a.tactic = AiTactic::Rounding;
        a.psi_target = heading_for(m.twd, -m.tack * max(m.theta_up, std::fabs(twa)));
        return true;
      }
      if (m.s.v >= 0.3f) {
        // The tack is not possible now: as close to the guide as this tack goes, and wait (a loop the long way
        // round near a mark and other boats is worse than a late tack).
        a.psi_target = heading_for(m.twd, m.tack * m.theta_up);
        return true;
      }
      a.turn_dir = static_cast<std::int8_t>(e > 0.0f ? -1 : 1);
    }
  }
  a.psi_target = psi;
  return true;
}

// §4.5 finish aim.
Vec2 finish_aim(AC& x, AB& a, const Me& m, bool& beat) {
  const CourseStep& st = x.course.steps.back();
  const Vec2 A = x.course.end_a(st), B = x.course.end_b(st);
  const Vec2 mid = v_mid(A, B);
  const float th = std::fabs(wrap_pi(m.twd - bearing(m.c, mid)));
  beat = th < m.theta_up + 3.0f * DEG;
  const Vec2 AB_ = v_sub(B, A);
  const float len = max(1.0f, v_len(AB_));
  const float inset = min(0.45f, (m.L + m.B) / len);
  if (beat) {
    const Vec2 w = dir(a.twd_ref);
    const bool b_fav = v_dot(AB_, w) > 0.0f;
    const float u = b_fav ? 1.0f - inset : inset;
    return v_add(A, v_scale(AB_, u));
  }
  // The point of the line on the present course over ground, if well inside the ends.
  const Vec2 d = dir(m.b.outputs().cog);
  const float det = v_cross(d, AB_);
  if (std::fabs(det) > 1e-3f) {
    const Vec2 q = v_sub(A, m.c);
    const float s = v_cross(q, AB_) / det;
    const float u = v_cross(q, d) / det;
    if (s > 0.0f && u > inset && u < 1.0f - inset) return v_add(A, v_scale(AB_, u));
  }
  const float u0 = clamp(v_dot(v_sub(m.c, A), AB_) / (len * len), 1.0f / 3.0f, 2.0f / 3.0f);
  return v_add(A, v_scale(AB_, u0));
}

// §7.6 penalty turns. True while the turn owns the helm.
float penalty_helm(const Me& m) { return m.tws < 9.0f * KNOT ? 0.6f : kPenaltyHelm; }

// Within `extra` metres of the zone of the step's marks.
bool near_zone(AC& x, const Me& m, std::int32_t step, float extra) {
  const ResolvedCourse& co = x.course;
  if (step <= 0 || step >= static_cast<std::int32_t>(co.steps.size()) - 1) return false;
  const CourseStep& st = co.steps[static_cast<std::size_t>(step)];
  const float Z = x.race.zone_lengths() * m.L;
  for (const std::int32_t k : {st.marks[0], st.marks[1]}) {
    if (k >= 0 && v_dist(m.c, co.marks[static_cast<std::size_t>(k)].pos) < Z + 0.5f * m.L + extra) return true;
  }
  return false;
}

// A penalty turn from here in direction `dir` (+1 clockwise) keeps the hull out of the zones of the next mark and
// the last one rounded: the turn's circle (radius R, a margin for the speed it loses) stays clear of them.
bool turn_clear_of_zones(AC& x, const Me& m, std::int32_t next, float dir_, float R) {
  const ResolvedCourse& co = x.course;
  const Vec2 C = v_add(m.c, v_scale(right_of(dir(m.s.psi)), dir_ * 1.3f * R));
  const float Z = x.race.zone_lengths() * m.L;
  for (const std::int32_t step : {next, m.rb.last_rounded}) {
    if (step <= 0 || step >= static_cast<std::int32_t>(co.steps.size()) - 1) continue;
    const CourseStep& st = co.steps[static_cast<std::size_t>(step)];
    for (const std::int32_t k : {st.marks[0], st.marks[1]}) {
      if (k >= 0 && v_dist(C, co.marks[static_cast<std::size_t>(k)].pos) < Z + 1.3f * R + 0.6f * m.L) return false;
    }
  }
  return true;
}

}  // namespace

bool penalty_turns(AC& x, AB& a, const Me& m, Leg leg) {
  const BoatRules& br = m.br;
  a.pen_prepare = false;
  a.pen_block = -1;
  auto stop = [&]() {
    a.pen_on = false;
    a.helm_fixed = NAN;
    if (a.man == Man::penalty) a.man = Man::straight;
  };
  if (br.pending.empty() || !x.race.rules_live()) {
    if (a.pen_on) stop();
    return false;
  }
  // Entry penalties of a match race are taken after the gun (rules.md §9.6).
  const RuleCode r0 = br.pending.front().rule;
  if ((r0 == RuleCode::c_prep || r0 == RuleCode::c_entry) && !x.race.after_gun(x.n)) return false;
  const float R = radius_for_helm(m.b.perf().dynamics, penalty_helm(m));
  const std::int32_t next = m.rb.started ? m.rb.next : 0;
  if (a.pen_on) {
    if (br.served > a.pen_served0) {
      stop();
      return false;
    }
    const float t = x.now - a.pen_t0;
    // In irons: stopped for 4 s. Give up this turn, build speed and start again.
    a.pen_stall_t = m.s.v < 0.3f ? a.pen_stall_t + 2.0f * DT : 0.0f;
    if (a.pen_stall_t > 4.0f || t > 90.0f || near_zone(x, m, next, -0.5f * m.L) ||
        near_zone(x, m, m.rb.last_rounded, -0.5f * m.L)) {
      stop();
      a.low_until = x.now + 5.0f;
      return false;
    }
    a.helm_fixed = (m.s.v < 0.0f ? -a.pen_dir : a.pen_dir) * penalty_helm(m);
    a.forced = true;
    a.tactic = AiTactic::PenaltyTurn;
    a.man = Man::penalty;
    // Downwind sail down first in a breeze.
    if (m.tws > 10.0f * KNOT && m.b.sails().spinnaker_flying() && !m.b.sails().busy()) x.w.drop_front(a.i);
    return true;
  }
  auto why = [&](const char* reason) {  // the turn waits (for speed or clear water); the reason is for debugging
    (void)reason;
    a.pen_prepare = true;
    return false;
  };
  if (a.man != Man::straight) return why("man");
  // The turn only counts outside the zones of the next mark and the last one rounded: stay clear of them by the
  // turn's diameter.
  // Direction: on a beat or a reach luff into a tack, on a run bear away into a gybe; the other way if only that
  // keeps the turn out of the zones.
  float dir_ = leg == Leg::run ? -m.tack : m.tack;
  if (!turn_clear_of_zones(x, m, next, dir_, R)) dir_ = -dir_;
  if (!turn_clear_of_zones(x, m, next, dir_, R)) return why("zone");
  // Urgent from 20 s before the deadline (the turn must be in progress when it passes, rules.md §9.4): then only
  // the zones, a minimum of way and an immediate collision risk hold it back.
  const bool urgent = br.deadline_s >= 0.0f && br.deadline_s < 20.0f;
  const float V = polar_speed(a, m, std::fabs(m.twa));
  if (m.s.v < (urgent ? 0.4f : 0.75f) * V && x.now < a.low_until + 8.0f) return why("slow");
  if (urgent) {
    for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
      if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
      if (v_dist(x.race.boat(j).c, m.c) < 0.5f * m.L + x.r_hull[j] + R) {
        a.pen_block = static_cast<std::int32_t>(j);
        return why("urgent-boat");
      }
    }
  } else {
    if (x.now < a.low_until) return why("low");
    if (m.s.v < 0.75f * V) return why("slow2");
    // Not so close to the next zone that the turn could not be completed before it (about 20 s of sailing).
    if (next > 0 && next < static_cast<std::int32_t>(x.course.steps.size()) - 1 &&
        near_zone(x, m, next, 2.0f * R + 20.0f * max(1.0f, m.s.v))) {
      return why("nextzone");
    }
    // Clear of other boats: none within 1.5 L of the turn's reach, or 3 L ahead.
    const Vec2 f = dir(m.s.psi);
    for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
      if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
      const Vec2 cj = x.race.boat(j).c;
      const float d = v_dist(cj, m.c);
      if (d < 1.5f * m.L + x.r_hull[j] + R || (d < 3.0f * m.L + x.r_hull[j] && v_dot(v_sub(cj, m.c), f) > 0.0f)) {
        a.pen_block = static_cast<std::int32_t>(j);
        return why("boat");
      }
    }
  }
  // Start: on a beat or a reach luff into a tack, on a run bear away into a gybe.
  a.pen_on = true;
  a.pen_t0 = x.now;
  a.pen_stall_t = 0.0f;
  a.pen_served0 = br.served;
  a.pen_dir = dir_;
  a.helm_fixed = (m.s.v < 0.0f ? -a.pen_dir : a.pen_dir) * penalty_helm(m);
  a.forced = true;
  a.tactic = AiTactic::PenaltyTurn;
  a.man = Man::penalty;
  return true;
}

namespace {

// Mean clean wind speed sampled along a heading (§3.3 reading the water).
float read_track(AC& x, const AB& a, const Me& m, float psi) {
  const WindField& wf = x.w.wind();
  const WindTick& wt = wf.current_tick();
  const Vec2 d = dir(psi);
  float sum = 0.0f;
  std::int32_t n = 0;
  for (float r = 100.0f; r <= a.P.r_read + 0.5f; r = r + 100.0f) {
    const Vec2 p = v_add(m.c, v_scale(d, r));
    sum = sum + wf.wind_clean(wt, p.x, p.y).speed;
    ++n;
  }
  return n > 0 ? sum / static_cast<float>(n) : 0.0f;
}

// §8: the source's peak blanket loss scaled to the threshold.
float bad_threshold(AC& x, std::int32_t src) {
  const wm::Boat& b = x.w.boat(static_cast<std::size_t>(src));
  const WindShadowParams& p = b.perf().dynamics.wind_shadow;
  return 0.35f * (b.sails().spinnaker_flying() ? p.blanket_depth_spinnaker : p.blanket_depth);
}

// §8 anticipation cost of sailing on a heading for 15 s.
float anticipation_cost(AC& x, const AB& a, const Me& m, float psi, float d_bad) {
  const float V = max(1.0f, m.s.v);
  const Vec2 p = v_add(m.c, v_scale(dir(psi), 15.0f * V));
  return 5.0f * predicted_deficit(x, a, p) / d_bad;
}

// §9 cover: returns true (and tacks) when covering asks for a tack now.
bool cover(AC& x, AB& a, const Me& m, bool beat, Vec2 R) {
  if (a.P.cover == AiCover::none) return false;
  const bool match = x.race.race_type() == RaceType::match;
  if (!match && a.P.cover != AiCover::all) return false;
  const std::size_t i = static_cast<std::size_t>(a.i);
  const float D_me = m.rb.D;
  std::int32_t opp = -1;
  float best = 1e30f;
  if (match) {
    for (std::size_t j = 0; j < x.w.boat_count() && j < 2; ++j) {
      if (j != i && x.race.racing(j)) opp = static_cast<std::int32_t>(j);
    }
    if (opp < 0) return false;
    const RaceBoat& o = x.race.boat(static_cast<std::size_t>(opp));
    if (!(o.next == m.rb.next && o.D > D_me && o.D - D_me < 12.0f * m.L)) return false;
  } else {
    if (!beat || m.rb.rank > 3) return false;
    // The last beat: no later step's leg is a beat.
    bool last_beat = true;
    const Vec2 w = dir(x.race.twd_mean());
    for (std::size_t k = static_cast<std::size_t>(m.rb.next) + 1; k < x.course.steps.size(); ++k) {
      const Vec2 d = v_sub(x.course.steps[k].ref, x.course.steps[k - 1].ref);
      if (v_dot(d, w) > 0.707f * v_len(d)) last_beat = false;
    }
    if (!last_beat) return false;
    for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
      if (j == i || !x.race.racing(j)) continue;
      const RaceBoat& o = x.race.boat(j);
      if (o.next != m.rb.next || !(o.D > D_me) || o.D - D_me > 10.0f * m.L) continue;
      if (o.D - D_me < best) {
        best = o.D - D_me;
        opp = static_cast<std::int32_t>(j);
      }
    }
    if (opp < 0) return false;
  }
  const wm::Boat& ob = x.w.boat(static_cast<std::size_t>(opp));
  const float otwa = wrap_pi(x.w.env(static_cast<std::size_t>(opp)).wind_from_clean - ob.state().psi);
  const std::int8_t otk = static_cast<std::int8_t>(sgn(otwa));
  if (a.cover_opp != opp) {
    a.cover_opp = opp;
    a.opp_tack_prev = otk;
    a.opp_other_t = 0.0f;
  }
  if (otk != a.opp_tack_prev) a.opp_tacked_at = x.now;
  a.opp_tack_prev = otk;
  const bool other = otk != static_cast<std::int8_t>(m.tack);
  a.opp_other_t = other ? a.opp_other_t + 2.0f * DT : 0.0f;
  const float gap = v_dist(m.c, x.race.boat(static_cast<std::size_t>(opp)).c);
  const bool tight = match && beat && gap < 5.0f * m.L;
  bool want = false;
  if (tight) want = other && x.now - a.opp_tacked_at < 2.0f && std::fabs(otwa) > 20.0f * DEG;
  if (!want) want = other && a.opp_other_t >= 10.0f;
  if (!want) return false;
  (void)R;
  if (beat) return request_tack(x, a, m, AiTactic::Cover, false);
  return request_gybe(x, a, m, AiTactic::Cover, false);
}

// §8 bad air: true when an escape is running or started.
bool bad_air(AC& x, AB& a, const Me& m, Leg leg) {
  // The source of the tick's strongest shadow; the smoothed deficit outlasts it at the blanket's edges, so the last
  // one seen stands in while there is none.
  std::int32_t src = m.env.shadow_source;
  if (src >= 0) a.bad_last = src;
  else src = a.bad_last;
  if (x.now < a.foot_until) {
    if (a.d_f < 0.3f * (a.bad_src >= 0 ? bad_threshold(x, a.bad_src) : 0.08f)) a.foot_until = -1e9f;
  }
  const bool prestart_end = x.t_race > -10.0f && x.t_race < 0.0f;
  if (src < 0 || prestart_end || is_zone(x, m, m.rb.next)) {
    a.bad_t = 0.0f;
    return x.now < a.foot_until;
  }
  const float d_bad = bad_threshold(x, src);
  const bool near = v_dist(m.c, x.race.boat(static_cast<std::size_t>(src)).c) <= 8.0f * m.L;
  a.bad_t = (a.d_f >= d_bad && near) ? a.bad_t + 2.0f * DT : 0.0f;
  if (a.bad_t < a.P.badair_react) return x.now < a.foot_until;
  a.bad_t = 0.0f;
  a.bad_src = src;
  AiBadAirRecord rec;
  rec.tick = x.n;
  rec.d_at = a.d_f;
  a.tel.bad_air.push_back(rec);
  a.tactic = AiTactic::BadAir;
  const Vec2 cs = x.race.boat(static_cast<std::size_t>(src)).c;
  const Vec2 f = dir(m.s.psi);
  const float lat = v_cross(f, v_sub(cs, m.c));  // > 0: source to the left
  const bool src_leeward = lat * m.tack > 0.0f;  // starboard tack: leeward is to the left
  const bool src_ahead = v_dot(v_sub(cs, m.c), f) > 0.0f;
  if (leg == Leg::beat) {
    // Tack unless a starboard boat would have to be ducked on the new tack.
    bool duck = false;
    if (m.tack > 0.0f) {
      const float psi_new = heading_for(m.twd, -m.theta_up);
      for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
        if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
        const Vec2 cj = x.race.boat(j).c;
        if (v_dist(cj, m.c) > 5.0f * m.L) continue;
        const float tj = wrap_pi(x.w.env(j).wind_from_clean - x.w.boat(j).state().psi);
        if (tj >= 0.0f && std::fabs(tj) < HALF_PI && v_dot(v_sub(cj, m.c), dir(psi_new)) > -m.L) duck = true;
      }
    }
    if (!duck && request_tack(x, a, m, AiTactic::BadAir, false)) return true;
    a.foot_until = x.now + 20.0f;
    bool clear_windward = true;
    for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
      if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
      const Vec2 dj = v_sub(x.race.boat(j).c, m.c);
      if (v_len(dj) < 3.0f * m.L && v_cross(f, dj) * m.tack < 0.0f) clear_windward = false;
    }
    a.foot_delta = (src_leeward && src_ahead && clear_windward) ? 3.0f * DEG : -5.0f * DEG;
    return true;
  }
  if (leg == Leg::run) {
    if (request_gybe(x, a, m, AiTactic::BadAir, false)) return true;
    a.foot_until = x.now + 20.0f;
    a.foot_delta = 10.0f * DEG;
    return true;
  }
  a.foot_until = x.now + 20.0f;
  a.foot_delta = src_leeward ? -10.0f * DEG : 10.0f * DEG;
  return true;
}

// §8 on a reach: head up or bear away 10° out of the shadow (the TWA change is kept within close-hauled).
void reach_bad_air(AC& x, AB& a, const Me& m) {
  if (a.man != Man::straight) return;
  (void)bad_air(x, a, m, Leg::reach);
  if (x.now >= a.foot_until) return;
  const float twa = wrap_pi(m.twd - a.psi_target);
  const float t2 = max(m.theta_up, std::fabs(twa) - a.foot_delta);
  a.psi_target = heading_for(m.twd, sgn(twa) * min(t2, 175.0f * DEG));
}

// §6.2 sails: returns the planned sail requests to the world.
void sails(AC& x, AB& a, const Me& m, bool has_mark, const MarkTarget& t, Leg leg) {
  const Sails& sl = m.b.sails();
  if (sl.busy()) {
    a.change_t = 0.0f;
    return;
  }
  const std::int32_t cur = sl.front();
  const float tws = m.tws;
  const float twa_now = std::fabs(m.twa);
  float leg_twa = twa_now;
  if (leg == Leg::beat) leg_twa = m.theta_up;
  else if (leg == Leg::run) leg_twa = m.theta_dn;
  const std::int32_t want = a.pol->best_sail(tws, leg_twa);
  auto t_peel = [&](std::int32_t to, std::int32_t from, float twa_abs) {
    float t = 0.0f;
    const PerfData& p = m.b.perf();
    if (to >= 0 && p.sails[static_cast<std::size_t>(to)].has_handling) {
      const SailHandling& h = p.sails[static_cast<std::size_t>(to)].handling;
      t = (t + h.prepare_hoist_time.at(tws, twa_abs)) + h.hoist_time.at(tws, twa_abs);
    }
    if (from >= 0 && p.sails[static_cast<std::size_t>(from)].has_handling) {
      const SailHandling& h = p.sails[static_cast<std::size_t>(from)].handling;
      t = (t + h.prepare_drop_time.at(tws, twa_abs)) + h.drop_time.at(tws, twa_abs);
    }
    return t;
  };
  auto request = [&](std::int32_t s) {
    if (s == cur) return;
    if (s < 0) x.w.drop_front(a.i);
    else x.w.hoist(a.i, s);
    a.tel.sail_changes = a.tel.sail_changes + 1;
    a.change_t = 0.0f;
  };
  // Drop before the rounding: the next leg's sail when its peel needs the approach.
  if (has_mark) {
    const Vec2 N = next_ref(x, m);
    const float thN = std::fabs(wrap_pi(m.twd - bearing(t.M, N)));
    float twaN = thN;
    if (thN < m.theta_up + 3.0f * DEG) twaN = m.theta_up;
    else if (thN > m.theta_dn - 3.0f * DEG) twaN = m.theta_dn;
    const std::int32_t wantN = a.pol->best_sail(tws, twaN);
    if (wantN != cur && twaN < twa_now + 5.0f * DEG) {
      const float d = max(0.0f, v_dist(m.c, t.M) - t.rho);
      const float V = max(1.0f, m.s.v);
      if (d <= V * (t_peel(wantN, cur, twa_now) + a.P.drop_lead)) {
        request(wantN);
        return;
      }
    }
  }
  if (want == cur) {
    a.change_t = 0.0f;
    return;
  }
  // After a rounding: 1 L past the mark and borne away to where the new sail is faster.
  const float v_cur = a.pol->speed_with(tws, twa_now, cur), v_new = a.pol->speed_with(tws, twa_now, want);
  const std::int32_t last = m.rb.last_rounded;
  bool just_rounded = false;
  if (last > 0 && last < static_cast<std::int32_t>(x.course.steps.size()) - 1) {
    const CourseStep& ls = x.course.steps[static_cast<std::size_t>(last)];
    for (const std::int32_t k : {ls.marks[0], ls.marks[1]}) {
      if (k < 0) continue;
      const float d = v_dist(m.c, x.course.marks[static_cast<std::size_t>(k)].pos);
      if (d < 8.0f * m.L) just_rounded = true;
      if (d < m.L + x.course.marks[static_cast<std::size_t>(k)].radius) return;  // not yet 1 L past
    }
  }
  if (just_rounded) {
    if (v_new > v_cur) request(want);
    return;
  }
  // A change on the leg: 3 % faster for 5 s and the leg long enough.
  if (v_new >= 1.03f * v_cur) a.change_t = a.change_t + 2.0f * DT;
  else a.change_t = 0.0f;
  if (a.change_t >= 5.0f) {
    const float remain = has_mark ? v_dist(m.c, t.M) / max(1.0f, m.s.v) : 1e9f;
    if (remain >= t_peel(want, cur, twa_now) + 10.0f) request(want);
  }
}

}  // namespace

Me me_of(AC& x, AB& a) {
  const std::size_t i = static_cast<std::size_t>(a.i);
  const wm::Boat& b = x.w.boat(i);
  const BoatState& s = b.state();
  const EnvAtBoat& env = x.w.env(i);
  static const RaceBoat kNoRace;
  static const BoatRules kNoRules;
  const bool cr = x.created;
  Me m{b,
       s,
       cr ? x.race.boat(i) : kNoRace,
       cr ? x.rules.boat(i) : kNoRules,
       env,
       {s.pos_x, s.pos_y},
       b.perf().dynamics.loa,
       b.perf().dynamics.bwl,
       a.tws_f,
       a.twd_f,
       0.0f,
       1.0f,
       0.7f,
       2.6f,
       0.0f,
       0.0f,
       b.controls().performance_scale,
       {env.current_x, env.current_y}};
  if (cr) {
    m.L = m.rb.L;
    m.B = m.rb.B;
  }
  m.twa = wrap_pi(m.twd - s.psi);
  m.tack = sgn(m.twa);
  const float tws = max(m.tws, 0.5f);
  m.theta_up = a.pol->theta_up(tws);
  m.theta_dn = a.pol->theta_dn(tws);
  m.v_up = a.pol->v_up(tws) * m.scale;
  m.v_dn = a.pol->v_dn(tws) * m.scale;
  return m;
}

float polar_speed(const AB& a, const Me& m, float twa_abs) { return a.pol->speed(max(m.tws, 0.5f), twa_abs) * m.scale; }

float cog_heading(const Me& m, float brg, float speed) {
  // Solve for the heading whose water track plus the current points along `brg`: the cross-track part of the
  // current is cancelled by the boat's velocity.
  const Vec2 u = dir(brg);
  const float cross = v_cross(u, m.cur);  // current to the left of the track (> 0)
  const float V = max(0.5f, speed);
  const float s = clamp(-cross / V, -0.7f, 0.7f);
  return wrap_2pi(brg - wm_asin(s));
}

bool manoeuvre_checks(AC& x, AB& a, const Me& m, bool forced) {
  if (a.man != Man::straight) return false;
  if (!forced) {
    if (x.now - a.last_man < a.P.t_cool) return false;
    if (m.s.v < 0.6f * polar_speed(a, m, std::fabs(m.twa))) return false;
    if (holding_course(x, a, m)) return false;
  }
  return true;
}

void start_tack(AC& x, AB& a, const Me& m, AiTactic why) {
  a.man = Man::tack;
  a.man_t0 = x.now;
  a.man_from = static_cast<std::int8_t>(m.tack);
  a.man_to = static_cast<std::int8_t>(-m.tack);
  a.man_passed = false;
  a.irons_t = 0.0f;
  a.irons_until = -1e9f;
  a.last_man = x.now;
  a.pend_tack = 0;
  a.foot_until = -1e9f;
  a.tactic = why;
  a.turn_dir = static_cast<std::int8_t>(m.tack);
  a.psi_target = heading_for(m.twd, -m.tack * m.theta_up);
}

void start_gybe(AC& x, AB& a, const Me& m, AiTactic why) {
  a.man = Man::gybe;
  a.man_t0 = x.now;
  a.man_from = static_cast<std::int8_t>(m.tack);
  a.man_to = static_cast<std::int8_t>(-m.tack);
  a.last_man = x.now;
  a.foot_until = -1e9f;
  a.tactic = why;
  a.turn_dir = static_cast<std::int8_t>(-m.tack);
  a.psi_target = heading_for(m.twd, -m.tack * m.theta_dn);
}

bool request_tack(AC& x, AB& a, const Me& m, AiTactic why, bool forced) {
  if (!manoeuvre_checks(x, a, m, forced)) return false;
  const float psi_new = heading_for(m.twd, -m.tack * m.theta_up);
  if (!tack_safe(x, a, m, psi_new, false)) return false;
  if (a.P.anticipate && why != AiTactic::Layline && why != AiTactic::KeepClear && why != AiTactic::Land) {
    const float d_bad = 0.35f * m.b.perf().dynamics.wind_shadow.blanket_depth;
    const float c_new = anticipation_cost(x, a, m, psi_new, d_bad);
    const float c_cur = anticipation_cost(x, a, m, m.s.psi, d_bad);
    if (c_new - c_cur > 5.0f) return false;
  }
  // §10: slow entry, first sail 5° lower for up to 8 s (unless forced).
  const float V = polar_speed(a, m, std::fabs(m.twa));
  if (!forced && m.s.v < 0.6f * V) {
    if (a.pend_tack == 0) {
      a.pend_tack = static_cast<std::int8_t>(-m.tack);
      a.pend_reason = why;
      a.low_until = x.now + 8.0f;
    }
    return true;
  }
  start_tack(x, a, m, why);
  return true;
}

bool request_gybe(AC& x, AB& a, const Me& m, AiTactic why, bool forced) {
  if (!manoeuvre_checks(x, a, m, forced)) return false;
  const float psi_new = heading_for(m.twd, -m.tack * m.theta_dn);
  if (!tack_safe(x, a, m, psi_new, true)) return false;
  start_gybe(x, a, m, why);
  return true;
}

void beat_run(AC& x, AB& a, const Me& m, Vec2 R, bool beat, float mlay, bool triggers) {
  const float th = beat ? m.theta_up : m.theta_dn;
  const float Vp = max(0.5f, beat ? m.v_up : m.v_dn);
  if (a.man == Man::tack || a.man == Man::gybe) {
    a.psi_target = heading_for(m.twd, static_cast<float>(a.man_to) * (a.man == Man::tack ? m.theta_up : m.theta_dn));
    return;
  }
  const float tk = m.tack;
  const float psi_cur = heading_for(m.twd, tk * th), psi_oth = heading_for(m.twd, -tk * th);
  const Vec2 u = v_unit(v_add(v_scale(dir(psi_cur), Vp), m.cur), dir(psi_cur));
  const Vec2 vv = v_unit(v_add(v_scale(dir(psi_oth), Vp), m.cur), dir(psi_oth));
  const Vec2 d = v_sub(R, m.c);
  const float det = v_cross(u, vv);
  bool lay = false;
  float A_ = 1e9f, B_ = 1e9f;
  if (std::fabs(det) > 1e-3f) {
    A_ = v_cross(d, vv) / det;
    B_ = v_cross(u, d) / det;
    if (B_ < 0.0f) {
      // The point is to leeward of this tack's course: sail straight at it (current corrected).
      float psi = cog_heading(m, bearing(m.c, R), m.s.v);
      const float twa = wrap_pi(m.twd - psi);
      if (beat && std::fabs(twa) < th) psi = psi_cur;
      if (!beat && std::fabs(twa) > th) psi = psi_cur;
      a.psi_target = psi;
      return;
    }
    const float trigger = 0.5f * Vp * t_manoeuvre(m, beat) - mlay * m.L;
    lay = A_ <= trigger;
  }
  // A pending slow-entry tack.
  if (a.pend_tack != 0) {
    if (a.pend_tack == static_cast<std::int8_t>(tk) || x.now > a.low_until ||
        m.s.v >= 0.8f * polar_speed(a, m, std::fabs(m.twa))) {
      const bool go = a.pend_tack != static_cast<std::int8_t>(tk);
      const AiTactic why = a.pend_reason;
      a.pend_tack = 0;
      if (go && a.man == Man::straight) {
        if (beat) start_tack(x, a, m, why);
        else start_gybe(x, a, m, why);
        return;
      }
    } else {
      a.psi_target = heading_for(m.twd, tk * (th + (beat ? 5.0f : -5.0f) * DEG));
      return;
    }
  }
  if (lay) {
    a.tactic = AiTactic::Layline;
    if (beat ? request_tack(x, a, m, AiTactic::Layline, true) : request_gybe(x, a, m, AiTactic::Layline, true)) return;
  } else if (triggers) {
    auto man = [&](AiTactic why) {
      return beat ? request_tack(x, a, m, why, false) : request_gybe(x, a, m, why, false);
    };
    const Vec2 w = dir(a.twd_ref);
    const float e = v_cross(w, v_sub(m.c, R));
    const float D_axis = beat ? v_dot(d, w) : -v_dot(d, w);
    float Wc = max(4.0f * m.L, min(0.35f * D_axis, 500.0f));
    // §9: a group leader does not split to the far side.
    if (a.P.cover == AiCover::all) {
      bool ahead = false;
      for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
        if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
        const RaceBoat& o = x.race.boat(j);
        if (o.next == m.rb.next && o.D < m.rb.D && v_dist(o.c, m.c) < 8.0f * m.L) ahead = true;
      }
      if (!ahead) Wc = 0.5f * Wc;
    }
    const float away = v_cross(w, dir(m.b.outputs().cog)) * e;
    const float brg_R = bearing(m.c, R);
    const bool headed = a.P.shifts && a.shift * sgn(wrap_pi(psi_cur - brg_R)) > 0.0f &&
                        std::fabs(a.shift) >= (beat ? a.P.h_up : a.P.h_dn);
    a.headed_t = headed ? a.headed_t + 2.0f * DT : 0.0f;
    bool pressure = false;
    if (a.P.r_read > 0.0f && (x.n % 20u) == 0u) {
      const float w_cur = read_track(x, a, m, psi_cur), w_oth = read_track(x, a, m, psi_oth);
      const float unfav = a.shift * sgn(wrap_pi(psi_oth - brg_R));
      pressure = w_oth >= 1.12f * w_cur && !(unfav > 3.0f * DEG);
      a.pressure_t = pressure ? a.pressure_t + 1.0f : 0.0f;
    }
    const bool not_overstand = A_ > 0.0f && B_ > 0.0f;
    if (std::fabs(e) >= Wc && away > 0.0f && man(AiTactic::Corridor)) return;
    if (a.headed_t >= 6.0f && not_overstand && man(AiTactic::Shift)) return;
    if (a.pressure_t >= 10.0f && not_overstand && man(AiTactic::Pressure)) return;
    if (cover(x, a, m, beat, R)) return;
  }
  // §8 bad air on every beat and run (the zones excluded inside), also close to the mark.
  if (bad_air(x, a, m, beat ? Leg::beat : Leg::run) && a.man != Man::straight) return;
  // Speed build (§4.3) and footing out of bad air (§8).
  const float Vt = polar_speed(a, m, th);
  if (m.s.v < 0.85f * Vt) a.speed_build = true;
  if (m.s.v > 0.92f * Vt) a.speed_build = false;
  float twa_t = th;
  if (a.speed_build) twa_t = beat ? th + 4.0f * DEG : th - 4.0f * DEG;
  if (x.now < a.foot_until) twa_t = twa_t - a.foot_delta;
  if (x.now < a.low_until && a.pend_tack == 0 && beat) twa_t = max(twa_t, th + 5.0f * DEG);
  a.psi_target = heading_for(m.twd, tk * twa_t);
}

void sail_to_point(AC& x, AB& a, const Me& m, Vec2 p) {
  const float brg = bearing(m.c, p);
  const float th = std::fabs(wrap_pi(m.twd - brg));
  if (th < m.theta_up + 3.0f * DEG && v_dist(m.c, p) > 2.0f * m.L) {
    beat_run(x, a, m, p, true, 0.0f, false);
    return;
  }
  if (a.man == Man::tack) {
    a.psi_target = heading_for(m.twd, static_cast<float>(a.man_to) * m.theta_up);
    return;
  }
  float psi = cog_heading(m, brg, m.s.v);
  const float twa = wrap_pi(m.twd - psi);
  if (std::fabs(twa) < m.theta_up) psi = heading_for(m.twd, sgn(twa) * m.theta_up);
  // Never turn through the wind to get there: go the other way round.
  const float e = wrap_pi(psi - m.s.psi);
  const float twa_mid = wrap_pi(m.twd - (m.s.psi + 0.5f * e));
  if (sgn(twa) != m.tack && std::fabs(twa_mid) < HALF_PI && a.man == Man::straight) {
    a.turn_dir = static_cast<std::int8_t>(e > 0.0f ? -1 : 1);
  }
  a.psi_target = psi;
}

// Racing after the start (§4, §6, §7.6, §8, §9).
void racing(AC& x, AB& a, const Me& m) {
  const std::size_t nsteps = x.course.steps.size();
  const std::int32_t last_step = static_cast<std::int32_t>(nsteps) - 1;
  const std::int32_t next = m.rb.next < 1 ? 1 : (m.rb.next > last_step ? last_step : m.rb.next);
  if (a.leg_step != next) {
    a.leg_step = next;
    a.headed_t = 0.0f;
    a.pressure_t = 0.0f;
    a.foot_until = -1e9f;
    a.pend_tack = 0;
  }
  const CourseStep& st = x.course.steps[static_cast<std::size_t>(next)];
  MarkTarget t;
  Vec2 R;
  bool finish_beat = false;
  if (st.kind == StepKind::finish) {
    R = finish_aim(x, a, m, finish_beat);
  } else {
    t = mark_target(x, a, m);
    R = t.M;
  }
  // Leg type with hysteresis (§4.1).
  const float thR = std::fabs(wrap_pi(m.twd - bearing(m.c, R)));
  const float h3 = 3.0f * DEG;
  Leg leg = a.leg;
  const float up_b = m.theta_up + 3.0f * DEG, dn_b = m.theta_dn - 3.0f * DEG;
  if (leg == Leg::beat) {
    if (thR > up_b + h3) leg = thR > dn_b ? Leg::run : Leg::reach;
  } else if (leg == Leg::run) {
    if (thR < dn_b - h3) leg = thR < up_b ? Leg::beat : Leg::reach;
  } else {
    if (thR < up_b - h3) leg = Leg::beat;
    else if (thR > dn_b + h3) leg = Leg::run;
  }
  a.leg = leg;

  if (penalty_turns(x, a, m, leg)) return;
  if (a.man == Man::penalty) a.man = Man::straight;

  if (t.is_mark) {
    const Vec2 w = dir(a.twd_f);
    Vec2 aim = t.M;
    if (leg == Leg::beat) aim = pass_point(t, w, 0.5f * m.L);
    else if (leg == Leg::run) aim = pass_point(t, v_scale(w, -1.0f), 0.5f * m.L);
    const float dist = v_dist(m.c, t.M);
    a.dbg.aim = aim;
    if (dist < t.rho + 4.0f * m.L && a.man != Man::gybe && round_mark(x, a, m, t)) {
      sails(x, a, m, true, t, leg);
      return;
    }
    if (leg == Leg::reach) {
      // The tangent point of the circle on the required side.
      const float brg = bearing(m.c, t.M);
      const float g = dist > t.rho ? wm_asin(clamp(t.rho / dist, 0.0f, 1.0f)) : HALF_PI;
      sail_to_point(x, a, m, v_add(m.c, v_scale(dir(wrap_2pi(brg + t.sigma * g)), dist)));
      reach_bad_air(x, a, m);
    } else {
      beat_run(x, a, m, aim, leg == Leg::beat, dist < 8.0f * m.L ? 0.0f : a.P.m_lay, dist > 6.0f * m.L);
    }
    sails(x, a, m, true, t, leg);
  } else {
    a.dbg.aim = R;
    if (leg == Leg::reach) {
      sail_to_point(x, a, m, R);
      reach_bad_air(x, a, m);
    } else {
      beat_run(x, a, m, R, leg == Leg::beat, a.P.m_lay, true);
    }
    sails(x, a, m, false, t, leg);
  }
  (void)finish_beat;
  // A penalty waiting for clear water: up to 15° away from the boat in the way (not above close-hauled).
  if (a.pen_prepare && a.pen_block >= 0 && a.man == Man::straight && a.tactic != AiTactic::Rounding) {
    const Vec2 cj = x.race.boat(static_cast<std::size_t>(a.pen_block)).c;
    const float side = v_cross(dir(a.psi_target), v_sub(cj, m.c)) > 0.0f ? 1.0f : -1.0f;  // > 0: boat to the left
    const float psi = wrap_2pi(a.psi_target + side * 15.0f * DEG);
    const float twa = wrap_pi(m.twd - psi);
    if (std::fabs(twa) >= m.theta_up && sgn(twa) == m.tack) a.psi_target = psi;
  }
}

// race.md §6.2: 5 L beyond the finish line and 2·(place)·L along it, then stop there.
void finished_autopilot(AC& x, AB& a, const Me& m) {
  const CourseStep& st = x.course.steps.back();
  const Vec2 A = x.course.end_a(st), B = x.course.end_b(st);
  const Vec2 u = v_unit(v_sub(B, A), {1.0f, 0.0f});
  const Vec2 beyond = right_of(u);
  const float place = static_cast<float>(max(1, m.rb.place));
  const Vec2 P = v_add(v_add(v_mid(A, B), v_scale(beyond, 5.0f * m.L)), v_scale(u, 2.0f * place * m.L));
  if (v_dist(m.c, P) < 2.0f * m.L) {
    a.psi_target = heading_for(m.twd, m.tack * 60.0f * DEG);
    a.let_fly = true;
  } else {
    sail_to_point(x, a, m, P);
  }
}

}  // namespace wm::ai_detail

namespace wm::ai_detail {

void ai_decide(AC& x, AB& a) {
  // Defaults of a decision; the manoeuvre in progress keeps its own.
  a.let_fly = false;
  a.forced = false;
  if (a.man != Man::tack && a.man != Man::penalty) a.helm_fixed = NAN;
  if (a.man != Man::gybe) a.r_limit = NAN;
  if (a.man == Man::gybe) a.r_limit = 15.0f * DEG;
  a.tactic = AiTactic::None;
  const Me m = me_of(x, a);
  if (!x.created) {
    a.psi_target = m.s.psi;
    return;
  }
  const RaceState rs = x.race.state();
  if (rs == RaceState::closed || rs == RaceState::abandoned) {
    a.psi_target = m.s.psi;
    a.let_fly = true;
    return;
  }
  if (m.rb.finished || m.rb.ghost) {
    if (a.man == Man::penalty) a.man = Man::straight;
    a.helm_fixed = NAN;
    finished_autopilot(x, a, m);
    return;
  }
  if (a.autopilot_only) return;
  Vec2 aim = m.c;
  if (rs == RaceState::created || rs == RaceState::free_sailing) {
    free_sailing(x, a, m);
  } else if (!m.rb.started && !m.rb.ocs_scored) {
    // A pre-start penalty is taken before the start when clear (rules.md §9.3), not in the last 20 s.
    if ((x.t_race < -20.0f || x.race.after_gun(x.n) || a.pen_on)) {
      if (penalty_turns(x, a, m, std::fabs(m.twa) > HALF_PI ? Leg::run : Leg::beat)) {
        rules_overlay(x, a, m, m.c);
        return;
      }
      if (a.pen_prepare && !x.race.after_gun(x.n)) {
        // Speed and clear water for the turn: a broad reach on starboard away from the line, sails in.
        a.tactic = AiTactic::PenaltyTurn;
        a.psi_target = heading_for(m.twd, 110.0f * DEG);
        if (m.tack < 0.0f && std::fabs(m.twa) < HALF_PI) a.turn_dir = 1;
        avoid_objects(x, a, m, -1);
        if (!land_check(x, a, m)) rules_overlay(x, a, m, m.c);
        return;
      }
    }
    if (!x.race.after_gun(x.n)) prestart(x, a, m);
    else after_gun(x, a, m);
    aim = a.dbg.spot;
  } else {
    racing(x, a, m);
    aim = a.dbg.aim;
  }
  avoid_objects(x, a, m, a.tactic == AiTactic::Rounding ? a.round_mark : -1);
  if (!land_check(x, a, m)) rules_overlay(x, a, m, aim);
}

}  // namespace wm::ai_detail
