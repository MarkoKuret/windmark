// The start (ai.md §5): free sailing, line analysis, setup point, hovering, the go decision, the final approach,
// the launch, OCS returns and the match race entry.
#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

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

// §5.3, §5.4: the setup point lies on the bearing θ_CH + 25° from the spot (the middle of the sector from which the
// spot can be laid on starboard, between close-hauled and a beam reach), so drifting while parked does not put the
// spot out of reach. The approach itself sails the bearing to the spot.
float approach_heading(const Me& m) { return heading_for(m.twd, m.theta_up + 25.0f * DEG); }

// The approach TWA to the spot from here: the bearing's, between close-hauled + 2° and 115°.
float approach_twa(const Me& m, Vec2 spot) {
  return clamp(wrap_pi(m.twd - bearing(m.c, spot)), m.theta_up + 2.0f * DEG, 115.0f * DEG);
}

// §5.2 line analysis: the spot each AI would like (the favoured end, or the middle, plus its own spread draw).
float wanted_spot(AC& x, AB& a, const Line& l, float L) {
  if (!a.drawn) {
    a.drawn = true;
    a.spread_r = draw(x, a, RngStream::ai_first);
    a.e_start = rng_range(a.P.e_start_lo, a.P.e_start_hi, x.race.settings().race_seed, RngStream::ai_first,
                          (static_cast<std::uint64_t>(static_cast<std::uint32_t>(a.i)) << 32) | a.k16++);
  }
  const Vec2 w = dir(a.twd_ref);
  const float du = v_dot(v_sub(l.B, l.A), w);
  const bool significant = std::fabs(du) > max(L, 0.05f * l.len);
  float u = 0.5f;
  if (significant) u = du > 0.0f ? 0.85f : 0.15f;
  return clamp(u + a.P.spread * (a.spread_r - 0.5f), 0.05f, 0.95f);
}

void choose_spot(AC& x, AB& a, const Me& m, const Line& l) {
  // Fleet spots are assigned jointly (assign_spots); a match race boat takes her side's.
  if (x.race.race_type() == RaceType::match) {
    (void)wanted_spot(x, a, l, m.L);
    a.spot_u = a.i == 0 ? 0.62f : 0.38f;
    a.spot_fixed = true;
  }
}

}  // namespace

// §5.2 fleet spots, for all AIs together: the spots are the AIs' wanted spots, spread to at least 2 L apart, and
// they are handed out in the order of the boats' present positions along the line, so no two approaches cross.
// Chosen when the race is created, again at -75 s (the mean wind is known better by then), and when an AI's
// bias estimate changes by more than 5°.
void assign_spots(AC& x) {
  if (!x.created || x.race.race_type() == RaceType::match || x.ai == nullptr) return;
  const RaceState rs = x.race.state();
  if (!(rs == RaceState::free_sailing || rs == RaceState::sequence) || x.race.after_gun(x.n)) return;
  const Line l = start_line(x);
  const bool final_choice = rs == RaceState::sequence && x.t_race >= -75.0f;
  std::vector<AB*> fleet;
  bool need = false;
  float L = 1.0f;
  for (const auto& p : *x.ai) {
    AB& a = *p;
    const std::size_t i = static_cast<std::size_t>(a.i);
    if (!a.active || a.autopilot_only || i >= x.w.boat_count() || !a.init) continue;
    const RaceBoat& rb = x.race.boat(i);
    if (rb.ghost || rb.started) continue;
    fleet.push_back(&a);
    L = max(L, rb.L);
    const float beta = wrap_pi(compass(l.n) - a.twd_ref);
    if (!a.spot_fixed || (final_choice && a.phase == StartPhase::free) ||
        std::fabs(wrap_pi(beta - a.spot_beta)) > 5.0f * DEG) {
      need = true;
    }
  }
  if (!need || fleet.empty()) return;
  std::vector<float> want;
  for (AB* a : fleet) want.push_back(wanted_spot(x, *a, l, L));
  std::sort(want.begin(), want.end());
  const std::size_t n = want.size();
  const float step = n > 1 ? min(2.0f * L / l.len, 0.9f / static_cast<float>(n - 1)) : 0.0f;
  for (std::size_t k = 1; k < n; ++k) want[k] = max(want[k], want[k - 1] + step);
  if (want[n - 1] > 0.95f) {
    want[n - 1] = 0.95f;
    for (std::size_t k = n - 1; k > 0; --k) want[k - 1] = min(want[k - 1], want[k] - step);
  }
  // Boats in the order of their positions along the line (ties by index).
  std::vector<std::pair<float, std::int32_t>> order;
  for (std::size_t k = 0; k < n; ++k) {
    order.push_back({v_dot(v_sub(x.race.boat(static_cast<std::size_t>(fleet[k]->i)).c, l.A), l.u), static_cast<std::int32_t>(k)});
  }
  std::sort(order.begin(), order.end(), [&](const auto& p, const auto& q) {
    return p.first != q.first ? p.first < q.first : fleet[static_cast<std::size_t>(p.second)]->i < fleet[static_cast<std::size_t>(q.second)]->i;
  });
  for (std::size_t k = 0; k < n; ++k) {
    AB& a = *fleet[static_cast<std::size_t>(order[k].second)];
    a.spot_u = clamp(want[k], 0.05f, 0.95f);
    a.spot_rank = static_cast<std::int32_t>(k);
    a.spot_fixed = true;
    a.spot_beta = wrap_pi(compass(l.n) - a.twd_ref);
    if (final_choice) a.phase = StartPhase::hover;
  }
}

