#include "core_sim.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cmath>

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

CoreSim::~CoreSim() {
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
  return boat_ok(boat) && ok(wm_world_place_boat(world_, i32(boat), f32(x), f32(y), f32(psi)));
}

bool CoreSim::create_race(const String& course_path) {
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
  if (!boat_ok(boat)) return WM_REQUEST_NONE;
  const wm_input_frame f{f32(h_cmd), f32(sheet_cmd), static_cast<uint8_t>(sail_req & 0xFF),
                         static_cast<uint8_t>(flags & 0xFF)};
  int32_t r = WM_REQUEST_NONE;
  if (!ok(wm_world_apply_input(world_, i32(boat), &f, &r))) return WM_REQUEST_NONE;
  return r;
}

bool CoreSim::set_helm(int64_t b, double h) { return boat_ok(b) && ok(wm_world_set_helm(world_, i32(b), f32(h))); }
bool CoreSim::set_sheet(int64_t b, double s) { return boat_ok(b) && ok(wm_world_set_sheet(world_, i32(b), f32(s))); }
bool CoreSim::set_auto_trim(int64_t b, bool on) { return boat_ok(b) && ok(wm_world_set_auto_trim(world_, i32(b), on)); }
bool CoreSim::set_let_fly(int64_t b, bool on) { return boat_ok(b) && ok(wm_world_set_let_fly(world_, i32(b), on)); }
int64_t CoreSim::hoist(int64_t b, int64_t sail) {
  int32_t r = WM_REQUEST_NONE;
  if (boat_ok(b)) ok(wm_world_hoist(world_, i32(b), i32(sail), &r));
  return r;
}
int64_t CoreSim::drop_front(int64_t b) {
  int32_t r = WM_REQUEST_NONE;
  if (boat_ok(b)) ok(wm_world_drop_front(world_, i32(b), &r));
  return r;
}
bool CoreSim::retire(int64_t b) { return boat_ok(b) && ok(wm_world_retire(world_, i32(b))); }
bool CoreSim::protest(int64_t b) { return boat_ok(b) && ok(wm_world_protest(world_, i32(b))); }

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

int64_t CoreSim::step() { return world_ != nullptr ? static_cast<int64_t>(wm_world_step(world_)) : 0; }
int64_t CoreSim::checksum() const { return static_cast<int64_t>(wm_world_checksum(world_)); }
int64_t CoreSim::tick() const { return wm_world_tick(world_); }
int64_t CoreSim::boat_count() const { return wm_world_boat_count(world_); }
bool CoreSim::has_race() const { return wm_world_has_race(world_) != 0; }
int64_t CoreSim::time_ms() const { return wm_world_time_ms(world_); }
double CoreSim::render_time_ms(double alpha) const { return wm_world_render_time_ms(world_, f32(alpha)); }

// ---- boats ----------------------------------------------------------------------------------------------------

Dictionary CoreSim::class_info(int64_t boat) const {
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
  wm_boat_state s{};
  if (boat_ok(boat)) ok(wm_world_boat_state(world_, i32(boat), &s));
  return floats(s);
}

PackedFloat32Array CoreSim::boat_controls(int64_t boat) const {
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
  wm_boat_outputs o{};
  if (boat_ok(boat)) ok(wm_world_boat_outputs(world_, i32(boat), &o));
  return floats(o);
}

PackedFloat32Array CoreSim::boat_env(int64_t boat) const {
  wm_boat_env e{};
  if (boat_ok(boat)) ok(wm_world_boat_env(world_, i32(boat), &e));
  PackedFloat32Array a;
  for (float v : {e.wind_speed, e.wind_from, e.wind_speed_clean, e.wind_from_clean, e.current_x, e.current_y,
                  e.shadow_loss, e.shadow_header, static_cast<float>(e.shadow_source)})
    a.append(v);
  return a;
}

PackedFloat32Array CoreSim::render_pose(int64_t boat, double alpha) const {
  wm_render_pose p{};
  if (boat_ok(boat)) ok(wm_world_render_pose(world_, i32(boat), f32(alpha), &p));
  return floats(p);
}

