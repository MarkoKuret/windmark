// The rules block of the world snapshot (rules.md §14, conventions.md §9.1).
#include "rules/rules.h"
#include "state/snapshot_util.h"

namespace wm {

using namespace snap;

namespace {

bool boat_ok(std::int32_t b, std::size_t n, bool allow_none = true) {
  return (allow_none && b == -1) || (b >= 0 && static_cast<std::size_t>(b) < n);
}

}  // namespace

void Rules::save(SnapshotWriter& w) const {
  w.put_u32(n_);
  put_enum(w, umpire_);

  put_count(w, st_.size());
  for (const BoatState& s : st_) {
    w.put_bool(s.racing);
    put_vec2s(w, s.hull);
    put_vec2(w, s.c);
    put_vec2(w, s.bow);
    put_vec2(w, s.stern);
    w.put_f32(s.twa);
    w.put_f32(s.theta_ch);
    w.put_f32(s.theta_dn);
    w.put_f32(s.vmg_tws);
    w.put_bool(s.tack_init);
    w.put_i8(s.tack);
    w.put_bool(s.flipped);
    w.put_bool(s.head_to_wind);
    w.put_bool(s.has_tack_change);
    w.put_u32(s.tack_change_tick);
    w.put_bool(s.tacking);
    w.put_i8(s.tacking_to);
    w.put_bool(s.has_tacking_end);
    w.put_u32(s.tacking_end_tick);
    w.put_f32(s.twa_prev);
    w.put_f32(s.psi_prev);
    w.put_bool(s.has_prev);
    w.put_i32(s.cc_run);
    w.put_i8(s.cc_run_dir);
    w.put_bool(s.cc_active);
    w.put_bool(s.cc_started_now);
    w.put_i8(s.cc_dir);
    w.put_u32(s.cc_back);
    w.put_i32(s.cc_calm);
    put_f32s(w, s.psi_hist);
    put_f32s(w, s.v_hist);
    w.put_f32(s.above_time);
    w.put_bool(s.above);
    w.put_i8(s.t_dir);
    w.put_i32(s.t_run);
    w.put_i32(s.t_pause);
    w.put_i32(s.t_tacks);
    w.put_i32(s.t_gybes);
    w.put_bool(s.t_started);
    w.put_f32(s.t_theta);
    w.put_f32(s.t_extreme);
    w.put_bool(s.has_last_penalty);
    w.put_u32(s.last_penalty_tick);
    w.put_bool(s.dsq_done);
    put_u8s(w, s.in_zone);
    put_u8s(w, s.stbd_since_zone);
    put_u32s(w, s.zone_enter);
    put_f32s(w, s.dmin);
    w.put_i32(s.r183_mark);
    put_u32s(w, s.touch_tick);
    put_u8s(w, s.touched);
    w.put_i32(s.out_ticks);
    w.put_bool(s.returning_prev);
    w.put_bool(s.pen_turn_prev);
    w.put_bool(s.has_status_end);
    w.put_u32(s.status_end_tick);
    w.put_i32(s.gate_step);
    w.put_i8(s.gate_buoy);
  }

  put_count(w, rec_.size());
  for (const BoatRules& b : rec_) {
    w.put_i8(b.tack);
    w.put_bool(b.tacking);
    w.put_bool(b.turning_for_penalty);
    w.put_f32(b.turn_progress);
    w.put_i32(b.turn_tacks);
    w.put_i32(b.turn_gybes);
    w.put_bool(b.turn_in_zone);
    put_enum(w, b.turn_reset);
    w.put_u32(b.turn_reset_tick);
    put_count(w, b.pending.size());
    for (const Penalty& p : b.pending) {
      put_enum(w, p.rule);
      w.put_i32(p.other);
      w.put_u32(p.tick);
      w.put_i32(p.count);
    }
    w.put_i32(b.served);
    w.put_i32(b.received);
    w.put_f32(b.deadline_s);
    w.put_bool(b.returning_to_start);
    w.put_bool(b.dsq);
    w.put_bool(b.out_of_bounds);
  }

  put_count(w, pairs_.size());
  for (const auto& [key, ps] : pairs_) {
    (void)key;
    w.put_i32(ps.i);
    w.put_i32(ps.j);
    w.put_bool(ps.judged);
    w.put_u32(ps.first_tick);
    put_enum(w, ps.raw);
    put_enum(w, ps.raw_prev);
    put_enum(w, ps.raw_before);
    w.put_bool(ps.has_raw);
    w.put_u32(ps.raw_change_tick);
    put_enum(w, ps.rel);
    w.put_i32(ps.giver);
    put_enum(w, ps.kc_rule);
    w.put_u32(ps.onset_tick);
    w.put_bool(ps.r15_pending);
    w.put_bool(ps.r15_breach);
    w.put_u32(ps.r15_start);
    put_enum(w, ps.kc);
    put_enum(w, ps.kc_prev);
    for (const std::uint8_t h : ps.kc_hist) w.put_u8(h);
    w.put_bool(ps.has_breach_tick);
    w.put_u32(ps.last_breach_tick);
    w.put_bool(ps.w161);
    w.put_bool(ps.w162);
    w.put_bool(ps.r161);
    w.put_bool(ps.r162);
    w.put_u32(ps.w161_start);
    w.put_u32(ps.w162_start);
    w.put_i32(ps.w16_holder);
    w.put_i32(ps.r17_holder);
    w.put_bool(ps.r17);
    put_count(w, ps.rooms.size());
    for (const MarkRoom& m : ps.rooms) {
      w.put_i32(m.mark);
      w.put_i32(m.entitled);
      w.put_i32(m.giver);
      put_enum(w, m.rule);
      w.put_bool(m.frozen);
      put_vec2s(w, m.corridor);
      w.put_bool(m.could_act);
      put_enum(w, m.state);
      w.put_bool(m.breach);
    }
    put_i32s(w, ps.used_marks);
    w.put_bool(ps.r183);
    w.put_bool(ps.r184);
    w.put_i32(ps.r183_holder);
    w.put_i32(ps.r184_holder);
    w.put_bool(ps.r19_on);
    w.put_bool(ps.r19_could_act);
    w.put_bool(ps.r19_breach);
    w.put_i32(ps.r19_entitled);
    w.put_i32(ps.r19_giver);
    w.put_i32(ps.r19_obst);
    put_enum(w, ps.r19_state);
    put_vec2s(w, ps.r19_corridor);
    w.put_i32(ps.br_culprit);
    put_enum(w, ps.br_rule);
    w.put_u32(ps.br_since);
    w.put_bool(ps.has_decisive);
    w.put_i32(ps.dec_culprit);
    put_enum(w, ps.dec_rule);
    w.put_u32(ps.dec_tick);
    w.put_bool(ps.inc_open);
    w.put_bool(ps.inc_contact);
    w.put_bool(ps.inc_penalised_noncontact);
    w.put_i32(ps.inc_culprit);
    put_enum(w, ps.inc_rule);
    w.put_u32(ps.inc_tick);
    w.put_u32(ps.clear_since);
    w.put_bool(ps.protest_open);
    w.put_u32(ps.protest_deadline);
    w.put_i32(ps.protest_fouled);
    w.put_f32(ps.protest_min_gap);
    w.put_bool(ps.contact_now);
    w.put_bool(ps.has_contact_pen);
    w.put_i32(ps.contact_pen_boat);
    w.put_u32(ps.contact_pen_tick);
    w.put_f32(ps.gap);
    w.put_f32(ps.ttc);
  }

  put_count(w, pair_rec_.size());
  for (const PairRecord& p : pair_rec_) {
    w.put_i32(p.i);
    w.put_i32(p.j);
    put_enum(w, p.relation);
    w.put_i32(p.kc_giver);
    w.put_i32(p.kc_holder);
    put_enum(w, p.kc_rule);
    put_enum(w, p.kc_state);
    w.put_i32(p.room_entitled);
    w.put_i32(p.room_giver);
    put_enum(w, p.room_rule);
    w.put_i32(p.room_mark);
    put_enum(w, p.room_state);
    put_count(w, p.limits.size());
    for (const auto& [holder, rule] : p.limits) {
      w.put_i32(holder);
      put_enum(w, rule);
    }
    w.put_i32(p.rule17_holder);
    w.put_bool(p.incident);
    w.put_i32(p.incident_culprit);
    put_enum(w, p.incident_rule);
    w.put_u32(p.incident_tick);
    w.put_f32(p.gap);
    w.put_f32(p.ttc);
  }

  put_count(w, dsq_.size());
  for (const auto& [boat, why] : dsq_) {
    w.put_i32(boat);
    put_enum(w, why);
  }
}

bool Rules::load(SnapshotReader& r) {
  constexpr RuleCode kLastRule = RuleCode::si_boundary;
  const std::size_t nm = course_ != nullptr ? course_->marks.size() : 0;
  const std::size_t nb = st_.size();

  std::uint32_t n = r.get_u32();
  const UmpireMode umpire = get_enum(r, UmpireMode::protest);

  if (get_count(r, 1) != nb) return false;
  std::vector<BoatState> st = st_;
  for (BoatState& s : st) {
    s.racing = r.get_bool();
    get_vec2s(r, s.hull);
    s.c = get_vec2(r);
    s.bow = get_vec2(r);
    s.stern = get_vec2(r);
    s.twa = r.get_f32();
    s.theta_ch = r.get_f32();
    s.theta_dn = r.get_f32();
    s.vmg_tws = r.get_f32();
    s.tack_init = r.get_bool();
    s.tack = r.get_i8();
    s.flipped = r.get_bool();
    s.head_to_wind = r.get_bool();
    s.has_tack_change = r.get_bool();
    s.tack_change_tick = r.get_u32();
    s.tacking = r.get_bool();
    s.tacking_to = r.get_i8();
    s.has_tacking_end = r.get_bool();
    s.tacking_end_tick = r.get_u32();
    s.twa_prev = r.get_f32();
    s.psi_prev = r.get_f32();
    s.has_prev = r.get_bool();
    s.cc_run = r.get_i32();
    s.cc_run_dir = r.get_i8();
    s.cc_active = r.get_bool();
    s.cc_started_now = r.get_bool();
    s.cc_dir = r.get_i8();
    s.cc_back = r.get_u32();
    s.cc_calm = r.get_i32();
    get_f32s(r, s.psi_hist);
    get_f32s(r, s.v_hist);
    s.above_time = r.get_f32();
    s.above = r.get_bool();
    s.t_dir = r.get_i8();
    s.t_run = r.get_i32();
    s.t_pause = r.get_i32();
    s.t_tacks = r.get_i32();
    s.t_gybes = r.get_i32();
    s.t_started = r.get_bool();
    s.t_theta = r.get_f32();
    s.t_extreme = r.get_f32();
    s.has_last_penalty = r.get_bool();
    s.last_penalty_tick = r.get_u32();
    s.dsq_done = r.get_bool();
    get_u8s(r, s.in_zone);
    get_u8s(r, s.stbd_since_zone);
    get_u32s(r, s.zone_enter);
    get_f32s(r, s.dmin);
    s.r183_mark = r.get_i32();
    get_u32s(r, s.touch_tick);
    get_u8s(r, s.touched);
    s.out_ticks = r.get_i32();
    s.returning_prev = r.get_bool();
    s.pen_turn_prev = r.get_bool();
    s.has_status_end = r.get_bool();
    s.status_end_tick = r.get_u32();
    s.gate_step = r.get_i32();
    s.gate_buoy = r.get_i8();
    if (s.in_zone.size() != nm || s.stbd_since_zone.size() != nm || s.zone_enter.size() != nm ||
        s.dmin.size() != nm || s.touch_tick.size() != nm || s.touched.size() != nm) {
      r.fail();
    }
    if (!s.hull.empty() && s.hull.size() != s.perf->dynamics.collision.outline.size()) r.fail();
    // Caches of the tick: rebuilt by predict() before they are read.
    s.pred.clear();
    s.pred_hulls.clear();
    s.pred_placed.clear();
    for (int k = 0; k < 4; ++k) {
      s.man[k].clear();
      s.man_valid[k] = false;
    }
  }

  if (get_count(r, 1) != nb) return false;
  std::vector<BoatRules> rec(nb);
  for (BoatRules& b : rec) {
    b.tack = r.get_i8();
    b.tacking = r.get_bool();
    b.turning_for_penalty = r.get_bool();
    b.turn_progress = r.get_f32();
    b.turn_tacks = r.get_i32();
    b.turn_gybes = r.get_i32();
    b.turn_in_zone = r.get_bool();
    b.turn_reset = get_enum(r, TurnReset::rounded);
    b.turn_reset_tick = r.get_u32();
    const std::uint32_t np = get_count(r, 13);
    for (std::uint32_t k = 0; k < np && !r.failed(); ++k) {
      Penalty p;
      p.rule = get_enum(r, kLastRule);
      p.other = r.get_i32();
      p.tick = r.get_u32();
      p.count = r.get_i32();
      if (!boat_ok(p.other, nb)) r.fail();
      b.pending.push_back(p);
    }
    b.served = r.get_i32();
    b.received = r.get_i32();
    b.deadline_s = r.get_f32();
    b.returning_to_start = r.get_bool();
    b.dsq = r.get_bool();
    b.out_of_bounds = r.get_bool();
  }

  std::map<std::uint64_t, PairState> pairs;
  const std::uint32_t npairs = get_count(r, 100);
  std::uint64_t last_key = 0;
  for (std::uint32_t k = 0; k < npairs && !r.failed(); ++k) {
    PairState ps;
    ps.i = r.get_i32();
    ps.j = r.get_i32();
    ps.judged = r.get_bool();
    ps.first_tick = r.get_u32();
    ps.raw = get_enum(r, Relation::overlapped_via);
    ps.raw_prev = get_enum(r, Relation::overlapped_via);
    ps.raw_before = get_enum(r, Relation::overlapped_via);
    ps.has_raw = r.get_bool();
    ps.raw_change_tick = r.get_u32();
    ps.rel = get_enum(r, Relation::overlapped_via);
    ps.giver = r.get_i32();
    ps.kc_rule = get_enum(r, kLastRule);
    ps.onset_tick = r.get_u32();
    ps.r15_pending = r.get_bool();
    ps.r15_breach = r.get_bool();
    ps.r15_start = r.get_u32();
    ps.kc = get_enum(r, KcState::breach);
    ps.kc_prev = get_enum(r, KcState::breach);
    for (std::uint8_t& h : ps.kc_hist) h = r.get_u8();
    ps.has_breach_tick = r.get_bool();
    ps.last_breach_tick = r.get_u32();
    ps.w161 = r.get_bool();
    ps.w162 = r.get_bool();
    ps.r161 = r.get_bool();
    ps.r162 = r.get_bool();
    ps.w161_start = r.get_u32();
    ps.w162_start = r.get_u32();
    ps.w16_holder = r.get_i32();
    ps.r17_holder = r.get_i32();
    ps.r17 = r.get_bool();
    const std::uint32_t nrooms = get_count(r, 20);
    for (std::uint32_t m = 0; m < nrooms && !r.failed(); ++m) {
      MarkRoom mr;
      mr.mark = r.get_i32();
      mr.entitled = r.get_i32();
      mr.giver = r.get_i32();
      mr.rule = get_enum(r, kLastRule);
      mr.frozen = r.get_bool();
      get_vec2s(r, mr.corridor);
      mr.could_act = r.get_bool();
      mr.state = get_enum(r, KcState::breach);
      mr.breach = r.get_bool();
      ps.rooms.push_back(std::move(mr));
    }
    get_i32s(r, ps.used_marks);
    ps.r183 = r.get_bool();
    ps.r184 = r.get_bool();
    ps.r183_holder = r.get_i32();
    ps.r184_holder = r.get_i32();
    ps.r19_on = r.get_bool();
    ps.r19_could_act = r.get_bool();
    ps.r19_breach = r.get_bool();
    ps.r19_entitled = r.get_i32();
    ps.r19_giver = r.get_i32();
    ps.r19_obst = r.get_i32();
    ps.r19_state = get_enum(r, KcState::breach);
    get_vec2s(r, ps.r19_corridor);
    ps.br_culprit = r.get_i32();
    ps.br_rule = get_enum(r, kLastRule);
    ps.br_since = r.get_u32();
    ps.has_decisive = r.get_bool();
    ps.dec_culprit = r.get_i32();
    ps.dec_rule = get_enum(r, kLastRule);
    ps.dec_tick = r.get_u32();
    ps.inc_open = r.get_bool();
    ps.inc_contact = r.get_bool();
    ps.inc_penalised_noncontact = r.get_bool();
    ps.inc_culprit = r.get_i32();
    ps.inc_rule = get_enum(r, kLastRule);
    ps.inc_tick = r.get_u32();
    ps.clear_since = r.get_u32();
    ps.protest_open = r.get_bool();
    ps.protest_deadline = r.get_u32();
    ps.protest_fouled = r.get_i32();
    ps.protest_min_gap = r.get_f32();
    ps.contact_now = r.get_bool();
    ps.has_contact_pen = r.get_bool();
    ps.contact_pen_boat = r.get_i32();
    ps.contact_pen_tick = r.get_u32();
    ps.gap = r.get_f32();
    ps.ttc = r.get_f32();
    if (!boat_ok(ps.i, nb, false) || !boat_ok(ps.j, nb, false) || !(ps.i < ps.j)) {
      r.fail();
      break;
    }
    const std::uint64_t key = static_cast<std::uint64_t>(ps.i) << 32 | static_cast<std::uint32_t>(ps.j);
    if (k > 0 && !(last_key < key)) r.fail();
    last_key = key;
    pairs.emplace(key, std::move(ps));
  }

  std::vector<PairRecord> recs;
  const std::uint32_t nrec = get_count(r, 60);
  for (std::uint32_t k = 0; k < nrec && !r.failed(); ++k) {
    PairRecord p;
    p.i = r.get_i32();
    p.j = r.get_i32();
    p.relation = get_enum(r, Relation::overlapped_via);
    p.kc_giver = r.get_i32();
    p.kc_holder = r.get_i32();
    p.kc_rule = get_enum(r, kLastRule);
    p.kc_state = get_enum(r, KcState::breach);
    p.room_entitled = r.get_i32();
    p.room_giver = r.get_i32();
    p.room_rule = get_enum(r, kLastRule);
    p.room_mark = r.get_i32();
    p.room_state = get_enum(r, KcState::breach);
    const std::uint32_t nl = get_count(r, 5);
    for (std::uint32_t m = 0; m < nl && !r.failed(); ++m) {
      const std::int32_t holder = r.get_i32();
      p.limits.emplace_back(holder, get_enum(r, kLastRule));
    }
    p.rule17_holder = r.get_i32();
    p.incident = r.get_bool();
    p.incident_culprit = r.get_i32();
    p.incident_rule = get_enum(r, kLastRule);
    p.incident_tick = r.get_u32();
    p.gap = r.get_f32();
    p.ttc = r.get_f32();
    if (!boat_ok(p.i, nb, false) || !boat_ok(p.j, nb, false)) r.fail();
    recs.push_back(std::move(p));
  }

  std::vector<std::pair<std::int32_t, DsqReason>> dsq;
  const std::uint32_t nd = get_count(r, 5);
  for (std::uint32_t k = 0; k < nd && !r.failed(); ++k) {
    const std::int32_t boat = r.get_i32();
    const DsqReason why = get_enum(r, DsqReason::late);
    if (!boat_ok(boat, nb, false)) r.fail();
    dsq.emplace_back(boat, why);
  }

  if (r.failed()) return false;
  n_ = n;
  umpire_ = umpire;
  st_ = std::move(st);
  rec_ = std::move(rec);
  pairs_ = std::move(pairs);
  pair_rec_ = std::move(recs);
  dsq_ = std::move(dsq);
  events_.clear();
  in_.clear();
  return true;
}

}  // namespace wm
