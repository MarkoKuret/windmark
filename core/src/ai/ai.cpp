// AI skippers (ai.md): the interface, perception (§3), the decision dispatch and the helm (§10, §11). The start
// is in ai_start.cpp, sailing the course (strategy, marks, sails, penalties, bad air, cover) in ai_course.cpp and
// rules-aware sailing in ai_rules.cpp.
#include "ai/ai.h"

#include <cmath>

#include "ai/ai_internal.h"
#include "ai/ai_steps.h"

namespace wm {

using namespace ai_detail;

const char* ai_tactic_name(AiTactic t) {
  switch (t) {
    case AiTactic::None: return "None";
    case AiTactic::Start: return "Start";
    case AiTactic::Rounding: return "Rounding";
    case AiTactic::KeepClear: return "KeepClear";
    case AiTactic::Emergency: return "Emergency";
    case AiTactic::BadAir: return "BadAir";
    case AiTactic::Cover: return "Cover";
    case AiTactic::Shift: return "Shift";
    case AiTactic::Pressure: return "Pressure";
    case AiTactic::Layline: return "Layline";
    case AiTactic::Corridor: return "Corridor";
    case AiTactic::PenaltyTurn: return "PenaltyTurn";
    case AiTactic::Land: return "Land";
  }
  return "?";
}

AiLevelParams ai_level_params(AiLevel level, bool speed_only) {
  AiLevelParams p;
  const AiLevel rows = speed_only ? AiLevel::intermediate : level;
  switch (rows) {
    case AiLevel::easy:
      p.e_start_lo = 1.0f; p.e_start_hi = 6.0f; p.spread = 0.9f; p.t_final = 35.0f; p.m_lay = 3.0f;
      p.shifts = false; p.h_up = 0.0f; p.h_dn = 0.0f; p.r_read = 0.0f; p.t_cool = 30.0f; p.h_avoid = 6.0f;
      p.c_lvl = 1.5f; p.badair_react = 6.0f; p.anticipate = false; p.cover = AiCover::none; p.drop_lead = 7.0f;
      break;
    case AiLevel::intermediate:
      p.e_start_lo = 0.0f; p.e_start_hi = 2.5f; p.spread = 0.6f; p.t_final = 30.0f; p.m_lay = 2.0f;
      p.shifts = true; p.h_up = 10.0f * DEG; p.h_dn = 15.0f * DEG; p.r_read = 0.0f; p.t_cool = 20.0f;
      p.h_avoid = 5.0f; p.c_lvl = 1.0f; p.badair_react = 3.0f; p.anticipate = false; p.cover = AiCover::match_only;
      p.drop_lead = 4.0f;
      break;
    case AiLevel::expert:
      p.e_start_lo = -0.5f; p.e_start_hi = 1.2f; p.spread = 0.45f; p.t_final = 25.0f; p.m_lay = 1.0f;
      p.shifts = true; p.h_up = 7.0f * DEG; p.h_dn = 11.0f * DEG; p.r_read = 250.0f; p.t_cool = 15.0f;
      p.h_avoid = 4.0f; p.c_lvl = 0.6f; p.badair_react = 2.0f; p.anticipate = true; p.cover = AiCover::all;
      p.drop_lead = 4.0f;
      break;
    case AiLevel::pro:
      p.e_start_lo = -0.3f; p.e_start_hi = 0.5f; p.spread = 0.35f; p.t_final = 22.0f; p.m_lay = 0.5f;
      p.shifts = true; p.h_up = 5.0f * DEG; p.h_dn = 8.0f * DEG; p.r_read = 400.0f; p.t_cool = 12.0f;
      p.h_avoid = 3.5f; p.c_lvl = 0.4f; p.badair_react = 2.0f; p.anticipate = true; p.cover = AiCover::all;
      p.drop_lead = 3.0f;
      break;
  }
  switch (level) {
    case AiLevel::easy: p.performance_scale = 0.90f; break;
    case AiLevel::intermediate: p.performance_scale = 1.00f; break;
    case AiLevel::expert: p.performance_scale = 1.025f; break;
    case AiLevel::pro: p.performance_scale = 1.04f; break;
  }
  return p;
}

BoatEntry ai_entry(const PerfData* perf, AiLevel level) {
  BoatEntry e;
  e.perf = perf;
  e.human = false;
  e.ai = true;
  e.performance_scale = ai_level_params(level).performance_scale;
  e.auto_trim = true;
  return e;
}

AiSkippers::AiSkippers() = default;
AiSkippers::~AiSkippers() = default;

AiSkippers::Boat& AiSkippers::get(std::int32_t boat) {
  for (auto& b : boats_) {
    if (b->i == boat) return *b;
  }
  boats_.push_back(std::make_unique<Boat>());
  boats_.back()->i = boat;
  return *boats_.back();
}

void AiSkippers::add(std::int32_t boat, AiLevel level, bool speed_only) {
  Boat& a = get(boat);
  a.level = level;
  a.P = ai_level_params(level, speed_only);
  a.speed_only = speed_only;
  a.autopilot_only = false;
  a.active = true;
}

void AiSkippers::take_over(std::int32_t boat) { add(boat, AiLevel::intermediate); }

void AiSkippers::release(std::int32_t boat) {
  for (auto& b : boats_) {
    if (b->i == boat) b->active = false;
  }
}

void AiSkippers::add_autopilot(std::int32_t boat) {
  Boat& a = get(boat);
  a.P = ai_level_params(AiLevel::intermediate);
  a.autopilot_only = true;
  a.active = true;
}

bool AiSkippers::has(std::int32_t boat) const {
  for (const auto& b : boats_) {
    if (b->i == boat && b->active && !b->autopilot_only) return true;
  }
  return false;
}

const AiTelemetry& AiSkippers::telemetry(std::int32_t boat) const {
  static const AiTelemetry none;
  for (const auto& b : boats_) {
    if (b->i == boat) return b->tel;
  }
  return none;
}

const AiDebug& AiSkippers::debug(std::int32_t boat) const {
  static const AiDebug none;
  for (const auto& b : boats_) {
    if (b->i == boat) return b->dbg;
  }
  return none;
}

const AiPolar& AiSkippers::polar(const PerfData* perf) {
  auto it = polars_.find(perf);
  if (it == polars_.end()) it = polars_.emplace(perf, std::make_unique<AiPolar>(*perf)).first;
  return *it->second;
}

const ShadowClass& AiSkippers::shadow_class(const PerfData* perf) {
  auto it = shadow_classes_.find(perf);
  if (it == shadow_classes_.end()) it = shadow_classes_.emplace(perf, make_shadow_class(perf->dynamics.wind_shadow)).first;
  return it->second;
}

namespace {

// §3.3 filters, every tick; and the per race telemetry of §15.
void perceive(AiSkippers::Ctx& x, AiSkippers::Boat& a) {
  const std::size_t i = static_cast<std::size_t>(a.i);
  const EnvAtBoat& env = x.w.env(i);
  const float from = env.wind_from_clean;
  const Vec2 f = dir(from);
  if (!a.init) {
    a.fx = f.x; a.fy = f.y; a.rx = f.x; a.ry = f.y; a.sx = f.x; a.sy = f.y;
    a.tws_f = env.wind_speed_clean;
    a.tws_felt = env.wind_speed;
    a.d_f = 0.0f;
    a.init = true;
  }
  const float a2 = filt_a(2.0f), a5 = filt_a(5.0f), a90 = filt_a(90.0f);
  a.fx = a.fx + a2 * (f.x - a.fx);
  a.fy = a.fy + a2 * (f.y - a.fy);
  a.sx = a.sx + a5 * (f.x - a.sx);
  a.sy = a.sy + a5 * (f.y - a.sy);
  a.tws_f = a.tws_f + a2 * (env.wind_speed_clean - a.tws_f);
  a.tws_felt = a.tws_felt + a2 * (env.wind_speed - a.tws_felt);
  const float d_raw = env.wind_speed_clean > 0.05f ? max(0.0f, 1.0f - env.wind_speed / env.wind_speed_clean) : 0.0f;
  a.d_f = a.d_f + a2 * (d_raw - a.d_f);
  a.twd_f = compass({a.fx, a.fy});
  a.twd_5 = compass({a.sx, a.sy});
  // TWD_ref follows the 2 s direction with a 90 s time constant (angles as unit vectors).
  const Vec2 ff = dir(a.twd_f);
  a.rx = a.rx + a90 * (ff.x - a.rx);
  a.ry = a.ry + a90 * (ff.y - a.ry);
  a.twd_ref = compass({a.rx, a.ry});
  a.shift = wrap_pi(a.twd_5 - a.twd_ref);

  if (!x.created) return;
  const RaceBoat& rb = x.race.boat(i);
  const BoatState& s = x.w.boat(i).state();
  // Stuck: below 0.3 m/s for more than 5 s after the start.
  if (rb.started && !rb.finished && !rb.ghost) {
    if (s.v < 0.3f) {
      a.slow_t = a.slow_t + DT;
      if (a.slow_t > 5.0f) a.tel.stuck_s = a.tel.stuck_s + (a.slow_t - DT > 5.0f ? DT : a.slow_t);
    } else {
      a.slow_t = 0.0f;
    }
  }
  if (rb.started && a.tel.start_delay < 0.0f) a.tel.start_delay = rb.t_start;
  if (!a.ocs_counted && (rb.ocs || rb.ocs_i) && x.race.after_gun(x.n)) {
    a.ocs_counted = true;
    a.tel.ocs = a.tel.ocs + 1;
  }
  const BoatRules& br = x.rules.boat(i);
  if (br.received > a.pen_seen) {
    a.tel.penalties = a.tel.penalties + (br.received - a.pen_seen);
    a.pen_seen = br.received;
  }
  if (x.race.rules_live() && !rb.ghost) {
    for (const PairRecord* p : x.pairs_of[i]) {
      const std::int32_t j = p->i == a.i ? p->j : p->i;
      if (!x.race.racing(static_cast<std::size_t>(j))) continue;
      a.tel.min_gap = min(a.tel.min_gap, p->gap);
    }
  }
  for (AiBadAirRecord& r : a.tel.bad_air) {
    if (r.d_after < 0.0f && x.n >= r.tick + 400u) r.d_after = a.d_f;
  }
  // Tacks and gybes actually made (the tack label flips).
  const std::int8_t tk = static_cast<std::int8_t>(sgn(wrap_pi(from - s.psi)));
  if (a.tack_prev != 0 && tk != a.tack_prev && rb.started && !rb.finished) {
    if (std::fabs(wrap_pi(from - s.psi)) < HALF_PI) a.tel.tacks = a.tel.tacks + 1;
    else a.tel.gybes = a.tel.gybes + 1;
  }
  a.tack_prev = tk;
}

// §11 heading controller, every tick.
void helm(AiSkippers::Ctx& x, AiSkippers::Boat& a) {
  const std::size_t i = static_cast<std::size_t>(a.i);
  const wm::Boat& b = x.w.boat(i);
  const BoatState& s = b.state();
  const Dynamics& dyn = b.perf().dynamics;
  const float twd = x.w.env(i).wind_from_clean;
  const float twa = wrap_pi(twd - s.psi);
  const float av = std::fabs(s.v);
  const std::int32_t ib = a.i;

  // The tack in progress (§10): a fixed helm through the wind, then the controller on the new heading.
  if (a.man == Man::tack) {
    const float t_man = x.now - a.man_t0;
    const bool on_new = static_cast<std::int8_t>(sgn(twa)) == a.man_to && std::fabs(twa) < HALF_PI;
    if (on_new && std::fabs(twa) > 20.0f * DEG) a.man_passed = true;
    // In irons: stopped head to wind for 3 s.
    if (s.v < 0.5f && std::fabs(twa) < 25.0f * DEG) a.irons_t = a.irons_t + DT;
    else a.irons_t = 0.0f;
    if (a.irons_t > 3.0f && a.irons_until < x.now) a.irons_until = x.now + 2.0f;
    if (a.irons_until >= x.now) {
      // Fall off onto the new tack: the bow must turn away from the wind on the new side.
      const float turn = static_cast<float>(a.man_from);  // the tack's turning direction
      const float h = s.v < 0.0f ? -turn : turn;
      a.helm_fixed = h;
      a.let_fly = true;
    } else if (!a.man_passed) {
      const float turn = static_cast<float>(a.man_from);
      a.helm_fixed = (s.v < 0.0f ? -turn : turn) * 0.6f;
      a.forced = true;
    } else {
      a.helm_fixed = NAN;
    }
    if (a.man_passed && std::fabs(wrap_pi(a.psi_target - s.psi)) < 8.0f * DEG) a.man = Man::straight;
    if (t_man > 25.0f) a.man = Man::straight;
    if (a.man == Man::straight) {
      a.helm_fixed = NAN;
      a.turn_dir = 0;
      a.irons_t = 0.0f;
    }
  } else if (a.man == Man::gybe) {
    const bool on_new = static_cast<std::int8_t>(sgn(twa)) == a.man_to;
    if ((on_new && std::fabs(wrap_pi(a.psi_target - s.psi)) < 10.0f * DEG) || x.now - a.man_t0 > 15.0f) {
      a.man = Man::straight;
      a.turn_dir = 0;
      a.r_limit = NAN;
    }
  }

  float h;
  if (!std::isnan(a.helm_fixed)) {
    h = a.helm_fixed;
  } else {
    float e = wrap_pi(a.psi_target - s.psi);
    if (a.turn_dir != 0) {
      if (sgn(e) != static_cast<float>(a.turn_dir) && std::fabs(e) > 10.0f * DEG) {
        e = e + static_cast<float>(a.turn_dir) * TWO_PI;
      } else if (std::fabs(e) < 20.0f * DEG) {
        a.turn_dir = 0;
      }
    }
    float r_max = av / dyn.turn_radius_full;
    if (!std::isnan(a.r_limit)) r_max = min(r_max, a.r_limit);
    const float r_star = clamp(e / 1.2f, -r_max, r_max);
    float hh = 0.0f;
    if (std::fabs(r_star) > 1e-6f) {
      const float R_star = av / std::fabs(r_star);
      const float mag = min(1.0f, (dyn.turn_radius_full + dyn.turn_radius_offset) / (R_star + dyn.turn_radius_offset));
      hh = sgn(r_star) * mag;
    }
    const float turn_rate = b.outputs().turn_rate;
    // The damping acts on the heading rate; with sternway the rudder works backwards.
    hh = s.v < 0.0f ? -hh : hh;
    const float damp = 0.5f * (turn_rate - r_star);
    hh = hh - (s.v < 0.0f ? -damp : damp);
    // Weather helm (boat.md §5.9 helm_luff) turns the boat with the helm centred: an integral of the turn rate
    // error holds the heading against it. It only integrates with way on.
    // It is kept relative to the tack (the sail plan's balance flips with it).
    const float tk = sgn(twa);
    if (av > 0.3f) a.h_int = clamp(a.h_int + (tk * (1.0f * (r_star - turn_rate))) * DT, -0.6f, 0.6f);
    const float bias = tk * a.h_int;
    hh = hh + (s.v < 0.0f ? -bias : bias);
    h = clamp(hh, -1.0f, 1.0f);
    if (!a.forced) {
      // The largest helm whose rudder drag is at most 0.1 m/s² (never below 0.25, so the boat can always turn).
      const bool up = (h * sgn(twa)) > 0.0f;
      const Table& drag = up ? dyn.rudder_drag_luff : dyn.rudder_drag_bear;
      float lim = 0.25f;
      for (std::int32_t k = 20; k >= 5; --k) {
        const float hk = static_cast<float>(k) * 0.05f;
        if (drag.at(av, hk) <= 0.1f) {
          lim = hk;
          break;
        }
      }
      h = clamp(h, -lim, lim);
    }
  }
  x.w.set_helm(ib, h);
  x.w.set_let_fly(ib, a.let_fly);
  a.dbg.psi_target = a.psi_target;
}

}  // namespace

void AiSkippers::step(World& w) {
  const Race& race = w.race();
  Ctx x{w, race, w.rules(), w.course(), 0u, 0.0f, 0.0f, false, {}, {}, {}, nullptr};
  x.n = w.tick();
  x.now = static_cast<float>(w.tick()) * DT;
  x.created = w.race_created();
  x.t_race = x.created ? race.race_time(x.n) : -1e6f;
  x.ai = &boats_;
  const std::size_t nb = w.boat_count();
  x.pairs_of.assign(nb, {});
  if (x.created) {
    for (const PairRecord& p : w.rules().pairs()) {
      if (p.i >= 0 && static_cast<std::size_t>(p.i) < nb) x.pairs_of[static_cast<std::size_t>(p.i)].push_back(&p);
      if (p.j >= 0 && static_cast<std::size_t>(p.j) < nb) x.pairs_of[static_cast<std::size_t>(p.j)].push_back(&p);
    }
  }
  x.r_hull.assign(nb, 0.0f);
  x.snap.resize(nb);
  for (std::size_t j = 0; j < nb; ++j) {
    const wm::Boat& b = w.boat(j);
    for (const Vec2 v : b.perf().dynamics.collision.outline) x.r_hull[j] = max(x.r_hull[j], v_len(v));
    const BoatState& s = b.state();
    ShadowSource& src = x.snap[j];
    src.cls = &shadow_class(&b.perf());
    src.pos_x = s.pos_x;
    src.pos_y = s.pos_y;
    src.psi = s.psi;
    src.aws = s.aws;
    src.awd_from = s.awd_from;
    src.awa = s.awa;
    src.twa = s.twa;
    src.spinnaker = b.sails().spinnaker_flying();
    src.casts = w.setup().shadows && (!x.created || race.casts(j));
  }
  const bool decide_tick = (x.n % 2u) == 0u;
  for (auto& bp : boats_) {
    Boat& a = *bp;
    if (!a.active || a.i < 0 || static_cast<std::size_t>(a.i) >= nb) continue;
    if (a.pol == nullptr) a.pol = &polar(&w.boat(static_cast<std::size_t>(a.i)).perf());
    perceive(x, a);
  }
  if (decide_tick) assign_spots(x);
  for (auto& bp : boats_) {
    Boat& a = *bp;
    if (!a.active || a.i < 0 || static_cast<std::size_t>(a.i) >= nb) continue;
    if (decide_tick || !a.decided) {
      ai_decide(x, a);
      a.decided = true;
      if (a.tactic != a.prev_tactic && a.tactic != AiTactic::None) {
        a.tel.activations[static_cast<std::size_t>(a.tactic)] += 1;
      }
      a.prev_tactic = a.tactic;
      a.dbg.tactic = a.tactic;
    }
    // An autopilot-only boat (an offline human) is steered only once she has finished (race.md §6.2).
    if (a.autopilot_only && !(x.created && (x.race.boat(static_cast<std::size_t>(a.i)).finished ||
                                            x.race.boat(static_cast<std::size_t>(a.i)).ghost))) {
      continue;
    }
    helm(x, a);
    a.dbg.d = a.d_f;
    a.dbg.twd_ref = a.twd_ref;
    a.dbg.twd_f = a.twd_f;
    a.dbg.tws_f = a.tws_f;
    a.dbg.leg = static_cast<std::int32_t>(a.leg);
    a.dbg.manoeuvre = static_cast<std::int32_t>(a.man);
  }
}

}  // namespace wm
