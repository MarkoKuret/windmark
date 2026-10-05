#include "core_sim.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cmath>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <thread>

#if !defined(_WIN32)
#include <pthread.h>
#endif

using namespace godot;

namespace windmark_godot {

namespace {

std::string os_path(const String& p) {
  const String g = ProjectSettings::get_singleton()->globalize_path(p);
  return std::string(g.utf8().get_data());
}

float f32(double v) { return static_cast<float>(v); }
int32_t i32(int64_t v) { return static_cast<int32_t>(v); }

template <class T>
PackedFloat32Array floats(const T& s) {
  static_assert(sizeof(T) % sizeof(float) == 0);
  PackedFloat32Array a;
  a.resize(static_cast<int64_t>(sizeof(T) / sizeof(float)));
  const float* p = reinterpret_cast<const float*>(&s);
  for (int64_t i = 0; i < a.size(); ++i) a.set(i, p[i]);
  return a;
}

double get_f(const Dictionary& d, const char* k, double def) { return d.has(k) ? double(d[k]) : def; }
int64_t get_i(const Dictionary& d, const char* k, int64_t def) { return d.has(k) ? int64_t(d[k]) : def; }

}  // namespace

// ---- the worker thread ----------------------------------------------------------------------------------------
//
// One thread per world, made at the first step_begin(): it sleeps until a tick is handed to it, steps the world
// and signals the end. The main thread hands the tick over and takes it back (step_end, or settle() in any other
// call), so the world is touched by one thread at a time and steps exactly as it does on the main thread.

struct CoreSim::Worker {
  std::mutex m;
  std::condition_variable cv;
  wm_world* world = nullptr;
  bool job = false;
  bool done = false;
  bool quit = false;
#if defined(_WIN32)
  std::thread thread;
#else
  pthread_t thread{};
#endif

  void run() {
    std::unique_lock<std::mutex> lk(m);
    for (;;) {
      cv.wait(lk, [this] { return job || quit; });
      if (quit) return;
      wm_world* w = world;
      lk.unlock();
      wm_world_step(w);
      lk.lock();
      job = false;
      done = true;
      cv.notify_all();
    }
  }

#if !defined(_WIN32)
  static void* entry(void* self) {
    static_cast<Worker*>(self)->run();
    return nullptr;
  }
#endif

  bool start() {
#if defined(_WIN32)
    thread = std::thread([this] { run(); });
    return true;
#else
    // the main thread's stack size: the core is written for it (std::thread would give 512 KiB on macOS)
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setstacksize(&a, 8u << 20);
    const bool r = pthread_create(&thread, &a, &Worker::entry, this) == 0;
    pthread_attr_destroy(&a);
    return r;
#endif
  }

  void begin(wm_world* w) {
    std::lock_guard<std::mutex> lk(m);
    world = w;
    done = false;
    job = true;
    cv.notify_all();
  }

  void wait() {
    std::unique_lock<std::mutex> lk(m);
    cv.wait(lk, [this] { return done; });
  }