double CoreSim::trim_speed_at(int64_t boat, double tws, double awa_abs, double eps) const {
  float v = NAN;
  if (boat_ok(boat)) (void)wm_world_trim_speed_at(world_, i32(boat), f32(tws), f32(awa_abs), f32(eps), &v);
  return v;
}

double CoreSim::perf_table(int64_t boat, int64_t front_sail, const String& name, double x, double y,
                           double w) const {
  float v = NAN;
  if (!boat_ok(boat)) return v;
  (void)wm_perf_table(wm_world_boat_perf(world_, i32(boat)), i32(front_sail), name.utf8().get_data(), f32(x), f32(y),
                      f32(w), &v, nullptr);
  return v;
}

double CoreSim::polar(int64_t boat, double tws, double twa, int64_t front_sail) const {
  if (!boat_ok(boat)) return NAN;
  return wm_perf_polar(wm_world_boat_perf(world_, i32(boat)), f32(tws), f32(twa), i32(front_sail));
}

Dictionary CoreSim::polar_vmg(int64_t boat, double tws) const {
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
  wm_sail s{};
  if (boat_ok(boat)) ok(wm_world_sail(world_, i32(boat), i32(sail), &s));
  PackedFloat32Array a;
  for (float v : {static_cast<float>(s.phase), s.progress, s.beta, s.pole, s.k_h, s.m_opt, s.beta_opt, s.beta_t,
                  s.trim_error, s.luff_shiver, static_cast<float>(s.motion), static_cast<float>(s.backed)})
    a.append(v);
  return a;
}

Array CoreSim::sail_events(int64_t boat) const {
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
  float s = 0.0f, f = 0.0f;
  if (world_ != nullptr) wm_world_wind_clean(world_, f32(x), f32(y), &s, &f);
  return Vector2(s, f);
}

double CoreSim::wind_global_from() { return world_ != nullptr ? wm_world_wind_global_from(world_) : 0.0; }

Vector2 CoreSim::current_at(double x, double y, int64_t t_ms) {
  float cx = 0.0f, cy = 0.0f;
  if (world_ != nullptr) wm_world_current_at(world_, f32(x), f32(y), static_cast<uint32_t>(t_ms), &cx, &cy);
  return Vector2(cx, cy);
}

Dictionary CoreSim::wind_state(int64_t t_ms) {
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
  return world_ != nullptr ? wm_world_sea_height(world_, f32(x), f32(y)) : 0.0;
}

double CoreSim::sea_height_at(double x, double y, int64_t t_ms) {
  if (world_ == nullptr) return 0.0;
  return wm_world_sea_height_at(world_, f32(x), f32(y), static_cast<uint32_t>(t_ms < 0 ? 0 : t_ms));
}

Vector2 CoreSim::sea_slope(double x, double y) {
  float dx = 0.0f, dy = 0.0f;
  if (world_ != nullptr) wm_world_sea_slope(world_, f32(x), f32(y), &dx, &dy);
  return Vector2(dx, dy);
}

Array CoreSim::sea_components() const {
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
  Dictionary d;
  wm_course_info ci{};
  if (world_ == nullptr || wm_world_course(world_, &ci) != WM_OK) return d;
  d["id"] = String::utf8(ci.id);
  d["twd_c"] = ci.twd_c;
  d["k"] = ci.k;
  d["laps"] = ci.laps;
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

Dictionary CoreSim::boat_rules(int64_t boat) const {
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

  ClassDB::bind_method(D_METHOD("step"), &CoreSim::step);
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
  ClassDB::bind_method(D_METHOD("boat_rules", "boat"), &CoreSim::boat_rules);
  ClassDB::bind_method(D_METHOD("pairs"), &CoreSim::pairs);
  ClassDB::bind_method(D_METHOD("race_events"), &CoreSim::race_events);
  ClassDB::bind_method(D_METHOD("rules_events"), &CoreSim::rules_events);
  ClassDB::bind_method(D_METHOD("contact_events"), &CoreSim::contact_events);
  ClassDB::bind_static_method("CoreSim", D_METHOD("rule_code_name", "rule"), &CoreSim::rule_code_name);
  ClassDB::bind_static_method("CoreSim", D_METHOD("score_code_name", "code"), &CoreSim::score_code_name);
}

}  // namespace windmark_godot
