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
  m.cur = {x.w.env(j).current_x, x.w.env(j).current_y};
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
  mj.cur = {x.w.env(j).current_x, x.w.env(j).current_y};
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
  predict_plan(mo, plan_to(m, psi_to, turn, slow, rate), kSamples, out);
}

struct Candidate {
  float psi = 0.0f;
  std::int8_t turn = 0;
  bool slow = false;
  bool manoeuvre = false;
  float cost = 1e30f;
};

}  // namespace

bool tack_safe(AC& x, AB& a, const Me& m, float psi_new, bool gybe) {
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
      std::vector<Track> tr(nb.size());
      std::size_t kB = nb.size();
      for (std::size_t q = 0; q < nb.size(); ++q) {
        predict_ctrv(motion_of(x, nb[q]), kSamples, tr[q]);
        if (static_cast<std::int32_t>(nb[q]) == B) kB = q;
      }
      Track trB;
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
        Track own;
        own_track(m, c.psi, c.turn, c.slow, c.manoeuvre, own);
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
        const float V = c.slow ? 0.0f : polar_speed(a, m, std::fabs(twa_c));
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
        c.cost = cost;
        if (pick == nullptr || cost < pick->cost) pick = &c;
        if (x.now < a.avoid_hold && !c.manoeuvre && c.slow == a.avoid_slow &&
            std::fabs(wrap_pi(c.psi - a.avoid_psi)) < 2.6f * DEG) {
          keep = &c;
        }
      }
      if (keep != nullptr) pick = keep;
      if (pick == nullptr) {
        // Nothing clears: brake and turn away from her.
        a.let_fly = true;
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
      a.let_fly = pick->slow;
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
  if (r17 && a.man == Man::straight) {
    const float thR = std::fabs(wrap_pi(m.twd - bearing(m.c, aim)));
    float proper = thR;
    if (thR < m.theta_up) proper = m.theta_up;
    else if (thR > m.theta_dn) proper = m.theta_dn;
    const float twa_t = wrap_pi(m.twd - a.psi_target);
    if (std::fabs(twa_t) < proper - 5.0f * DEG) a.psi_target = heading_for(m.twd, sgn(twa_t) * (proper - 5.0f * DEG));
  }
}

}  // namespace wm::ai_detail
