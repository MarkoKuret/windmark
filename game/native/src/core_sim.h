// CoreSim: the Windmark core (through its C API, core/include/windmark.h) as a Godot class. GDScript reaches it
// through CoreSimSource (game/scripts/sim/core_sim_source.gd), which implements SimSource on top of it.
//
// Records that are read every tick come back as PackedFloat32Array in a fixed field order (the order of the C
// structs, see the *_FIELDS constants in core_sim_source.gd); the rest come back as Dictionaries with the C
// field names.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <memory>
#include <vector>

#include "windmark.h"

namespace windmark_godot {

class CoreSim : public godot::RefCounted {
  GDCLASS(CoreSim, godot::RefCounted)

 public:
  CoreSim();
  ~CoreSim() override;

  // set-up
  static godot::Dictionary default_settings();
  bool create(const godot::Dictionary& settings, const godot::String& venue_path);
  godot::Dictionary resolve_settings(const godot::Dictionary& settings, const godot::String& venue_path,
                                     const godot::String& course_path);
  bool is_created() const { return world_ != nullptr; }
  int64_t add_boat(const godot::String& perf_path, const godot::Dictionary& entry);
  bool place_boat(int64_t boat, double x, double y, double psi);
  bool scenario_place(int64_t boat, double x, double y, double psi, double v, int64_t front_sail);
  bool create_race(const godot::String& course_path);
  godot::String last_error() const { return error_; }
  int64_t api_version() const { return wm_api_version(); }

  // controls
  int64_t apply_input(int64_t boat, double h_cmd, double sheet_cmd, int64_t sail_req, int64_t flags);
  bool set_helm(int64_t boat, double h);
  bool set_sheet(int64_t boat, double s);
  bool set_auto_trim(int64_t boat, bool on);
  bool set_let_fly(int64_t boat, bool on);
  int64_t hoist(int64_t boat, int64_t sail);
  int64_t drop_front(int64_t boat);
  bool retire(int64_t boat);
  bool protest(int64_t boat);
  static godot::PackedByteArray encode_input(double h_cmd, double sheet_cmd, int64_t sail_req, int64_t flags);

  // AI skippers (ai.md; levels 0 easy, 1 intermediate, 2 expert, 3 pro)
  int64_t add_ai_boat(const godot::String& perf_path, int64_t level, bool speed_only);
  bool ai_add(int64_t boat, int64_t level, bool speed_only);
  bool ai_take_over(int64_t boat);
  bool ai_release(int64_t boat);
  bool ai_add_autopilot(int64_t boat);
  bool ai_has(int64_t boat) const;
  int64_t ai_count() const;
  godot::Dictionary ai_telemetry(int64_t boat) const;
  godot::Dictionary ai_debug(int64_t boat) const;
  static double ai_performance_scale(int64_t level);
  static godot::String ai_tactic_name(int64_t tactic);

  // snapshots
  godot::PackedByteArray save_world();
  bool load_world(const godot::String& course_path, const godot::PackedByteArray& bytes);
  godot::PackedByteArray ai_save();
  bool ai_load(const godot::PackedByteArray& bytes);

  // stepping. step_begin() runs the next tick on the worker thread (game/README.md "The simulation on a second
  // core"); every other call waits for it first, so nothing reads or changes the world while it steps.
  void step();
  bool step_begin();
  int64_t step_end();
  bool is_stepping() const { return stepping_; }
  int64_t step_ticks(int64_t n, bool stop_when_closed);
  int64_t checksum() const;
  int64_t tick() const;
  int64_t boat_count() const;
  bool has_race() const;
  int64_t time_ms() const;
  double render_time_ms(double alpha) const;

  // boats
  godot::Dictionary class_info(int64_t boat) const;
  godot::PackedFloat32Array boat_state(int64_t boat) const;
  godot::PackedFloat32Array boat_controls(int64_t boat) const;
  godot::PackedFloat32Array boat_outputs(int64_t boat) const;
  godot::PackedFloat32Array boat_env(int64_t boat) const;
  godot::PackedFloat32Array render_pose(int64_t boat, double alpha) const;
  godot::PackedFloat32Array render_poses(double alpha) const;
  double trim_speed_at(int64_t boat, double tws, double awa_abs, double eps) const;
  double perf_table(int64_t boat, int64_t front_sail, const godot::String& name, double x, double y, double w) const;
  double polar(int64_t boat, double tws, double twa, int64_t front_sail) const;
  godot::Dictionary polar_vmg(int64_t boat, double tws) const;
  godot::Dictionary sails(int64_t boat) const;
  godot::PackedFloat32Array sail(int64_t boat, int64_t sail) const;
  godot::Array sail_events(int64_t boat) const;

  // environment
  godot::Vector2 wind_clean(double x, double y);
  double wind_global_from();
  godot::Vector2 current_at(double x, double y, int64_t t_ms);
  godot::Dictionary wind_state(int64_t t_ms);
  double sea_height(double x, double y);
  double sea_height_at(double x, double y, int64_t t_ms);
  godot::Vector2 sea_slope(double x, double y);
  godot::Array sea_components() const;
  godot::Dictionary sea_exposure() const;

  // venue
  godot::Array venue_land() const;
  godot::Array venue_obstacles() const;

  // course, race and rules
  godot::Dictionary course() const;
  godot::Dictionary race() const;
  godot::Dictionary race_boat(int64_t boat) const;
  godot::PackedInt32Array race_order() const;
  godot::Array results() const;
  double race_split(int64_t boat, int64_t step) const;
  godot::Dictionary race_start_status(int64_t boat) const;
  godot::Dictionary boat_rules(int64_t boat) const;
  godot::Array pairs() const;
  godot::Array race_events() const;
  godot::Array rules_events() const;
  godot::Array contact_events() const;
  static godot::String rule_code_name(int64_t rule);
  static godot::String score_code_name(int64_t code);

 protected:
  static void _bind_methods();

 private:
  bool ok(wm_status s) const;
  bool boat_ok(int64_t boat) const;
  wm_perf* perf_for(const godot::String& path);
  // waits for a tick running on the worker thread
  void settle() const;

  struct Worker;

  wm_world* world_ = nullptr;
  std::vector<std::pair<godot::String, wm_perf*>> perfs_;  // loaded classes by file path
  mutable godot::String error_;
  std::unique_ptr<Worker> worker_;
  mutable bool stepping_ = false;
};

}  // namespace windmark_godot