  void stop() {
    {
      std::lock_guard<std::mutex> lk(m);
      quit = true;
      cv.notify_all();
    }
#if defined(_WIN32)
    if (thread.joinable()) thread.join();
#else
    pthread_join(thread, nullptr);
#endif
  }
};

CoreSim::CoreSim() = default;

void CoreSim::settle() const {
  if (!stepping_) return;
  worker_->wait();
  stepping_ = false;
}

// Starts the next tick on the worker thread; false (nothing started) without a world or a thread.
bool CoreSim::step_begin() {
  settle();
  if (world_ == nullptr) return false;
  if (!worker_) {
    auto w = std::make_unique<Worker>();
    if (!w->start()) {
      error_ = "the simulation thread did not start";
      return false;
    }
    worker_ = std::move(w);
  }
  worker_->begin(world_);
  stepping_ = true;
  return true;
}

// Waits for the tick started by step_begin() (at once when it is done); returns the tick count.
int64_t CoreSim::step_end() {
  settle();
  return world_ != nullptr ? static_cast<int64_t>(wm_world_tick(world_)) : 0;
}

CoreSim::~CoreSim() {
  settle();
  if (worker_) worker_->stop();
  wm_world_free(world_);
  for (auto& p : perfs_) wm_perf_free(p.second);
}

bool CoreSim::ok(wm_status s) const {
  if (s == WM_OK) return true;
  error_ = String::utf8(wm_last_error());
  return false;
}

bool CoreSim::boat_ok(int64_t boat) const {
  if (world_ == nullptr) {
    error_ = "no world";
    return false;
  }
  if (boat < 0 || boat >= wm_world_boat_count(world_)) {
    error_ = "bad boat index";
    return false;
  }
  return true;
}

// ---- set-up ---------------------------------------------------------------------------------------------------

Dictionary CoreSim::default_settings() {
  wm_world_settings s;
  wm_world_settings_init(&s);
  Dictionary d;
  d["race_seed"] = static_cast<int64_t>(s.race_seed);
  d["wind_speed"] = s.wind_speed;
  d["wind_from"] = s.wind_from;
  d["shift_preset"] = s.shift_preset;
  d["shift_trend_rate"] = s.shift_trend_rate;
  d["puffs"] = s.puffs != 0;
  d["oscillation"] = s.oscillation != 0;
  d["current_speed"] = s.current_speed;
  d["current_to"] = s.current_to;
  d["sea"] = s.sea != 0;
  d["sea_scale"] = s.sea_scale;
  d["shadows"] = s.shadows != 0;
  d["race_type"] = s.race_type;
  d["sequence"] = s.sequence;
  d["prep_flag"] = s.prep_flag;
  d["free_sailing_s"] = s.free_sailing_s;
  d["general_recall"] = s.general_recall != 0;
  d["rules_level"] = s.rules_level;
  d["penalty"] = s.penalty;
  d["umpire"] = s.umpire;
  d["time_limit_s"] = s.time_limit_s;
  d["finish_window"] = s.finish_window != 0;
  d["start_limit_s"] = s.start_limit_s;
  return d;
}

bool CoreSim::create(const Dictionary& d, const String& venue_path) {
  settle();
  if (world_ != nullptr) {
    error_ = "the world exists already";
    return false;
  }
  wm_world_settings s;
  wm_world_settings_init(&s);
  s.race_seed = static_cast<uint64_t>(get_i(d, "race_seed", static_cast<int64_t>(s.race_seed)));
  s.wind_speed = f32(get_f(d, "wind_speed", s.wind_speed));
  s.wind_from = f32(get_f(d, "wind_from", s.wind_from));
  s.shift_preset = i32(get_i(d, "shift_preset", s.shift_preset));
  s.shift_trend_rate = f32(get_f(d, "shift_trend_rate", s.shift_trend_rate));
  s.puffs = i32(get_i(d, "puffs", s.puffs));
  s.oscillation = i32(get_i(d, "oscillation", s.oscillation));
  s.current_speed = f32(get_f(d, "current_speed", s.current_speed));
  s.current_to = f32(get_f(d, "current_to", s.current_to));
  s.sea = i32(get_i(d, "sea", s.sea));
  s.sea_scale = f32(get_f(d, "sea_scale", s.sea_scale));
  s.shadows = i32(get_i(d, "shadows", s.shadows));
  s.race_type = i32(get_i(d, "race_type", s.race_type));
  s.sequence = i32(get_i(d, "sequence", s.sequence));
  s.prep_flag = i32(get_i(d, "prep_flag", s.prep_flag));
  s.free_sailing_s = f32(get_f(d, "free_sailing_s", s.free_sailing_s));
  s.general_recall = i32(get_i(d, "general_recall", s.general_recall));
  s.rules_level = i32(get_i(d, "rules_level", s.rules_level));
  s.penalty = i32(get_i(d, "penalty", s.penalty));
  s.umpire = i32(get_i(d, "umpire", s.umpire));
  s.time_limit_s = f32(get_f(d, "time_limit_s", s.time_limit_s));
  s.finish_window = i32(get_i(d, "finish_window", s.finish_window));
  s.start_limit_s = f32(get_f(d, "start_limit_s", s.start_limit_s));
  wm_venue* venue = nullptr;
  if (!venue_path.is_empty() && !ok(wm_venue_load(os_path(venue_path).c_str(), &venue))) return false;
  const bool r = ok(wm_world_create(&s, venue, &world_));
  wm_venue_free(venue);  // the world keeps its own reference
  return r;
}

wm_perf* CoreSim::perf_for(const String& path) {
  for (auto& p : perfs_) {
    if (p.first == path) return p.second;
  }
  wm_perf* p = nullptr;
  if (!ok(wm_perf_load(os_path(path).c_str(), &p))) return nullptr;
  perfs_.emplace_back(path, p);
  return p;
}

int64_t CoreSim::add_boat(const String& perf_path, const Dictionary& d) {
  settle();
  if (world_ == nullptr) {
    error_ = "no world";
    return -1;
  }
  wm_perf* p = perf_for(perf_path);
  if (p == nullptr) return -1;
  wm_boat_entry e;
  wm_boat_entry_init(&e, p);
  e.human = i32(get_i(d, "human", e.human));
  e.ai = i32(get_i(d, "ai", e.ai));
  e.performance_scale = f32(get_f(d, "performance_scale", e.performance_scale));
  e.auto_trim = i32(get_i(d, "auto_trim", e.auto_trim));
  e.front_sail = i32(get_i(d, "front_sail", e.front_sail));
  int32_t idx = -1;
  if (!ok(wm_world_add_boat(world_, &e, &idx))) return -1;
  return idx;
}

bool CoreSim::place_boat(int64_t boat, double x, double y, double psi) {
  settle();
  return boat_ok(boat) && ok(wm_world_place_boat(world_, i32(boat), f32(x), f32(y), f32(psi)));
}

bool CoreSim::scenario_place(int64_t boat, double x, double y, double psi, double v, int64_t front_sail) {
  settle();
  return boat_ok(boat) &&
         ok(wm_world_scenario_place(world_, i32(boat), f32(x), f32(y), f32(psi), f32(v), i32(front_sail)));
}

bool CoreSim::create_race(const String& course_path) {
  settle();
  if (world_ == nullptr) {
    error_ = "no world";
    return false;
  }
  wm_course* c = nullptr;
  if (!ok(wm_course_load(os_path(course_path).c_str(), &c))) return false;
  const bool r = ok(wm_world_create_race(world_, c));
  wm_course_free(c);
  return r;
}

// ---- controls -------------------------------------------------------------------------------------------------

int64_t CoreSim::apply_input(int64_t boat, double h_cmd, double sheet_cmd, int64_t sail_req, int64_t flags) {
  settle();
  if (!boat_ok(boat)) return WM_REQUEST_NONE;
  const wm_input_frame f{f32(h_cmd), f32(sheet_cmd), static_cast<uint8_t>(sail_req & 0xFF),
                         static_cast<uint8_t>(flags & 0xFF)};
  int32_t r = WM_REQUEST_NONE;
  if (!ok(wm_world_apply_input(world_, i32(boat), &f, &r))) return WM_REQUEST_NONE;
  return r;
}

bool CoreSim::set_helm(int64_t b, double h) {
  settle();
  return boat_ok(b) && ok(wm_world_set_helm(world_, i32(b), f32(h)));
}
bool CoreSim::set_sheet(int64_t b, double s) {
  settle();
  return boat_ok(b) && ok(wm_world_set_sheet(world_, i32(b), f32(s)));
}
bool CoreSim::set_auto_trim(int64_t b, bool on) {
  settle();
  return boat_ok(b) && ok(wm_world_set_auto_trim(world_, i32(b), on));
}
bool CoreSim::set_let_fly(int64_t b, bool on) {
  settle();
  return boat_ok(b) && ok(wm_world_set_let_fly(world_, i32(b), on));
}
int64_t CoreSim::hoist(int64_t b, int64_t sail) {
  settle();
  int32_t r = WM_REQUEST_NONE;
  if (boat_ok(b)) ok(wm_world_hoist(world_, i32(b), i32(sail), &r));
  return r;
}
int64_t CoreSim::drop_front(int64_t b) {
  settle();
  int32_t r = WM_REQUEST_NONE;
  if (boat_ok(b)) ok(wm_world_drop_front(world_, i32(b), &r));
  return r;
}
bool CoreSim::retire(int64_t b) { settle(); return boat_ok(b) && ok(wm_world_retire(world_, i32(b))); }
bool CoreSim::protest(int64_t b) { settle(); return boat_ok(b) && ok(wm_world_protest(world_, i32(b))); }

PackedByteArray CoreSim::encode_input(double h_cmd, double sheet_cmd, int64_t sail_req, int64_t flags) {
  const wm_input_frame f{f32(h_cmd), f32(sheet_cmd), static_cast<uint8_t>(sail_req & 0xFF),
                         static_cast<uint8_t>(flags & 0xFF)};
  uint8_t b[6];
  wm_input_encode(&f, b);
  PackedByteArray a;
  a.resize(6);
  for (int i = 0; i < 6; ++i) a.set(i, b[i]);
  return a;
}

// ---- stepping -------------------------------------------------------------------------------------------------

void CoreSim::step() {
  settle();
  if (world_ != nullptr) wm_world_step(world_);
}

// Fast-forward without rendering: n ticks (or until the race is closed); returns the ticks stepped. Only the last
// tick's events remain readable.
int64_t CoreSim::step_ticks(int64_t n, bool stop_when_closed) {
  settle();
  if (world_ == nullptr) return 0;
  int64_t k = 0;
  for (; k < n; ++k) {
    if (stop_when_closed) {
      wm_race_info ri;
      if (wm_world_race(world_, &ri) == WM_OK && ri.state == WM_RACE_CLOSED) break;
    }
    wm_world_step(world_);
  }
  return k;
}

// ---- AI skippers ----------------------------------------------------------------------------------------------

int64_t CoreSim::add_ai_boat(const String& perf_path, int64_t level, bool speed_only) {
  settle();
  if (world_ == nullptr) {
    error_ = "no world";
    return -1;
  }
  wm_perf* p = perf_for(perf_path);
  if (p == nullptr) return -1;
  int32_t idx = -1;
  if (!ok(wm_world_add_ai_boat(world_, p, i32(level), speed_only ? 1 : 0, &idx))) return -1;
  return idx;
}

bool CoreSim::ai_add(int64_t b, int64_t level, bool speed_only) {
  settle();
  return boat_ok(b) && ok(wm_world_ai_add(world_, i32(b), i32(level), speed_only ? 1 : 0));
}
bool CoreSim::ai_take_over(int64_t b) { settle(); return boat_ok(b) && ok(wm_world_ai_take_over(world_, i32(b))); }
bool CoreSim::ai_release(int64_t b) { settle(); return boat_ok(b) && ok(wm_world_ai_release(world_, i32(b))); }
bool CoreSim::ai_add_autopilot(int64_t b) {
  settle();
  return boat_ok(b) && ok(wm_world_ai_add_autopilot(world_, i32(b)));
}
bool CoreSim::ai_has(int64_t b) const { settle(); return world_ != nullptr && wm_world_ai_has(world_, i32(b)) != 0; }
int64_t CoreSim::ai_count() const { settle(); return wm_world_ai_count(world_); }

Dictionary CoreSim::ai_telemetry(int64_t boat) const {
  settle();
  Dictionary d;
  wm_ai_telemetry t;
  if (!boat_ok(boat) || !ok(wm_world_ai_telemetry(world_, i32(boat), &t))) return d;
  d["tacks"] = t.tacks;
  d["gybes"] = t.gybes;
  d["penalties"] = t.penalties;
  d["ocs"] = t.ocs;
  Dictionary act;
  for (int k = 0; k < WM_AI_TACTIC_COUNT; ++k) act[String::utf8(wm_ai_tactic_name(k))] = t.activations[k];
  d["activations"] = act;
  d["stuck_s"] = t.stuck_s;
  d["min_gap"] = t.min_gap;
  d["sail_changes"] = t.sail_changes;
  Array bad;
  for (int32_t i = 0; i < t.bad_air_count; ++i) {
    uint32_t tick = 0;
    float at = 0.0f, after = 0.0f;
    wm_world_ai_bad_air(world_, i32(boat), i, &tick, &at, &after);
    Array r;
    r.append(static_cast<int64_t>(tick));
    r.append(at);
    r.append(after);
    bad.append(r);
  }
  d["bad_air"] = bad;
  d["start_delay"] = t.start_delay;
  return d;
}

Dictionary CoreSim::ai_debug(int64_t boat) const {
  settle();
  Dictionary d;
  wm_ai_debug g;
  if (!boat_ok(boat) || !ok(wm_world_ai_debug(world_, i32(boat), &g))) return d;
  d["tactic"] = g.tactic;
  d["tactic_name"] = String::utf8(wm_ai_tactic_name(g.tactic));
  d["psi_target"] = g.psi_target;
  d["d"] = g.d;
  d["twd_ref"] = g.twd_ref;
  d["twd_f"] = g.twd_f;
  d["tws_f"] = g.tws_f;
  d["leg"] = g.leg;
  d["manoeuvre"] = g.manoeuvre;
  d["aim"] = Vector2(g.aim_x, g.aim_y);
  d["spot"] = Vector2(g.spot_x, g.spot_y);
  return d;
}

double CoreSim::ai_performance_scale(int64_t level) { return wm_ai_performance_scale(i32(level)); }
String CoreSim::ai_tactic_name(int64_t tactic) { return String::utf8(wm_ai_tactic_name(i32(tactic))); }

// ---- snapshots ------------------------------------------------------------------------------------------------

namespace {
PackedByteArray bytes_of(const uint8_t* p, size_t n) {
  PackedByteArray a;
  a.resize(static_cast<int64_t>(n));
  if (n > 0) std::memcpy(a.ptrw(), p, n);
  return a;
}
}  // namespace

PackedByteArray CoreSim::save_world() {
  settle();
  const uint8_t* p = nullptr;
  size_t n = 0;
  if (world_ == nullptr || !ok(wm_world_save(world_, &p, &n))) return PackedByteArray();
  return bytes_of(p, n);
}

bool CoreSim::load_world(const String& course_path, const PackedByteArray& bytes) {
  settle();
  if (world_ == nullptr) {
    error_ = "no world";
    return false;
  }
  wm_course* c = nullptr;
  if (!course_path.is_empty() && !ok(wm_course_load(os_path(course_path).c_str(), &c))) return false;
  const bool r = ok(wm_world_load(world_, c, bytes.ptr(), static_cast<size_t>(bytes.size())));
  wm_course_free(c);
  return r;
}

PackedByteArray CoreSim::ai_save() {
  settle();
  const uint8_t* p = nullptr;
  size_t n = 0;
  if (world_ == nullptr || !ok(wm_world_ai_save(world_, &p, &n))) return PackedByteArray();
  return bytes_of(p, n);
}

bool CoreSim::ai_load(const PackedByteArray& bytes) {
  settle();
  if (world_ == nullptr) {
    error_ = "no world";
    return false;
  }
  return ok(wm_world_ai_load(world_, bytes.ptr(), static_cast<size_t>(bytes.size())));
}
int64_t CoreSim::checksum() const { settle(); return static_cast<int64_t>(wm_world_checksum(world_)); }
int64_t CoreSim::tick() const { settle(); return wm_world_tick(world_); }
int64_t CoreSim::boat_count() const { settle(); return wm_world_boat_count(world_); }
bool CoreSim::has_race() const { settle(); return wm_world_has_race(world_) != 0; }
int64_t CoreSim::time_ms() const { settle(); return wm_world_time_ms(world_); }
double CoreSim::render_time_ms(double alpha) const { settle(); return wm_world_render_time_ms(world_, f32(alpha)); }

// ---- boats ----------------------------------------------------------------------------------------------------

Dictionary CoreSim::class_info(int64_t boat) const {
  settle();
  Dictionary d;
  if (!boat_ok(boat)) return d;
  const wm_perf* p = wm_world_boat_perf(world_, i32(boat));
  wm_class_info ci;
  if (!ok(wm_perf_info(p, &ci))) return d;
  d["class_id"] = String::utf8(ci.class_id);
  d["file_sha256"] = String::utf8(ci.file_sha256);
  d["loa"] = ci.loa;
  d["lwl"] = ci.lwl;
  d["bwl"] = ci.bwl;
  d["rudder_max"] = ci.rudder_max;
  d["main_sail"] = ci.main_sail;
  d["start_front_sail"] = ci.start_front_sail;
  Array sails;
  for (int32_t i = 0; i < ci.sail_count; ++i) {
    wm_sail_info si;
    if (!ok(wm_perf_sail(p, i, &si))) continue;
    Dictionary s;
    s["id"] = String::utf8(si.id);
    s["type"] = si.type;
    s["sheet_min"] = si.sheet_min;
    s["sheet_max"] = si.sheet_max;
    sails.append(s);
  }
  d["sails"] = sails;
  return d;
}

PackedFloat32Array CoreSim::boat_state(int64_t boat) const {
  settle();
  wm_boat_state s{};
  if (boat_ok(boat)) ok(wm_world_boat_state(world_, i32(boat), &s));
  return floats(s);
}

PackedFloat32Array CoreSim::boat_controls(int64_t boat) const {
  settle();
  wm_boat_controls c{};
  if (boat_ok(boat)) ok(wm_world_boat_controls(world_, i32(boat), &c));
  PackedFloat32Array a;
  a.append(c.h_cmd);
  a.append(c.sheet_cmd);
  a.append(static_cast<float>(c.auto_trim));
  a.append(static_cast<float>(c.let_fly));
  a.append(c.performance_scale);
  return a;
}

PackedFloat32Array CoreSim::boat_outputs(int64_t boat) const {
  settle();
  wm_boat_outputs o{};
  if (boat_ok(boat)) ok(wm_world_boat_outputs(world_, i32(boat), &o));
  return floats(o);
}

PackedFloat32Array CoreSim::boat_env(int64_t boat) const {
  settle();
  wm_boat_env e{};
  if (boat_ok(boat)) ok(wm_world_boat_env(world_, i32(boat), &e));
  PackedFloat32Array a;
  for (float v : {e.wind_speed, e.wind_from, e.wind_speed_clean, e.wind_from_clean, e.current_x, e.current_y,
                  e.shadow_loss, e.shadow_header, static_cast<float>(e.shadow_source)})
    a.append(v);
  return a;
}

PackedFloat32Array CoreSim::render_pose(int64_t boat, double alpha) const {
  settle();
  wm_render_pose p{};
  if (boat_ok(boat)) ok(wm_world_render_pose(world_, i32(boat), f32(alpha), &p));
  return floats(p);
}

// Every boat's render pose at alpha in one array: boat b's fields (POSE_FIELDS) at 9 b.
PackedFloat32Array CoreSim::render_poses(double alpha) const {
  settle();
  PackedFloat32Array a;
  if (world_ == nullptr) return a;
  constexpr int64_t kN = static_cast<int64_t>(sizeof(wm_render_pose) / sizeof(float));
  const int32_t n = wm_world_boat_count(world_);
  a.resize(kN * n);
  float* out = a.ptrw();
  for (int32_t b = 0; b < n; ++b) {
    wm_render_pose p{};
    wm_world_render_pose(world_, b, f32(alpha), &p);
    std::memcpy(out + kN * b, &p, sizeof(p));
  }
  return a;
}

double CoreSim::trim_speed_at(int64_t boat, double tws, double awa_abs, double eps) const {
  settle();
  float v = NAN;
  if (boat_ok(boat)) (void)wm_world_trim_speed_at(world_, i32(boat), f32(tws), f32(awa_abs), f32(eps), &v);
  return v;
}

double CoreSim::perf_table(int64_t boat, int64_t front_sail, const String& name, double x, double y,
                           double w) const {
  settle();
  float v = NAN;
  if (!boat_ok(boat)) return v;
  (void)wm_perf_table(wm_world_boat_perf(world_, i32(boat)), i32(front_sail), name.utf8().get_data(), f32(x), f32(y),
                      f32(w), &v, nullptr);
  return v;
}

double CoreSim::polar(int64_t boat, double tws, double twa, int64_t front_sail) const {
  settle();
  if (!boat_ok(boat)) return NAN;
  return wm_perf_polar(wm_world_boat_perf(world_, i32(boat)), f32(tws), f32(twa), i32(front_sail));
}

Dictionary CoreSim::polar_vmg(int64_t boat, double tws) const {
  settle();
  Dictionary d;
  float us = NAN, ua = NAN, ds = NAN, da = NAN;
  if (!boat_ok(boat) || wm_perf_polar_vmg(wm_world_boat_perf(world_, i32(boat)), f32(tws), &us, &ua, &ds, &da) != WM_OK)
    return d;
  d["up_speed"] = us;
  d["up_twa"] = ua;
  d["down_speed"] = ds;
  d["down_twa"] = da;
  return d;
}

Dictionary CoreSim::sails(int64_t boat) const {
  settle();
  Dictionary d;
  wm_sails s{};
  if (!boat_ok(boat) || !ok(wm_world_sails(world_, i32(boat), &s))) return d;
  d["front"] = s.front;
  d["sail_count"] = s.sail_count;
  d["queue_len"] = s.queue_len;
  d["queue_pos"] = s.queue_pos;
  d["queue_progress"] = s.queue_progress;
  Array q;
  for (int32_t i = 0; i < s.queue_len && i < WM_SAIL_QUEUE_MAX; ++i) {
    Array st;
    st.append(s.queue[i].sail);
    st.append(s.queue[i].phase);
    st.append(s.queue[i].reversed != 0);
    q.append(st);
  }
  d["queue"] = q;
  return d;
}

PackedFloat32Array CoreSim::sail(int64_t boat, int64_t sail) const {
  settle();
  wm_sail s{};
  if (boat_ok(boat)) ok(wm_world_sail(world_, i32(boat), i32(sail), &s));
  PackedFloat32Array a;
  for (float v : {static_cast<float>(s.phase), s.progress, s.beta, s.pole, s.k_h, s.m_opt, s.beta_opt, s.beta_t,
                  s.trim_error, s.luff_shiver, static_cast<float>(s.motion), static_cast<float>(s.backed)})
    a.append(v);
  return a;
}

Array CoreSim::sail_events(int64_t boat) const {
  settle();
  Array out;
  if (!boat_ok(boat)) return out;
  for (int32_t i = 0; i < wm_world_sail_event_count(world_, i32(boat)); ++i) {
    int32_t s = 0, ph = 0;
    wm_world_sail_event(world_, i32(boat), i, &s, &ph);
    Array e;
    e.append(s);
    e.append(ph);
    out.append(e);
  }
  return out;
}

// ---- environment ----------------------------------------------------------------------------------------------

Vector2 CoreSim::wind_clean(double x, double y) {
  settle();
  float s = 0.0f, f = 0.0f;
  if (world_ != nullptr) wm_world_wind_clean(world_, f32(x), f32(y), &s, &f);
  return Vector2(s, f);
}

double CoreSim::wind_global_from() { settle(); return world_ != nullptr ? wm_world_wind_global_from(world_) : 0.0; }

Vector2 CoreSim::current_at(double x, double y, int64_t t_ms) {
  settle();
  float cx = 0.0f, cy = 0.0f;
  if (world_ != nullptr) wm_world_current_at(world_, f32(x), f32(y), static_cast<uint32_t>(t_ms), &cx, &cy);
  return Vector2(cx, cy);
}

Dictionary CoreSim::wind_state(int64_t t_ms) {
  settle();
  Dictionary d;
  if (world_ == nullptr) return d;
  const uint32_t t = static_cast<uint32_t>(t_ms < 0 ? 0 : t_ms);
  wm_wind_state w{};
  wm_world_wind_state(world_, t, &w);
  d["base_speed"] = w.base_speed;
  d["base_from"] = w.base_from;
  d["global_from"] = w.global_from;
  d["puff_tile"] = w.puff_tile;
  d["cap_up"] = w.cap_up;
  d["cap_down"] = w.cap_down;
  d["puffs"] = w.puffs != 0;
  Array patches;
  const int32_t n = wm_world_puffs_at(world_, t, nullptr, 0);
  std::vector<wm_puff> p(static_cast<std::size_t>(n));
  wm_world_puffs_at(world_, t, p.data(), n);
  for (const wm_puff& q : p) {
    Array a;
    a.append(q.px);
    a.append(q.py);
    a.append(q.R);
    a.append(q.s);
    a.append(q.e);
    patches.append(a);
  }
  d["patches"] = patches;
  return d;
}

double CoreSim::sea_height(double x, double y) {
  settle();
  return world_ != nullptr ? wm_world_sea_height(world_, f32(x), f32(y)) : 0.0;
}

double CoreSim::sea_height_at(double x, double y, int64_t t_ms) {
  settle();
  if (world_ == nullptr) return 0.0;
  return wm_world_sea_height_at(world_, f32(x), f32(y), static_cast<uint32_t>(t_ms < 0 ? 0 : t_ms));
}

Vector2 CoreSim::sea_slope(double x, double y) {
  settle();
  float dx = 0.0f, dy = 0.0f;
  if (world_ != nullptr) wm_world_sea_slope(world_, f32(x), f32(y), &dx, &dy);
  return Vector2(dx, dy);
}

Array CoreSim::sea_components() const {
  settle();
  Array out;
  if (world_ == nullptr) return out;
  const int32_t n = wm_world_sea_components(world_, nullptr, 0);
  std::vector<wm_sea_component> c(static_cast<std::size_t>(n));
  wm_world_sea_components(world_, c.data(), n);
  for (const wm_sea_component& k : c) {
    Array a;
    a.append(k.a);
    a.append(k.kx);
    a.append(k.ky);
    a.append(k.c);
    a.append(static_cast<int64_t>(k.T));
    out.append(a);
  }
  return out;
}

Dictionary CoreSim::sea_exposure() const {
  settle();
  Dictionary d;
  wm_exposure_grid g{};
  if (world_ == nullptr || wm_world_sea_exposure_grid(world_, &g) != WM_OK) return d;
  d["x0"] = g.x0;
  d["y0"] = g.y0;
  d["dx"] = g.dx;
  d["dy"] = g.dy;
  d["nx"] = static_cast<int64_t>(g.nx);
  d["ny"] = static_cast<int64_t>(g.ny);
  d["default"] = g.exposure_default;
  PackedFloat32Array e;
  e.resize(static_cast<int64_t>(g.nx) * g.ny);
  for (int64_t i = 0; i < e.size(); ++i) e.set(i, g.e[i]);
  d["e"] = e;
  return d;
}

// ---- course, race and rules -----------------------------------------------------------------------------------

Array CoreSim::venue_land() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_land_count(world_); ++i) {
    wm_land l{};
    wm_world_land(world_, i, &l);
    PackedVector2Array pts;
    for (int32_t k = 0; k < l.point_count; ++k) {
      float x = 0.0f, y = 0.0f;
      wm_world_land_point(world_, i, k, &x, &y);
      pts.append(Vector2(x, y));
    }
    Dictionary d;
    d["id"] = String::utf8(l.id);
    d["points"] = pts;
    out.append(d);
  }
  return out;
}

