// Sail inventory, sail changes and trim of one boat (sails.md). The boat step (boat.md §5.3, §5.4) calls
// advance() then trim() once per tick; requests arrive as control events between ticks.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "data/perf.h"
#include "state/checksum.h"

namespace wm {

// sails.md §3.1: the numbering is part of the snapshot.
enum class SailPhase : std::uint8_t { down = 0, prepare_hoist = 1, hoisting = 2, up = 3, prepare_drop = 4, dropping = 5 };

// sails.md §5.5, for crew and winch animation and sounds.
enum class SailMotion : std::uint8_t { idle = 0, sheeting = 1, easing = 2 };

enum class SailRequest : std::uint8_t { accepted = 0, rejected = 1 };

// sails.md §3.1, serialised in sail order.
struct SailState {
  SailPhase phase = SailPhase::down;
  float progress = 0.0f;  // 0..1: fraction hoisted (hoisting) or lowered (dropping)
  float beta = 0.0f;      // sail angle, rad, [-pi, pi)
  float pole = 0.0f;      // pole / boom angle, rad
};

// sails.md §3.2: one step of a sail change.
struct SailStep {
  std::int8_t sail = 0;
  SailPhase phase = SailPhase::down;
  std::uint8_t reversed = 0;
};

// sails.md §7, recomputed each tick (not state).
struct SailOutput {
  float k_h = 0.0f;         // hoist factor (§5.4)
  float m_opt = 0.0f;       // optimal angle magnitude (§5.1)
  float beta_opt = 0.0f;    // signed optimal angle
  float beta_t = 0.0f;      // target angle of the sail motion (§5.4), for winch and crew sounds (§7)
  float trim_error = 0.0f;  // eps (§5.6): + eased beyond the optimum, - sheeted in beyond it
  float luff_shiver = 0.0f; // 0..1
  SailMotion motion = SailMotion::idle;
  bool backed = false;
};

// sails.md §7: every phase change is reported once, in the order it happens within the tick.
struct SailPhaseEvent {
  std::int8_t sail;
  SailPhase phase;
};

// This tick's inputs to the trim (sails.md §5; boat.md §2).
struct TrimInput {
  float awa = 0.0f;
  float tws = 0.0f;
  float phi = 0.0f;
  float sheet_cmd = 0.0f;
  bool auto_trim = true;
  bool let_fly = false;
};

class Sails {
 public:
  static constexpr std::size_t kQueueMax = 6;

  // `perf` must outlive this object.
  void init(const PerfData* perf);

  // sails.md §3.2 reset: main up, `front_sail` (-1 = none) up, every other sail down, queue empty. The angles are
  // set by the first trim(..., /*place=*/true).
  void reset(std::int32_t front_sail);

  // sails.md §4.2 requests. Rejected requests change nothing.
  SailRequest hoist(std::int32_t sail);
  SailRequest drop_front();

  // sails.md §4.3, boat step 5.3. `tws`, `twa_abs` are this tick's values.
  void advance(float tws, float twa_abs);

  // sails.md §4.5: slowdown of the running change step, 1 when idle.
  float man_coef(float twa) const;

  // sails.md §5, boat step 5.4, for every sail in sail order. `place` sets every sail straight to its target
  // (reset, boat.md §6.6).
  void trim(const TrimInput& in, bool place = false);

  // The config whose tables drive the boat (main only or main + front).
  const ConfigPerf& config() const { return *perf_->config_for(front_); }
  // boat.md §5.4: the front sail if one is up, else the main.
  std::int32_t driving_sail() const { return front_ >= 0 ? front_ : perf_->main_sail; }
  float driving_trim_error() const { return out_[static_cast<std::size_t>(driving_sail())].trim_error; }

  std::int32_t front() const { return front_; }
  bool busy() const { return queue_pos_ < queue_len_; }
  std::size_t sail_count() const { return sails_.size(); }
  const SailState& sail(std::size_t i) const { return sails_[i]; }
  const SailOutput& output(std::size_t i) const { return out_[i]; }
  // boat.md §5.8, sails.md §7: a hoisted kite flown beyond its usable angle flogs; its luff shiver is at least that.
  void set_kite_flog(float f_k);
  // boat.md §5.8: the kite's flogging share at (tws, twa_abs) (0 with no kite up) and its own flogging drag (m/s²)
  float kite_flog_share(float tws, float twa_abs) const;
  float kite_flog_drag(float aws, float awa_abs) const;
  // World snapshot load (conventions.md §9.1): the outputs of the last step, one per sail in sail order.
  void restore_outputs(const std::vector<SailOutput>& o) { out_ = o; }
  const std::vector<SailPhaseEvent>& events() const { return events_; }
  void clear_events() { events_.clear(); }
  std::uint8_t queue_len() const { return queue_len_; }
  std::uint8_t queue_pos() const { return queue_pos_; }
  const SailStep& queue_step(std::size_t i) const { return queue_[i]; }
  float queue_progress() const { return queue_progress_; }

  // wind_shadow.md §3: the front sail is a spinnaker of either type and is up or being prepared for the drop.
  bool spinnaker_flying() const;

  // conventions.md §9: per sail in sail order, then the per-boat block of sails.md §3.2.
  void save(SnapshotWriter& w) const;
  bool load(SnapshotReader& r);

 private:
  float duration(std::int32_t sail, SailPhase phase, float tws, float twa_abs) const;
  void set_queue(std::initializer_list<SailStep> steps);
  float optimal(std::size_t sail, float tws, float awa_abs) const;
  float hoist_factor(std::size_t sail) const;

  const PerfData* perf_ = nullptr;
  std::vector<SailState> sails_;
  std::vector<SailOutput> out_;
  std::vector<float> m_s_;  // scratch: sheet target magnitudes of this tick (§5.2)
  std::vector<SailPhaseEvent> events_;
  std::int8_t front_ = -1;
  std::array<SailStep, kQueueMax> queue_{};
  std::uint8_t queue_len_ = 0;
  std::uint8_t queue_pos_ = 0;
  float queue_progress_ = 0.0f;
};

}  // namespace wm