namespace {

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
  if (m.rb.ocs || (!m.rb.pre_seen && s > -1.0f * m.L)) {
    // Back to the pre-start side, 2 L behind the line: bear away and gybe round (never tack). A boat not yet seen
    // completely on the pre-start side after the gun (race.md §4.2) dips back too.
    const Vec2 p = v_sub(m.c, v_scale(l.n, s + 2.0f * m.L));
    sail_to_point(x, a, m, p);
    return;
  }
  a.ret_stage = 0;
  // Behind the line in the band: go and start.
  if (u > 0.06f && u < 0.94f) {
    beat_run(x, a, m, x.course.steps[1].ref, true, 0.0f, false);
    const float twa = wrap_pi(m.twd - a.psi_target);
    const Vec2 f = dir(a.psi_target);
    // Heading away from the line on this tack: take the other.
    if (v_dot(f, l.n) <= 0.1f) a.psi_target = heading_for(m.twd, -sgn(twa) * m.theta_up);
    return;
  }
  // Outside the band: to a point behind the line inside it, then up through it.
  const float u_in = clamp(u, 0.12f, 0.88f);
  const Vec2 on_line = v_add(l.A, v_scale(v_sub(l.B, l.A), u_in));
  const Vec2 entry = v_sub(on_line, v_scale(l.n, 1.5f * m.L));
  sail_to_point(x, a, m, s < -0.5f * m.L && std::fabs(u - u_in) * l.len < 1.0f * m.L
                             ? v_add(on_line, v_scale(l.n, 2.0f * m.L))
                             : entry);
}

}  // namespace

float time_to_spot(const AB& a, const Me& m, Vec2 spot, float psi_app) {
  // §5.5 with the boat's own acceleration law (boat.md §5.8): from rest the rate blends from accel_rest to accel
  // at half the target speed; sails let fly take about 2 s to come in.
  (void)psi_app;
  const float v0 = max(0.0f, m.s.v);
  const float turn_radius = m.b.perf().dynamics.turn_radius_full;
  const float th_a = approach_twa(m, spot);
  const float dpsi = std::fabs(wrap_pi(heading_for(m.twd, th_a) - m.s.psi));
  float t = min(dpsi / (max(v0, 0.5f) / turn_radius), 8.0f);
  if (m.b.controls().let_fly) t = t + 2.0f;
  const float tws = max(0.5f, m.tws);
  const std::int32_t front = m.b.sails().front();
  const ConfigPerf* cp = m.b.perf().config_for(front);
  const float V = m.b.polar_at(tws, th_a, front) * m.scale;
  const float acc = m.b.accel_at(tws, th_a, front);
  const float acc_rest = cp != nullptr && cp->accel_rest.present ? cp->accel_rest.table.at(tws, th_a) : acc;
  const Vec2 bow = v_add(m.c, v_scale(dir(m.s.psi), 0.5f * m.L));
  const float d_path = v_dist(bow, spot);
  float v = v0, xx = 0.0f;
  for (std::int32_t k = 0; k < 1200 && xx < d_path; ++k) {
    float aa = 0.0f;
    if (v < V) {
      const float vb = 0.5f * V;
      aa = v < vb ? acc_rest + (acc - acc_rest) * (v / vb) : acc;
    }
    v = min(v + aa * 0.1f, max(V, v0));
    xx = xx + v * 0.1f;
    t = t + 0.1f;
  }
  (void)a;
  return t;
}

// The go decision's estimate: the boat reaches the table speed later than the tables alone say (the trim settles,
// the heading wanders), so a margin that errs on the early side, which the final approach takes off by letting fly.
float time_to_spot_go(const AB& a, const Me& m, Vec2 spot) { return 1.1f * time_to_spot(a, m, spot, 0.0f) + 2.0f; }

