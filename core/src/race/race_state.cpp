// The race block of the world snapshot (race.md §13, conventions.md §9.1).
#include "race/race.h"
#include "state/snapshot_util.h"

namespace wm {

using namespace snap;

void Race::save(SnapshotWriter& w) const {
  put_enum(w, race_type_);
  put_enum(w, sequence_);
  put_enum(w, prep_flag_);
  put_enum(w, state_);
  w.put_u32(n_created_);
  put_i64(w, n_gun_);
  put_i64(w, n_warning_);
  w.put_i32(signals_done_);
  w.put_i32(recalls_);
  w.put_bool(x_flag_);
  w.put_bool(rules_live_);
  w.put_bool(any_finished_);
  put_i64(w, n_window_end_);
  put_i64(w, n_time_limit_);
  w.put_f32(L_max_);
  w.put_f32(twd_mean_);
  w.put_f32(legs_twd_);

  put_count(w, legs_.size());
  for (const LegAxis& a : legs_) {
    put_vec2(w, a.e);
    w.put_bool(a.wind_axis);
    w.put_f32(a.length);
  }

  put_count(w, boats_.size());
  for (const RaceBoat& b : boats_) {
    w.put_bool(b.human);
    w.put_u32(b.joined_tick);
    w.put_bool(b.has_prev);
    put_vec2(w, b.c_prev);
    put_vec2(w, b.c);
    w.put_f32(b.psi_prev);
    w.put_f32(b.psi);
    put_vec2s(w, b.hull_prev);
    put_vec2s(w, b.hull);
    for (const bool f : {b.came_near, b.pre_seen, b.ocs, b.ocs_i, b.i_around_end, b.z_flag, b.u_flag, b.black_flag,
                         b.ocs_scored, b.started}) {
      w.put_bool(f);
    }
    w.put_f32(b.t_start);
    w.put_bool(b.entry_crossed);
    w.put_bool(b.entered);
    w.put_i32(b.next);
    w.put_f32(b.phi[0]);
    w.put_f32(b.phi[1]);
    w.put_f32(b.phi_done[0]);
    w.put_f32(b.phi_done[1]);
    w.put_i32(b.n_cross);
    w.put_bool(b.finish_armed);
    w.put_bool(b.rounded_this_tick);
    w.put_i32(b.last_rounded);
    put_f32s(w, b.splits);
    w.put_bool(b.finished);
    put_i64(w, b.t_finish_us);
    w.put_i32(b.place);
    w.put_u32(b.finish_tick);
    w.put_bool(b.cleared);
    w.put_bool(b.ghost);
    put_enum(w, b.ghost_reason);
    w.put_bool(b.retired);
    w.put_bool(b.dsq);
    put_enum(w, b.code);
    w.put_bool(b.projected);
    w.put_f32(b.t_proj);
    w.put_f32(b.D);
    w.put_i32(b.rank);
  }

  put_i32s(w, order_);

  put_count(w, results_.size());
  for (const ResultRow& r : results_) {
    w.put_i32(r.boat);
    w.put_i32(r.place);
    put_enum(w, r.code);
    w.put_f32(r.points);
    put_i64(w, r.t_finish_us);
    w.put_bool(r.projected);
  }

  put_count(w, penalty_requests_.size());
  for (const RacePenaltyRequest& p : penalty_requests_) {
    w.put_i32(p.boat);
    put_enum(w, p.rule);
  }
}

bool Race::load(SnapshotReader& r) {
  // Read into a copy so a failed load leaves this race unchanged.
  Race t = *this;
  t.race_type_ = get_enum(r, RaceType::match);
  t.sequence_ = get_enum(r, SequenceKind::match);
  t.prep_flag_ = get_enum(r, PrepFlag::black);
  t.state_ = get_enum(r, RaceState::abandoned);
  t.n_created_ = r.get_u32();
  t.n_gun_ = get_i64(r);
  t.n_warning_ = get_i64(r);
  t.signals_done_ = r.get_i32();
  t.recalls_ = r.get_i32();
  t.x_flag_ = r.get_bool();
  t.rules_live_ = r.get_bool();
  t.any_finished_ = r.get_bool();
  t.n_window_end_ = get_i64(r);
  t.n_time_limit_ = get_i64(r);
  t.L_max_ = r.get_f32();
  t.twd_mean_ = r.get_f32();
  t.legs_twd_ = r.get_f32();

  const std::uint32_t nl = get_count(r, 13);
  if (nl != course_.steps.size() && nl != 0) r.fail();
  t.legs_.assign(nl, LegAxis{});
  for (LegAxis& a : t.legs_) {
    a.e = get_vec2(r);
    a.wind_axis = r.get_bool();
    a.length = r.get_f32();
  }

  const std::uint32_t nb = get_count(r, 1);
  if (nb != boats_.size()) return false;
  for (RaceBoat& b : t.boats_) {
    b.human = r.get_bool();
    b.joined_tick = r.get_u32();
    b.has_prev = r.get_bool();
    b.c_prev = get_vec2(r);
    b.c = get_vec2(r);
    b.psi_prev = r.get_f32();
    b.psi = r.get_f32();
    get_vec2s(r, b.hull_prev);
    get_vec2s(r, b.hull);
    for (bool* f : {&b.came_near, &b.pre_seen, &b.ocs, &b.ocs_i, &b.i_around_end, &b.z_flag, &b.u_flag,
                    &b.black_flag, &b.ocs_scored, &b.started}) {
      *f = r.get_bool();
    }
    b.t_start = r.get_f32();
    b.entry_crossed = r.get_bool();
    b.entered = r.get_bool();
    b.next = r.get_i32();
    b.phi[0] = r.get_f32();
    b.phi[1] = r.get_f32();
    b.phi_done[0] = r.get_f32();
    b.phi_done[1] = r.get_f32();
    b.n_cross = r.get_i32();
    b.finish_armed = r.get_bool();
    b.rounded_this_tick = r.get_bool();
    b.last_rounded = r.get_i32();
    get_f32s(r, b.splits);
    b.finished = r.get_bool();
    b.t_finish_us = get_i64(r);
    b.place = r.get_i32();
    b.finish_tick = r.get_u32();
    b.cleared = r.get_bool();
    b.ghost = r.get_bool();
    b.ghost_reason = get_enum(r, GhostReason::left);
    b.retired = r.get_bool();
    b.dsq = r.get_bool();
    b.code = get_enum(r, ScoreCode::DSQ);
    b.projected = r.get_bool();
    b.t_proj = r.get_f32();
    b.D = r.get_f32();
    b.rank = r.get_i32();
    if (b.next < 0 || static_cast<std::size_t>(b.next) > course_.steps.size()) r.fail();
    if (!b.hull.empty() && b.hull.size() != b.perf->dynamics.collision.outline.size()) r.fail();
    if (!b.hull_prev.empty() && b.hull_prev.size() != b.perf->dynamics.collision.outline.size()) r.fail();
  }

  get_i32s(r, t.order_);
  for (const std::int32_t i : t.order_) {
    if (i < 0 || static_cast<std::uint32_t>(i) >= nb) r.fail();
  }

  const std::uint32_t nr = get_count(r, 22);
  t.results_.assign(nr, ResultRow{});
  for (ResultRow& x : t.results_) {
    x.boat = r.get_i32();
    x.place = r.get_i32();
    x.code = get_enum(r, ScoreCode::DSQ);
    x.points = r.get_f32();
    x.t_finish_us = get_i64(r);
    x.projected = r.get_bool();
  }

  const std::uint32_t np = get_count(r, 5);
  t.penalty_requests_.clear();
  for (std::uint32_t k = 0; k < np && !r.failed(); ++k) {
    RacePenaltyRequest p{};
    p.boat = r.get_i32();
    p.rule = get_enum(r, RacePenaltyRule::c_entry);
    if (p.boat < 0 || static_cast<std::uint32_t>(p.boat) >= nb) r.fail();
    t.penalty_requests_.push_back(p);
  }

  if (r.failed()) return false;
  t.events_.clear();
  t.finished_this_tick_.clear();
  *this = std::move(t);
  return true;
}

}  // namespace wm
