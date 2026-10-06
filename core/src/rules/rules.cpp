// The racing rules engine (rules.md): the per-tick pipeline of §2.2.
#include "rules/rules.h"

#include <algorithm>
#include <cmath>

#include "course/geometry.h"

namespace wm {

std::string_view rule_code_str(RuleCode r) {
  switch (r) {
    case RuleCode::none: return "";
    case RuleCode::r10: return "10";
    case RuleCode::r11: return "11";
    case RuleCode::r12: return "12";
    case RuleCode::r13: return "13";
    case RuleCode::r14: return "14";
    case RuleCode::r15: return "15";
    case RuleCode::r16_1: return "16.1";
    case RuleCode::r16_2: return "16.2";
    case RuleCode::r17: return "17";
    case RuleCode::r18_2: return "18.2";
    case RuleCode::r18_3: return "18.3";
    case RuleCode::r18_4: return "18.4";
    case RuleCode::r19: return "19";
    case RuleCode::r20: return "20";
    case RuleCode::r21_1: return "21.1";
    case RuleCode::r21_2: return "21.2";
    case RuleCode::r31: return "31";
    case RuleCode::late: return "44.2-late";
    case RuleCode::c_prep: return "C-prep";
    case RuleCode::c_entry: return "C-entry";
    case RuleCode::si_boundary: return "SI-boundary";
  }
  return "?";
}

namespace {

constexpr std::uint32_t kTicksPerS = 20;

std::uint32_t ticks(float s) { return static_cast<std::uint32_t>(std::ceil(s / DT)); }
std::uint64_t pair_key(std::int32_t i, std::int32_t j) {
  return (static_cast<std::uint64_t>(static_cast<std::uint32_t>(i)) << 32) | static_cast<std::uint32_t>(j);
}
bool fast_persist(RuleCode r) {
  return r == RuleCode::r10 || r == RuleCode::r13 || r == RuleCode::r15 || r == RuleCode::r16_1 ||
         r == RuleCode::r16_2 || r == RuleCode::r18_3 || r == RuleCode::r21_1 || r == RuleCode::r21_2;
}
bool part2(RuleCode r) {
  switch (r) {
    case RuleCode::r10: case RuleCode::r11: case RuleCode::r12: case RuleCode::r13: case RuleCode::r14:
    case RuleCode::r15: case RuleCode::r16_1: case RuleCode::r16_2: case RuleCode::r17: case RuleCode::r18_2:
    case RuleCode::r18_3: case RuleCode::r18_4: case RuleCode::r19: case RuleCode::r20: case RuleCode::r21_1:
    case RuleCode::r21_2:
      return true;
    default:
      return false;
  }
}
bool overlapped(Relation r) { return r == Relation::overlapped || r == Relation::overlapped_via; }

// The stern of an outline placed in the world: midpoint of the vertices with the smallest body x (race.md §0).
Vec2 stern_point(const std::vector<Vec2>& body, Vec2 pos, float psi) {
  float xmin = INFINITY;
  for (const Vec2 v : body) xmin = min(xmin, v.x);
  Vec2 s{0.0f, 0.0f};
  float n = 0.0f;
  for (const Vec2 v : body) {
    if (v.x == xmin) {
      s = v_add(s, v);
      n = n + 1.0f;
    }
  }
  return place_point({s.x / n, s.y / n}, pos, psi);
}

Vec2 bow_point(const std::vector<Vec2>& body, Vec2 pos, float psi) {
  std::size_t best = 0;
  for (std::size_t k = 1; k < body.size(); ++k) {
    if (body[k].x > body[best].x) best = k;
  }
  return place_point(body[best], pos, psi);
}

void push_hist(std::vector<float>& h, float v, std::size_t n) {
  if (h.size() == n) h.erase(h.begin());
  h.push_back(v);
}

}  // namespace

// ---- Set-up ----

void Rules::init(const Race& race, const VenueData* venue, const RulesParams& p) {
  p_ = p;
  venue_ = venue;
  course_ = &race.course();
  zone_lengths_ = race.zone_lengths();
  match_ = race.race_type() == RaceType::match;
  st_.clear();
  rec_.clear();
  boats_.clear();
  pairs_.clear();
  sync_boats(race);
}

void Rules::sync_boats(const Race& race) {
  const std::size_t nm = race.course().marks.size();
  while (st_.size() < race.boat_count()) {
    const RaceBoat& rb = race.boat(st_.size());
    BoatState s;
    s.perf = rb.perf;
    s.L = rb.L;
    s.B = rb.B;
    for (const Vec2 v : rb.perf->dynamics.collision.outline) s.r_hull = max(s.r_hull, v_len(v));
    s.in_zone.assign(nm, 0);
    s.stbd_since_zone.assign(nm, 0);
    s.zone_enter.assign(nm, 0);
    s.dmin.assign(nm, INFINITY);
    s.touch_tick.assign(nm, 0);
    s.touched.assign(nm, 0);
    st_.push_back(std::move(s));
    rec_.emplace_back();
    boats_.push_back(rb.perf);
  }
}

bool Rules::rule_on(RuleCode r, const Race& race) const {
  const RulesLevel lv = race.settings().rules_level;
  if (lv == RulesLevel::none) return false;
  if (lv == RulesLevel::basic) {
    switch (r) {
      case RuleCode::r17: case RuleCode::r18_2: case RuleCode::r18_3: case RuleCode::r18_4: case RuleCode::r19:
      case RuleCode::si_boundary:
        return false;
      default:
        return true;
    }
  }
  if (r == RuleCode::r17 && match_) return false;  // rules.md §9.6
  return true;
}

Rules::PairState& Rules::pair_state(std::int32_t i, std::int32_t j) {
  const std::uint64_t k = pair_key(i, j);
  auto it = pairs_.find(k);
  if (it == pairs_.end()) {
    PairState ps;
    ps.i = i;
    ps.j = j;
    it = pairs_.emplace(k, std::move(ps)).first;
  }
  return it->second;
}

const PairRecord* Rules::pair(std::int32_t i, std::int32_t j) const {
  if (i > j) std::swap(i, j);
  for (const PairRecord& r : pair_rec_) {
    if (r.i == i && r.j == j) return &r;
  }
  return nullptr;
}

void Rules::pending_flags(std::vector<std::uint8_t>& out) const {
  out.resize(rec_.size());
  for (std::size_t i = 0; i < rec_.size(); ++i) out[i] = rec_[i].pending.empty() ? 0 : 1;
}

// ---- Per boat (§2.2 step 1) ----

void Rules::boat_step(std::uint32_t n, std::size_t i, const Race& race, const RulesBoatInput& in) {
  BoatState& s = st_[i];
  const std::vector<Vec2>& body = s.perf->dynamics.collision.outline;
  s.c = in.pos;
  place_outline(body, in.pos, in.psi, s.hull);
  place_hull(body, in.pos, in.psi, s.placed);
  s.bow = bow_point(body, in.pos, in.psi);
  s.stern = stern_point(body, in.pos, in.psi);
  s.twa_prev = s.has_prev ? s.twa : wrap_pi(in.twd - in.psi);
  s.twa = wrap_pi(in.twd - in.psi);
  if (in.tws != s.vmg_tws) {
    const PolarVmg v = polar_vmg(*s.perf, in.tws, vmg_[s.perf]);
    s.theta_ch = v.up_twa > 0.0f ? v.up_twa : 0.7f;
    s.theta_dn = v.down_twa > 0.0f ? v.down_twa : 2.6f;
    s.vmg_tws = in.tws;
  }
  predict(i, in);

  // race.md §0 rules tack with its hysteresis.
  const float a = std::fabs(s.twa);
  const std::int8_t old = s.tack;
  if (!s.tack_init) {
    if (a < HALF_PI) s.tack = s.twa > 0.0f ? 1 : -1;
    else s.tack = in.main_beta > 0.0f ? -1 : 1;
    s.tack_init = true;
  } else if (a < HALF_PI) {
    if (s.tack == 1 && s.twa < -DEG) s.tack = -1;
    else if (s.tack == -1 && s.twa > DEG) s.tack = 1;
  } else {
    if (in.main_beta > 2.0f * DEG) s.tack = -1;
    else if (in.main_beta < -2.0f * DEG) s.tack = 1;
  }
  s.flipped = s.tack != old && s.has_prev;
  s.head_to_wind = s.flipped && a < HALF_PI;
  if (s.flipped) {
    s.has_tack_change = true;
    s.tack_change_tick = n;
  }
  // §3.4 tacking.
  if (s.head_to_wind) {
    if (s.tacking && s.tack != s.tacking_to) {
      s.tacking = false;  // back onto the old tack
    } else {
      s.tacking = true;
      s.tacking_to = s.tack;
    }
  }
  if (s.tacking && !s.head_to_wind) {
    if (s.tack != s.tacking_to) {
      s.tacking = false;
    } else if (a >= s.theta_ch - 5.0f * DEG) {
      s.tacking = false;
      s.has_tacking_end = true;
      s.tacking_end_tick = n;
    }
  }

  // §5.3 course change.
  s.cc_started_now = false;
  const float r = in.turn_rate;
  if (std::fabs(r) > p_.cc_rate) {
    const std::int8_t d = r > 0.0f ? 1 : -1;
    s.cc_run = d == s.cc_run_dir ? s.cc_run + 1 : 1;
    s.cc_run_dir = d;
  } else {
    s.cc_run = 0;
  }
  push_hist(s.psi_hist, in.psi, 41);
  push_hist(s.v_hist, in.v, 41);
  const std::size_t hn = s.psi_hist.size();
  const float dpsi_1s = hn > 20 ? wrap_pi(in.psi - s.psi_hist[hn - 21]) : 0.0f;
  if (!s.cc_active) {
    const bool run = s.cc_run >= static_cast<std::int32_t>(ticks(p_.cc_time));
    if (run || std::fabs(dpsi_1s) > p_.cc_heading) {
      s.cc_active = true;
      s.cc_started_now = true;
      s.cc_dir = run ? s.cc_run_dir : (dpsi_1s > 0.0f ? 1 : -1);
      s.cc_back = run ? static_cast<std::uint32_t>(s.cc_run - 1) : 20u;
      s.cc_calm = 0;
    }
  } else {
    s.cc_calm = std::fabs(r) < p_.cc_end_rate ? s.cc_calm + 1 : 0;
    if (s.cc_calm >= static_cast<std::int32_t>(ticks(p_.cc_end_time))) s.cc_active = false;
  }

  // §3.7 proper course towards the next step.
  const RaceBoat& rb = race.boat(i);
  const ResolvedCourse& course = race.course();
  Vec2 R = s.c;
  if (!rb.started && !rb.ocs_scored) {
    const CourseStep& st0 = course.start();
    R = v_mid(course.end_a(st0), course.end_b(st0));
  } else if (rb.next > 0) {
    const CourseStep& st = course.steps[static_cast<std::size_t>(rb.next)];
    const Vec2 m0 = course.marks[static_cast<std::size_t>(st.marks[0])].pos;
    const Vec2 m1 = course.marks[static_cast<std::size_t>(st.marks[1] >= 0 ? st.marks[1] : st.marks[0])].pos;
    if (st.kind == StepKind::mark) R = m0;
    else if (st.kind == StepKind::gate) R = v_dist(s.c, m0) <= v_dist(s.c, m1) ? m0 : m1;
    else R = st.ref;
  }
  const float beta = compass(v_sub(R, s.c));
  const float th_r = std::fabs(wrap_pi(in.twd - beta));
  const float proper = th_r < s.theta_ch ? s.theta_ch : (th_r > s.theta_dn ? s.theta_dn : th_r);
  // No proper course before her starting signal (definition): never above it in the pre-start.
  if (race.after_gun(n) && a < proper - p_.proper_tol) s.above_time = s.above_time + DT;
  else s.above_time = 0.0f;
  s.above = s.above_time > p_.proper_time;

  // Rule 15 causes: the end of a return to start or of a penalty turn.
  const bool ret = race.returning(i);
  const bool pen = rec_[i].turning_for_penalty;
  if ((s.returning_prev && !ret) || (s.pen_turn_prev && !pen)) {
    s.has_status_end = true;
    s.status_end_tick = n;
  }
  s.returning_prev = ret;
  s.pen_turn_prev = pen;

  // §7.2 gate buoy: the one whose bearing is closer to the course over ground, 10° hysteresis.
  if (rb.next > 0 && course.steps[static_cast<std::size_t>(rb.next)].kind == StepKind::gate) {
    const CourseStep& st = course.steps[static_cast<std::size_t>(rb.next)];
    const float cog = in.sog > 0.05f ? in.cog : in.psi;
    const float e0 = std::fabs(wrap_pi(compass(v_sub(course.marks[static_cast<std::size_t>(st.marks[0])].pos, s.c)) - cog));
    const float e1 = std::fabs(wrap_pi(compass(v_sub(course.marks[static_cast<std::size_t>(st.marks[1])].pos, s.c)) - cog));
    if (s.gate_step != rb.next) {
      s.gate_step = rb.next;
      s.gate_buoy = e0 <= e1 ? 0 : 1;
    } else if (s.gate_buoy == 0 && e1 + 10.0f * DEG < e0) {
      s.gate_buoy = 1;
    } else if (s.gate_buoy == 1 && e0 + 10.0f * DEG < e1) {
      s.gate_buoy = 0;
    }
  }

  rec_[i].tack = s.tack;
  rec_[i].tacking = s.tacking;
  rec_[i].returning_to_start = ret;
  s.psi_prev = in.psi;
  s.has_prev = true;
}

// §7.1 zones of the marks a boat is heading for and has last rounded, with her own length.
void Rules::zones(std::uint32_t n, std::size_t i, const Race& race) {
  BoatState& s = st_[i];
  const RaceBoat& rb = race.boat(i);
  const ResolvedCourse& course = race.course();
  const float Z = zone_lengths_ * s.L;
  std::vector<std::int32_t> marks;
  const std::int32_t last = static_cast<std::int32_t>(course.steps.size()) - 1;
  auto add_step = [&](std::int32_t k) {
    if (k <= 0 || k > last) return;
    const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
    marks.push_back(st.marks[0]);
    if (st.kind != StepKind::mark) marks.push_back(st.marks[1]);  // gate buoys; finishing line ends (§7.10)
  };
  if (rb.started || rb.ocs_scored) {
    add_step(rb.next);
    add_step(rb.last_rounded);
  }
  for (std::size_t m = 0; m < s.in_zone.size(); ++m) {
    bool relevant = false;
    for (const std::int32_t x : marks) relevant = relevant || x == static_cast<std::int32_t>(m);
    bool in = false;
    const Vec2 M = course.marks[m].pos;
    if (relevant) {
      const float Zm = Z + mark_radius(static_cast<std::int32_t>(m));  // measured from the mark (§7.1)
      for (const Vec2 p : s.hull) in = in || v_dist(p, M) <= Zm;
    }
    if (in && !s.in_zone[m]) {
      s.zone_enter[m] = n;
      s.stbd_since_zone[m] = s.tack == 1 ? 1 : 0;
      s.dmin[m] = v_dist(s.c, M);
    }
    if (in) {
      if (s.tack != 1) s.stbd_since_zone[m] = 0;
      s.dmin[m] = min(s.dmin[m], v_dist(s.c, M));
      // §7.5: passing head to wind from port to starboard in the zone.
      if (s.head_to_wind && s.tack == 1) s.r183_mark = static_cast<std::int32_t>(m);
    } else if (s.r183_mark == static_cast<std::int32_t>(m)) {
      s.r183_mark = -1;
    }
    s.in_zone[m] = in ? 1 : 0;
  }
}

// §9.3 penalty turn tracker.
void Rules::turn_tracker(std::uint32_t n, std::size_t i, const Race& race, const RulesBoatInput& in) {
  BoatState& s = st_[i];
  BoatRules& br = rec_[i];
  auto reset = [&]() {
    s.t_run = 0;
    s.t_dir = 0;
    s.t_started = false;
    s.t_theta = 0.0f;
    s.t_extreme = 0.0f;
    s.t_pause = 0;
    s.t_tacks = 0;
    s.t_gybes = 0;
  };
  bool allowed = !br.pending.empty();
  if (allowed) {
    const RuleCode r = br.pending.front().rule;
    if ((r == RuleCode::c_prep || r == RuleCode::c_entry) && !race.after_gun(n)) allowed = false;
  }
  // Where: anywhere in a fleet race. In a match race (Appendix C) no part of the turn inside the zone of a rounding
  // mark of her leg (the next mark and the last one rounded), and a rounding resets it.
  if (match_ && allowed) {
    const RaceBoat& rb = race.boat(i);
    const ResolvedCourse& course = race.course();
    const std::int32_t last = static_cast<std::int32_t>(course.steps.size()) - 1;
    for (const std::int32_t k : {rb.next, rb.last_rounded}) {
      if (k <= 0 || k >= last || !(rb.started || rb.ocs_scored)) continue;
      const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
      for (const std::int32_t m : {st.marks[0], st.marks[1]}) {
        if (m >= 0 && s.in_zone[static_cast<std::size_t>(m)]) allowed = false;
      }
    }
    if (rb.rounded_this_tick) allowed = false;
  }
  if (!allowed) {
    reset();
  } else {
    const float r = in.turn_rate;
    const float dpsi = wrap_pi(in.psi - s.psi_hist[s.psi_hist.size() >= 2 ? s.psi_hist.size() - 2 : 0]);
    const std::int8_t d = r >= p_.turn_rate_min ? 1 : (r <= -p_.turn_rate_min ? -1 : 0);
    const bool flipped = s.has_prev && (s.twa >= 0.0f) != (s.twa_prev >= 0.0f);
    if (s.t_dir == 0) {
      if (d != 0) {
        s.t_dir = d;
        s.t_run = 1;
        s.t_theta = dpsi;
        if (flipped && dpsi * static_cast<float>(d) > 0.0f) {
          if (std::fabs(s.twa) < HALF_PI) ++s.t_tacks;
          else ++s.t_gybes;
        }
      }
    } else {
      s.t_theta = s.t_theta + dpsi;
      const float along = static_cast<float>(s.t_dir) * s.t_theta;
      s.t_extreme = max(s.t_extreme, along);
      if (d == s.t_dir) {
        ++s.t_run;
        s.t_pause = 0;
      } else if (!keep_clear_[i]) {
        ++s.t_pause;  // a pause only as long as needed to keep clear under 21.2 is not counted (§9.3)
      }
      if (s.t_run >= static_cast<std::int32_t>(ticks(p_.turn_start))) s.t_started = true;
      // Tacks and gybes during the turn, in the turn's direction (a boat see-sawing in irons does not tack).
      if (flipped && dpsi * static_cast<float>(s.t_dir) > 0.0f) {
        if (std::fabs(s.twa) < HALF_PI) ++s.t_tacks;
        else ++s.t_gybes;
      }
      if (s.t_pause > static_cast<std::int32_t>(ticks(p_.turn_pause)) || along < s.t_extreme - p_.turn_reversal) {
        reset();
        if (d != 0) {
          s.t_dir = d;
          s.t_run = 1;
          s.t_theta = dpsi;
        }
      }
    }
    if (s.t_started && !br.pending.empty()) {
      const Penalty& pen = br.pending.front();
      if (std::fabs(s.t_theta) >= p_.turn_one && s.t_tacks >= 1 && s.t_gybes >= 1) {
        RulesEvent e;
        e.kind = RulesEventKind::penalty_served;
        e.tick = n;
        e.boat = static_cast<std::int32_t>(i);
        e.rule = pen.rule;
        emit(e);
        br.pending.erase(br.pending.begin());
        ++br.served;
        reset();
      }
    }
  }
  br.turning_for_penalty = s.t_started && !br.pending.empty();
  br.turn_progress = s.t_theta;
  br.turn_tacks = s.t_tacks;
  br.turn_gybes = s.t_gybes;
}

// courses.md §5.1 boundaries and exclusion zones.
void Rules::boundary(std::uint32_t n, std::size_t i, const Race& race) {
  BoatState& s = st_[i];
  const ResolvedCourse& c = race.course();
  bool out = c.has_boundary && !point_in_polygon(s.c, c.boundary);
  for (const std::vector<Vec2>& ex : c.exclusions) out = out || point_in_polygon(s.c, ex);
  rec_[i].out_of_bounds = out;
  if (!out || !rule_on(RuleCode::si_boundary, race)) {
    s.out_ticks = 0;
    return;
  }
  ++s.out_ticks;
  if (s.out_ticks == static_cast<std::int32_t>(ticks(p_.boundary_penalty))) {
    issue(n, static_cast<std::int32_t>(i), RuleCode::si_boundary, -1);
  }
  if (s.out_ticks == static_cast<std::int32_t>(ticks(p_.boundary_dsq)) && !s.dsq_done) {
    s.dsq_done = true;
    rec_[i].dsq = true;
    dsq_.push_back({static_cast<std::int32_t>(i), DsqReason::boundary});
    RulesEvent e;
    e.kind = RulesEventKind::disqualified;
    e.tick = n;
    e.boat = static_cast<std::int32_t>(i);
    e.rule = RuleCode::si_boundary;
    emit(e);
  }
}

// ---- Pair geometry (§3.2, §3.3) ----

Relation Rules::direct_relation(std::size_t a, std::size_t b) const {
  const Vec2 fa = dir(in_[a].psi), fb = dir(in_[b].psi);
  float a_max_b = -INFINITY, b_min_b = INFINITY, b_max_a = -INFINITY, a_min_a = INFINITY;
  for (const Vec2 p : st_[a].hull) {
    a_max_b = max(a_max_b, v_dot(p, fb));
    a_min_a = min(a_min_a, v_dot(p, fa));
  }
  for (const Vec2 q : st_[b].hull) {
    b_min_b = min(b_min_b, v_dot(q, fb));
    b_max_a = max(b_max_a, v_dot(q, fa));
  }
  // Equipment in normal position: the bowsprit tip, while a sail is tacked to it (§3.2).
  if (in_[a].sprit > 0.0f) a_max_b = max(a_max_b, v_dot(v_add(st_[a].bow, v_scale(fa, in_[a].sprit)), fb));
  if (in_[b].sprit > 0.0f) b_max_a = max(b_max_a, v_dot(v_add(st_[b].bow, v_scale(fb, in_[b].sprit)), fa));
  if (a_max_b < b_min_b) return Relation::i_astern;
  if (b_max_a < a_min_a) return Relation::i_ahead;
  return Relation::overlapped;
}

// §3.3: a windward of b (same tack).
bool Rules::windward_of(std::size_t a, std::size_t b, const Race& race) const {
  const Vec2 da = dir(in_[a].psi), db = dir(in_[b].psi);
  const Vec2 s{da.x + db.x, da.y + db.y};
  const Vec2 m = v_len(s) < 1e-4f ? da : v_unit(s, da);
  const float lam = v_cross(m, v_sub(st_[a].c, st_[b].c));
  if (std::fabs(lam) < 0.1f) {
    const Vec2 w = dir(race.twd_mean());
    const float ua = v_dot(st_[a].c, w), ub = v_dot(st_[b].c, w);
    if (ua != ub) return ua > ub;
    return a < b;
  }
  return st_[a].tack == -1 ? lam > 0.0f : lam < 0.0f;
}

std::int32_t Rules::buoy_of(std::size_t i, const Race& race, std::int32_t& step) const {
  const RaceBoat& rb = race.boat(i);
  step = -1;
  if (!(rb.started || rb.ocs_scored) || rb.finished || rb.next <= 0) return -1;
  const CourseStep& st = race.course().steps[static_cast<std::size_t>(rb.next)];
  if (st.kind == StepKind::mark) {
    step = rb.next;
    return st.marks[0];
  }
  if (st.kind == StepKind::gate) {
    step = rb.next;
    return st.marks[st_[i].gate_step == rb.next ? st_[i].gate_buoy : 0];
  }
  if (rb.next == static_cast<std::int32_t>(race.course().steps.size()) - 1) {
    // §7.10 finishing marks: the end she is nearer to.
    const ResolvedCourse& course = race.course();
    step = rb.next;
    const float d0 = v_dist(st_[i].c, course.marks[static_cast<std::size_t>(st.marks[0])].pos);
    const float d1 = v_dist(st_[i].c, course.marks[static_cast<std::size_t>(st.marks[1])].pos);
    return st.marks[d0 <= d1 ? 0 : 1];
  }
  return -1;
}

float Rules::mark_radius(std::int32_t mark) const {
  float r = course_->marks[static_cast<std::size_t>(mark)].radius;
  for (const CourseObject& o : course_->objects) {
    if (o.mark == mark) r = o.r;
  }
  return r;
}

// The side a mark of step k is left on; a finishing line end as a gate buoy seen from the last mark (§7.10).
Side Rules::mark_side(const ResolvedCourse& course, std::int32_t k, std::int32_t mark) const {
  const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
  if (st.kind == StepKind::finish) {
    const Vec2 P = course.steps[static_cast<std::size_t>(k - 1)].ref;
    return side_left(course.marks[static_cast<std::size_t>(mark)].pos, P, st.ref) > 0.0f ? Side::port : Side::starboard;
  }
  return st.marks[0] == mark ? st.sides[0] : st.sides[1];
}

// Where the course goes after mark `mark` of step k (§7.4): the next step's reference point; past a finishing
// mark, `reach` metres beyond it across the line.
Vec2 Rules::after_mark(const ResolvedCourse& course, std::int32_t k, std::int32_t mark, float reach) const {
  const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
  if (st.kind == StepKind::finish) {
    const Vec2 P = course.steps[static_cast<std::size_t>(k - 1)].ref;
    const Vec2 u = v_unit(v_sub(st.ref, P), {0.0f, 1.0f});
    return v_add(course.marks[static_cast<std::size_t>(mark)].pos, v_scale(u, reach));
  }
  return course.steps[static_cast<std::size_t>(k + 1)].ref;
}

// §7.6 fetching: her straight track passes the mark on the required side within 2 L, the mark ahead.
bool Rules::fetching(std::size_t x, Vec2 M, Side side, const RulesBoatInput& in) const {
  const float cog = in.sog > 0.05f ? in.cog : in.psi;
  const Vec2 d = dir(cog);
  const float off = side_left(M, st_[x].c, v_add(st_[x].c, d));
  const bool ahead = v_dot(v_sub(M, st_[x].c), d) > 0.0f;
  return ahead && std::fabs(off) <= 2.0f * st_[x].L && (side == Side::port ? off > 0.0f : off < 0.0f);
}

bool Rules::within_mark_room(std::size_t e, const MarkRoom& mr) const {
  if (mr.corridor.size() < 2) return true;
  const float half = 0.5f * st_[e].B + 0.5f * st_[e].L;
  float d = INFINITY;
  for (std::size_t k = 1; k < mr.corridor.size(); ++k) d = min(d, point_segment_dist(st_[e].c, mr.corridor[k - 1], mr.corridor[k]));
  return d <= half;
}

// ---- Rules 18 (§7.2 – §7.7) ----

void Rules::mark_rules(std::uint32_t n, PairState& ps, const Race& race, std::span<const RulesBoatInput> in) {
  const std::size_t A = static_cast<std::size_t>(ps.i), B = static_cast<std::size_t>(ps.j);
  ps.r183 = ps.r184 = false;
  for (MarkRoom& mr : ps.rooms) mr.breach = false;
  std::int32_t sa = -1, sb = -1;
  const std::int32_t ma = buoy_of(A, race, sa), mb = buoy_of(B, race, sb);
  const ResolvedCourse& course = race.course();
  bool applies = false;
  std::int32_t M = -1;
  Side side = Side::port;
  if (ma >= 0 && ma == mb) {
    const Side side_a = mark_side(course, sa, ma);
    const Side side_b = mark_side(course, sb, mb);
    if (side_a == side_b) {
      M = ma;
      side = side_a;
    }
  }
  const bool on = rule_on(RuleCode::r18_2, race);
  Vec2 Mp{0.0f, 0.0f};
  float Z = 0.0f;
  bool zone_a = false, zone_b = false;
  if (M >= 0 && on) {
    Mp = course.marks[static_cast<std::size_t>(M)].pos;
    const float La = st_[A].L, Lb = st_[B].L;
    const float L_near = v_dist(st_[A].c, Mp) <= v_dist(st_[B].c, Mp) ? La : Lb;
    Z = zone_lengths_ * L_near + mark_radius(M);  // measured from the mark (§7.1)
    for (const Vec2 p : st_[A].hull) zone_a = zone_a || v_dist(p, Mp) <= Z;
    for (const Vec2 p : st_[B].hull) zone_b = zone_b || v_dist(p, Mp) <= Z;
    applies = zone_a || zone_b;
    if (applies && st_[A].tack != st_[B].tack) {
      // 18.1(a)(1): not between opposite-tack boats both beating to the mark.
      auto beating = [&](std::size_t x) {
        const float br = compass(v_sub(Mp, st_[x].c));
        return std::fabs(st_[x].twa) < HALF_PI &&
               std::fabs(wrap_pi(br - in[x].twd)) <= st_[x].theta_ch + 10.0f * DEG;
      };
      if (beating(A) && beating(B)) applies = false;
      // 18.1(a)(2): nor when at the mark one of them must tack to sail her proper course and the other need not.
      // From her heading, turning the rounding way to the course after the mark: a tack when the turn passes head
      // to wind; none when a beat follows (the turn stops at the first close-hauled heading).
      const float h_out = compass(v_sub(after_mark(course, sa, M, 5.0f * st_[A].L), Mp));
      auto must_tack = [&](std::size_t x) {
        if (std::fabs(wrap_pi(in[x].twd - h_out)) < st_[x].theta_ch) return false;
        const bool ccw = side == Side::port;  // a mark left to port is rounded turning to port
        const float sweep = ccw ? wrap_2pi(in[x].psi - h_out) : wrap_2pi(h_out - in[x].psi);
        const float to_wind = ccw ? wrap_2pi(in[x].psi - in[x].twd) : wrap_2pi(in[x].twd - in[x].psi);
        return to_wind < sweep;
      };
      if (applies && must_tack(A) != must_tack(B)) applies = false;
    }
  }
  // Rule 18 applies: clear astern / ahead / overlap are used for opposite tacks too (§7.2).
  if (applies && ps.rel == Relation::n_a) ps.rel = ps.raw;

  // End statuses whose conditions are gone.
  for (std::size_t k = 0; k < ps.rooms.size();) {
    MarkRoom& mr = ps.rooms[k];
    const std::size_t E = static_cast<std::size_t>(mr.entitled);
    bool keep = applies && mr.mark == M;
    if (keep && mr.rule == RuleCode::r18_2) {
      const bool e_zone = E == A ? zone_a : zone_b;
      if (!e_zone || st_[E].head_to_wind) keep = false;
      if (!mr.frozen && !overlapped(ps.raw)) keep = false;
    }
    if (!keep) ps.rooms.erase(ps.rooms.begin() + static_cast<std::ptrdiff_t>(k));
    else ++k;
  }
  if (!zone_a && !zone_b) ps.used_marks.clear();
  if (!applies) return;

  const Vec2 next_ref = after_mark(course, sa, M, 5.0f * min(st_[A].L, st_[B].L));
  auto has_room = [&](std::int32_t mark) {
    for (const MarkRoom& mr : ps.rooms) {
      if (mr.mark == mark) return true;
    }
    return false;
  };
  auto used = [&](std::int32_t mark) {
    return std::find(ps.used_marks.begin(), ps.used_marks.end(), mark) != ps.used_marks.end();
  };
  auto inside_of = [&](Relation rel) -> std::int32_t {
    if (rel == Relation::i_ahead) return ps.i;
    if (rel == Relation::i_astern) return ps.j;
    // Overlapped: the boat on the mark side along the mean heading.
    const Vec2 da = dir(in[A].psi), db = dir(in[B].psi);
    const Vec2 s{da.x + db.x, da.y + db.y};
    const Vec2 m = v_len(s) < 1e-4f ? da : v_unit(s, da);
    const float lam = v_cross(m, v_sub(st_[A].c, st_[B].c));  // > 0: A left of B
    const bool a_inside = side == Side::port ? lam > 0.0f : lam < 0.0f;
    return a_inside ? ps.i : ps.j;
  };

  // §7.5 rule 18.3 (port-hand marks only): a boat T that passed head to wind onto starboard in the zone and a
  // starboard boat S fetching the mark: no 18.2 between them; T's duties if S has been on starboard since she
  // entered the zone.
  std::int32_t tacker = -1;
  for (const std::size_t T : {A, B}) {
    const std::size_t S = T == A ? B : A;
    if (side != Side::port || st_[T].r183_mark != M || st_[T].tack != 1) continue;
    if (st_[S].tack != 1 || !rule_on(RuleCode::r18_3, race)) continue;
    if (!fetching(S, Mp, side, in[S])) continue;
    tacker = static_cast<std::int32_t>(T);
    ps.rooms.erase(std::remove_if(ps.rooms.begin(), ps.rooms.end(),
                                  [&](const MarkRoom& mr) { return mr.rule == RuleCode::r18_2; }),
                   ps.rooms.end());
    if (st_[S].stbd_since_zone.empty() || !st_[S].stbd_since_zone[static_cast<std::size_t>(M)]) continue;
    if (std::fabs(st_[S].twa) <= st_[S].theta_ch + 3.0f * DEG && pred_gap(T, S, 1.0f, max(1.0f, margin(T, S))) < margin(T, S)) {
      ps.r183 = true;
      ps.r183_holder = static_cast<std::int32_t>(T);
    }
    if (overlapped(ps.raw) && inside_of(ps.raw) == static_cast<std::int32_t>(S) && !has_room(M)) {
      MarkRoom mr;
      mr.mark = M;
      mr.entitled = static_cast<std::int32_t>(S);
      mr.giver = static_cast<std::int32_t>(T);
      mr.rule = RuleCode::r18_3;
      mark_room_path(S, M, side, next_ref, mr.corridor);
      ps.rooms.push_back(std::move(mr));
    }
  }

  // §7.3.1 the status when the first of them reaches the zone; §7.3.3 18.2(a) without a status.
  if (tacker < 0 && !has_room(M)) {
    Relation rel = ps.raw;
    if (ps.has_raw && n - ps.raw_change_tick < ticks(p_.doubt)) rel = ps.raw_before;  // 18.2(d)
    if (!used(M)) {
      MarkRoom mr;
      mr.mark = M;
      mr.entitled = inside_of(rel);
      if (!overlapped(rel)) {
        // 18.2(a)(2): not overlapped when the first of them reaches the zone: the boat that has not reached it
        // gives. Both inside already: the one that entered earlier; the same tick: the one clear ahead.
        const std::size_t mi = static_cast<std::size_t>(M);
        if (zone_a != zone_b) {
          mr.entitled = zone_a ? ps.i : ps.j;
        } else if (st_[A].in_zone[mi] && st_[B].in_zone[mi] && st_[A].zone_enter[mi] != st_[B].zone_enter[mi]) {
          mr.entitled = st_[A].zone_enter[mi] < st_[B].zone_enter[mi] ? ps.i : ps.j;
        }
      }
      mr.giver = mr.entitled == ps.i ? ps.j : ps.i;
      mr.frozen = true;
      mark_room_path(static_cast<std::size_t>(mr.entitled), M, side, next_ref, mr.corridor);
      ps.rooms.push_back(std::move(mr));
      ps.used_marks.push_back(M);
    } else if (overlapped(ps.raw) && ps.raw_change_tick == n) {
      MarkRoom mr;
      mr.mark = M;
      mr.entitled = inside_of(ps.raw);
      mr.giver = mr.entitled == ps.i ? ps.j : ps.i;
      mr.frozen = false;
      mark_room_path(static_cast<std::size_t>(mr.entitled), M, side, next_ref, mr.corridor);
      // No duty if the outside boat could not give room from the moment the overlap began.
      std::vector<Vec2> path;
      std::vector<Pose> ep;
      mark_room_path(static_cast<std::size_t>(mr.entitled), M, side, next_ref, path);
      along_path(static_cast<std::size_t>(mr.entitled), path, p_.room_horizon, ep);
      const std::size_t Gb = static_cast<std::size_t>(mr.giver), E = static_cast<std::size_t>(mr.entitled);
      std::vector<Pose> gp(ep.size());
      for (std::size_t k = 0; k < gp.size(); ++k) gp[k] = st_[Gb].pred[k];
      const bool room_now = poses_gap(Gb, gp, E, ep, margin(E, Gb) + 0.5f) >= margin(E, Gb);
      // 18.2(d): the 'unable from the start of the overlap' exemption only for an inside overlap obtained from
      // clear astern or by tacking to windward of the outside boat.
      const Relation e_astern = mr.entitled == ps.i ? Relation::i_astern : Relation::i_ahead;
      const bool e_tacked = st_[E].tacking ||
                            (st_[E].has_tacking_end && n - st_[E].tacking_end_tick <= ticks(p_.r182d_tack));
      const bool exempt_kind = ps.raw_before == e_astern || (e_tacked && windward_of(E, Gb, race));
      if (room_now || !exempt_kind || escape_room(Gb, ep, E, p_.room_horizon, margin(E, Gb))) {
        ps.rooms.push_back(std::move(mr));
      }
    }
  }

  // §7.4 the mark-room test for each entitlement.
  for (MarkRoom& mr : ps.rooms) {
    const std::size_t E = static_cast<std::size_t>(mr.entitled), Gb = static_cast<std::size_t>(mr.giver);
    const float m = margin(E, Gb);
    std::vector<Vec2> path;
    std::vector<Pose> ep, ep1;
    mark_room_path(E, mr.mark, side, next_ref, path);
    along_path(E, path, p_.room_horizon, ep);
    ep1.assign(ep.begin(), ep.begin() + static_cast<std::ptrdiff_t>(std::min<std::size_t>(ep.size(), 11)));
    std::vector<Pose> gp(ep.size());
    for (std::size_t k = 0; k < gp.size(); ++k) gp[k] = st_[Gb].pred[k];
    const bool room4 = poses_gap(Gb, gp, E, ep, m + 0.5f) >= m;
    std::vector<Pose> gp1(gp.begin(), gp.begin() + static_cast<std::ptrdiff_t>(ep1.size()));
    const bool room1 = poses_gap(Gb, gp1, E, ep1, m + 0.5f) >= m;
    if (!within_mark_room(E, mr)) {
      mr.state = KcState::clear;  // sailing wide: no room owed beyond her mark-room
      mr.could_act = false;
      continue;
    }
    if (room4) {
      mr.state = KcState::clear;
      mr.could_act = false;
    } else {
      if (!mr.could_act && escape_room(Gb, ep, E, p_.room_horizon, m)) mr.could_act = true;
      mr.state = KcState::warning;
      if (!room1 && mr.could_act) {
        mr.state = KcState::breach;
        mr.breach = true;
      }
    }
  }

  // §7.7 rule 18.4: an entitled right-of-way boat that must gybe at the mark sails no farther than needed.
  const StepKind kind_m = course.steps[static_cast<std::size_t>(sa)].kind;
  if (rule_on(RuleCode::r18_4, race) && kind_m == StepKind::mark) {  // not at a gate mark nor a finishing mark
    for (const MarkRoom& mr : ps.rooms) {
      if (mr.rule != RuleCode::r18_2) continue;
      const std::size_t E = static_cast<std::size_t>(mr.entitled);
      if (ps.giver != mr.giver || std::fabs(st_[E].twa) <= HALF_PI || !overlapped(ps.raw)) continue;
      const float next_twa = wrap_pi(in[E].twd - compass(v_sub(next_ref, Mp)));
      if ((next_twa >= 0.0f ? 1 : -1) == st_[E].tack) continue;
      const float dm = st_[E].dmin[static_cast<std::size_t>(M)];
      if (v_dist(st_[E].c, Mp) > dm + st_[E].L) {
        ps.r184 = true;
        ps.r184_holder = mr.entitled;
      }
    }
  }
}

// ---- Rule 19 (§7.8) ----

void Rules::obstruction_rules(std::uint32_t /*n*/, PairState& ps, const Race& race, std::span<const RulesBoatInput> in) {
  ps.r19_breach = false;
  const std::size_t A = static_cast<std::size_t>(ps.i), B = static_cast<std::size_t>(ps.j);
  if (!rule_on(RuleCode::r19, race) || st_[A].tack != st_[B].tack || !overlapped(ps.raw)) {
    ps.r19_on = false;
    return;
  }
  const ResolvedCourse& course = race.course();
  // Obstructions: land, obstacles, exclusion zones, and course objects that are not a mark of either boat's leg.
  struct Obst {
    std::int32_t id;
    bool circle;
    Vec2 c;
    float r;
    const std::vector<Vec2>* poly;
    bool convex;
    bool start_mark;
  };
  std::vector<Obst> obs;
  auto leg_mark = [&](std::size_t x, std::int32_t mark) {
    const RaceBoat& rb = race.boat(x);
    for (const std::int32_t k : {rb.next - 1, rb.next}) {
      if (k < 0 || k >= static_cast<std::int32_t>(course.steps.size())) continue;
      const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
      if (st.marks[0] == mark || st.marks[1] == mark) return true;
    }
    return false;
  };
  const CourseStep& s0 = course.start();
  const bool approaching = !(race.boat(A).started && race.boat(B).started);
  std::int32_t id = 0;
  for (const CourseObject& o : course.objects) {
    ++id;
    if (leg_mark(A, o.mark) || leg_mark(B, o.mark)) continue;
    const bool start_mark = o.mark == s0.marks[0] || o.mark == s0.marks[1];
    if (start_mark && approaching) continue;  // no room at a starting mark while approaching to start
    obs.push_back({id, !o.is_boat, o.c, o.r, o.is_boat ? &o.polygon : nullptr, true, start_mark});
  }
  if (venue_ != nullptr) {
    for (const VenueObstacle& o : venue_->obstacles) {
      ++id;
      Vec2 c = o.c;
      float r = o.r;
      if (!o.is_circle) {
        c = {0.0f, 0.0f};
        for (const Vec2 v : o.polygon) c = v_add(c, v);
        c = v_scale(c, 1.0f / static_cast<float>(o.polygon.size()));
        r = 0.0f;
        for (const Vec2 v : o.polygon) r = max(r, v_dist(v, c));
      }
      obs.push_back({id, o.is_circle, c, r, o.is_circle ? nullptr : &o.polygon, true, false});
    }
    for (const VenueLand& l : venue_->land) {
      ++id;
      Vec2 c{0.0f, 0.0f};
      for (const Vec2 v : l.points) c = v_add(c, v);
      c = v_scale(c, 1.0f / static_cast<float>(l.points.size()));
      float r = 0.0f;
      for (const Vec2 v : l.points) r = max(r, v_dist(v, c));
      obs.push_back({id, false, c, r, &l.points, false, false});
    }
  }
  for (const std::vector<Vec2>& ex : course.exclusions) {
    ++id;
    Vec2 c{0.0f, 0.0f};
    for (const Vec2 v : ex) c = v_add(c, v);
    c = v_scale(c, 1.0f / static_cast<float>(ex.size()));
    float r = 0.0f;
    for (const Vec2 v : ex) r = max(r, v_dist(v, c));
    obs.push_back({id, false, c, r, &ex, false, false});
  }
  auto gap_to = [&](std::span<const Vec2> hull, const Obst& o) {
    if (o.circle) return convex_circle_gap(hull, o.c, o.r);
    return o.convex ? convex_gap(hull, *o.poly) : polygon_gap(hull, *o.poly);
  };
  auto near_point = [&](Vec2 p, const Obst& o) {
    if (o.circle) return v_add(o.c, v_scale(v_unit(v_sub(p, o.c), {1.0f, 0.0f}), o.r));
    Vec2 best = o.c;
    float bd = INFINITY;
    const std::vector<Vec2>& q = *o.poly;
    for (std::size_t k = 0; k < q.size(); ++k) {
      const Vec2 a = q[k], b = q[(k + 1) % q.size()];
      const Vec2 ab = v_sub(b, a);
      const float l2 = v_dot(ab, ab);
      const float t = l2 > 0.0f ? clamp(v_dot(v_sub(p, a), ab) / l2, 0.0f, 1.0f) : 0.0f;
      const Vec2 x = v_add(a, v_scale(ab, t));
      const float d = v_dist(p, x);
      if (d < bd) {
        bd = d;
        best = x;
      }
    }
    return best;
  };
  const float H = p_.obstruction_h;
  const std::size_t K = static_cast<std::size_t>(std::lround(H / 0.1f)) + 1;
  const Obst* found = nullptr;
  float best_gap = INFINITY;
  for (const Obst& o : obs) {
    bool both = true;
    for (const std::size_t x : {A, B}) {
      const float reach = st_[x].r_hull + (std::fabs(in[x].v) + v_len(in[x].current)) * H + st_[x].L;
      if (v_dist(st_[x].c, o.c) - o.r > reach) {
        both = false;
        break;
      }
      // A land polygon's bounding circle spans the whole shore; its edges are the real bound (no hull point
      // reaches beyond `reach` of the centre within the horizon).
      if (!o.convex && !o.circle && !point_in_polygon(st_[x].c, *o.poly) &&
          point_polygon_edge_dist(st_[x].c, *o.poly) > reach) {
        both = false;
        break;
      }
      float g = INFINITY;
      for (std::size_t k = 0; k < K && g >= st_[x].L; k += 5) g = min(g, gap_to(pred_hull(x, k).pts(), o));
      if (!(g < st_[x].L)) both = false;
    }
    if (!both) continue;
    // Same side of both tracks.
    auto side_of = [&](std::size_t x) {
      const Vec2 q = near_point(st_[x].c, o);
      return side_left(q, st_[x].c, v_add(st_[x].c, dir(in[x].psi))) > 0.0f;
    };
    if (side_of(A) != side_of(B)) continue;
    const float g = min(gap_to(st_[A].hull, o), gap_to(st_[B].hull, o));
    if (g < best_gap) {
      best_gap = g;
      found = &o;
    }
  }
  if (found == nullptr) {
    ps.r19_on = false;
    ps.r19_could_act = false;
    ps.r19_state = KcState::clear;
    return;
  }
  const Obst& o = *found;
  const std::size_t I = gap_to(st_[A].hull, o) <= gap_to(st_[B].hull, o) ? A : B;
  const std::size_t Gb = I == A ? B : A;
  ps.r19_on = true;
  ps.r19_entitled = static_cast<std::int32_t>(I);
  ps.r19_giver = static_cast<std::int32_t>(Gb);
  ps.r19_obst = o.id;
  // I's path: her heading deflected away from the obstruction just enough to keep 0.5 B + 0.25 L from it.
  const Vec2 q = near_point(st_[I].c, o);
  const bool obst_left = side_left(q, st_[I].c, v_add(st_[I].c, dir(in[I].psi))) > 0.0f;
  const float away = obst_left ? 1.0f : -1.0f;  // turn to starboard when the obstruction is to port
  const float clear = 0.5f * st_[I].B + 0.25f * st_[I].L;
  const float v = max(in[I].v, 0.5f);
  std::vector<Pose> ip;
  std::vector<Vec2> hull;
  for (std::int32_t step = 0; step <= 45; ++step) {
    const float psi = in[I].psi + away * (static_cast<float>(step) * 2.0f * DEG);
    const Vec2 u = dir(psi);
    ip.resize(static_cast<std::size_t>(std::lround(p_.room_horizon / 0.1f)) + 1);
    float g = INFINITY;
    for (std::size_t k = 0; k < ip.size(); ++k) {
      const float t = static_cast<float>(k) * 0.1f;
      ip[k] = {{st_[I].c.x + (v * u.x + in[I].current.x) * t, st_[I].c.y + (v * u.y + in[I].current.y) * t}, psi};
      if (k % 5 == 0) {
        place_outline(st_[I].perf->dynamics.collision.outline, ip[k].c, psi, hull);
        g = min(g, gap_to(hull, o));
      }
    }
    if (g >= clear) break;
  }
  const float m = margin(I, Gb);
  std::vector<Pose> gp(ip.size());
  for (std::size_t k = 0; k < gp.size(); ++k) gp[k] = st_[Gb].pred[k];
  const bool room4 = poses_gap(Gb, gp, I, ip, m + 0.5f) >= m;
  const std::vector<Pose> ip1(ip.begin(), ip.begin() + 11), gp1(gp.begin(), gp.begin() + 11);
  const bool room1 = poses_gap(Gb, gp1, I, ip1, m + 0.5f) >= m;
  if (room4) {
    ps.r19_state = KcState::clear;
    ps.r19_could_act = false;
  } else {
    if (!ps.r19_could_act && escape_room(Gb, ip, I, p_.room_horizon, m)) ps.r19_could_act = true;
    ps.r19_state = KcState::warning;
    if (!room1 && ps.r19_could_act) {
      ps.r19_state = KcState::breach;
      ps.r19_breach = true;
    }
  }
}

// ---- One pair (§2.2 steps 2 – 6) ----

void Rules::judge_pair(std::uint32_t n, PairState& ps, const Race& race, std::span<const RulesBoatInput> in) {
  const std::size_t A = static_cast<std::size_t>(ps.i), B = static_cast<std::size_t>(ps.j);
  BoatState& sa = st_[A];
  BoatState& sb = st_[B];
  const float m = margin(A, B);

  // Relation (§3.2); `raw` was set for every judged pair before this call, with overlaps via a third boat.
  const bool same_tack = sa.tack == sb.tack;
  const bool both_free = std::fabs(sa.twa) > HALF_PI && std::fabs(sb.twa) > HALF_PI;
  ps.rel = (same_tack || both_free) ? ps.raw : Relation::n_a;

  // Obligation (§4).
  std::int32_t giver = -1;
  RuleCode rule = RuleCode::none;
  const bool ret_a = race.returning(A), ret_b = race.returning(B);
  const bool pen_a = rec_[A].turning_for_penalty, pen_b = rec_[B].turning_for_penalty;
  if (ret_a != ret_b) {
    giver = ret_a ? ps.i : ps.j;
    rule = RuleCode::r21_1;
  } else if (pen_a != pen_b) {
    giver = pen_a ? ps.i : ps.j;
    rule = RuleCode::r21_2;
  } else if (sa.tacking != sb.tacking) {
    giver = sa.tacking ? ps.i : ps.j;
    rule = RuleCode::r13;
  } else if (sa.tacking && sb.tacking) {
    rule = RuleCode::r13;
    const bool a_port = side_left(sa.c, sb.stern, sb.bow) > 0.0f && !(side_left(sb.c, sa.stern, sa.bow) > 0.0f);
    const bool b_port = side_left(sb.c, sa.stern, sa.bow) > 0.0f && !(side_left(sa.c, sb.stern, sb.bow) > 0.0f);
    if (a_port) giver = ps.i;
    else if (b_port) giver = ps.j;
    else {
      const Vec2 da = dir(in[A].psi), db = dir(in[B].psi);
      const Vec2 mh = v_unit({da.x + db.x, da.y + db.y}, da);
      giver = v_dot(v_sub(sa.c, sb.c), mh) < 0.0f ? ps.i : ps.j;
    }
  } else if (!same_tack) {
    giver = sa.tack == -1 ? ps.i : ps.j;
    rule = RuleCode::r10;
  } else if (overlapped(ps.rel)) {
    giver = windward_of(A, B, race) ? ps.i : ps.j;
    rule = RuleCode::r11;
  } else {
    giver = ps.rel == Relation::i_astern ? ps.i : ps.j;
    rule = RuleCode::r12;
  }
  const std::int32_t holder = giver == ps.i ? ps.j : ps.i;
  const std::size_t Gb = static_cast<std::size_t>(giver), H = static_cast<std::size_t>(holder);

  // §5.2 rule 15 onset and cause.
  if (giver != ps.giver) {
    ps.onset_tick = n;
    const BoatState& hb = st_[H];
    const std::uint32_t win = ticks(p_.r15_cause);
    bool holder_action = (hb.has_tack_change && n - hb.tack_change_tick <= win) ||
                         (hb.has_tacking_end && n - hb.tacking_end_tick <= win) ||
                         (hb.has_status_end && n - hb.status_end_tick <= win);
    // The holder established a leeward overlap from clear astern.
    const Relation h_astern = holder == ps.i ? Relation::i_astern : Relation::i_ahead;
    if (ps.raw_prev == h_astern && overlapped(ps.raw) && same_tack && rule == RuleCode::r11) holder_action = true;
    ps.r15_pending = holder_action;
    ps.r15_start = n;
    ps.giver = giver;
  }
  ps.kc_rule = rule;
  ps.r15_breach = false;
  if (ps.r15_pending) {
    if (n - ps.r15_start > ticks(p_.r15_room) || escape(Gb, H, p_.escape_h)) ps.r15_pending = false;
    else ps.r15_breach = true;
  }

  // §3.5 keep-clear state.
  ps.kc_prev = ps.kc;
  const float g1 = pred_gap(Gb, H, p_.h_breach, m + 0.5f);
  const float g4 = g1 < m ? g1 : pred_gap(Gb, H, p_.h_warn, m + 0.5f);
  const bool ov = overlapped(ps.rel);
  if (ps.contact_now) ps.kc = KcState::breach;
  else if (g1 < m || (ov && turn_test_hits(Gb, H, p_.delta))) ps.kc = KcState::breach;
  else if (g4 < m || (ov && turn_test_hits(Gb, H, p_.delta_warn))) ps.kc = KcState::warning;
  else ps.kc = KcState::clear;
  if (ps.kc == KcState::breach) {
    ps.has_breach_tick = true;
    ps.last_breach_tick = n;
  }
  ps.kc_hist[n % 32u] = static_cast<std::uint8_t>(ps.kc);
  if (ps.kc_prev == KcState::clear && ps.kc != KcState::clear) {
    RulesEvent e;
    e.kind = RulesEventKind::rule_warning;
    e.tick = n;
    e.boat = giver;
    e.other = holder;
    e.rule = rule;
    emit(e);
  }

  // §5.3 rule 16.
  ps.r161 = ps.r162 = false;
  const bool r16_exempt_mark = [&]() {
    for (const MarkRoom& mr : ps.rooms) {
      if (mr.entitled == holder && within_mark_room(H, mr)) return true;
    }
    return false;
  }();
  if (st_[H].cc_started_now) {
    // t_c is the first tick of the course change; A's state at t_c is her state on the tick before it.
    const std::uint32_t back = st_[H].cc_back + 1u;
    const KcState at_tc = n >= back && n - back >= ps.first_tick ? static_cast<KcState>(ps.kc_hist[(n - back) % 32u])
                                                                   : KcState::clear;
    const std::uint32_t t_c = n - st_[H].cc_back;
    if (at_tc != KcState::breach) {
      ps.w161 = true;
      ps.w161_start = t_c;
      ps.w16_holder = holder;
    }
    const bool upwind = std::fabs(st_[Gb].twa) < HALF_PI && std::fabs(st_[H].twa) < HALF_PI;
    const bool bearing_away = st_[H].cc_dir == -st_[H].tack;
    if (st_[Gb].tack == -1 && st_[H].tack == 1 && upwind && bearing_away && at_tc == KcState::clear) {
      // Gb passing astern of H: on straight tracks at their headings at t_c, at the closest approach within 5 s
      // Gb's reference point is aft of H's abeam line.
      const std::vector<float>& hh = st_[H].psi_hist;
      const std::size_t bk = std::min<std::size_t>(st_[H].cc_back, hh.size() - 1);
      const float psi_h = hh[hh.size() - 1 - bk];
      const Vec2 fh = dir(psi_h);
      const Vec2 d0 = v_sub(st_[Gb].c, st_[H].c);
      const Vec2 vg = v_scale(dir(in[Gb].psi), in[Gb].v), vh = v_scale(fh, in[H].v);
      const Vec2 dv = v_sub(vg, vh);
      const float dv2 = v_dot(dv, dv);
      const float ts = dv2 > 1e-6f ? clamp(-v_dot(d0, dv) / dv2, 0.0f, 5.0f) : 0.0f;
      const Vec2 dc = v_add(d0, v_scale(dv, ts));
      if (v_dot(dc, fh) < 0.0f) {
        ps.w162 = true;
        ps.w162_start = t_c;
        ps.w16_holder = holder;
      }
    }
  }
  if (ps.w161 && (ps.w16_holder != holder || n - ps.w161_start > ticks(p_.r16_window))) ps.w161 = false;
  if (ps.w162 && (ps.w16_holder != holder || n - ps.w162_start > ticks(p_.r16_window))) ps.w162 = false;
  if (!r16_exempt_mark) {
    if (ps.w161 && ps.kc == KcState::breach && !escape(Gb, H, p_.escape_h)) ps.r161 = true;
    if (ps.w162 && ps.kc != KcState::clear) ps.r162 = true;
  }

  // §5.4 rule 17.
  ps.r17 = false;
  if (rule_on(RuleCode::r17, race)) {
    const float gap = ps.gap;  // hull_gap(A, B) of this tick (step 2)
    if (ps.r17_holder >= 0) {
      const std::size_t Lw = static_cast<std::size_t>(ps.r17_holder);
      if (!overlapped(ps.raw) || !same_tack || gap > p_.r17_clear * st_[Lw].L) ps.r17_holder = -1;
    }
    if (ps.r17_holder < 0 && same_tack && overlapped(ps.raw)) {
      for (const std::size_t X : {A, B}) {
        const std::size_t W = X == A ? B : A;
        const Relation x_astern = X == A ? Relation::i_astern : Relation::i_ahead;
        // 2025-2028: also when the overlap begins while the windward boat is tacking.
        if (ps.raw_prev == x_astern && !windward_of(X, W, race) && gap < p_.r17_dist * st_[X].L) {
          ps.r17_holder = static_cast<std::int32_t>(X);
        }
      }
    }
    if (ps.r17_holder >= 0 && ps.r17_holder == holder && rule == RuleCode::r11 && st_[H].above &&
        ps.kc != KcState::clear) {
      ps.r17 = true;
    }
  } else {
    ps.r17_holder = -1;
  }

  mark_rules(n, ps, race, in);
  obstruction_rules(n, ps, race, in);

  // §5.5, §6.1 decisive breach.
  std::int32_t culprit = -1;
  RuleCode crule = RuleCode::none;
  auto limit = [&](bool on, RuleCode r, std::int32_t who) {
    if (culprit < 0 && on && rule_on(r, race)) {
      culprit = who;
      crule = r;
    }
  };
  limit(ps.r183, RuleCode::r18_3, ps.r183_holder);  // the specific rule at the mark first (§5.5)
  limit(ps.r15_breach, RuleCode::r15, holder);
  limit(ps.r162, RuleCode::r16_2, holder);
  limit(ps.r161, RuleCode::r16_1, holder);
  limit(ps.r17, RuleCode::r17, holder);
  limit(ps.r184, RuleCode::r18_4, ps.r184_holder);
  if (culprit < 0) {
    for (const MarkRoom& mr : ps.rooms) {
      if (mr.breach && culprit < 0) {
        culprit = mr.giver;
        crule = RuleCode::r18_2;
      }
    }
  }
  if (culprit < 0 && ps.r19_breach) {
    culprit = ps.r19_giver;
    crule = RuleCode::r19;
  }
  if (culprit < 0 && ps.kc == KcState::breach && !ps.contact_now) {
    bool exonerated = false;
    for (const MarkRoom& mr : ps.rooms) {
      if (mr.entitled == giver && mr.giver == holder && within_mark_room(Gb, mr)) exonerated = true;  // 21(a)
    }
    if (ps.r19_on && ps.r19_entitled == giver) exonerated = true;
    if (ps.has_contact_pen && ps.contact_pen_boat == holder && n - ps.contact_pen_tick < 2 * kTicksPerS) {
      exonerated = true;  // 21(b)
    }
    if (!exonerated) {
      culprit = giver;
      crule = rule;
    }
  }
  if (culprit >= 0) {
    ps.has_decisive = true;
    ps.dec_culprit = culprit;
    ps.dec_rule = crule;
    ps.dec_tick = n;
  }

  // §9.1 persistence of a non-contact breach.
  if (culprit >= 0) {
    if (culprit != ps.br_culprit || crule != ps.br_rule) {
      ps.br_culprit = culprit;
      ps.br_rule = crule;
      ps.br_since = n;
    }
    float t_persist = fast_persist(crule) ? p_.t_persist_fast : p_.t_persist_slow;
    const UmpireMode um = race.settings().umpire;
    bool penalise = true;
    if (um == UmpireMode::contact_only) {
      const bool hard = crule == RuleCode::r10 || crule == RuleCode::r13 || crule == RuleCode::r21_1 ||
                        crule == RuleCode::r21_2;
      penalise = hard;
      t_persist = p_.t_persist_slow;
    }
    if (penalise && n - ps.br_since + 1 >= ticks(t_persist) && !ps.inc_open) {
      counted_breach(n, ps, culprit, crule, false);
    }
  } else {
    ps.br_culprit = -1;
    ps.br_rule = RuleCode::none;
  }

  // Incident close: 5 s with nothing (§9.1).
  bool quiet = ps.kc == KcState::clear && culprit < 0 && !ps.contact_now;
  for (const MarkRoom& mr : ps.rooms) quiet = quiet && mr.state == KcState::clear;
  quiet = quiet && ps.r19_state == KcState::clear;
  if (!quiet) ps.clear_since = n;
  if (ps.inc_open && n - ps.clear_since >= ticks(p_.incident_close)) ps.inc_open = false;
  if (ps.protest_open) {
    ps.protest_min_gap = min(ps.protest_min_gap, ps.gap);  // hull_gap(A, B) of this tick (step 2)
    const std::size_t F = static_cast<std::size_t>(ps.protest_fouled);
    if (in[F].ai && ps.protest_min_gap < 0.5f * m) protest(ps.protest_fouled, n);
    if (ps.protest_open && n >= ps.protest_deadline) ps.protest_open = false;
  }

  // §11.1 record.
  PairRecord r;
  r.i = ps.i;
  r.j = ps.j;
  r.relation = ps.rel;
  r.kc_giver = giver;
  r.kc_holder = holder;
  r.kc_rule = rule;
  r.kc_state = ps.kc;
  for (const MarkRoom& mr : ps.rooms) {
    r.room_entitled = mr.entitled;
    r.room_giver = mr.giver;
    r.room_rule = mr.rule;
    r.room_mark = mr.mark;
    r.room_state = mr.state;
  }
  if (r.room_entitled < 0 && ps.r19_on) {
    r.room_entitled = ps.r19_entitled;
    r.room_giver = ps.r19_giver;
    r.room_rule = RuleCode::r19;
    r.room_mark = -1 - ps.r19_obst;
    r.room_state = ps.r19_state;
  }
  if (ps.r15_breach) r.limits.push_back({holder, RuleCode::r15});
  if (ps.r161) r.limits.push_back({holder, RuleCode::r16_1});
  if (ps.r162) r.limits.push_back({holder, RuleCode::r16_2});
  if (ps.r17) r.limits.push_back({holder, RuleCode::r17});
  if (ps.r184) r.limits.push_back({ps.r184_holder, RuleCode::r18_4});
  r.rule17_holder = ps.r17_holder;
  r.incident = ps.inc_open;
  r.incident_culprit = ps.inc_culprit;
  r.incident_rule = ps.inc_rule;
  r.incident_tick = ps.inc_tick;
  r.gap = ps.gap;
  // Time to contact on current motion within 10 s.
  // Coarse samples every 0.5 s, then the first contact inside the first interval that ends in contact.
  r.ttc = INFINITY;
  auto touching = [&](std::size_t k) {
    const float lb = v_dist(sa.pred[k].c, sb.pred[k].c) - sa.r_hull - sb.r_hull;
    return lb <= 0.0f && convex_intersect(pred_hull(A, k).pts(), pred_hull(B, k).pts());
  };
  if (touching(0)) {
    r.ttc = 0.0f;
  } else {
    for (std::size_t k = 5; k < 101 && r.ttc == INFINITY; k += 5) {
      if (!touching(k)) continue;
      std::size_t first = k;
      for (std::size_t q = k - 4; q < k; ++q) {
        if (touching(q)) {
          first = q;
          break;
        }
      }
      r.ttc = static_cast<float>(first) * 0.1f;
    }
  }
  ps.ttc = r.ttc;
  pair_rec_.push_back(std::move(r));
}

// ---- Incidents and penalties (§9) ----

void Rules::counted_breach(std::uint32_t n, PairState& ps, std::int32_t culprit, RuleCode rule, bool contact) {
  const std::int32_t other = culprit == ps.i ? ps.j : ps.i;
  if (ps.inc_open) {
    // A contact after a non-contact penalty: only the other boat's own fault gives a second penalty.
    if (contact && ps.inc_penalised_noncontact && culprit != ps.inc_culprit) {
      issue(n, culprit, rule, other);
      ps.inc_penalised_noncontact = false;
    }
    return;
  }
  ps.inc_open = true;
  ps.inc_culprit = culprit;
  ps.inc_rule = rule;
  ps.inc_tick = n;
  ps.inc_contact = contact;
  ps.clear_since = n;
  RulesEvent e;
  e.kind = RulesEventKind::incident;
  e.tick = n;
  e.boat = culprit;
  e.other = other;
  e.rule = rule;
  e.contact = contact;
  emit(e);
  if (!contact && umpire_ == UmpireMode::protest) {
    ps.protest_open = true;
    ps.protest_deadline = n + ticks(p_.protest_prompt);
    ps.protest_fouled = other;
    ps.protest_min_gap = INFINITY;
    RulesEvent q;
    q.kind = RulesEventKind::protestable;
    q.tick = n;
    q.boat = culprit;
    q.other = other;
    q.rule = rule;
    q.deadline = p_.protest_prompt;
    emit(q);
    return;
  }
  issue(n, culprit, rule, other);
  ps.inc_penalised_noncontact = !contact;
}

void Rules::protest(std::int32_t boat, std::uint32_t n) {
  for (auto& [key, ps] : pairs_) {
    (void)key;
    if (!ps.protest_open || ps.protest_fouled != boat) continue;
    ps.protest_open = false;
    RulesEvent e;
    e.kind = RulesEventKind::protested;
    e.tick = n;
    e.boat = ps.inc_culprit;
    e.other = boat;
    e.rule = ps.inc_rule;
    emit(e);
    issue(n, ps.inc_culprit, ps.inc_rule, boat);
    ps.inc_penalised_noncontact = true;
  }
}

void Rules::issue(std::uint32_t n, std::int32_t boat, RuleCode rule, std::int32_t other) {
  BoatState& s = st_[static_cast<std::size_t>(boat)];
  BoatRules& br = rec_[static_cast<std::size_t>(boat)];
  if (br.dsq) return;
  const bool spaced = rule == RuleCode::si_boundary;
  if (!spaced && s.has_last_penalty && n - s.last_penalty_tick < ticks(p_.penalty_spacing)) {
    // 44.1(a): a Part 2 breach in the same incident as a mark touch owes only the Part 2 penalty; it replaces the
    // still pending rule-31 one (§8), which keeps its tick (the incident began with the touch).
    if (part2(rule) && !br.pending.empty() && br.pending.back().rule == RuleCode::r31 &&
        br.pending.back().tick == s.last_penalty_tick) {
      Penalty& q = br.pending.back();
      RulesEvent c;
      c.kind = RulesEventKind::penalty_cancelled;
      c.tick = n;
      c.boat = boat;
      c.rule = q.rule;
      emit(c);
      q.rule = rule;
      q.other = other;
      RulesEvent e;
      e.kind = RulesEventKind::penalty;
      e.tick = n;
      e.boat = boat;
      e.other = other;
      e.rule = rule;
      e.count = 1;
      emit(e);
    }
    return;
  }
  Penalty p;
  p.rule = rule;
  p.other = other;
  p.tick = n;
  p.count = 1;  // every penalty is one turn (§9.2)
  br.pending.push_back(p);
  ++br.received;
  if (!spaced) {
    s.has_last_penalty = true;
    s.last_penalty_tick = n;
  }
  RulesEvent e;
  e.kind = RulesEventKind::penalty;
  e.tick = n;
  e.boat = boat;
  e.other = other;
  e.rule = rule;
  e.count = p.count;
  emit(e);
}

void Rules::contacts(std::uint32_t n, const Race& race, std::span<const ContactEvent> cs) {
  for (const ContactEvent& c : cs) {
    if (!c.begin) continue;
    const std::size_t a = static_cast<std::size_t>(c.boat);
    if (a >= st_.size() || !st_[a].racing) continue;
    if (c.other_kind == ContactKind::boat) {
      const std::size_t b = static_cast<std::size_t>(c.other);
      if (b >= st_.size() || !st_[b].racing) continue;
      const std::int32_t i = static_cast<std::int32_t>(std::min(a, b)), j = static_cast<std::int32_t>(std::max(a, b));
      auto it = pairs_.find(pair_key(i, j));
      if (it == pairs_.end() || !it->second.judged) continue;
      PairState& ps = it->second;
      const std::int32_t giver = ps.giver, holder = giver == i ? j : i;
      // The culprit: a limit breach of the right-of-way boat, else the give-way boat unless exonerated.
      std::int32_t culprit = -1;
      RuleCode rule = ps.kc_rule;
      if (ps.has_decisive && ps.dec_tick == n) {
        culprit = ps.dec_culprit;
        rule = ps.dec_rule;
      }
      if (culprit < 0) {
        bool exonerated = ps.r15_breach || ps.r161 || ps.r162 || ps.r17;
        for (const MarkRoom& mr : ps.rooms) {
          if (mr.entitled == giver && within_mark_room(static_cast<std::size_t>(giver), mr)) exonerated = true;
        }
        if (!exonerated) culprit = giver;
      }
      if (culprit >= 0) {
        counted_breach(n, ps, culprit, rule, true);
        ps.has_contact_pen = true;
        ps.contact_pen_boat = culprit;
        ps.contact_pen_tick = n;
      }
      // §5.1 rule 14 for the right-of-way boat in a damaging contact.
      if (c.closing_speed >= p_.v_damage && culprit != holder && rule_on(RuleCode::r14, race) &&
          ps.has_breach_tick && n - ps.last_breach_tick <= ticks(p_.r14_window) + 1) {
        const BoatState& hs = st_[static_cast<std::size_t>(holder)];
        const std::size_t w = std::min<std::size_t>(hs.psi_hist.size(), ticks(p_.r14_window) + 1);
        bool acted = false;
        if (w >= 2) {
          const float psi0 = hs.psi_hist[hs.psi_hist.size() - w], v0 = hs.v_hist[hs.v_hist.size() - w];
          for (std::size_t k = hs.psi_hist.size() - w; k < hs.psi_hist.size(); ++k) {
            if (std::fabs(wrap_pi(hs.psi_hist[k] - psi0)) >= 10.0f * DEG) acted = true;
            if (hs.v_hist[k] <= 0.9f * v0) acted = true;
          }
        }
        if (!acted) issue(n, holder, RuleCode::r14, giver);
      }
      continue;
    }
    if (c.other_kind != ContactKind::mark && c.other_kind != ContactKind::course_object) continue;
    // §8 rule 31: touching a mark.
    const std::int32_t mark = c.other;
    const RaceBoat& rb = race.boat(a);
    const ResolvedCourse& course = race.course();
    const CourseStep& s0 = course.start();
    const CourseStep& fin = course.finish();
    bool touch = false;
    if (!rb.started && !rb.ocs_scored && (mark == s0.marks[0] || mark == s0.marks[1])) touch = true;
    if ((rb.started || rb.ocs_scored) && !rb.finished) {
      for (const std::int32_t k : {rb.next - 1, rb.next}) {
        if (k < 0) continue;
        const CourseStep& st = course.steps[static_cast<std::size_t>(k)];
        if (st.marks[0] == mark || st.marks[1] == mark) touch = true;
      }
    }
    if (rb.finished && !rb.cleared && (mark == fin.marks[0] || mark == fin.marks[1])) touch = true;
    if (!touch || !rule_on(RuleCode::r31, race)) continue;
    BoatState& s = st_[a];
    const std::size_t mi = static_cast<std::size_t>(mark);
    RulesEvent e;
    e.kind = RulesEventKind::mark_touch;
    e.tick = n;
    e.boat = c.boat;
    e.mark = mark;
    emit(e);
    // 21(b): during or less than 2 s after another boat's breach towards her, that boat's incident instead.
    bool exonerated = false;
    for (auto& [key, ps] : pairs_) {
      (void)key;
      if (ps.i != c.boat && ps.j != c.boat) continue;
      if (ps.has_decisive && ps.dec_culprit != c.boat && n - ps.dec_tick <= 2 * kTicksPerS) {
        counted_breach(n, ps, ps.dec_culprit, ps.dec_rule, false);
        exonerated = true;
        break;
      }
    }
    if (exonerated) continue;
    if (s.touched[mi] && n - s.touch_tick[mi] < ticks(p_.mark_touch_gap)) continue;
    s.touched[mi] = 1;
    s.touch_tick[mi] = n;
    issue(n, c.boat, RuleCode::r31, -1);
  }
}

void Rules::penalties(std::uint32_t n, const Race& race) {
  // Race penalties (match entry).
  for (const RacePenaltyRequest& r : race.penalty_requests()) {
    issue(n, r.boat, r.rule == RacePenaltyRule::c_prep ? RuleCode::c_prep : RuleCode::c_entry, -1);
  }
  // §9.6 match offsetting.
  if (match_ && rec_.size() == 2 && !rec_[0].pending.empty() && !rec_[1].pending.empty()) {
    for (std::size_t i = 0; i < 2; ++i) {
      RulesEvent e;
      e.kind = RulesEventKind::penalty_cancelled;
      e.tick = n;
      e.boat = static_cast<std::int32_t>(i);
      e.rule = rec_[i].pending.front().rule;
      emit(e);
      rec_[i].pending.erase(rec_[i].pending.begin());
    }
  }
  for (std::size_t i = 0; i < st_.size(); ++i) {
    BoatState& s = st_[i];
    BoatRules& br = rec_[i];
    if (br.dsq) {
      br.deadline_s = -1.0f;
      continue;
    }
    // §9.4 deadline: the oldest pending penalty completed within T_serve of its incident, the clock never
    // paused. Match races (§9.6): only with two pending, from the incident that made it two. A penalty that may
    // only be taken after the starting signal (C-prep, C-entry) counts from the signal.
    br.deadline_s = -1.0f;
    bool late = false;
    const std::size_t np = br.pending.size();
    const std::size_t base = match_ ? 1 : 0;
    if (np > base && s.racing) {
      const Penalty& pb = br.pending[base];
      std::int64_t t0 = static_cast<std::int64_t>(pb.tick);
      const RuleCode r0 = br.pending.front().rule;
      if ((r0 == RuleCode::c_prep || r0 == RuleCode::c_entry) && race.n_gun() > t0) t0 = race.n_gun();
      const std::int64_t dl = t0 + static_cast<std::int64_t>(ticks(p_.t_serve));
      late = static_cast<std::int64_t>(n) >= dl;
      br.deadline_s = static_cast<float>(std::max(dl - static_cast<std::int64_t>(n), std::int64_t{0})) * DT;
    }
    // §9.5 disqualification.
    const bool too_many = static_cast<std::int32_t>(br.pending.size()) >= p_.dsq_pending;
    const bool too_often = br.received >= p_.dsq_total;
    if ((late || too_many || too_often) && !s.dsq_done) {
      s.dsq_done = true;
      br.dsq = true;
      const DsqReason why = late ? DsqReason::late : (too_many ? DsqReason::pending : DsqReason::total);
      dsq_.push_back({static_cast<std::int32_t>(i), why});
      if (late) {
        RulesEvent l;
        l.kind = RulesEventKind::penalty_late;
        l.tick = n;
        l.boat = static_cast<std::int32_t>(i);
        l.rule = br.pending.front().rule;
        emit(l);
      }
      RulesEvent e;
      e.kind = RulesEventKind::disqualified;
      e.tick = n;
      e.boat = static_cast<std::int32_t>(i);
      if (late) e.rule = RuleCode::late;
      emit(e);
      br.pending.clear();
      br.deadline_s = -1.0f;
    }
  }
}

// ---- The tick ----

void Rules::update(std::uint32_t n, const Race& race, std::span<const RulesBoatInput> boats,
                   std::span<const ContactEvent> cs) {
  n_ = n;
  sync_boats(race);
  in_.assign(boats.begin(), boats.end());
  pair_rec_.clear();
  dsq_.clear();
  umpire_ = race.settings().umpire;
  const std::size_t nb = std::min(st_.size(), in_.size());
  const bool live = race.settings().rules_level != RulesLevel::none;

  // §9.3 boats keeping clear under 21.2 while taking a penalty, from the pair states of the last tick.
  keep_clear_.assign(nb, 0);
  for (const auto& [key, ps] : pairs_) {
    (void)key;
    if (ps.judged && ps.kc_rule == RuleCode::r21_2 && ps.kc != KcState::clear && ps.giver >= 0 &&
        static_cast<std::size_t>(ps.giver) < nb) {
      keep_clear_[static_cast<std::size_t>(ps.giver)] = 1;
    }
  }

  // 1. per boat
  for (std::size_t i = 0; i < nb; ++i) {
    st_[i].racing = live && race.racing(i) && !rec_[i].dsq;
    boat_step(n, i, race, in_[i]);
    zones(n, i, race);
    if (st_[i].racing) {
      turn_tracker(n, i, race, in_[i]);
      boundary(n, i, race);
    } else {
      rec_[i].turning_for_penalty = false;
    }
  }

  // Boat–boat contacts of the last collision step (any contact, begin or not, puts the pair in Breach).
  std::vector<std::uint64_t> touching;
  for (const ContactEvent& c : cs) {
    if (c.other_kind != ContactKind::boat) continue;
    const std::int32_t i = std::min(c.boat, c.other), j = std::max(c.boat, c.other);
    touching.push_back(pair_key(i, j));
  }

  // 2. pairs in range, relations first (overlaps via a third boat need every direct relation).
  float L_max = 0.0f;
  for (std::size_t i = 0; i < nb; ++i) L_max = max(L_max, st_[i].L);
  std::vector<std::uint64_t> judged;
  for (std::size_t i = 0; i < nb; ++i) {
    for (std::size_t j = i + 1; j < nb; ++j) {
      const std::uint64_t key = pair_key(static_cast<std::int32_t>(i), static_cast<std::int32_t>(j));
      auto it = pairs_.find(key);
      if (!st_[i].racing || !st_[j].racing) {
        if (it != pairs_.end()) pairs_.erase(it);
        continue;
      }
      const float lb = v_dist(st_[i].c, st_[j].c) - st_[i].r_hull - st_[j].r_hull;
      const float gap = lb < p_.r_drop * L_max ? hull_gap(i, j) : lb;
      if (gap > p_.r_drop * L_max) {
        if (it != pairs_.end()) pairs_.erase(it);
        continue;
      }
      if (gap >= p_.r_pair * L_max) {
        if (it != pairs_.end()) {
          it->second.judged = false;
          it->second.inc_open = false;  // out of range closes the incident
        }
        continue;
      }
      PairState& ps = pair_state(static_cast<std::int32_t>(i), static_cast<std::int32_t>(j));
      if (!ps.judged && !ps.has_raw) ps.first_tick = n;
      ps.judged = true;
      ps.gap = gap;
      ps.contact_now = std::find(touching.begin(), touching.end(), key) != touching.end();
      const Relation raw = direct_relation(i, j);
      ps.raw_prev = ps.has_raw ? ps.raw : raw;
      ps.raw = raw;
      judged.push_back(key);
    }
  }
  // overlapped_via (§3.2).
  for (const std::uint64_t key : judged) {
    PairState& ps = pairs_.at(key);
    if (ps.raw == Relation::overlapped) continue;
    const std::size_t a = static_cast<std::size_t>(ps.i), b = static_cast<std::size_t>(ps.j);
    for (std::size_t c = 0; c < nb; ++c) {
      if (c == a || c == b || !st_[c].racing) continue;
      if (v_dot(v_sub(st_[c].c, st_[a].c), v_sub(st_[c].c, st_[b].c)) >= 0.0f) continue;
      auto ac = pairs_.find(pair_key(static_cast<std::int32_t>(std::min(a, c)), static_cast<std::int32_t>(std::max(a, c))));
      auto bc = pairs_.find(pair_key(static_cast<std::int32_t>(std::min(b, c)), static_cast<std::int32_t>(std::max(b, c))));
      if (ac != pairs_.end() && bc != pairs_.end() && ac->second.judged && bc->second.judged &&
          ac->second.raw == Relation::overlapped && bc->second.raw == Relation::overlapped) {
        ps.raw = Relation::overlapped_via;
        break;
      }
    }
  }
  for (const std::uint64_t key : judged) {
    PairState& ps = pairs_.at(key);
    const bool was_ov = overlapped(ps.raw_prev), is_ov = overlapped(ps.raw);
    if (!ps.has_raw || ps.raw != ps.raw_prev) {
      if (ps.has_raw && (was_ov != is_ov || ps.raw != ps.raw_prev)) {
        ps.raw_before = ps.raw_prev;
        ps.raw_change_tick = n;
      }
      ps.has_raw = true;
    }
  }
  for (const std::uint64_t key : judged) judge_pair(n, pairs_.at(key), race, in_);

  // 7. contacts, 8. penalties
  if (live) {
    contacts(n, race, cs);
    penalties(n, race);
  }
}

}  // namespace wm