Array CoreSim::venue_obstacles() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_obstacle_count(world_); ++i) {
    wm_obstacle o{};
    wm_world_obstacle(world_, i, &o);
    PackedVector2Array pts;
    for (int32_t k = 0; k < o.point_count; ++k) {
      float x = 0.0f, y = 0.0f;
      wm_world_obstacle_point(world_, i, k, &x, &y);
      pts.append(Vector2(x, y));
    }
    Dictionary d;
    d["id"] = String::utf8(o.id);
    d["circle"] = o.kind == WM_OBSTACLE_CIRCLE;
    d["points"] = pts;
    d["c"] = Vector2(o.cx, o.cy);
    d["r"] = o.r;
    out.append(d);
  }
  return out;
}

Dictionary CoreSim::course() const {
  settle();
  Dictionary d;
  wm_course_info ci{};
  if (world_ == nullptr || wm_world_course(world_, &ci) != WM_OK) return d;
  d["id"] = String::utf8(ci.id);
  d["twd_c"] = ci.twd_c;
  d["k"] = ci.k;
  d["laps"] = ci.laps;
  d["zone_lengths"] = ci.zone_lengths;
  Array marks;
  for (int32_t i = 0; i < ci.mark_count; ++i) {
    wm_mark m{};
    wm_world_course_mark(world_, i, &m);
    Dictionary md;
    md["id"] = String::utf8(m.id);
    md["type"] = m.type;
    md["x"] = m.x;
    md["y"] = m.y;
    md["radius"] = m.radius;
    md["heading"] = m.heading;
    md["length"] = m.length;
    md["beam"] = m.beam;
    md["zone_r"] = m.zone_r;
    marks.append(md);
  }
  d["marks"] = marks;
  Array steps;
  for (int32_t i = 0; i < ci.step_count; ++i) {
    wm_step s{};
    wm_world_course_step(world_, i, &s);
    Dictionary sd;
    sd["kind"] = s.kind;
    sd["marks"] = PackedInt32Array({s.marks[0], s.marks[1]});
    sd["sides"] = PackedInt32Array({s.sides[0], s.sides[1]});
    sd["gate_cross"] = s.gate_cross != 0;
    sd["lap"] = s.lap;
    sd["leg_in_lap"] = s.leg_in_lap;
    sd["ref"] = Vector2(s.ref_x, s.ref_y);
    steps.append(sd);
  }
  d["steps"] = steps;
  PackedVector2Array boundary;
  for (int32_t i = 0; i < ci.boundary_count; ++i) {
    float x = 0.0f, y = 0.0f;
    wm_world_course_boundary(world_, i, &x, &y);
    boundary.append(Vector2(x, y));
  }
  d["boundary"] = boundary;
  return d;
}