// §5.4 staying near S: sail back to it when more than 2 L away (slowing on the way in), else park on starboard
// close-hauled with the sails let fly. The way back never tacks (sail_to_point turns through a gybe).
void hover(AC& x, AB& a, const Me& m, Vec2 S, bool may_loop) {
  const float d = v_dist(m.c, S);
  const float V = polar_speed(a, m, 60.0f * DEG);
  if (d > 3.0f * m.L && may_loop) a.loop = true;
  if (d < 1.0f * m.L) a.loop = false;
  if (a.loop) {
    sail_to_point(x, a, m, S);
    // Arrive slowly.
    if (d < 5.0f * m.L && m.s.v > 0.6f * V) a.let_fly = true;
    return;
  }
  a.psi_target = heading_for(m.twd, 50.0f * DEG);
  if (m.tack < 0.0f) a.turn_dir = 1;  // port: back to starboard by bearing away
  // The sails come in to turn onto the parking heading (a stopped boat does not steer), then go out.
  const bool on_heading = std::fabs(wrap_pi(a.psi_target - m.s.psi)) < 15.0f * DEG;
  a.let_fly = m.tack > 0.0f && (on_heading || m.s.v > 0.5f * V);
  a.hover_fly = a.let_fly;
}

void free_sailing(AC& x, AB& a, const Me& m) {
  // Near the own setup point, a little farther back (§5.1): each boat has its own, so the fleet does not bunch.
  const Line l = start_line(x);
  choose_spot(x, a, m, l);
  const Vec2 spot = spot_point(a, l, 0.3f * m.L);
  const float d_back = m.v_up * a.P.t_final;
  const float stagger = static_cast<float>(a.spot_rank % 2) * 1.5f * m.L;
  hover(x, a, m, v_sub(v_sub(spot, v_scale(dir(approach_heading(m)), 1.2f * d_back)), v_scale(l.n, stagger)), true);
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
      hover(x, a, m, v_sub(v_add(end, v_scale(out, 6.0f * m.L)), v_scale(l.n, 2.0f * m.L)), true);
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
  // Neighbouring spots park at depths 1.5 L apart, so a boat on her way to her setup point passes the parked ones.
  const Vec2 S = v_sub(v_sub(spot, v_scale(dir(psi_app), d_back)),
                       v_scale(l.n, static_cast<float>(a.spot_rank % 2) * 1.5f * m.L));
  // Over the line before the gun: back to the pre-start side at once.
  if (v_dot(v_sub(m.c, l.A), l.n) > -0.5f * m.L && s_bow > -0.1f * m.L && !a.go) {
    sail_to_point(x, a, m, v_sub(m.c, v_scale(l.n, s_bow + 3.0f * m.L)));
    return;
  }
  if (!a.go) {
    if (t >= -75.0f) {
      const float t_run = time_to_spot_go(a, m, spot);
      if (-t <= t_run + 1.0f + a.e_start) {
        a.go = true;
        a.loop = false;
        // A spot above close-hauled from here is out of reach: take the one the close-hauled course meets, when
        // that is inside the band.
        const float twa_s = wrap_pi(m.twd - bearing(m.c, spot));
        if (twa_s < m.theta_up + 2.0f * DEG) {
          const Vec2 f = dir(heading_for(m.twd, m.theta_up + 2.0f * DEG));
          const float den = v_dot(f, l.n);
          if (den > 0.1f) {
            const float k = -v_dot(v_sub(m.c, l.A), l.n) / den;
            const float u_reach = v_dot(v_sub(v_add(m.c, v_scale(f, k)), l.A), l.u) / l.len;
            if (u_reach > 0.08f && u_reach < 0.92f) a.spot_u = u_reach;
          }
        }
      }
    }
    if (!a.go) {
      hover(x, a, m, S, true);
      return;
    }
  }
  // §5.6 final approach on starboard: the bearing to the spot (current corrected), no higher than close-hauled.
  float psi = cog_heading(m, heading_for(m.twd, approach_twa(m, spot)), m.s.v);
  if (v_dist(m.c, spot) < 2.0f * m.L) psi = heading_for(m.twd, m.theta_up + 2.0f * DEG);
  const float t_run = time_to_spot(a, m, spot, psi_app);
  const float want = (-t) + a.e_start;  // arrival time wanted, from now
  const float early = want - t_run;
  if (early > 1.0f) a.let_fly = true;
  // Late: full speed on the course to the spot (bearing away from it only makes the boat miss it).
  // Brake: at the present speed the bow would reach the line before the gun and it is within the stopping distance
  // with the sails let fly (about 5 s of the present speed: a let-fly boat loses speed slowly).
  const Vec2 vel = v_add(v_scale(dir(m.s.psi), max(0.0f, m.s.v)), m.cur);
  const float v_n = max(0.05f, v_dot(vel, l.n));
  const float D = max(0.0f, -s_bow);
  if (t < -0.3f && D < v_n * 5.0f + 0.3f * m.L && D / v_n < -t + max(0.0f, a.e_start) - 0.3f) a.let_fly = true;
  if (t < -0.3f && D < 0.3f * m.L) {
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
