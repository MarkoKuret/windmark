// Performance file `windmark.perf/1` (data_format.md §4): everything the core needs to sail a class. Loaded and
// fully validated at once; the core never runs with partly valid data.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "data/load_error.h"
#include "data/vmg_table.h"
#include "math/wm_math.h"
#include "table/table.h"

namespace wm {

// collisions.md §2.1
struct CollisionShape {
  std::vector<Vec2> outline;  // convex, counter-clockwise, body frame (x forward, y port)
  float mass = 0.0f;          // kg, sailing displacement with crew
  float yaw_gyration = 0.0f;  // m
  float sprit = 0.0f;         // m, bowsprit reach ahead of the outline's bow when a sail is tacked to it (rules.md §3.2)
};

// wind_shadow.md §2, every key required.
struct WindShadowParams {
  float height, ce_x, stern_x, chord, width_min, width_spinnaker;
  float length_coef, length_knee;
  float blanket_depth, blanket_depth_spinnaker, blanket_peak, blanket_near, blanket_reach_up, blanket_spread;
  float turb_length, turb_depth, turb_width, turb_spread, turb_angle, turb_awa_fade, turb_awa_max;
  float header_coef, header_max;
};

// boat.md §4.1, computed once at load in the spec's order.
struct DerivedDynamics {
  float heel_k1, heel_k2, pitch_k1, pitch_k2, heave_a, turn_c, yaw_a;
  float drift_lift;  // 4 / drift_grip: keel lift slope over cross-flow drag coefficient (boat.md §6.4), 0 without
  static constexpr float FILT_A = 0.0243902430f;  // DT / (2 s + DT)
};

// data_format.md §4.2
struct Dynamics {
  float helm_rate, rudder_max, turn_radius_full, turn_radius_offset;
  float yaw_time;  // s, the hull's yaw-rate time constant (boat.md §4, §5.9)
  float decel_linear, decel_const;
  float decel_windage;  // 1/m, windage deceleration per aws^2 head to wind (boat.md §4, §5.8)
  Table heel_speed_factor;  // (heel_abs) -> 1
  Table rudder_drag_luff;   // (boat_speed_abs, helm_abs) -> m/s2
  Table rudder_drag_bear;
  float heel_max, heel_limit, heel_freq, heel_damping;
  float pitch_freq, pitch_damping, wave_roll_gain, wave_pitch_gain;
  float wobble_heel, wobble_pitch, wobble_freq;
  float heave_time, waterline_offset, surf_gain;
  // boat.md §5.6: how the heeled hull floats, optional (absent 0)
  OptionalTable heel_rise;  // (heel_abs) -> m
  OptionalTable heel_trim;  // (heel_abs) -> rad, + bow up
  // Sideways drift (boat.md §4, §6.4): optional, both or neither; absent, the boat never drifts sideways.
  bool has_drift = false;
  float drift_grip = 0.0f;    // keel grip: grip speed over the drift speed
  float drift_length = 0.0f;  // m, sway mass over the cross-flow drag coefficient
  bool full_leeway = false;   // leeway at every speed from each config's `leeway` table; off in the shipped classes
  bool has_hull_points = false;  // absent: sea.md §5.1 derives 8 points from lwl, bwl
  std::vector<Vec2> hull_points;
  float lwl, bwl, loa;
  CollisionShape collision;
  WindShadowParams wind_shadow;
  DerivedDynamics derived;
};

enum class SailType : std::uint8_t { main, jib, genoa, code_zero, spinnaker_sym, spinnaker_asym };

bool sail_type_from_name(std::string_view name, SailType& out);
std::string_view sail_type_name(SailType t);

// A handling duration (sails.md §4.4): a constant or Table2D(tws, twa_abs) -> s.
struct Duration {
  bool is_table = false;
  float constant = 0.0f;
  Table table;
  float at(float tws, float twa_abs) const { return is_table ? table.at(tws, twa_abs) : constant; }
};

struct SailHandling {
  Duration prepare_hoist_time, hoist_time, prepare_drop_time, drop_time;
  float slow_prepare_hoist, slow_hoist, slow_prepare_drop, slow_drop;
};

// data_format.md §4.4, sails.md §2
struct SailPerf {
  std::string id;
  SailType type = SailType::main;
  float sheet_min = 0.0f, sheet_max = 0.0f;
  OptionalTable sheet_max_by_heel;  // (heel_abs) -> rad
  float rate_in = 0.0f, rate_out = 0.0f;
  OptionalTable pole_angle;         // (tws, awa_abs) -> rad
  bool has_pole_rate = false;
  float pole_rate = 0.0f;
  Table shiver_angle;               // (tws) -> rad
  bool shiver_free = false;
  bool has_handling = false;        // front sails only, required for them
  SailHandling handling;
};

// data_format.md §4.3, sails.md §6
struct ConfigPerf {
  std::int32_t front_sail = -1;  // index into PerfData::sails, -1 = main only
  Table polar;                   // (tws, twa_abs) -> m/s
  Table heel;                    // (tws, twa_abs) -> rad
  Table accel;                   // (tws, twa_abs) -> m/s2
  OptionalTable accel_rest;      // (tws, twa_abs) -> m/s2, absent: accel
  OptionalTable trim_speed;      // (tws, awa_abs, trim_error) -> 1, absent: 1
  OptionalTable trim_heel;       // (tws, awa_abs, trim_error) -> 1, absent: 1
  OptionalTable weather_helm;    // (tws, twa_abs) -> rad/s, absent: 0
  OptionalTable fall_off;        // (boat_speed, twa_abs) -> rad/s, absent: 0
  OptionalTable flog_drag;       // (aws, awa_abs) -> m/s2, absent: 0
  OptionalTable drift;           // (tws, twa_abs) -> m/s, sideways drift at rest, sails luffing; absent: 0
  OptionalTable drift_flog;      // (tws, twa_abs) -> m/s, the same with the sails flogging; absent: drift
  OptionalTable leeway;          // (tws, twa_abs) -> rad, required with dynamics.full_leeway, else ignored
  Table optimal_main;            // optimal_angle.<main id>: (tws, awa_abs) -> rad
  Table optimal_front;           // optimal_angle.<front id>; empty for main only
};

struct PerfData {
  std::string class_id;
  std::int64_t class_version = 0;
  std::string class_sha256;  // lowercase hex of the class file bytes
  std::string generator_tool, generator_version;
  std::string file_sha256;   // lowercase hex of the perf file bytes (announced online, data_format.md §4.1)
  Dynamics dynamics{};
  std::vector<SailPerf> sails;      // in file order; exactly one main
  std::int32_t main_sail = -1;      // index of the main in sails
  std::vector<ConfigPerf> configs;  // in file order; one main-only config and one per front sail
  std::int32_t start_front_sail = -1;
  VmgTable vmg;  // derived at load from the configs' polars (rules.md §3.7)

  std::int32_t find_sail(std::string_view id) const;  // -1 if absent
  // The config driven by the front sail at `front_sail` (-1 = main only); never null after a successful load.
  const ConfigPerf* config_for(std::int32_t front_sail) const;
};

// Parses and validates. `file` names the source in errors.
bool parse_perf(std::string_view text, std::string_view file, PerfData& out, LoadError& err);
bool load_perf(const std::string& file, PerfData& out, LoadError& err);

}  // namespace wm