Dictionary CoreSim::race() const {
  settle();
  Dictionary d;
  wm_race_info r{};
  if (world_ == nullptr || wm_world_race(world_, &r) != WM_OK) return d;
  d["state"] = r.state;
  d["race_type"] = r.race_type;
  d["sequence"] = r.sequence;
  d["prep_flag"] = r.prep_flag;
  d["n_created"] = static_cast<int64_t>(r.n_created);
  d["n_gun"] = r.n_gun;
  d["race_time"] = r.race_time;
  d["general_recalls"] = r.general_recalls;
  d["x_flag"] = r.x_flag != 0;
  d["rules_live"] = r.rules_live != 0;
  d["twd_mean"] = r.twd_mean;
  d["L_max"] = r.L_max;
  d["boat_count"] = r.boat_count;
  return d;
}

Dictionary CoreSim::race_boat(int64_t boat) const {
  settle();
  Dictionary d;
  wm_race_boat b{};
  if (world_ == nullptr || wm_world_race_boat(world_, i32(boat), &b) != WM_OK) return d;
  d["started"] = b.started != 0;
  d["t_start"] = b.t_start;
  d["ocs"] = b.ocs != 0;
  d["ocs_i"] = b.ocs_i != 0;
  d["ocs_scored"] = b.ocs_scored != 0;
  d["returning"] = b.returning != 0;
  d["next"] = b.next;
  d["last_rounded"] = b.last_rounded;
  d["finished"] = b.finished != 0;
  d["t_finish_us"] = b.t_finish_us;
  d["place"] = b.place;
  d["ghost"] = b.ghost != 0;
  d["ghost_reason"] = b.ghost_reason;
  d["retired"] = b.retired != 0;
  d["dsq"] = b.dsq != 0;
  d["code"] = b.code;
  d["D"] = b.D;
  d["rank"] = b.rank;
  return d;
}

