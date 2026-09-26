#include "sails/sails.h"

#include <cmath>

#include "math/wm_math.h"

namespace wm {

namespace {

constexpr float kGybeTarget = 4.71238898f;  // 3 pi / 2: an asymmetric kite is driven round the bow (§5.4)
constexpr float kFiveDeg = 0.0872664626f;
constexpr float kOneDeg = 0.0174532924f;

bool is_timed(SailPhase p) {
  return p == SailPhase::prepare_hoist || p == SailPhase::hoisting || p == SailPhase::prepare_drop ||
         p == SailPhase::dropping;
}

}  // namespace

void Sails::init(const PerfData* perf) {
  perf_ = perf;
  const std::size_t n = perf->sails.size();
  sails_.assign(n, SailState{});
  out_.assign(n, SailOutput{});
  m_s_.assign(n, 0.0f);
  events_.clear();
  events_.reserve(4 * kQueueMax);
  reset(-1);
}

void Sails::reset(std::int32_t front_sail) {
  for (SailState& s : sails_) s = SailState{};
  sails_[static_cast<std::size_t>(perf_->main_sail)].phase = SailPhase::up;
  front_ = -1;
  if (front_sail >= 0 && front_sail != perf_->main_sail && front_sail < static_cast<std::int32_t>(sails_.size())) {
    sails_[static_cast<std::size_t>(front_sail)].phase = SailPhase::up;
    front_ = static_cast<std::int8_t>(front_sail);
  }
  queue_ = {};
  queue_len_ = 0;
  queue_pos_ = 0;
  queue_progress_ = 0.0f;
  events_.clear();
}

void Sails::set_queue(std::initializer_list<SailStep> steps) {
  queue_ = {};
  std::uint8_t n = 0;
  for (const SailStep& s : steps) queue_[n++] = s;
  queue_len_ = n;
  queue_pos_ = 0;
  queue_progress_ = 0.0f;
}

// §4.2
SailRequest Sails::hoist(std::int32_t x) {
  if (x < 0 || x >= static_cast<std::int32_t>(sails_.size()) || x == perf_->main_sail) return SailRequest::rejected;
  const std::int8_t xs = static_cast<std::int8_t>(x);
  const std::int8_t f = front_;
  if (!busy()) {
    if (xs == f) return SailRequest::rejected;
    if (f >= 0) {
      set_queue({{xs, SailPhase::prepare_hoist, 0}, {xs, SailPhase::hoisting, 0}, {xs, SailPhase::up, 0},
                 {f, SailPhase::prepare_drop, 0}, {f, SailPhase::dropping, 0}, {f, SailPhase::down, 0}});
    } else {
      set_queue({{xs, SailPhase::prepare_hoist, 0}, {xs, SailPhase::hoisting, 0}, {xs, SailPhase::up, 0}});
    }
    return SailRequest::accepted;
  }
  const SailStep run = queue_[queue_pos_];
  const float p = sails_[static_cast<std::size_t>(run.sail)].progress;
  // Cancel a hoist: asking again for the sail still up while the new sail is on its way up.
  if (xs == f && run.sail != f && run.reversed == 0) {
    if (run.phase == SailPhase::prepare_hoist) {
      set_queue({{run.sail, SailPhase::down, 0}});
      return SailRequest::accepted;
    }
    if (run.phase == SailPhase::hoisting) {
      set_queue({{run.sail, SailPhase::hoisting, 1}, {run.sail, SailPhase::down, 0}});
      queue_progress_ = 1.0f - p;
      return SailRequest::accepted;
    }
  }
  // Cancel a drop: asking for the sail of a lone drop (started by drop_front()).
  const bool lone_drop = queue_len_ == 3 && queue_[0].sail == xs && queue_[0].phase == SailPhase::prepare_drop &&
                         queue_[1].sail == xs && queue_[1].phase == SailPhase::dropping && queue_[2].sail == xs &&
                         queue_[2].phase == SailPhase::down;
  if (lone_drop && run.sail == xs && run.reversed == 0) {
    if (run.phase == SailPhase::prepare_drop) {
      set_queue({{xs, SailPhase::up, 0}});
      return SailRequest::accepted;
    }
    if (run.phase == SailPhase::dropping) {
      set_queue({{xs, SailPhase::dropping, 1}, {xs, SailPhase::up, 0}});
      queue_progress_ = 1.0f - p;
      return SailRequest::accepted;
    }
  }
  return SailRequest::rejected;
}

SailRequest Sails::drop_front() {
  if (busy()) {
    // Cancel a first hoist: with no front sail up there is no hoist(F) to ask for, so drop_front() cancels a
    // lone hoist the way hoist(F) cancels a peel (§4.2).
    const SailStep run = queue_[queue_pos_];
    const bool lone_hoist = front_ < 0 && queue_len_ == 3 && queue_[0].phase == SailPhase::prepare_hoist &&
                            queue_[1].phase == SailPhase::hoisting && queue_[2].phase == SailPhase::up &&
                            queue_[0].sail == run.sail && queue_[1].sail == run.sail && queue_[2].sail == run.sail;
    if (lone_hoist && run.reversed == 0) {
      if (run.phase == SailPhase::prepare_hoist) {
        set_queue({{run.sail, SailPhase::down, 0}});
        return SailRequest::accepted;
      }
      if (run.phase == SailPhase::hoisting) {
        const float p = sails_[static_cast<std::size_t>(run.sail)].progress;
        set_queue({{run.sail, SailPhase::hoisting, 1}, {run.sail, SailPhase::down, 0}});
        queue_progress_ = 1.0f - p;
        return SailRequest::accepted;
      }
    }
    return SailRequest::rejected;
  }
  if (front_ < 0) return SailRequest::rejected;
  const std::int8_t f = front_;
  set_queue({{f, SailPhase::prepare_drop, 0}, {f, SailPhase::dropping, 0}, {f, SailPhase::down, 0}});
  return SailRequest::accepted;
}

// §4.4: reversed steps use the duration of their own phase.
float Sails::duration(std::int32_t sail, SailPhase phase, float tws, float twa_abs) const {
  const SailPerf& sp = perf_->sails[static_cast<std::size_t>(sail)];
  if (!sp.has_handling) return 0.0f;
  const SailHandling& h = sp.handling;
  switch (phase) {
    case SailPhase::prepare_hoist: return h.prepare_hoist_time.at(tws, twa_abs);
    case SailPhase::hoisting: return h.hoist_time.at(tws, twa_abs);
    case SailPhase::prepare_drop: return h.prepare_drop_time.at(tws, twa_abs);
    case SailPhase::dropping: return h.drop_time.at(tws, twa_abs);
    default: return 0.0f;
  }
}

// §4.3. The time left over when a step finishes is carried into the next step as seconds (`dt_left`), so the
// change takes the sum of its durations; for a step that runs the whole tick this is the spec's
// `queue_progress + DT/d`.
void Sails::advance(float tws, float twa_abs) {
  events_.clear();
  float dt_left = DT;
  while (queue_pos_ < queue_len_) {
    const SailStep st = queue_[queue_pos_];
    SailState& s = sails_[static_cast<std::size_t>(st.sail)];
    if (s.phase != st.phase) events_.push_back({st.sail, st.phase});
    s.phase = st.phase;
    if (st.phase == SailPhase::up) {
      front_ = st.sail;
      s.progress = 0.0f;
    } else if (st.phase == SailPhase::down) {
      if (front_ == st.sail) front_ = -1;
      s.progress = 0.0f;
    } else {
      const float d = duration(st.sail, st.phase, tws, twa_abs);
      queue_progress_ = d > 1e-5f ? queue_progress_ + dt_left / d : 1.0f;
      const float q = clamp(queue_progress_, 0.0f, 1.0f);
      s.progress = st.reversed ? 1.0f - q : q;
      if (queue_progress_ < 1.0f) break;
      dt_left = d > 1e-5f ? (queue_progress_ - 1.0f) * d : dt_left;
    }
    queue_pos_ = static_cast<std::uint8_t>(queue_pos_ + 1);
    queue_progress_ = 0.0f;
  }
  if (queue_pos_ >= queue_len_) {
    queue_len_ = 0;
    queue_pos_ = 0;
    queue_progress_ = 0.0f;
  }
}

// §4.5
float Sails::man_coef(float twa) const {
  if (!busy()) return 1.0f;
  const SailStep st = queue_[queue_pos_];
  if (!is_timed(st.phase)) return 1.0f;
  const SailPerf& sp = perf_->sails[static_cast<std::size_t>(st.sail)];
  if (!sp.has_handling) return 1.0f;
  float s = 1.0f;
  switch (st.phase) {
    case SailPhase::prepare_hoist: s = sp.handling.slow_prepare_hoist; break;
    case SailPhase::hoisting: s = sp.handling.slow_hoist; break;
    case SailPhase::prepare_drop: s = sp.handling.slow_prepare_drop; break;
    case SailPhase::dropping: s = sp.handling.slow_drop; break;
    default: break;
  }
  return s + (1.0f - s) * std::fabs(wm_sin(0.5f * twa));
}

// §5.1: the main trims in the current config, a front sail in the config it drives.
float Sails::optimal(std::size_t i, float tws, float awa_abs) const {
  const SailPerf& sp = perf_->sails[i];
  float m;
  if (static_cast<std::int32_t>(i) == perf_->main_sail) {
    m = config().optimal_main.at(tws, awa_abs);
  } else {
    const ConfigPerf* c = perf_->config_for(static_cast<std::int32_t>(i));
    m = (c != nullptr && !c->optimal_front.empty()) ? c->optimal_front.at(tws, awa_abs) : sp.sheet_min;
  }
  return clamp(m, sp.sheet_min, sp.sheet_max);
}

// §5.4
float Sails::hoist_factor(std::size_t i) const {
  if (perf_->sails[i].type == SailType::spinnaker_sym) return 1.0f;
  const SailState& s = sails_[i];
  switch (s.phase) {
    case SailPhase::hoisting: return clamp((2.0f * s.progress) * s.progress, 0.1f, 1.0f);
    case SailPhase::up:
    case SailPhase::prepare_drop: return 1.0f;
    default: return 0.1f;
  }
}

void Sails::trim(const TrimInput& in, bool place) {
  const std::size_t n = sails_.size();
  const float aa = std::fabs(in.awa);
  const float side = -sgn(in.awa);
  const std::size_t main = static_cast<std::size_t>(perf_->main_sail);

  // §5.1, §5.2, §5.3: optimum and sheet target of every sail. Front sails first: the main's manual target
  // follows the front sail's.
  for (std::size_t i = 0; i < n; ++i) {
    out_[i].m_opt = optimal(i, in.tws, aa);
    out_[i].beta_opt = side * out_[i].m_opt;
  }
  for (std::size_t i = 0; i < n; ++i) {
    if (i == main) continue;
    const SailPerf& sp = perf_->sails[i];
    m_s_[i] = in.auto_trim ? out_[i].m_opt : sp.sheet_min + in.sheet_cmd * (sp.sheet_max - sp.sheet_min);
  }
  {
    const SailPerf& sp = perf_->sails[main];
    if (in.auto_trim) {
      m_s_[main] = out_[main].m_opt;
    } else if (front_ < 0) {
      m_s_[main] = sp.sheet_min + in.sheet_cmd * (sp.sheet_max - sp.sheet_min);
    } else {
      const std::size_t f = static_cast<std::size_t>(front_);
      m_s_[main] = clamp((m_s_[f] - out_[f].m_opt) + out_[main].m_opt, 0.0f, sp.sheet_max);
    }
  }
  // §5.3: let fly runs every sheet out to fully eased at once; §5.4 still holds the sail at the heel limit and on
  // the wind line, never beyond.
  if (in.let_fly) {
    for (std::size_t i = 0; i < n; ++i) m_s_[i] = perf_->sails[i].sheet_max;
  }

  for (std::size_t i = 0; i < n; ++i) {
    const SailPerf& sp = perf_->sails[i];
    SailState& s = sails_[i];
    SailOutput& o = out_[i];

    // §5.4 target angle
    const float lim =
        sp.sheet_max_by_heel.present ? min(sp.sheet_max, sp.sheet_max_by_heel.table.at(std::fabs(in.phi)))
                                     : sp.sheet_max;
    const float m = clamp(m_s_[i], sp.sheet_min, lim);
    const float k_h = hoist_factor(i);
    o.k_h = k_h;
    float beta_t = (side * m) * k_h;
    bool gybe_target = false;
    if (!place && sp.type == SailType::spinnaker_asym && s.beta * beta_t < -1e-5f) {
      beta_t = (s.beta >= 0.0f ? 1.0f : -1.0f) * kGybeTarget;
      gybe_target = true;
    } else if (aa < std::fabs(beta_t)) {
      beta_t = sgn(beta_t) * aa;
    }

    o.beta_t = beta_t;

    // §5.5 sail motion
    o.motion = SailMotion::idle;
    const float dbeta = beta_t - s.beta;
    if (place || std::fabs(dbeta) <= 1e-5f || sp.type == SailType::spinnaker_sym) {
      s.beta = beta_t;
    } else {
      float rate;
      if (((-in.awa) - s.beta) * dbeta <= 0.0f) {
        rate = sp.rate_in;
        o.motion = SailMotion::sheeting;
      } else {
        rate = sp.rate_out;
        o.motion = SailMotion::easing;
      }
      const float step = ((std::fabs(dbeta) + kFiveDeg) * DT) * rate;
      if (std::fabs(dbeta) < kOneDeg) o.motion = SailMotion::idle;
      s.beta = wrap_pi(s.beta + sgn(dbeta) * min(step, std::fabs(dbeta)));
    }
    if (sp.pole_angle.present) {
      const float pole_t = side * sp.pole_angle.table.at(in.tws, aa);
      if (place) {
        s.pole = pole_t * k_h;
      } else {
        s.pole = s.pole + ((pole_t * k_h) - s.pole) * (DT * sp.pole_rate);
      }
    } else {
      s.pole = s.beta;
    }

    // §5.6 trim error, §7 outputs
    // With let fly held the error is the target's: the drive of the fully eased sails applies at once while the
    // drawn sail swings out at its easing rate.
    const float b = (in.let_fly && !gybe_target) ? beta_t : s.beta;
    o.trim_error = side * wrap_pi(b - o.beta_opt);
    const float d = s.beta + in.awa;
    if (!sp.shiver_free && std::fabs(d) >= HALF_PI) {
      o.luff_shiver = 0.0f;
    } else {
      const float q = clamp(std::fabs(wm_sin(d)) / (wm_sin(sp.shiver_angle.at(in.tws)) + 1e-4f), 0.0f, 1.0f);
      o.luff_shiver = 1.0f - q * q;
    }
    o.backed = sgn(s.beta) == sgn(in.awa) && std::fabs(s.beta) > 0.02f;
  }
}

bool Sails::spinnaker_flying() const {
  if (front_ < 0) return false;
  const std::size_t f = static_cast<std::size_t>(front_);
  const SailType t = perf_->sails[f].type;
  const SailPhase p = sails_[f].phase;
  return (t == SailType::spinnaker_sym || t == SailType::spinnaker_asym) &&
         (p == SailPhase::up || p == SailPhase::prepare_drop);
}

void Sails::save(SnapshotWriter& w) const {
  for (const SailState& s : sails_) {
    w.put_u8(static_cast<std::uint8_t>(s.phase));
    w.put_f32(s.progress);
    w.put_f32(s.beta);
    w.put_f32(s.pole);
  }
  w.put_i8(front_);
  for (const SailStep& st : queue_) {
    w.put_i8(st.sail);
    w.put_u8(static_cast<std::uint8_t>(st.phase));
    w.put_u8(st.reversed);
  }
  w.put_u8(queue_len_);
  w.put_u8(queue_pos_);
  w.put_f32(queue_progress_);
}

bool Sails::load(SnapshotReader& r) {
  const std::int32_t n = static_cast<std::int32_t>(sails_.size());
  auto phase_ok = [](std::uint8_t p) { return p <= static_cast<std::uint8_t>(SailPhase::dropping); };
  for (SailState& s : sails_) {
    const std::uint8_t p = r.get_u8();
    if (!phase_ok(p)) return false;
    s.phase = static_cast<SailPhase>(p);
    s.progress = r.get_f32();
    s.beta = r.get_f32();
    s.pole = r.get_f32();
  }
  front_ = r.get_i8();
  if (front_ < -1 || front_ >= n) return false;
  for (SailStep& st : queue_) {
    st.sail = r.get_i8();
    const std::uint8_t p = r.get_u8();
    if (st.sail < 0 || st.sail >= n || !phase_ok(p)) return false;
    st.phase = static_cast<SailPhase>(p);
    st.reversed = r.get_u8();
  }
  queue_len_ = r.get_u8();
  queue_pos_ = r.get_u8();
  queue_progress_ = r.get_f32();
  events_.clear();
  return !r.failed() && queue_len_ <= kQueueMax && queue_pos_ <= queue_len_;
}

}  // namespace wm
