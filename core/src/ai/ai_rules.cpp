// Rules-aware sailing (ai.md §7): keeping clear by candidate evaluation, the checks before gaining right of way,
// holding course, rule 17, the emergency evasion; land and the race area (§4.6); the anticipated wind deficit.
#include <cmath>

#include "ai/ai_predict.h"
#include "ai/ai_steps.h"

namespace wm::ai_detail {

namespace {

constexpr std::int32_t kSamples = 60;  // 6 s at 0.1 s

Motion motion_of(AC& x, std::size_t j) {
  const wm::Boat& b = x.w.boat(j);
  const BoatState& s = b.state();
  Motion m;
  m.c = {s.pos_x, s.pos_y};
  m.psi = s.psi;
  m.v = s.v;
  m.r = b.outputs().turn_rate;
  // The drift over the ground: current plus the sideways drift of a stalled boat (rules.md §3.1).
  m.cur = v_add(Vec2{x.w.env(j).current_x, x.w.env(j).current_y}, b.drift_velocity());
  return m;
}

const std::vector<Vec2>& hull(AC& x, std::size_t j) { return x.w.boat(j).perf().dynamics.collision.outline; }

float margin(AC& x) { return max(x.rules.params().margin_min, x.rules.params().margin_coef * x.race.L_max()); }

OwnPlan plan_to(const Me& m, float psi_to, std::int8_t dir_, bool slow, float rate) {
  OwnPlan p;
  p.psi_to = psi_to;
  p.dir = dir_;
  p.slow = slow;
  const float v = max(0.5f, std::fabs(m.s.v));
  p.rate = rate > 0.0f ? rate : v / m.b.perf().dynamics.turn_radius_full;
  p.twd = m.twd;
  p.decel_linear = m.b.perf().dynamics.decel_linear;
  p.decel_const = m.b.perf().dynamics.decel_const;
  if (slow) p.slow_floor = m.b.let_fly_drive() * max(0.0f, m.s.v);
  return p;
}

// Other racing boats near the AI, nearest first by centre distance.
void neighbours(AC& x, const AB& a, const Me& m, float radius, std::vector<std::size_t>& out) {
  out.clear();
  for (std::size_t j = 0; j < x.w.boat_count(); ++j) {
    if (static_cast<std::int32_t>(j) == a.i || !x.race.racing(j)) continue;
    if (v_dist(x.race.boat(j).c, m.c) < radius) out.push_back(j);
  }
}

// rules.md §3.6 from predicted tracks: can boat `j` (track tj from sample k0) keep clear of `own` over 3 s?
bool escape(AC& x, std::size_t j, const Track& tj, std::int32_t k0, const Track& own, const std::vector<Vec2>& own_hull,
            float r_own) {
  const wm::Boat& b = x.w.boat(j);
  const Dynamics& d = b.perf().dynamics;
  Motion mj;
  mj.c = tj.c[static_cast<std::size_t>(k0)];
  mj.psi = tj.psi[static_cast<std::size_t>(k0)];
  mj.v = b.state().v;
  mj.r = b.outputs().turn_rate;
  mj.cur = v_add(Vec2{x.w.env(j).current_x, x.w.env(j).current_y}, b.drift_velocity());
  const float rate = max(0.3f, std::fabs(mj.v)) / d.turn_radius_full;
  // Own track from k0 on.
  Track o;
  o.c.assign(own.c.begin() + k0, own.c.end());
  o.psi.assign(own.psi.begin() + k0, own.psi.end());
  const std::int32_t K = 30;
  for (std::int32_t k = 0; k < 4; ++k) {
    OwnPlan p;
    p.delay = 0.3f;
    p.twd = mj.psi;  // no no-go slowdown for the escape turns
    p.decel_linear = d.decel_linear;
    p.decel_const = d.decel_const;
    if (k == 0) {
      p.psi_to = mj.psi;
      p.rate = 0.0f;
    } else if (k == 1 || k == 2) {
      p.psi_to = wrap_2pi(mj.psi + (k == 1 ? -1.0f : 1.0f) * 3.0f);
      p.dir = static_cast<std::int8_t>(k == 1 ? -1 : 1);
      p.rate = rate;
    } else {
      p.psi_to = mj.psi;
      p.slow = true;
      p.slow_floor = b.let_fly_drive() * max(0.0f, mj.v);
    }
    Motion mm = mj;
    if (k == 0) mm.r = 0.0f;
    Track e;
    predict_plan(mm, p, K, e);
    if (tracks_gap(hull(x, j), x.r_hull[j], e, own_hull, r_own, o, 0, K, 1.0f) > 0.0f) return true;
  }
  return false;
}

// The own track of a candidate: a heading (turning at |v|/R_full), a tack or gybe (helm 0.6), or braking.
void own_track(const Me& m, float psi_to, std::int8_t turn, bool slow, bool manoeuvre, Track& out) {
  Motion mo;
  mo.c = m.c;
  mo.psi = m.s.psi;
  mo.v = max(0.0f, m.s.v);
  mo.r = 0.0f;
  mo.cur = m.cur;
  float rate = 0.0f;
  if (manoeuvre) {
    const float R = radius_for_helm(m.b.perf().dynamics, 0.6f);
    rate = max(0.5f, mo.v) / R;
  }
  OwnPlan p = plan_to(m, psi_to, turn, slow, rate);
  // A slow boat with the sails drawing picks up speed (boat.md §5.8): without it a stopped boat sees no way out.
  const float twa = std::fabs(wrap_pi(m.twd - psi_to));
  const std::int32_t front = m.b.sails().front();
  p.v_target = m.b.polar_at(max(0.5f, m.tws), twa, front) * m.scale;
  p.accel = 0.5f * m.b.accel_at(max(0.5f, m.tws), twa, front);
  predict_plan(mo, p, kSamples, out);
}

struct Candidate {
  float psi = 0.0f;
  std::int8_t turn = 0;
  bool slow = false;
  bool manoeuvre = false;
  float cost = 1e30f;
};

}  // namespace

// The hull along a predicted track stays clear of every course object (a tack or gybe does not sweep into a mark).
bool track_clear_of_objects(AC& x, const AB& a, const Track& own) {
  const std::vector<Vec2>& oh = hull(x, static_cast<std::size_t>(a.i));
  const float ro = x.r_hull[static_cast<std::size_t>(a.i)];
  for (const CourseObject& o : x.course.objects) {
    for (std::size_t k = 0; k < own.c.size(); k = k + 2) {
      if (v_dist(own.c[k], o.c) - ro - o.r > 1.0f) continue;
      const std::span<const Vec2> placed = own.hull(oh, k).pts();
      if (point_in_polygon(o.c, placed) || point_polygon_edge_dist(o.c, placed) < o.r + 0.3f) return false;
    }
  }
  return true;
}

bool tack_safe(AC& x, AB& a, const Me& m, float psi_new, bool gybe) {
  {
    Track own;
    own_track(m, psi_new, static_cast<std::int8_t>(gybe ? -m.tack : m.tack), false, true, own);
    if (!track_clear_of_objects(x, a, own)) return false;
  }
  if (!x.race.rules_live()) return true;
  static thread_local std::vector<std::size_t> nb;
  neighbours(x, a, m, 5.0f * m.L + 2.0f * x.r_hull[static_cast<std::size_t>(a.i)], nb);
  if (nb.empty()) return true;
  Track own;
  own_track(m, psi_new, static_cast<std::int8_t>(gybe ? -m.tack : m.tack), false, true, own);
  const std::vector<Vec2>& oh = hull(x, static_cast<std::size_t>(a.i));
  const float ro = x.r_hull[static_cast<std::size_t>(a.i)];
  const float new_tack = -m.tack;
  for (const std::size_t j : nb) {
    Track tj;
    predict_ctrv(motion_of(x, j), kSamples, tj);
    const float tj_twa = wrap_pi(x.w.env(j).wind_from_clean - x.w.boat(j).state().psi);
    const float g = tracks_gap(hull(x, j), x.r_hull[j], tj, oh, ro, own, 0, kSamples, 2.0f * m.L);
    // Rule 13: never tack within 3 L into the path of a boat on the tack we go to... or of one we must keep clear of.
    if (v_dist(x.race.boat(j).c, m.c) < 3.0f * m.L + x.r_hull[j] && g < m.L) return false;
    if (g < margin(x)) return false;
    // Rules 13/15: from the poses 3 s on, the other boat must still be able to keep clear of us.
    const bool we_gain = sgn(tj_twa) != new_tack || gybe;
    if (we_gain && g < 2.0f * m.L && !escape(x, j, tj, 30, own, oh, ro)) return false;
  }
  (void)a;
  return true;
}

bool holding_course(AC& x, AB& a, const Me& m) {
  for (const PairRecord* p : x.pairs_of[static_cast<std::size_t>(a.i)]) {
    if (p->kc_holder != a.i || p->kc_giver < 0) continue;
    if (!x.race.racing(static_cast<std::size_t>(p->kc_giver))) continue;
    if (p->gap < 5.0f * m.L && p->kc_state != KcState::breach) return true;
  }
  return false;
}

float predicted_deficit(AC& x, const AB& a, Vec2 p) {
  const WindField& wf = x.w.wind();
  const WindSample ws = wf.wind_clean(wf.current_tick(), p.x, p.y);
  const ShadowedWind sw = shadowed_wind(x.snap, a.i, p.x, p.y, ws.speed, ws.from);
  return sw.loss;
}

bool land_check(AC& x, AB& a, const Me& m) {
  if (a.man != Man::straight) return false;
  // Predicted position over 8 s on the present motion against land, obstacles, the area boundary and exclusions.
  const float v = max(0.0f, m.s.v);
  const Vec2 vel = v_add(v_scale(dir(m.s.psi), v), m.cur);
  const float lim = 2.0f * m.L;
  bool hit = false;
  Vec2 near_pt = m.c;
  const VenueData* ven = x.w.setup().venue;
  for (std::int32_t k = 0; k <= 8 && !hit; k = k + 2) {
    const Vec2 p = v_add(m.c, v_scale(vel, static_cast<float>(k)));
    if (ven != nullptr) {
      for (const VenueLand& l : ven->land) {
        if (point_in_polygon(p, l.points) || point_polygon_edge_dist(p, l.points) < lim) {
          hit = true;
          near_pt = p;
        }
      }
      for (const VenueObstacle& o : ven->obstacles) {
        const float d = o.is_circle ? v_dist(p, o.c) - o.r
                                    : (point_in_polygon(p, o.polygon) ? 0.0f : point_polygon_edge_dist(p, o.polygon));
        if (d < lim) {
          hit = true;
          near_pt = o.is_circle ? o.c : p;
        }
      }
    }
    if (x.course.has_boundary && x.course.boundary.size() >= 3) {
      if (!point_in_polygon(p, x.course.boundary) || point_polygon_edge_dist(p, x.course.boundary) < lim) {
        hit = true;
        near_pt = p;
      }
    }
    for (const std::vector<Vec2>& ex : x.course.exclusions) {
      if (point_in_polygon(p, ex) || point_polygon_edge_dist(p, ex) < lim) {
        hit = true;
        near_pt = p;
      }
    }
  }
  if (!hit) return false;
  // Turn away: beat → tack, run → gybe, reach → away from the side of the obstruction.
  a.tactic = AiTactic::Land;
  const float twa_abs = std::fabs(m.twa);
  const bool inside_area = !x.course.has_boundary || point_in_polygon(m.c, x.course.boundary);
  (void)inside_area;
  if (twa_abs < m.theta_up + 15.0f * DEG) {
    if (request_tack(x, a, m, AiTactic::Land, true)) return true;
  } else if (twa_abs > m.theta_dn - 15.0f * DEG) {
    if (request_gybe(x, a, m, AiTactic::Land, true)) return true;
  }
  const float side = v_cross(dir(m.s.psi), v_sub(near_pt, m.c));  // > 0: obstruction to the left
  const float turn = side > 0.0f ? 1.0f : -1.0f;
  float psi = wrap_2pi(m.s.psi + turn * 40.0f * DEG);
  const float twa = wrap_pi(m.twd - psi);
  if (std::fabs(twa) < m.theta_up) psi = heading_for(m.twd, sgn(m.twa) * m.theta_up);
  a.psi_target = psi;
  return true;
}

namespace {

// The hull along a predicted track touches one course object (a clearance of `clear` metres).
bool track_touches(AC& x, const AB& a, const Track& own, const CourseObject& o, float clear) {
  const std::vector<Vec2>& oh = hull(x, static_cast<std::size_t>(a.i));
  const float ro = x.r_hull[static_cast<std::size_t>(a.i)];
  for (std::size_t k = 0; k < own.c.size(); ++k) {
    if (v_dist(own.c[k], o.c) - ro - o.r > clear) continue;
    const std::span<const Vec2> placed = own.hull(oh, k).pts();
    if (point_in_polygon(o.c, placed) || point_polygon_edge_dist(o.c, placed) < o.r + clear) return true;
  }
  return false;
}

// §6.4 the rounding check: the planned heading of a rounding, sailed from here with the turn the helm makes (the
// reaction time, then the radius law's rate), keeps the hull off the mark for 4 s. If not, the nearest heading that
// does, turning away from the mark (the rounding side) by up to 45°, and still sailable; false when none is.
bool rounding_track_check(AC& x, AB& a, const Me& m, const CourseObject& o) {
  const float clear = 0.3f;
  Track own;
  own_track(m, a.psi_target, 0, false, false, own);
  own.c.resize(41);
  own.psi.resize(41);
  if (!track_touches(x, a, own, o, clear)) return true;
  // Away from the mark: a port rounding has it on the left, so away is clockwise.
  const float away = -a.round_sigma;
  for (std::int32_t k = 1; k <= 9; ++k) {
    const float psi = wrap_2pi(a.psi_target + away * static_cast<float>(k) * 5.0f * DEG);
    const float twa = wrap_pi(m.twd - psi);
    if (std::fabs(twa) < m.theta_up - 2.0f * DEG) break;  // not sailable: the caller tacks or slows
    own_track(m, psi, 0, false, false, own);
    own.c.resize(41);
    own.psi.resize(41);
    if (!track_touches(x, a, own, o, clear)) {
      a.psi_target = psi;
      return true;
    }
  }
  return false;
}

}  // namespace

void avoid_objects(AC& x, AB& a, const Me& m, std::int32_t skip_mark) {
  if (a.man != Man::straight) return;
  const float v = max(1.0f, m.s.v);
  const float reach = max(3.0f * m.L, 6.0f * v);
  const Vec2 f = dir(a.psi_target);
  float best_t = 1e30f;
  const CourseObject* hit = nullptr;
  float need = 0.0f;
  for (const CourseObject& o : x.course.objects) {
    const Vec2 d = v_sub(o.c, m.c);
    const float along = v_dot(d, f);
    if (along <= 0.0f || along > reach + o.r) continue;
    // The mark being rounded: only a collision course (the rounding circle keeps the planned clearance).
    float clear = o.mark == skip_mark ? (o.r + 0.5f * m.B) + 0.5f : (o.r + 0.5f * m.B) + (1.0f + 0.15f * m.L);
    // A committee or mark boat is long and flat-sided: the bow of a boat still turning onto the tangent reaches it
    // first, so keep another half length off.
    if (o.is_boat && o.mark != skip_mark) clear = clear + 0.5f * m.L;
    if (std::fabs(v_cross(f, d)) >= clear) continue;
    if (along < best_t) {
      best_t = along;
      hit = &o;
      need = clear;
    }
  }
  if (hit == nullptr && skip_mark >= 0 && skip_mark == a.round_mark) {
    // Clear of the straight line: the track through the turn must be too (the bow and stern sweep as she turns, and
    // she runs on before the turn takes hold).
    for (const CourseObject& o : x.course.objects) {
      if (o.mark != skip_mark || v_dist(o.c, m.c) > reach + o.r) continue;
      if (rounding_track_check(x, a, m, o)) return;
      hit = &o;
      need = (o.r + 0.5f * m.B) + 0.5f;
      best_t = 0.0f;
    }
  }
  if (hit == nullptr) return;
  // Pass it on the side it already is on, by the tangent to the clearance circle; the mark being rounded on the
  // rounding side (port rounding: on the left), even when the planned heading has it a little on the other.
  const float dist = v_dist(m.c, hit->c);
  const float g = dist > need ? wm_asin(clamp(need / dist, 0.0f, 1.0f)) : HALF_PI;
  const float brg = bearing(m.c, hit->c);
  float side = v_cross(f, v_sub(hit->c, m.c)) > 0.0f ? 1.0f : -1.0f;  // > 0: object to the left
  const bool rounding_mark = hit->mark == skip_mark && skip_mark == a.round_mark;
  if (rounding_mark) side = a.round_sigma;
  float psi = wrap_2pi(brg + side * g);
  float twa = wrap_pi(m.twd - psi);
  // Sailable from here without a tack or gybe: not above close-hauled and on the present tack.
  auto on_this_tack = [&](float t) { return std::fabs(t) >= m.theta_up - 2.0f * DEG && sgn(t) == m.tack; };
  if (rounding_mark && !on_this_tack(twa)) {
    // The mark being rounded is passed on its side only: tack (or gybe) away from it when that side is not on this
    // tack. If the manoeuvre is not safe, past it on the other side when that is sailable on this tack, rather than
    // into it: the rounding then goes on round (the winding of §6.1 counts it), which costs less than a touch and
    // its turn. Only when neither is possible pinch and slow; slowing needs way on: a boat nearly stopped at the
    // mark keeps her sails drawing, or she could never steer away (ai.md §6.4).
    const bool gybe = std::fabs(twa) > HALF_PI && std::fabs(m.twa) > HALF_PI;
    if (gybe ? request_gybe(x, a, m, AiTactic::Rounding, true) : request_tack(x, a, m, AiTactic::Rounding, true)) return;
    const float psi_o = wrap_2pi(brg - side * g);
    if (on_this_tack(wrap_pi(m.twd - psi_o))) {
      a.psi_target = psi_o;
      return;
    }
    a.psi_target = heading_for(m.twd, m.tack * m.theta_up);
    a.let_fly = m.s.v > 0.5f;
    return;
  }
  if (rounding_mark) {
    // The tangent, and then the track through the turn onto it: the bow and stern sweep as she turns.
    a.psi_target = psi;
    if (!rounding_track_check(x, a, m, *hit)) a.let_fly = m.s.v > 0.5f;
    return;
  }
  if (std::fabs(twa) < m.theta_up - 2.0f * DEG) {
    // Not sailable that way: the other side.
    psi = wrap_2pi(brg - side * g);
    twa = wrap_pi(m.twd - psi);
    if (std::fabs(twa) < m.theta_up - 2.0f * DEG) psi = heading_for(m.twd, m.tack * m.theta_up);
  }
  a.psi_target = psi;
}

void rules_overlay(AC& x, AB& a, const Me& m, Vec2 aim) {
  if (!x.race.rules_live() || m.rb.ghost) return;
  const std::size_t i = static_cast<std::size_t>(a.i);
  std::int32_t B = -1;
  float best_ttc = 1e30f;
  bool emergency = false;
  bool r17 = false;
  static thread_local std::vector<std::int32_t> holds;
  holds.clear();
  for (const PairRecord* p : x.pairs_of[i]) {
    const std::int32_t j = p->i == a.i ? p->j : p->i;
    if (!x.race.racing(static_cast<std::size_t>(j))) continue;
    if (p->gap > 10.0f * m.L) continue;
    if (p->kc_giver == a.i) {
      const bool trig = p->kc_state != KcState::clear || p->ttc < a.P.h_avoid;
      if (trig && p->ttc < best_ttc) {
        best_ttc = p->ttc;
        B = j;
      }
      if (trig && B < 0) B = j;
    } else if (p->kc_holder == a.i) {
      if (p->kc_state == KcState::breach && p->ttc < 1.5f) {
        emergency = true;
        if (p->ttc < best_ttc) {
          best_ttc = p->ttc;
          B = j;
        }
      } else if (p->gap < 5.0f * m.L) {
        holds.push_back(j);
      }
    }
    if (p->rule17_holder == a.i) r17 = true;
  }
  const bool in_man = a.man != Man::straight;
  const bool rounding = a.tactic == AiTactic::Rounding && a.round_mark >= 0;  // the plan of this decision
  const bool active = B >= 0 || x.now < a.avoid_until;
  if (active && (!in_man || emergency) && a.man != Man::penalty) {
    if (B < 0) B = a.avoid_other;
    if (B >= 0 && x.race.racing(static_cast<std::size_t>(B))) {
      if (B >= 0 && (x.now >= a.avoid_until || a.avoid_other != B)) a.avoid_until = x.now + 1.5f;
      a.avoid_other = B;
      // Candidates (§7.2).
      std::vector<Candidate> cand;
      for (std::int32_t k = -8; k <= 8; ++k) {
        Candidate c;
        c.psi = wrap_2pi(m.s.psi + static_cast<float>(k) * 5.0f * DEG);
        cand.push_back(c);
      }
      const bool upwind = std::fabs(m.twa) < HALF_PI;
      if (!emergency && manoeuvre_checks(x, a, m, true)) {
        Candidate c;
        c.psi = heading_for(m.twd, -m.tack * (upwind ? m.theta_up : m.theta_dn));
        c.turn = static_cast<std::int8_t>(upwind ? m.tack : -m.tack);
        c.manoeuvre = true;
        cand.push_back(c);
      }
      {
        Candidate c;
        c.psi = m.s.psi;
        c.slow = true;
        cand.push_back(c);
      }
      static thread_local std::vector<std::size_t> nb;
      neighbours(x, a, m, 5.0f * m.L + 2.0f * x.r_hull[i], nb);
      static thread_local std::vector<Track> tr;
      if (tr.size() < nb.size()) tr.resize(nb.size());
      std::size_t kB = nb.size();
      for (std::size_t q = 0; q < nb.size(); ++q) {
        predict_ctrv(motion_of(x, nb[q]), kSamples, tr[q]);
        if (static_cast<std::int32_t>(nb[q]) == B) kB = q;
      }
      static thread_local Track trB;
      if (kB == nb.size()) predict_ctrv(motion_of(x, static_cast<std::size_t>(B)), kSamples, trB);
      const Track& tB = kB < nb.size() ? tr[kB] : trB;
      const std::size_t jB = static_cast<std::size_t>(B);
      const float mg = margin(x);
      const float brg_aim = bearing(m.c, aim);
      const float V_ref = max(0.5f, polar_speed(a, m, std::fabs(wrap_pi(m.twd - a.psi_target))));
      const float vmc_ref = V_ref * wm_cos(wrap_pi(a.psi_target - brg_aim));
      const float brg_B = bearing(m.c, x.race.boat(jB).c);
      const std::vector<Vec2>& oh = hull(x, i);
      Candidate* pick = nullptr;
      Candidate* keep = nullptr;
      for (Candidate& c : cand) {
        if (emergency && !c.slow) {
          // Never turn towards the other boat in an emergency.
          const float e = wrap_pi(c.psi - m.s.psi), eb = wrap_pi(brg_B - m.s.psi);
          if (std::fabs(e) > 1.0f * DEG && sgn(e) == sgn(eb)) continue;
        }
        static thread_local Track own;
        own_track(m, c.psi, c.turn, c.slow, c.manoeuvre, own);
        if (!track_clear_of_objects(x, a, own)) continue;  // never into a mark or a committee boat
        const float gB = tracks_gap(hull(x, jB), x.r_hull[jB], tB, oh, x.r_hull[i], own, 0, kSamples, 4.0f * m.L);
        if (gB < mg) continue;
        bool contact = false;
        for (std::size_t q = 0; q < nb.size() && !contact; ++q) {
          if (q == kB) continue;
          if (tracks_gap(hull(x, nb[q]), x.r_hull[nb[q]], tr[q], oh, x.r_hull[i], own, 0, kSamples, 0.5f) <= 0.0f) {
            contact = true;
          }
        }
        if (contact) continue;
        const float twa_c = wrap_pi(m.twd - c.psi);
        const float V = (c.slow ? m.b.let_fly_drive() : 1.0f) * polar_speed(a, m, std::fabs(twa_c));
        const float vmc = V * wm_cos(wrap_pi(c.psi - brg_aim));
        float cost = 20.0f / max(gB, 0.5f) + 4.0f * (vmc_ref - vmc) / V_ref + (c.manoeuvre ? 3.0f : 0.0f);
        // A new obligation: ending on port near a starboard boat.
        if (sgn(twa_c) < 0.0f && m.tack > 0.0f) {
          for (const std::size_t j : nb) {
            if (static_cast<std::int32_t>(j) == B) continue;
            if (wrap_pi(x.w.env(j).wind_from_clean - x.w.boat(j).state().psi) >= 0.0f) {
              cost = cost + 10.0f;
              break;
            }
          }
        }
        if (emergency) cost = cost + 2.0f * std::fabs(wrap_pi(c.psi - x.w.boat(jB).state().psi));
        // §7.2: not onto the wrong side of the mark being rounded.
        if (rounding && !c.slow && into_rounding_mark(a, m, c.psi)) cost = cost + 30.0f;
        c.cost = cost;
        if (pick == nullptr || cost < pick->cost) pick = &c;
        if (x.now < a.avoid_hold && !c.manoeuvre && c.slow == a.avoid_slow &&
            std::fabs(wrap_pi(c.psi - a.avoid_psi)) < 2.6f * DEG) {
          keep = &c;
        }
      }
      if (keep != nullptr) pick = keep;
      if (pick == nullptr) {
        // Nothing clears: brake and turn away from her. A started boat stopped for more than 5 s keeps her sails
        // drawing instead, or she could never gather way to get clear (ai.md §7.2).
        a.let_fly = !(m.rb.started && a.slow_t > 5.0f);
        const float eb = wrap_pi(brg_B - m.s.psi);
        a.psi_target = wrap_2pi(m.s.psi - sgn(eb) * 30.0f * DEG);
        a.forced = true;
        a.tactic = emergency ? AiTactic::Emergency : AiTactic::KeepClear;
        return;
      }
      if (pick != keep) {
        a.avoid_hold = x.now + 1.5f;
        a.avoid_psi = pick->psi;
        a.avoid_slow = pick->slow;
      }
      a.tactic = emergency ? AiTactic::Emergency : AiTactic::KeepClear;
      a.forced = true;
      if (pick->manoeuvre) {
        if (upwind) start_tack(x, a, m, a.tactic);
        else start_gybe(x, a, m, a.tactic);
        return;
      }
      a.psi_target = pick->psi;
      a.let_fly = pick->slow && !(m.rb.started && a.slow_t > 5.0f);
      a.turn_dir = 0;
      return;
    }
  }
  // §7.4 hold course while a give-way boat is near.
  if (a.man == Man::straight) {
    for (const std::int32_t j : holds) {
      const float eb = wrap_pi(bearing(m.c, x.race.boat(static_cast<std::size_t>(j)).c) - m.s.psi);
      const float et = wrap_pi(a.psi_target - m.s.psi);
      if (sgn(et) == sgn(eb) && std::fabs(et) > 5.0f * DEG && a.tactic != AiTactic::Rounding) {
        a.psi_target = wrap_2pi(m.s.psi + sgn(et) * 5.0f * DEG);
      }
    }
  }
  // Rule 17: not above the proper course (rules.md §3.7).
  if (r17 && a.man == Man::straight && a.tactic != AiTactic::Rounding) {
    const float thR = std::fabs(wrap_pi(m.twd - bearing(m.c, aim)));
    float proper = thR;
    if (thR < m.theta_up) proper = m.theta_up;
    else if (thR > m.theta_dn) proper = m.theta_dn;
    const float twa_t = wrap_pi(m.twd - a.psi_target);
    if (std::fabs(twa_t) < proper - 5.0f * DEG) a.psi_target = heading_for(m.twd, sgn(twa_t) * (proper - 5.0f * DEG));
  }
}

}  // namespace wm::ai_detail