PackedInt32Array CoreSim::race_order() const {
  settle();
  PackedInt32Array a;
  if (world_ == nullptr) return a;
  const int32_t n = wm_world_race_order(world_, nullptr, 0);
  a.resize(n);
  std::vector<int32_t> v(static_cast<std::size_t>(n));
  wm_world_race_order(world_, v.data(), n);
  for (int32_t i = 0; i < n; ++i) a.set(i, v[static_cast<std::size_t>(i)]);
  return a;
}

Array CoreSim::results() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_result_count(world_); ++i) {
    wm_result r{};
    wm_world_result(world_, i, &r);
    Dictionary d;
    d["boat"] = r.boat;
    d["place"] = r.place;
    d["code"] = r.code;
    d["code_name"] = String::utf8(wm_score_code_name(r.code));
    d["points"] = r.points;
    d["t_finish_us"] = r.t_finish_us;
    d["projected"] = r.projected != 0;
    out.append(d);
  }
  return out;
}

double CoreSim::race_split(int64_t boat, int64_t step) const {
  settle();
  float t = 0.0f;
  if (world_ == nullptr || wm_world_race_split(world_, i32(boat), i32(step), &t) != WM_OK) return NAN;
  return t;
}

Dictionary CoreSim::race_start_status(int64_t boat) const {
  settle();
  Dictionary d;
  wm_start_status st{};
  if (world_ == nullptr || wm_world_race_start_status(world_, i32(boat), &st) != WM_OK) return d;
  d["a"] = Vector2(st.ax, st.ay);
  d["b"] = Vector2(st.bx, st.by);
  d["s_bow"] = st.s_bow;
  d["u_bow"] = st.u_bow;
  d["in_band"] = st.in_band != 0;
  d["course_side"] = st.course_side != 0;
  d["in_triangle"] = st.in_triangle != 0;
  d["pre_start"] = st.pre_start != 0;
  d["over"] = st.over != 0;
  return d;
}

