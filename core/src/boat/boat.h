// One boat: state, controls and the 50 ms step (boat.md). The sails (inventory, changes, trim) are a member
// (sails.md); the performance file supplies every class number.
#pragma once

#include <cstdint>

#include "boat/boat_env.h"
#include "boat/hull_sampling.h"
#include "data/perf.h"
#include "sails/sails.h"
#include "state/checksum.h"

namespace wm {

// boat.md §3, serialised in this order (conventions.md §9).
struct BoatState {
  float pos_x = 0.0f, pos_y = 0.0f;
  float z = 0.0f;
  float psi = 0.0f;
  float v = 0.0f;
  float h = 0.0f;
  float yaw_rate = 0.0f;  // the hull's own yaw rate (boat.md §5.9)
  float phi = 0.0f, phi_rate = 0.0f;
  float theta = 0.0f, theta_rate = 0.0f;
  float wobble_phase = 0.0f;
  float contact_vx = 0.0f, contact_vy = 0.0f;
  float contact_yaw_rate = 0.0f;
  float twd_from = 0.0f, awd_from = 0.0f;
  float tws = 0.0f, twa = 0.0f, aws = 0.0f, awa = 0.0f;
  float v_filt = 0.0f, sog_filt_x = 0.0f, sog_filt_y = 0.0f;
};

// boat.md §2 controls; they persist until changed.
struct BoatControls {
  float h_cmd = 0.0f;
  float sheet_cmd = 0.0f;
  bool auto_trim = true;
  bool let_fly = false;
  float performance_scale = 1.0f;
};

// boat.md §3 derived outputs, recomputed each tick.
struct BoatOutputs {
  float target_speed = 0.0f;
  float polar_speed = 0.0f;
  float heel_target = 0.0f;
  float turn_rate = 0.0f;
  float vmg = 0.0f;
  float sog = 0.0f;
  float cog = 0.0f;
  float man_coef = 1.0f;
  float trim_speed = 1.0f;
  float trim_heel = 1.0f;
  float heel_coef = 1.0f;
  float surf_coef = 1.0f;
  float wind_speed_clean = 0.0f;
};

class Boat {
 public:
  // `perf` must outlive the boat. `race_seed` and `index` seed the attitude wobble (boat.md §6.5).
  void init(const PerfData* perf, std::uint64_t race_seed, std::uint32_t index);

  // boat.md §6.6. `front_sail` is a sail index or -1.
  void reset(float pos_x, float pos_y, float psi, float v, std::int32_t front_sail, bool auto_trim,
             const BoatEnv& env);

  // Controls (boat.md §2, §8): clamped on write, NaN is the neutral value.
  void set_helm(float h_cmd);
  void set_sheet(float sheet_cmd);  // NaN leaves the sheet unchanged
  void set_auto_trim(bool on) { ctl_.auto_trim = on; }
  void set_let_fly(bool on) { ctl_.let_fly = on; }
  void set_performance_scale(float s);
  SailRequest hoist(std::int32_t sail) { return sails_.hoist(sail); }
  SailRequest drop_front() { return sails_.drop_front(); }

  // boat.md §5: one tick with the environment at t_n.
  void step(const BoatEnv& env);

  const BoatState& state() const { return s_; }
  BoatState& mutable_state() { return s_; }  // collisions write pos, v and contact_* (collisions.md §4)
  const BoatControls& controls() const { return ctl_; }
  const BoatOutputs& outputs() const { return out_; }
  // World snapshot load (conventions.md §9.1): the outputs of the last step, which the next tick reads first.
  void restore_outputs(const BoatOutputs& o) { out_ = o; }
  const Sails& sails() const { return sails_; }
  const PerfData& perf() const { return *perf_; }

  // AI helpers (boat.md §9): table lookups for a hypothetical wind angle and the turning radius for a helm.
  float polar_at(float tws, float twa, std::int32_t front_sail) const;
  float accel_at(float tws, float twa, std::int32_t front_sail) const;
  float turn_radius(float helm) const;  // m; infinite (a large number) for |helm| < 1e-5
  // trim_speed the driving sail would give let fly at this tick's wind (sails.md §5.3): 0 where let fly stops the
  // boat (fully eased sail on the wind line), near 1 running (the fully eased sails still draw).
  float let_fly_drive() const;
  // Windage deceleration at this tick's apparent wind (boat.md §5.8 `wind`), m/s^2 >= 0.
  float decel_wind() const;

  // conventions.md §9: boat.md §3 then sails.md §3.
  void save(SnapshotWriter& w) const;
  bool load(SnapshotReader& r);

 private:
  void wind_triangle(const BoatEnv& env);

  const PerfData* perf_ = nullptr;
  HullPoints hull_;
  std::uint64_t seed_ = 0;
  std::uint32_t index_ = 0;
  BoatState s_;
  BoatControls ctl_;
  BoatOutputs out_;
  Sails sails_;
};

}  // namespace wm