Dictionary CoreSim::boat_rules(int64_t boat) const {
  settle();
  Dictionary d;
  wm_boat_rules r{};
  if (world_ == nullptr || wm_world_boat_rules(world_, i32(boat), &r) != WM_OK) return d;
  d["tack"] = r.tack;
  d["tacking"] = r.tacking != 0;
  d["turning_for_penalty"] = r.turning_for_penalty != 0;
  d["turn_progress"] = r.turn_progress;
  d["turn_tacks"] = r.turn_tacks;
  d["turn_gybes"] = r.turn_gybes;
  d["served"] = r.served;
  d["received"] = r.received;
  d["deadline_s"] = r.deadline_s;
  d["returning_to_start"] = r.returning_to_start != 0;
  d["dsq"] = r.dsq != 0;
  d["out_of_bounds"] = r.out_of_bounds != 0;
  Array pending;
  for (int32_t i = 0; i < r.pending; ++i) {
    wm_penalty p{};
    wm_world_boat_penalty(world_, i32(boat), i, &p);
    Dictionary pd;
    pd["rule"] = p.rule;
    pd["rule_name"] = String::utf8(wm_rule_code_name(p.rule));
    pd["other"] = p.other;
    pd["tick"] = static_cast<int64_t>(p.tick);
    pd["count"] = p.count;
    pending.append(pd);
  }
  d["pending"] = pending;
  return d;
}

Array CoreSim::pairs() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_pair_count(world_); ++i) {
    wm_pair p{};
    wm_world_pair(world_, i, &p);
    Dictionary d;
    d["i"] = p.i;
    d["j"] = p.j;
    d["relation"] = p.relation;
    d["kc_giver"] = p.kc_giver;
    d["kc_holder"] = p.kc_holder;
    d["kc_rule"] = p.kc_rule;
    d["kc_state"] = p.kc_state;
    d["room_entitled"] = p.room_entitled;
    d["room_giver"] = p.room_giver;
    d["room_rule"] = p.room_rule;
    d["room_mark"] = p.room_mark;
    d["room_state"] = p.room_state;
    d["rule17_holder"] = p.rule17_holder;
    d["incident"] = p.incident != 0;
    d["incident_culprit"] = p.incident_culprit;
    d["incident_rule"] = p.incident_rule;
    d["incident_tick"] = static_cast<int64_t>(p.incident_tick);
    d["gap"] = p.gap;
    d["ttc"] = p.ttc;
    out.append(d);
  }
  return out;
}

Array CoreSim::race_events() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_race_event_count(world_); ++i) {
    wm_race_event e{};
    wm_world_race_event(world_, i, &e);
    Dictionary d;
    d["kind"] = e.kind;
    d["tick"] = static_cast<int64_t>(e.tick);
    d["boat"] = e.boat;
    d["signal"] = e.signal;
    d["flag"] = e.flag;
    d["step"] = e.step;
    d["buoy"] = e.buoy;
    d["t"] = e.t;
    d["t_us"] = e.t_us;
    d["place"] = e.place;
    d["block"] = e.block;
    d["ghost"] = e.ghost;
    d["value"] = e.value;
    out.append(d);
  }
  return out;
}

Array CoreSim::rules_events() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_rules_event_count(world_); ++i) {
    wm_rules_event e{};
    wm_world_rules_event(world_, i, &e);
    Dictionary d;
    d["kind"] = e.kind;
    d["tick"] = static_cast<int64_t>(e.tick);
    d["boat"] = e.boat;
    d["other"] = e.other;
    d["rule"] = e.rule;
    d["rule_name"] = String::utf8(wm_rule_code_name(e.rule));
    d["count"] = e.count;
    d["contact"] = e.contact != 0;
    d["mark"] = e.mark;
    d["deadline"] = e.deadline;
    out.append(d);
  }
  return out;
}

Array CoreSim::contact_events() const {
  settle();
  Array out;
  for (int32_t i = 0; i < wm_world_contact_event_count(world_); ++i) {
    wm_contact_event e{};
    wm_world_contact_event(world_, i, &e);
    Dictionary d;
    d["tick"] = static_cast<int64_t>(e.tick);
    d["boat"] = e.boat;
    d["other_kind"] = e.other_kind;
    d["other"] = e.other;
    d["point"] = Vector2(e.point_x, e.point_y);
    d["normal"] = Vector2(e.normal_x, e.normal_y);
    d["depth"] = e.depth;
    d["closing_speed"] = e.closing_speed;
    d["impulse"] = e.impulse;
    d["begin"] = e.begin != 0;
    out.append(d);
  }
  return out;
}

String CoreSim::rule_code_name(int64_t rule) { return String::utf8(wm_rule_code_name(i32(rule))); }
String CoreSim::score_code_name(int64_t code) { return String::utf8(wm_score_code_name(i32(code))); }

// ---- binding --------------------------------------------------------------------------------------------------

void CoreSim::_bind_methods() {
  ClassDB::bind_static_method("CoreSim", D_METHOD("default_settings"), &CoreSim::default_settings);
  ClassDB::bind_method(D_METHOD("create", "settings", "venue_path"), &CoreSim::create);
  ClassDB::bind_method(D_METHOD("is_created"), &CoreSim::is_created);
  ClassDB::bind_method(D_METHOD("add_boat", "perf_path", "entry"), &CoreSim::add_boat);
  ClassDB::bind_method(D_METHOD("place_boat", "boat", "x", "y", "psi"), &CoreSim::place_boat);
  ClassDB::bind_method(D_METHOD("scenario_place", "boat", "x", "y", "psi", "v", "front_sail"),
                       &CoreSim::scenario_place);
  ClassDB::bind_method(D_METHOD("create_race", "course_path"), &CoreSim::create_race);
  ClassDB::bind_method(D_METHOD("last_error"), &CoreSim::last_error);
  ClassDB::bind_method(D_METHOD("api_version"), &CoreSim::api_version);

  ClassDB::bind_method(D_METHOD("apply_input", "boat", "h_cmd", "sheet_cmd", "sail_req", "flags"),
                       &CoreSim::apply_input);
  ClassDB::bind_method(D_METHOD("set_helm", "boat", "h"), &CoreSim::set_helm);
  ClassDB::bind_method(D_METHOD("set_sheet", "boat", "s"), &CoreSim::set_sheet);
  ClassDB::bind_method(D_METHOD("set_auto_trim", "boat", "on"), &CoreSim::set_auto_trim);
  ClassDB::bind_method(D_METHOD("set_let_fly", "boat", "on"), &CoreSim::set_let_fly);
  ClassDB::bind_method(D_METHOD("hoist", "boat", "sail"), &CoreSim::hoist);
  ClassDB::bind_method(D_METHOD("drop_front", "boat"), &CoreSim::drop_front);
  ClassDB::bind_method(D_METHOD("retire", "boat"), &CoreSim::retire);
  ClassDB::bind_method(D_METHOD("protest", "boat"), &CoreSim::protest);
  ClassDB::bind_static_method("CoreSim", D_METHOD("encode_input", "h_cmd", "sheet_cmd", "sail_req", "flags"),
                              &CoreSim::encode_input);

  ClassDB::bind_method(D_METHOD("add_ai_boat", "perf_path", "level", "speed_only"), &CoreSim::add_ai_boat);
  ClassDB::bind_method(D_METHOD("ai_add", "boat", "level", "speed_only"), &CoreSim::ai_add);
  ClassDB::bind_method(D_METHOD("ai_take_over", "boat"), &CoreSim::ai_take_over);
  ClassDB::bind_method(D_METHOD("ai_release", "boat"), &CoreSim::ai_release);
  ClassDB::bind_method(D_METHOD("ai_add_autopilot", "boat"), &CoreSim::ai_add_autopilot);
  ClassDB::bind_method(D_METHOD("ai_has", "boat"), &CoreSim::ai_has);
  ClassDB::bind_method(D_METHOD("ai_count"), &CoreSim::ai_count);
  ClassDB::bind_method(D_METHOD("ai_telemetry", "boat"), &CoreSim::ai_telemetry);
  ClassDB::bind_method(D_METHOD("ai_debug", "boat"), &CoreSim::ai_debug);
  ClassDB::bind_static_method("CoreSim", D_METHOD("ai_performance_scale", "level"), &CoreSim::ai_performance_scale);
  ClassDB::bind_static_method("CoreSim", D_METHOD("ai_tactic_name", "tactic"), &CoreSim::ai_tactic_name);
  ClassDB::bind_method(D_METHOD("save_world"), &CoreSim::save_world);
  ClassDB::bind_method(D_METHOD("load_world", "course_path", "bytes"), &CoreSim::load_world);
  ClassDB::bind_method(D_METHOD("ai_save"), &CoreSim::ai_save);
  ClassDB::bind_method(D_METHOD("ai_load", "bytes"), &CoreSim::ai_load);

  ClassDB::bind_method(D_METHOD("step"), &CoreSim::step);
  ClassDB::bind_method(D_METHOD("step_ticks", "n", "stop_when_closed"), &CoreSim::step_ticks);
  ClassDB::bind_method(D_METHOD("step_begin"), &CoreSim::step_begin);
  ClassDB::bind_method(D_METHOD("step_end"), &CoreSim::step_end);
  ClassDB::bind_method(D_METHOD("is_stepping"), &CoreSim::is_stepping);
  ClassDB::bind_method(D_METHOD("checksum"), &CoreSim::checksum);
  ClassDB::bind_method(D_METHOD("tick"), &CoreSim::tick);
  ClassDB::bind_method(D_METHOD("boat_count"), &CoreSim::boat_count);
  ClassDB::bind_method(D_METHOD("has_race"), &CoreSim::has_race);
  ClassDB::bind_method(D_METHOD("time_ms"), &CoreSim::time_ms);
  ClassDB::bind_method(D_METHOD("render_time_ms", "alpha"), &CoreSim::render_time_ms);

  ClassDB::bind_method(D_METHOD("class_info", "boat"), &CoreSim::class_info);
  ClassDB::bind_method(D_METHOD("boat_state", "boat"), &CoreSim::boat_state);
  ClassDB::bind_method(D_METHOD("boat_controls", "boat"), &CoreSim::boat_controls);
  ClassDB::bind_method(D_METHOD("boat_outputs", "boat"), &CoreSim::boat_outputs);
  ClassDB::bind_method(D_METHOD("boat_env", "boat"), &CoreSim::boat_env);
  ClassDB::bind_method(D_METHOD("render_pose", "boat", "alpha"), &CoreSim::render_pose);
  ClassDB::bind_method(D_METHOD("render_poses", "alpha"), &CoreSim::render_poses);
  ClassDB::bind_method(D_METHOD("trim_speed_at", "boat", "tws", "awa_abs", "eps"), &CoreSim::trim_speed_at);
  ClassDB::bind_method(D_METHOD("perf_table", "boat", "front_sail", "name", "x", "y", "w"), &CoreSim::perf_table);
  ClassDB::bind_method(D_METHOD("polar", "boat", "tws", "twa", "front_sail"), &CoreSim::polar);
  ClassDB::bind_method(D_METHOD("polar_vmg", "boat", "tws"), &CoreSim::polar_vmg);
  ClassDB::bind_method(D_METHOD("sails", "boat"), &CoreSim::sails);
  ClassDB::bind_method(D_METHOD("sail", "boat", "sail"), &CoreSim::sail);
  ClassDB::bind_method(D_METHOD("sail_events", "boat"), &CoreSim::sail_events);

  ClassDB::bind_method(D_METHOD("wind_clean", "x", "y"), &CoreSim::wind_clean);
  ClassDB::bind_method(D_METHOD("wind_global_from"), &CoreSim::wind_global_from);
  ClassDB::bind_method(D_METHOD("current_at", "x", "y", "t_ms"), &CoreSim::current_at);
  ClassDB::bind_method(D_METHOD("wind_state", "t_ms"), &CoreSim::wind_state);
  ClassDB::bind_method(D_METHOD("sea_height", "x", "y"), &CoreSim::sea_height);
  ClassDB::bind_method(D_METHOD("sea_height_at", "x", "y", "t_ms"), &CoreSim::sea_height_at);
  ClassDB::bind_method(D_METHOD("sea_slope", "x", "y"), &CoreSim::sea_slope);
  ClassDB::bind_method(D_METHOD("sea_components"), &CoreSim::sea_components);
  ClassDB::bind_method(D_METHOD("sea_exposure"), &CoreSim::sea_exposure);

  ClassDB::bind_method(D_METHOD("venue_land"), &CoreSim::venue_land);
  ClassDB::bind_method(D_METHOD("venue_obstacles"), &CoreSim::venue_obstacles);
  ClassDB::bind_method(D_METHOD("course"), &CoreSim::course);
  ClassDB::bind_method(D_METHOD("race"), &CoreSim::race);
  ClassDB::bind_method(D_METHOD("race_boat", "boat"), &CoreSim::race_boat);
  ClassDB::bind_method(D_METHOD("race_order"), &CoreSim::race_order);
  ClassDB::bind_method(D_METHOD("results"), &CoreSim::results);
  ClassDB::bind_method(D_METHOD("race_split", "boat", "step"), &CoreSim::race_split);
  ClassDB::bind_method(D_METHOD("race_start_status", "boat"), &CoreSim::race_start_status);
  ClassDB::bind_method(D_METHOD("boat_rules", "boat"), &CoreSim::boat_rules);
  ClassDB::bind_method(D_METHOD("pairs"), &CoreSim::pairs);
  ClassDB::bind_method(D_METHOD("race_events"), &CoreSim::race_events);
  ClassDB::bind_method(D_METHOD("rules_events"), &CoreSim::rules_events);
  ClassDB::bind_method(D_METHOD("contact_events"), &CoreSim::contact_events);
  ClassDB::bind_static_method("CoreSim", D_METHOD("rule_code_name", "rule"), &CoreSim::rule_code_name);
  ClassDB::bind_static_method("CoreSim", D_METHOD("score_code_name", "code"), &CoreSim::score_code_name);
}

}  // namespace windmark_godot
