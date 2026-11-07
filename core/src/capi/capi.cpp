// The C API (include/windmark.h) over the world (world/world.h). A thin layer: handles own shared data, the world
// wrapper keeps the per-tick copies the readers need (the state before the last step for the render pose, the
// environment at the current time for point queries) and never changes what the world computes.
#include "windmark.h"

#include <cmath>
#include <cstring>
#include <memory>
#include <span>
#include <string>
#include <vector>

#include "ai/ai.h"
#include "course/course.h"
#include "course/geometry.h"
#include "data/perf.h"
#include "data/venue.h"
#include "math/wm_math.h"
#include "race/conditions.h"
#include "world/world.h"

struct wm_perf {
  std::shared_ptr<const wm::PerfData> p;
};
struct wm_venue {
  std::shared_ptr<const wm::VenueData> v;
};
struct wm_course {
  std::shared_ptr<const wm::CourseData> c;
};

struct wm_world {
  std::shared_ptr<const wm::VenueData> venue;
  std::vector<std::shared_ptr<const wm::PerfData>> perfs;       // every class a boat uses, by boat
  std::vector<std::unique_ptr<wm_perf>> perf_handles;          // by boat, for wm_world_boat_perf
  std::shared_ptr<const wm::CourseData> course;
  std::unique_ptr<wm::World> world;
  // Point queries at the current time: a second wind field with the same seed and settings (identical bits,
  // wind.md §4.3) and the sea surface of that time, so the world's own caches are never touched.
  std::unique_ptr<wm::WindField> wind;
  std::uint32_t wind_t = 0xFFFFFFFFu;
  wm::SeaTick sea_tick;
  std::uint32_t sea_t = 0xFFFFFFFFu;
  wm::SeaTick sea_tick_any;  // the last other time asked for (render clock, fractional ms)
  double sea_t_any = -1.0;
  wm::WindTick wind_r;       // the wind at the last fractional render time (wind.md §9)
  double wind_r_t = -1.0;
  std::vector<wm::BoatState> prev;  // state before the last step
  // Sail requests of the coming tick, answered on a copy of the sails (see wm_world_apply_input).
  std::vector<wm::Sails> req_sails;
  std::vector<std::uint8_t> req_valid;
  std::vector<std::uint8_t> last_flags;
  wm_controller_fn controller = nullptr;
  void* controller_user = nullptr;
  // The AI skippers (ai.md), run in step 2 before the host's controller once any boat was given to them.
  std::unique_ptr<wm::AiSkippers> ai = std::make_unique<wm::AiSkippers>();
  bool ai_used = false;
  std::vector<std::uint8_t> world_snapshot;  // the last wm_world_save
  std::vector<std::uint8_t> ai_snapshot;     // the last wm_world_ai_save
};

namespace {

thread_local std::string g_error;

wm_status fail(wm_status s, std::string msg) {
  g_error = std::move(msg);
  return s;
}

bool bad_boat(const wm_world* w, std::int32_t b) {
  return w == nullptr || b < 0 || static_cast<std::size_t>(b) >= w->world->boat_count();
}

wm_status boat_arg(const wm_world* w, std::int32_t b, const void* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (bad_boat(w, b)) return fail(WM_ERR_ARG, "boat index " + std::to_string(b) + " out of range");
  return WM_OK;
}

std::string read_text(const std::string& path, bool& ok) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  ok = f != nullptr;
  std::string s;
  if (!ok) return s;
  char buf[65536];
  std::size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, n);
  std::fclose(f);
  return s;
}

const wm::WindTick& wind_at(wm_world* w, std::uint32_t t) {
  if (w->wind_t != t) {
    (void)w->wind->advance(t);
    w->wind_t = t;
  }
  return w->wind->current_tick();
}

const wm::WindTick& wind_now(wm_world* w) { return wind_at(w, w->world->t_ms()); }

// A render time (ms, fractional) as its whole millisecond n and the fraction f in [0, 1): NaN and negative
// times are 0, times past the clock's range its last millisecond.
struct RenderTime {
  std::uint32_t n;
  double f;
};
RenderTime render_time(double t) {
  if (!(t > 0.0)) return {0u, 0.0};
  if (t >= 4294967295.0) return {0xFFFFFFFFu, 0.0};
  const double n = std::floor(t);
  return {static_cast<std::uint32_t>(n), t - n};
}

// wind.md §9 render time: the tick at n with its direction and its patches (same generation) lerped toward n + 1.
const wm::WindTick& wind_render(wm_world* w, double t_ms) {
  const RenderTime r = render_time(t_ms);
  if (r.f == 0.0) return wind_at(w, r.n);
  const double key = static_cast<double>(r.n) + r.f;
  if (w->wind_r_t == key) return w->wind_r;
  w->wind_r = wind_at(w, r.n);
  const wm::WindTick& b = wind_at(w, r.n + 1);
  const float f = static_cast<float>(r.f);
  w->wind_r.global_from = wm::angle_lerp(w->wind_r.global_from, b.global_from, f);
  for (std::size_t j = 0; j < w->wind_r.slots.size() && j < b.slots.size(); ++j) {
    wm::PuffPatch& p = w->wind_r.slots[j];
    const wm::PuffPatch& q = b.slots[j];
    if (p.generation != q.generation) continue;
    p.px = wm::lerp(p.px, q.px, f);
    p.py = wm::lerp(p.py, q.py, f);
    p.e = wm::lerp(p.e, q.e, f);
  }
  w->wind_r_t = key;
  return w->wind_r;
}

const wm::SeaTick* sea_now(wm_world* w) {
  const wm::SeaField* sea = w->world->sea();
  if (sea == nullptr) return nullptr;
  const std::uint32_t t = w->world->t_ms();
  if (w->sea_t != t) {
    w->sea_tick = sea->at(t);
    w->sea_t = t;
  }
  return &w->sea_tick;
}

void sync_boats(wm_world* w) {
  const std::size_t n = w->world->boat_count();
  while (w->prev.size() < n) w->prev.push_back(w->world->boat(w->prev.size()).state());
  w->req_sails.resize(n);
  w->req_valid.resize(n, 0);
  w->last_flags.resize(n, 0);
}

// Step 2 of the world: the AI skippers, then the host's callback. Installed only when one of them is set.
void install_controller(wm_world* w) {
  if (w->controller == nullptr && !w->ai_used) {
    w->world->set_controller(nullptr);
    return;
  }
  w->world->set_controller([w](wm::World& world) {
    if (w->ai_used) w->ai->step(world);
    if (w->controller != nullptr) w->controller(w, w->controller_user);
  });
}

void refresh_prev(wm_world* w) {
  for (std::size_t i = 0; i < w->world->boat_count(); ++i) w->prev[i] = w->world->boat(i).state();
}

wm::Sails& req_sails(wm_world* w, std::int32_t b) {
  const std::size_t i = static_cast<std::size_t>(b);
  if (!w->req_valid[i]) {
    w->req_sails[i] = w->world->boat(i).sails();
    w->req_valid[i] = 1;
  }
  return w->req_sails[i];
}

const wm::ConfigPerf* config(const wm::PerfData& p, std::int32_t front) { return p.config_for(front); }

wm_status trim_speed(const wm::ConfigPerf* c, float tws, float awa_abs, float eps, float* out) {
  if (c == nullptr || !c->trim_speed.present) {
    *out = NAN;
    return fail(WM_ERR_ABSENT, "the config has no trim_speed table");
  }
  *out = c->trim_speed.table.at(tws, awa_abs, eps);
  return WM_OK;
}

template <class T>
wm_status load_into(const char* path, const char* json, std::size_t len, const char* name, T** out,
                    auto&& parse) {
  if (out == nullptr) return fail(WM_ERR_ARG, "null argument");
  *out = nullptr;
  std::string text;
  std::string file;
  if (path != nullptr) {
    bool ok = false;
    file = path;
    text = read_text(file, ok);
    if (!ok) return fail(WM_ERR_LOAD, file + ": cannot read the file");
  } else {
    if (json == nullptr) return fail(WM_ERR_ARG, "null argument");
    text.assign(json, len);
    file = name != nullptr ? name : "<memory>";
  }
  wm::LoadError err;
  T* h = parse(text, file, err);
  if (h == nullptr) return fail(WM_ERR_LOAD, err.message());
  *out = h;
  return WM_OK;
}

}  // namespace

// The C enums mirror the core's numbering.
static_assert(WM_PHASE_DROPPING == static_cast<int>(wm::SailPhase::dropping));
static_assert(WM_RACE_ABANDONED == static_cast<int>(wm::RaceState::abandoned));
static_assert(WM_SCORE_DSQ == static_cast<int>(wm::ScoreCode::DSQ));
static_assert(WM_GHOST_LEFT == static_cast<int>(wm::GhostReason::left));
static_assert(WM_RULE_SI_BOUNDARY == static_cast<int>(wm::RuleCode::si_boundary));
static_assert(WM_EV_ABANDONED == static_cast<int>(wm::RaceEventKind::abandoned));
static_assert(WM_REV_DISQUALIFIED == static_cast<int>(wm::RulesEventKind::disqualified));
static_assert(WM_SIGNAL_X_DOWN == static_cast<int>(wm::SignalKind::x_down));
static_assert(WM_CONTACT_LAND == static_cast<int>(wm::ContactKind::land));
static_assert(WM_MARK_VIRTUAL == static_cast<int>(wm::MarkType::virtual_point));
static_assert(WM_STEP_FINISH == static_cast<int>(wm::StepKind::finish));
static_assert(WM_FLAG_BLACK == static_cast<int>(wm::PrepFlag::black));
static_assert(WM_SEQUENCE_MATCH == static_cast<int>(wm::SequenceKind::match));
static_assert(WM_UMPIRE_PROTEST == static_cast<int>(wm::UmpireMode::protest));
static_assert(WM_SAIL_SPINNAKER_ASYM == static_cast<int>(wm::SailType::spinnaker_asym));
static_assert(WM_SHIFT_UNSTABLE == static_cast<int>(wm::ShiftPreset::unstable));
static_assert(WM_REL_OVERLAPPED_VIA == static_cast<int>(wm::Relation::overlapped_via));
static_assert(WM_SAIL_QUEUE_MAX == wm::Sails::kQueueMax);

extern "C" {

int32_t wm_api_version(void) { return WM_API_VERSION; }
const char* wm_last_error(void) { return g_error.c_str(); }

// ---- data ---------------------------------------------------------------------------------------------------

namespace {
wm_perf* make_perf(const std::string& t, const std::string& f, wm::LoadError& e) {
  auto p = std::make_shared<wm::PerfData>();
  if (!wm::parse_perf(t, f, *p, e)) return nullptr;
  return new wm_perf{std::move(p)};
}
}  // namespace

wm_status wm_perf_load(const char* path, wm_perf** out) {
  if (path == nullptr) return fail(WM_ERR_ARG, "null argument");
  return load_into<wm_perf>(path, nullptr, 0, nullptr, out, make_perf);
}

wm_status wm_perf_parse(const char* json, size_t len, const char* name, wm_perf** out) {
  return load_into<wm_perf>(nullptr, json, len, name, out, make_perf);
}

void wm_perf_free(wm_perf* p) { delete p; }

namespace {
wm_venue* make_venue(const std::string& t, const std::string& f, wm::LoadError& e) {
  auto v = std::make_shared<wm::VenueData>();
  if (!wm::parse_venue(t, f, *v, e)) return nullptr;
  return new wm_venue{std::move(v)};
}
wm_course* make_course(const std::string& t, const std::string& f, wm::LoadError& e) {
  auto c = std::make_shared<wm::CourseData>();
  if (!wm::parse_course(t, f, *c, e)) return nullptr;
  return new wm_course{std::move(c)};
}
}  // namespace

wm_status wm_venue_load(const char* path, wm_venue** out) {
  if (path == nullptr) return fail(WM_ERR_ARG, "null argument");
  return load_into<wm_venue>(path, nullptr, 0, nullptr, out, make_venue);
}
wm_status wm_venue_parse(const char* json, size_t len, const char* name, wm_venue** out) {
  return load_into<wm_venue>(nullptr, json, len, name, out, make_venue);
}
void wm_venue_free(wm_venue* v) { delete v; }

wm_status wm_course_load(const char* path, wm_course** out) {
  if (path == nullptr) return fail(WM_ERR_ARG, "null argument");
  return load_into<wm_course>(path, nullptr, 0, nullptr, out, make_course);
}
wm_status wm_course_parse(const char* json, size_t len, const char* name, wm_course** out) {
  return load_into<wm_course>(nullptr, json, len, name, out, make_course);
}
void wm_course_free(wm_course* c) { delete c; }

wm_status wm_perf_info(const wm_perf* h, wm_class_info* out) {
  if (h == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::PerfData& p = *h->p;
  out->class_id = p.class_id.c_str();
  out->file_sha256 = p.file_sha256.c_str();
  out->loa = p.dynamics.loa;
  out->lwl = p.dynamics.lwl;
  out->bwl = p.dynamics.bwl;
  out->rudder_max = p.dynamics.rudder_max;
  out->sail_count = static_cast<int32_t>(p.sails.size());
  out->main_sail = p.main_sail;
  out->start_front_sail = p.start_front_sail;
  return WM_OK;
}

wm_status wm_perf_sail(const wm_perf* h, int32_t sail, wm_sail_info* out) {
  if (h == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (sail < 0 || static_cast<std::size_t>(sail) >= h->p->sails.size()) return fail(WM_ERR_ARG, "bad sail index");
  const wm::SailPerf& s = h->p->sails[static_cast<std::size_t>(sail)];
  out->id = s.id.c_str();
  out->type = static_cast<int32_t>(s.type);
  out->sheet_min = s.sheet_min;
  out->sheet_max = s.sheet_max;
  return WM_OK;
}

float wm_perf_polar(const wm_perf* h, float tws, float twa, int32_t front_sail) {
  if (h == nullptr) return NAN;
  const wm::ConfigPerf* c = config(*h->p, front_sail);
  return c != nullptr ? c->polar.at(tws, std::fabs(twa)) : 0.0f;
}

wm_status wm_perf_polar_vmg(const wm_perf* h, float tws, float* up_speed, float* up_twa, float* down_speed,
                            float* down_twa) {
  if (h == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::PolarVmg v = wm::polar_vmg(*h->p, tws);
  if (up_speed) *up_speed = v.up_speed;
  if (up_twa) *up_twa = v.up_twa;
  if (down_speed) *down_speed = v.down_speed;
  if (down_twa) *down_twa = v.down_twa;
  return WM_OK;
}

wm_status wm_perf_trim_speed(const wm_perf* h, int32_t front_sail, float tws, float awa_abs, float eps, float* out) {
  if (h == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  return trim_speed(config(*h->p, front_sail), tws, awa_abs, eps, out);
}

wm_status wm_perf_table(const wm_perf* h, int32_t front_sail, const char* name, float x, float y, float w,
                        float* out, int32_t* rank) {
  if (h == nullptr || name == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  *out = NAN;
  if (rank != nullptr) *rank = 0;
  const wm::ConfigPerf* c = config(*h->p, front_sail);
  if (c == nullptr) return fail(WM_ERR_ARG, "no config for that front sail");
  const std::string n(name);
  const wm::Table* t = nullptr;
  const wm::OptionalTable* o = nullptr;
  if (n == "polar") t = &c->polar;
  else if (n == "heel") t = &c->heel;
  else if (n == "accel") t = &c->accel;
  else if (n == "optimal_main") t = &c->optimal_main;
  else if (n == "optimal_front") t = &c->optimal_front;
  else if (n == "accel_rest") o = &c->accel_rest;
  else if (n == "trim_speed") o = &c->trim_speed;
  else if (n == "trim_heel") o = &c->trim_heel;
  else if (n == "weather_helm") o = &c->weather_helm;
  else if (n == "fall_off") o = &c->fall_off;
  else if (n == "flog_drag") o = &c->flog_drag;
  else return fail(WM_ERR_ARG, "unknown table " + n);
  if (o != nullptr) {
    if (!o->present) return fail(WM_ERR_ABSENT, "the config has no " + n + " table");
    t = &o->table;
  }
  if (t->empty()) return fail(WM_ERR_ABSENT, "the config has no " + n + " table");
  if (rank != nullptr) *rank = static_cast<int32_t>(t->rank());
  switch (t->rank()) {
    case 1: *out = t->at(x); break;
    case 2: *out = t->at(x, y); break;
    default: *out = t->at(x, y, w); break;
  }
  return WM_OK;
}

// ---- world set-up -------------------------------------------------------------------------------------------

namespace {

// The explicit environment fields of wm_world_settings to and from the core's settings.
void puff_out(const wm::PuffParams& q, wm_puff_params& o) {
  o.tile = q.tile;
  o.puff_count = static_cast<int32_t>(q.puff_count);
  o.lull_count = static_cast<int32_t>(q.lull_count);
  o.diameter_min = q.diameter_min;
  o.diameter_max = q.diameter_max;
  o.puff_strength_min = q.puff_strength_min;
  o.puff_strength_max = q.puff_strength_max;
  o.lull_strength_min = q.lull_strength_min;
  o.lull_strength_max = q.lull_strength_max;
  o.life_min_ms = q.life_min_ms;
  o.life_max_ms = q.life_max_ms;
  o.cap_up = q.cap_up;
  o.cap_down = q.cap_down;
}

bool puff_in(const wm_puff_params& o, wm::PuffParams& q) {
  if (o.puff_count < 0 || o.lull_count < 0 || o.puff_count > 64 || o.lull_count > 64) return false;
  q.tile = o.tile;
  q.puff_count = static_cast<std::uint32_t>(o.puff_count);
  q.lull_count = static_cast<std::uint32_t>(o.lull_count);
  q.diameter_min = o.diameter_min;
  q.diameter_max = o.diameter_max;
  q.puff_strength_min = o.puff_strength_min;
  q.puff_strength_max = o.puff_strength_max;
  q.lull_strength_min = o.lull_strength_min;
  q.lull_strength_max = o.lull_strength_max;
  q.life_min_ms = o.life_min_ms;
  q.life_max_ms = o.life_max_ms;
  q.cap_up = o.cap_up;
  q.cap_down = o.cap_down;
  return true;
}

void env_out(const wm::WindSettings& w, const wm::SeaSettings& sea, wm_world_settings* s) {
  s->wind_speed = w.base_speed;
  s->wind_from = w.base_from;
  s->shift_preset = WM_SHIFT_DEFAULT;
  s->shift_amplitude = w.shift_amplitude;
  s->shift_hold_max_ms = w.shift_hold_max_ms;
  s->shift_hold_min_ms = w.shift_hold_min_ms;
  s->shift_trend_rate = w.shift_trend_rate;
  s->shift_trend_max = w.shift_trend_max;
  s->oscillation = w.osc_enabled ? 1 : 0;
  s->osc_amplitude = w.osc_amplitude;
  s->osc_time_scale = w.osc_time_scale;
  s->puffs = w.puffs_enabled ? 1 : 0;
  s->puff_preset = WM_PUFFS_DEFAULT;
  puff_out(w.puffs, s->puff);
  s->current_speed = w.current_speed;
  s->current_to = w.current_to;
  s->tide_scale = w.tide_scale;
  s->tide_period_ms = w.tide_period_ms;
  s->tide_phase_ms = w.tide_phase_ms;
  s->sea_scale = sea.sea_scale;
  s->swell_count = static_cast<int32_t>(sea.swells.size());
  for (std::size_t i = 0; i < 4; ++i) {
    const wm::WaveTrain t = i < sea.swells.size() ? sea.swells[i] : wm::WaveTrain{};
    s->swells[i] = {t.hs, t.tp, t.from};
  }
}

void race_in(const wm_world_settings* s, wm::RaceSettings& r) {
  r = wm::RaceSettings{};
  if (s->race_type >= 0) r.race_type = static_cast<wm::RaceType>(s->race_type);
  if (s->sequence >= 0) r.sequence = static_cast<wm::SequenceKind>(s->sequence);
  if (s->prep_flag >= 0) r.prep_flag = static_cast<wm::PrepFlag>(s->prep_flag);
  r.free_sailing_s = s->free_sailing_s;
  r.general_recall = s->general_recall != 0;
  r.rules_level = static_cast<wm::RulesLevel>(s->rules_level);
  r.penalty = static_cast<wm::PenaltyKind>(s->penalty);
  r.umpire = static_cast<wm::UmpireMode>(s->umpire);
  r.time_limit_s = s->time_limit_s;
  r.finish_window = s->finish_window != 0;
  r.start_limit_s = s->start_limit_s;
}

const char* check_settings_enums(const wm_world_settings* s) {
  if (s->shift_preset < WM_SHIFT_DEFAULT || s->shift_preset > WM_SHIFT_UNSTABLE) return "bad shift preset";
  if (s->puff_preset < WM_PUFFS_DEFAULT || s->puff_preset > WM_PUFFS_GUSTY) return "bad puff preset";
  if (s->race_type < -1 || s->race_type > WM_RACE_MATCH) return "bad race type";
  if (s->sequence < -1 || s->sequence > WM_SEQUENCE_MATCH) return "bad sequence";
  if (s->prep_flag < -1 || s->prep_flag > WM_FLAG_BLACK) return "bad preparatory flag";
  if (s->rules_level < 0 || s->rules_level > WM_RULES_FULL) return "bad rules level";
  if (s->penalty != WM_PENALTY_ONE_TURN) return "bad penalty (one turn only)";
  if (s->umpire < 0 || s->umpire > WM_UMPIRE_PROTEST) return "bad umpire mode";
  if (s->swell_count < 0 || s->swell_count > 4) return "bad swell count";
  return nullptr;
}

}  // namespace

void wm_world_settings_init(wm_world_settings* s) {
  if (s == nullptr) return;
  std::memset(s, 0, sizeof *s);
  const wm::WindSettings wd;
  const wm::SeaSettings sd;
  const wm::RaceSettings rd;
  s->race_seed = 1;
  s->wind_speed = wd.base_speed;
  s->wind_from = wd.base_from;
  s->shift_preset = WM_SHIFT_DEFAULT;
  s->shift_trend_rate = wd.shift_trend_rate;
  s->puffs = wd.puffs_enabled ? 1 : 0;
  s->oscillation = wd.osc_enabled ? 1 : 0;
  s->current_speed = wd.current_speed;
  s->current_to = wd.current_to;
  s->sea = 1;
  s->sea_scale = sd.sea_scale;
  s->shadows = 1;
  s->weather_helm = 0;
  s->race_type = -1;
  s->sequence = -1;
  s->prep_flag = -1;
  s->free_sailing_s = rd.free_sailing_s;
  s->general_recall = rd.general_recall ? 1 : 0;
  s->rules_level = static_cast<int32_t>(rd.rules_level);
  s->penalty = static_cast<int32_t>(rd.penalty);
  s->umpire = static_cast<int32_t>(rd.umpire);
  s->time_limit_s = rd.time_limit_s;
  s->finish_window = rd.finish_window ? 1 : 0;
  s->start_limit_s = rd.start_limit_s;
  env_out(wd, sd, s);
  s->shift_preset = WM_SHIFT_DEFAULT;
  s->weather = WM_WEATHER_LOCAL;
}

wm_status wm_world_settings_resolve(wm_world_settings* s, const wm_venue* venue, const wm_course* course) {
  if (s == nullptr || venue == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (const char* why = check_settings_enums(s)) return fail(WM_ERR_ARG, why);
  if (s->weather < WM_WEATHER_LOCAL || s->weather > WM_WEATHER_CUSTOM) return fail(WM_ERR_ARG, "bad weather mode");
  if (!(s->wind_speed >= 0.0f) || !std::isfinite(s->wind_speed) || !std::isfinite(s->wind_from))
    return fail(WM_ERR_ARG, "bad wind");
  wm::WeatherChoice c;
  c.mode = static_cast<wm::WeatherMode>(s->weather);
  c.speed = s->wind_speed;
  c.from = s->wind_from;
  c.has_shift = s->shift_preset != WM_SHIFT_DEFAULT;
  if (c.has_shift) c.shift = static_cast<wm::ShiftPreset>(s->shift_preset);
  c.has_puffs = s->puff_preset != WM_PUFFS_DEFAULT;
  if (c.has_puffs) c.puffs = static_cast<wm::PuffPreset>(s->puff_preset);
  wm::RaceSettings race;
  race_in(s, race);
  const wm::RaceTiming timing = wm::race_timing(race, course != nullptr ? course->c.get() : nullptr);
  wm::WindSettings w;
  wm::SeaSettings sea;
  std::string error;
  if (!wm::resolve_weather(*venue->v, c, s->race_seed, timing, w, sea, error)) return fail(WM_ERR_ARG, error);
  env_out(w, sea, s);
  return WM_OK;
}

wm_status wm_world_create(const wm_world_settings* s, const wm_venue* venue, wm_world** out) {
  if (s == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  *out = nullptr;
  if (const char* why = check_settings_enums(s)) return fail(WM_ERR_ARG, why);
  if (!(s->wind_speed >= 0.0f) || !std::isfinite(s->wind_speed) || !std::isfinite(s->wind_from))
    return fail(WM_ERR_ARG, "bad wind");

  auto h = std::make_unique<wm_world>();
  if (venue != nullptr) h->venue = venue->v;
  wm::WorldSetup ws;
  ws.venue = h->venue.get();
  ws.race_seed = s->race_seed;
  ws.wind.base_speed = s->wind_speed;
  ws.wind.base_from = wm::wrap_2pi(s->wind_from);
  ws.wind.shift_amplitude = s->shift_amplitude;
  ws.wind.shift_hold_max_ms = s->shift_hold_max_ms;
  ws.wind.shift_hold_min_ms = s->shift_hold_min_ms;
  if (s->shift_preset != WM_SHIFT_DEFAULT) wm::apply_shift_preset(ws.wind, static_cast<wm::ShiftPreset>(s->shift_preset));
  ws.wind.shift_trend_rate = s->shift_trend_rate;
  ws.wind.shift_trend_max = s->shift_trend_max;
  ws.wind.osc_enabled = s->oscillation != 0;
  ws.wind.osc_amplitude = s->osc_amplitude;
  ws.wind.osc_time_scale = s->osc_time_scale;
  if (!puff_in(s->puff, ws.wind.puffs)) return fail(WM_ERR_ARG, "bad puff counts");
  ws.wind.puffs_enabled = s->puffs != 0;
  if (s->puff_preset != WM_PUFFS_DEFAULT) wm::apply_puff_preset(ws.wind, static_cast<wm::PuffPreset>(s->puff_preset));
  ws.wind.current_speed = s->current_speed;
  ws.wind.current_to = s->current_to;
  ws.wind.tide_scale = s->tide_scale;
  ws.wind.tide_period_ms = s->tide_period_ms;
  ws.wind.tide_phase_ms = s->tide_phase_ms;
  if (const char* why = wm::check_wind_settings(ws.wind)) return fail(WM_ERR_ARG, std::string("wind: ") + why);
  ws.sea = s->sea != 0;
  ws.sea_settings.sea_scale = s->sea_scale;
  for (int32_t i = 0; i < s->swell_count; ++i) ws.sea_settings.swells.push_back({s->swells[i].hs, s->swells[i].tp, s->swells[i].from});
  if (const char* why = wm::check_sea_settings(ws.sea_settings)) return fail(WM_ERR_ARG, std::string("sea: ") + why);
  ws.shadows = s->shadows != 0;
  ws.weather_helm = s->weather_helm != 0;
  race_in(s, ws.race);
  h->world = std::make_unique<wm::World>(ws);
  h->wind = std::make_unique<wm::WindField>(ws.race_seed, h->world->wind().settings());
  *out = h.release();
  return WM_OK;
}

void wm_world_free(wm_world* w) { delete w; }

void wm_boat_entry_init(wm_boat_entry* e, const wm_perf* perf) {
  if (e == nullptr) return;
  const wm::BoatEntry d;
  e->perf = perf;
  e->human = d.human ? 1 : 0;
  e->ai = d.ai ? 1 : 0;
  e->performance_scale = d.performance_scale;
  e->auto_trim = d.auto_trim ? 1 : 0;
  e->front_sail = d.front_sail;
}

wm_status wm_world_add_boat(wm_world* w, const wm_boat_entry* e, int32_t* index) {
  if (w == nullptr || e == nullptr || e->perf == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::PerfData& p = *e->perf->p;
  if (e->front_sail < -2 || e->front_sail >= static_cast<int32_t>(p.sails.size()) || e->front_sail == p.main_sail)
    return fail(WM_ERR_ARG, "bad front sail");
  wm::BoatEntry be;
  be.perf = &p;
  be.human = e->human != 0;
  be.ai = e->ai != 0;
  be.performance_scale = e->performance_scale;
  be.auto_trim = e->auto_trim != 0;
  be.front_sail = e->front_sail;
  const std::int32_t i = w->world->add_boat(be);
  if (i < 0) return fail(WM_ERR_FULL, "the race takes no more boats");
  w->perfs.push_back(e->perf->p);
  w->perf_handles.push_back(std::make_unique<wm_perf>(wm_perf{e->perf->p}));
  sync_boats(w);
  w->prev[static_cast<std::size_t>(i)] = w->world->boat(static_cast<std::size_t>(i)).state();
  if (index != nullptr) *index = i;
  return WM_OK;
}

wm_status wm_world_place_boat(wm_world* w, int32_t boat, float x, float y, float psi) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(psi)) return fail(WM_ERR_ARG, "bad placement");
  if (!w->world->place_boat(boat, {x, y}, psi)) return fail(WM_ERR_STATE, "boats are placed by the race");
  w->prev[static_cast<std::size_t>(boat)] = w->world->boat(static_cast<std::size_t>(boat)).state();
  w->req_valid[static_cast<std::size_t>(boat)] = 0;
  return WM_OK;
}

wm_status wm_world_scenario_place(wm_world* w, int32_t boat, float x, float y, float psi, float v,
                                  int32_t front_sail) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(psi) || !std::isfinite(v) || v < 0.0f)
    return fail(WM_ERR_ARG, "bad placement");
  const wm::PerfData& p = *w->perfs[static_cast<std::size_t>(boat)];
  if (front_sail < -2 || front_sail >= static_cast<int32_t>(p.sails.size()) || front_sail == p.main_sail)
    return fail(WM_ERR_ARG, "bad front sail");
  w->world->place_boat(boat, x, y, psi, v, front_sail);
  w->prev[static_cast<std::size_t>(boat)] = w->world->boat(static_cast<std::size_t>(boat)).state();
  w->req_valid[static_cast<std::size_t>(boat)] = 0;
  return WM_OK;
}

wm_status wm_world_create_race(wm_world* w, const wm_course* course) {
  if (w == nullptr || course == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (w->world->race_created()) return fail(WM_ERR_STATE, "the race exists already");
  std::string err;
  if (!w->world->create_race(*course->c, err)) {
    return fail(w->venue == nullptr || w->world->boat_count() == 0 ? WM_ERR_STATE : WM_ERR_LOAD, err);
  }
  w->course = course->c;
  refresh_prev(w);
  std::fill(w->req_valid.begin(), w->req_valid.end(), 0);
  return WM_OK;
}

// ---- controls -----------------------------------------------------------------------------------------------

void wm_input_encode(const wm_input_frame* f, uint8_t out[6]) {
  if (f == nullptr || out == nullptr) return;
  const float h = std::isnan(f->h_cmd) ? 0.0f : wm::clamp(f->h_cmd, -1.0f, 1.0f);
  const float s = std::isnan(f->sheet_cmd) ? 0.0f : wm::clamp(f->sheet_cmd, 0.0f, 1.0f);
  const std::int16_t hq = static_cast<std::int16_t>(std::nearbyint(h * 32767.0f));
  const std::uint16_t sq = static_cast<std::uint16_t>(std::nearbyint(s * 65535.0f));
  out[0] = static_cast<uint8_t>(static_cast<std::uint16_t>(hq) & 0xFF);
  out[1] = static_cast<uint8_t>(static_cast<std::uint16_t>(hq) >> 8);
  out[2] = static_cast<uint8_t>(sq & 0xFF);
  out[3] = static_cast<uint8_t>(sq >> 8);
  out[4] = f->sail_req;
  out[5] = f->flags;
}

void wm_input_decode(const uint8_t in[6], wm_input_frame* out) {
  if (in == nullptr || out == nullptr) return;
  const std::int16_t hq = static_cast<std::int16_t>(static_cast<std::uint16_t>(in[0] | (in[1] << 8)));
  const std::uint16_t sq = static_cast<std::uint16_t>(in[2] | (in[3] << 8));
  out->h_cmd = wm::clamp(static_cast<float>(hq) / 32767.0f, -1.0f, 1.0f);
  out->sheet_cmd = static_cast<float>(sq) / 65535.0f;
  out->sail_req = in[4];
  out->flags = in[5];
}

wm_status wm_world_apply_input(wm_world* w, int32_t boat, const wm_input_frame* f, int32_t* request) {
  if (f == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  wm::World& world = *w->world;
  world.set_helm(boat, f->h_cmd);
  world.set_sheet(boat, f->sheet_cmd);
  world.set_let_fly(boat, (f->flags & WM_INPUT_LET_FLY) != 0);
  world.set_auto_trim(boat, (f->flags & WM_INPUT_AUTO_TRIM) != 0);
  int32_t r = WM_REQUEST_NONE;
  if (f->sail_req == WM_SAIL_REQ_DROP_FRONT) {
    r = static_cast<int32_t>(req_sails(w, boat).drop_front());
    world.drop_front(boat);
  } else if (f->sail_req >= 1 && f->sail_req <= 15) {
    r = static_cast<int32_t>(req_sails(w, boat).hoist(f->sail_req - 1));
    world.hoist(boat, f->sail_req - 1);
  }
  // The protest flag acts on its rising edge (one protest per press).
  std::uint8_t& last = w->last_flags[static_cast<std::size_t>(boat)];
  if ((f->flags & WM_INPUT_PROTEST) != 0 && (last & WM_INPUT_PROTEST) == 0) world.protest(boat);
  last = f->flags;
  if (request != nullptr) *request = r;
  return WM_OK;
}

wm_status wm_world_set_helm(wm_world* w, int32_t boat, float h) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->world->set_helm(boat, h);
  return WM_OK;
}
wm_status wm_world_set_sheet(wm_world* w, int32_t boat, float s) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->world->set_sheet(boat, s);
  return WM_OK;
}
wm_status wm_world_set_auto_trim(wm_world* w, int32_t boat, int32_t on) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->world->set_auto_trim(boat, on != 0);
  return WM_OK;
}
wm_status wm_world_set_let_fly(wm_world* w, int32_t boat, int32_t on) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->world->set_let_fly(boat, on != 0);
  return WM_OK;
}
wm_status wm_world_hoist(wm_world* w, int32_t boat, int32_t sail, int32_t* request) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  const int32_t r = static_cast<int32_t>(req_sails(w, boat).hoist(sail));
  w->world->hoist(boat, sail);
  if (request != nullptr) *request = r;
  return WM_OK;
}
wm_status wm_world_drop_front(wm_world* w, int32_t boat, int32_t* request) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  const int32_t r = static_cast<int32_t>(req_sails(w, boat).drop_front());
  w->world->drop_front(boat);
  if (request != nullptr) *request = r;
  return WM_OK;
}
wm_status wm_world_retire(wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  if (!w->world->race_created()) return fail(WM_ERR_STATE, "no race");
  w->world->retire(boat);
  return WM_OK;
}
wm_status wm_world_protest(wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  if (!w->world->race_created()) return fail(WM_ERR_STATE, "no race");
  w->world->protest(boat);
  return WM_OK;
}

void wm_world_set_controller(wm_world* w, wm_controller_fn fn, void* user) {
  if (w == nullptr) return;
  w->controller = fn;
  w->controller_user = user;
  install_controller(w);
}

// ---- stepping -----------------------------------------------------------------------------------------------

void wm_world_step(wm_world* w) {
  if (w == nullptr) return;
  refresh_prev(w);
  w->world->step();
  std::fill(w->req_valid.begin(), w->req_valid.end(), 0);
}

uint64_t wm_world_checksum(const wm_world* w) { return w != nullptr ? w->world->checksum() : 0; }
uint32_t wm_world_tick(const wm_world* w) { return w != nullptr ? w->world->tick() : 0; }
int32_t wm_world_boat_count(const wm_world* w) {
  return w != nullptr ? static_cast<int32_t>(w->world->boat_count()) : 0;
}
int32_t wm_world_has_race(const wm_world* w) { return w != nullptr && w->world->race_created() ? 1 : 0; }

// ---- AI skippers --------------------------------------------------------------------------------------------

static_assert(WM_AI_PRO == static_cast<int>(wm::AiLevel::pro));
static_assert(WM_AI_TACTIC_LAND == static_cast<int>(wm::AiTactic::Land));
static_assert(WM_AI_TACTIC_COUNT == wm::kAiTacticCount);

namespace {
bool bad_level(int32_t level) { return level < WM_AI_EASY || level > WM_AI_PRO; }
wm::AiLevel ai_level(int32_t level) { return static_cast<wm::AiLevel>(level); }
void ai_on(wm_world* w) {
  if (!w->ai_used) {
    w->ai_used = true;
    install_controller(w);
  }
}
}  // namespace

const char* wm_ai_tactic_name(int32_t tactic) {
  if (tactic < 0 || tactic >= WM_AI_TACTIC_COUNT) return "?";
  return wm::ai_tactic_name(static_cast<wm::AiTactic>(tactic));
}

float wm_ai_performance_scale(int32_t level) {
  return bad_level(level) ? NAN : wm::ai_level_params(ai_level(level)).performance_scale;
}

void wm_ai_entry_init(wm_boat_entry* e, const wm_perf* perf, int32_t level) {
  if (e == nullptr) return;
  wm_boat_entry_init(e, perf);
  if (perf == nullptr || bad_level(level)) return;
  const wm::BoatEntry d = wm::ai_entry(perf->p.get(), ai_level(level));
  e->human = d.human ? 1 : 0;
  e->ai = d.ai ? 1 : 0;
  e->performance_scale = d.performance_scale;
  e->auto_trim = d.auto_trim ? 1 : 0;
  e->front_sail = d.front_sail;
}

wm_status wm_world_add_ai_boat(wm_world* w, const wm_perf* perf, int32_t level, int32_t speed_only,
                               int32_t* index) {
  if (w == nullptr || perf == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (bad_level(level)) return fail(WM_ERR_ARG, "bad AI level");
  wm_boat_entry e;
  wm_ai_entry_init(&e, perf, level);
  int32_t i = -1;
  if (const wm_status st = wm_world_add_boat(w, &e, &i); st != WM_OK) return st;
  w->ai->add(i, ai_level(level), speed_only != 0);
  w->ai->prepare(*perf->p);
  ai_on(w);
  if (index != nullptr) *index = i;
  return WM_OK;
}

wm_status wm_world_ai_add(wm_world* w, int32_t boat, int32_t level, int32_t speed_only) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  if (bad_level(level)) return fail(WM_ERR_ARG, "bad AI level");
  w->ai->add(boat, ai_level(level), speed_only != 0);
  w->ai->prepare(w->world->boat(static_cast<std::size_t>(boat)).perf());
  ai_on(w);
  return WM_OK;
}

wm_status wm_world_ai_take_over(wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->ai->take_over(boat);
  w->ai->prepare(w->world->boat(static_cast<std::size_t>(boat)).perf());
  ai_on(w);
  return WM_OK;
}

wm_status wm_world_ai_release(wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->ai->release(boat);
  return WM_OK;
}

wm_status wm_world_ai_add_autopilot(wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  w->ai->add_autopilot(boat);
  ai_on(w);
  return WM_OK;
}

int32_t wm_world_ai_has(const wm_world* w, int32_t boat) {
  return !bad_boat(w, boat) && w->ai->has(boat) ? 1 : 0;
}

int32_t wm_world_ai_count(const wm_world* w) {
  if (w == nullptr) return 0;
  int32_t n = 0;
  for (std::size_t i = 0; i < w->world->boat_count(); ++i) n += w->ai->has(static_cast<std::int32_t>(i)) ? 1 : 0;
  return n;
}

namespace {
// A boat the skippers know (added, taken over or autopilot, even when released): its records are kept.
bool ai_known(const wm_world* w, int32_t boat) {
  const wm::AiTelemetry& none = w->ai->telemetry(-1);
  return &w->ai->telemetry(boat) != &none;
}
}  // namespace

wm_status wm_world_ai_telemetry(const wm_world* w, int32_t boat, wm_ai_telemetry* out) {
  if (const wm_status s = boat_arg(w, boat, out); s != WM_OK) return s;
  std::memset(out, 0, sizeof *out);
  if (!ai_known(w, boat)) return fail(WM_ERR_ABSENT, "no AI sailed this boat");
  const wm::AiTelemetry& t = w->ai->telemetry(boat);
  out->tacks = t.tacks;
  out->gybes = t.gybes;
  out->penalties = t.penalties;
  out->ocs = t.ocs;
  for (std::size_t k = 0; k < wm::kAiTacticCount; ++k) out->activations[k] = t.activations[k];
  out->stuck_s = t.stuck_s;
  out->min_gap = t.min_gap;
  out->sail_changes = t.sail_changes;
  out->bad_air_count = static_cast<int32_t>(t.bad_air.size());
  out->start_delay = t.start_delay;
  return WM_OK;
}

wm_status wm_world_ai_debug(const wm_world* w, int32_t boat, wm_ai_debug* out) {
  if (const wm_status s = boat_arg(w, boat, out); s != WM_OK) return s;
  std::memset(out, 0, sizeof *out);
  if (!ai_known(w, boat)) return fail(WM_ERR_ABSENT, "no AI sailed this boat");
  const wm::AiDebug& d = w->ai->debug(boat);
  out->tactic = static_cast<int32_t>(d.tactic);
  out->psi_target = d.psi_target;
  out->d = d.d;
  out->twd_ref = d.twd_ref;
  out->twd_f = d.twd_f;
  out->tws_f = d.tws_f;
  out->leg = d.leg;
  out->manoeuvre = d.manoeuvre;
  out->aim_x = d.aim.x;
  out->aim_y = d.aim.y;
  out->spot_x = d.spot.x;
  out->spot_y = d.spot.y;
  return WM_OK;
}

wm_status wm_world_ai_bad_air(const wm_world* w, int32_t boat, int32_t i, uint32_t* tick, float* d_at,
                              float* d_after) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  const auto& v = w->ai->telemetry(boat).bad_air;
  if (i < 0 || static_cast<std::size_t>(i) >= v.size()) return fail(WM_ERR_ARG, "bad record index");
  const wm::AiBadAirRecord& r = v[static_cast<std::size_t>(i)];
  if (tick != nullptr) *tick = r.tick;
  if (d_at != nullptr) *d_at = r.d_at;
  if (d_after != nullptr) *d_after = r.d_after;
  return WM_OK;
}

// ---- snapshots ----------------------------------------------------------------------------------------------

wm_status wm_world_save(wm_world* w, const uint8_t** data, size_t* size) {
  if (w == nullptr || data == nullptr || size == nullptr) return fail(WM_ERR_ARG, "null argument");
  wm::SnapshotWriter sw;
  w->world->save(sw);
  w->world_snapshot = sw.bytes();
  *data = w->world_snapshot.data();
  *size = w->world_snapshot.size();
  return WM_OK;
}

wm_status wm_world_load(wm_world* w, const wm_course* course, const uint8_t* data, size_t size) {
  if (w == nullptr || (data == nullptr && size > 0)) return fail(WM_ERR_ARG, "null argument");
  std::string err;
  if (!w->world->load(std::span<const std::uint8_t>(data, size), course != nullptr ? course->c.get() : nullptr, err))
    return fail(WM_ERR_LOAD, "world snapshot: " + err);
  if (w->world->race_created() && course != nullptr) w->course = course->c;
  refresh_prev(w);
  std::fill(w->req_valid.begin(), w->req_valid.end(), 0);
  install_controller(w);
  return WM_OK;
}

wm_status wm_world_ai_save(wm_world* w, const uint8_t** data, size_t* size) {
  if (w == nullptr || data == nullptr || size == nullptr) return fail(WM_ERR_ARG, "null argument");
  wm::SnapshotWriter sw;
  w->ai->save(sw, *w->world);
  w->ai_snapshot = sw.bytes();
  *data = w->ai_snapshot.data();
  *size = w->ai_snapshot.size();
  return WM_OK;
}

wm_status wm_world_ai_load(wm_world* w, const uint8_t* data, size_t size) {
  if (w == nullptr || (data == nullptr && size > 0)) return fail(WM_ERR_ARG, "null argument");
  auto fresh = std::make_unique<wm::AiSkippers>();
  std::string err;
  if (!fresh->load(std::span<const std::uint8_t>(data, size), *w->world, err))
    return fail(WM_ERR_LOAD, "AI memory: " + err);
  w->ai = std::move(fresh);
  w->ai_used = true;
  install_controller(w);
  return WM_OK;
}

// ---- boats --------------------------------------------------------------------------------------------------

const wm_perf* wm_world_boat_perf(const wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return nullptr;
  return w->perf_handles[static_cast<std::size_t>(boat)].get();
}

static void copy_state(const wm::BoatState& s, wm_boat_state* o) {
  static_assert(sizeof(wm_boat_state) == sizeof(wm::BoatState));
  o->pos_x = s.pos_x; o->pos_y = s.pos_y; o->z = s.z; o->psi = s.psi; o->v = s.v; o->sway = s.sway; o->h = s.h; o->yaw_rate = s.yaw_rate;
  o->phi = s.phi; o->phi_rate = s.phi_rate; o->theta = s.theta; o->theta_rate = s.theta_rate;
  o->wobble_phase = s.wobble_phase;
  o->contact_vx = s.contact_vx; o->contact_vy = s.contact_vy; o->contact_yaw_rate = s.contact_yaw_rate;
  o->twd_from = s.twd_from; o->awd_from = s.awd_from; o->tws = s.tws; o->twa = s.twa; o->aws = s.aws;
  o->awa = s.awa; o->v_filt = s.v_filt; o->sog_filt_x = s.sog_filt_x; o->sog_filt_y = s.sog_filt_y;
}

wm_status wm_world_boat_state(const wm_world* w, int32_t boat, wm_boat_state* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  copy_state(w->world->boat(static_cast<std::size_t>(boat)).state(), out);
  return WM_OK;
}

wm_status wm_world_boat_controls(const wm_world* w, int32_t boat, wm_boat_controls* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const wm::BoatControls& c = w->world->boat(static_cast<std::size_t>(boat)).controls();
  out->h_cmd = c.h_cmd;
  out->sheet_cmd = c.sheet_cmd;
  out->auto_trim = c.auto_trim ? 1 : 0;
  out->let_fly = c.let_fly ? 1 : 0;
  out->performance_scale = c.performance_scale;
  return WM_OK;
}

wm_status wm_world_boat_outputs(const wm_world* w, int32_t boat, wm_boat_outputs* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const wm::BoatOutputs& o = w->world->boat(static_cast<std::size_t>(boat)).outputs();
  out->target_speed = o.target_speed; out->polar_speed = o.polar_speed; out->heel_target = o.heel_target;
  out->turn_rate = o.turn_rate; out->vmg = o.vmg; out->sog = o.sog; out->cog = o.cog;
  out->man_coef = o.man_coef; out->trim_speed = o.trim_speed; out->trim_heel = o.trim_heel;
  out->heel_coef = o.heel_coef; out->surf_coef = o.surf_coef; out->wind_speed_clean = o.wind_speed_clean;
  return WM_OK;
}

wm_status wm_world_boat_env(const wm_world* w, int32_t boat, wm_boat_env* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const wm::EnvAtBoat& e = w->world->env(static_cast<std::size_t>(boat));
  out->wind_speed = e.wind_speed; out->wind_from = e.wind_from;
  out->wind_speed_clean = e.wind_speed_clean; out->wind_from_clean = e.wind_from_clean;
  out->current_x = e.current_x; out->current_y = e.current_y;
  out->shadow_loss = e.shadow_loss; out->shadow_header = e.shadow_header;
  out->shadow_source = e.shadow_source;
  return WM_OK;
}

wm_status wm_world_render_pose(const wm_world* w, int32_t boat, float alpha, wm_render_pose* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const float t = std::isnan(alpha) ? 1.0f : wm::clamp(alpha, 0.0f, 1.0f);
  const wm::BoatState& a = w->prev[static_cast<std::size_t>(boat)];
  const wm::BoatState& b = w->world->boat(static_cast<std::size_t>(boat)).state();
  out->pos_x = wm::lerp(a.pos_x, b.pos_x, t);
  out->pos_y = wm::lerp(a.pos_y, b.pos_y, t);
  out->z = wm::lerp(a.z, b.z, t);
  out->psi = wm::angle_lerp(a.psi, b.psi, t);
  out->theta = wm::lerp(a.theta, b.theta, t);
  out->phi = wm::lerp(a.phi, b.phi, t);
  out->h = wm::lerp(a.h, b.h, t);
  out->twa = wm::wrap_pi(a.twa + t * wm::angle_diff(b.twa, a.twa));
  out->twd_from = wm::angle_lerp(a.twd_from, b.twd_from, t);
  return WM_OK;
}

wm_status wm_world_trim_speed_at(const wm_world* w, int32_t boat, float tws, float awa_abs, float eps, float* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  return trim_speed(&w->world->boat(static_cast<std::size_t>(boat)).sails().config(), tws, awa_abs, eps, out);
}

// ---- sails --------------------------------------------------------------------------------------------------

wm_status wm_world_sails(const wm_world* w, int32_t boat, wm_sails* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const wm::Sails& sl = w->world->boat(static_cast<std::size_t>(boat)).sails();
  std::memset(out, 0, sizeof *out);
  out->front = sl.front();
  out->sail_count = static_cast<int32_t>(sl.sail_count());
  out->queue_len = sl.queue_len();
  out->queue_pos = sl.queue_pos();
  out->queue_progress = sl.queue_progress();
  for (std::size_t i = 0; i < sl.queue_len() && i < wm::Sails::kQueueMax; ++i) {
    const wm::SailStep& st = sl.queue_step(i);
    out->queue[i] = {st.sail, static_cast<int32_t>(st.phase), st.reversed};
  }
  return WM_OK;
}

wm_status wm_world_sail(const wm_world* w, int32_t boat, int32_t sail, wm_sail* out) {
  if (wm_status s = boat_arg(w, boat, out)) return s;
  const wm::Sails& sl = w->world->boat(static_cast<std::size_t>(boat)).sails();
  if (sail < 0 || static_cast<std::size_t>(sail) >= sl.sail_count()) return fail(WM_ERR_ARG, "bad sail index");
  const wm::SailState& st = sl.sail(static_cast<std::size_t>(sail));
  const wm::SailOutput& o = sl.output(static_cast<std::size_t>(sail));
  out->phase = static_cast<int32_t>(st.phase);
  out->progress = st.progress;
  out->beta = st.beta;
  out->pole = st.pole;
  out->k_h = o.k_h;
  out->m_opt = o.m_opt;
  out->beta_opt = o.beta_opt;
  out->beta_t = o.beta_t;
  out->trim_error = o.trim_error;
  out->luff_shiver = o.luff_shiver;
  out->motion = static_cast<int32_t>(o.motion);
  out->backed = o.backed ? 1 : 0;
  return WM_OK;
}

int32_t wm_world_sail_event_count(const wm_world* w, int32_t boat) {
  if (bad_boat(w, boat)) return 0;
  return static_cast<int32_t>(w->world->boat(static_cast<std::size_t>(boat)).sails().events().size());
}

wm_status wm_world_sail_event(const wm_world* w, int32_t boat, int32_t i, int32_t* sail, int32_t* phase) {
  if (bad_boat(w, boat)) return fail(WM_ERR_ARG, "bad boat index");
  const auto& ev = w->world->boat(static_cast<std::size_t>(boat)).sails().events();
  if (i < 0 || static_cast<std::size_t>(i) >= ev.size()) return fail(WM_ERR_ARG, "bad event index");
  if (sail) *sail = ev[static_cast<std::size_t>(i)].sail;
  if (phase) *phase = static_cast<int32_t>(ev[static_cast<std::size_t>(i)].phase);
  return WM_OK;
}

// ---- wind and sea -------------------------------------------------------------------------------------------

wm_status wm_world_wind_clean(wm_world* w, float x, float y, float* speed, float* from) {
  if (w == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::WindSample s = w->wind->wind_clean(wind_now(w), x, y);
  if (speed) *speed = s.speed;
  if (from) *from = s.from;
  return WM_OK;
}

float wm_world_wind_global_from(wm_world* w) { return w != nullptr ? wind_now(w).global_from : NAN; }

wm_status wm_world_current(wm_world* w, float x, float y, float* cx, float* cy) {
  if (w == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::Vec2 c = w->wind->current(x, y, w->world->t_ms());
  if (cx) *cx = c.x;
  if (cy) *cy = c.y;
  return WM_OK;
}

int32_t wm_world_puffs(wm_world* w, wm_puff* out, int32_t cap) {
  if (w == nullptr) return 0;
  const std::vector<wm::PuffPatch> p = w->wind->puff_patches(wind_now(w));
  for (std::size_t i = 0; out != nullptr && i < p.size() && static_cast<int32_t>(i) < cap; ++i)
    out[i] = {p[i].px, p[i].py, p[i].R, p[i].s, p[i].e};
  return static_cast<int32_t>(p.size());
}

float wm_world_puff_tile(const wm_world* w) { return w != nullptr ? w->wind->settings().puffs.tile : NAN; }

int32_t wm_world_puffs_at(wm_world* w, double t_ms, wm_puff* out, int32_t cap) {
  if (w == nullptr) return 0;
  const std::vector<wm::PuffPatch> p = w->wind->puff_patches(wind_render(w, t_ms));
  for (std::size_t i = 0; out != nullptr && i < p.size() && static_cast<int32_t>(i) < cap; ++i)
    out[i] = {p[i].px, p[i].py, p[i].R, p[i].s, p[i].e};
  return static_cast<int32_t>(p.size());
}

wm_status wm_world_current_at(wm_world* w, float x, float y, double t_ms, float* cx, float* cy) {
  if (w == nullptr) return fail(WM_ERR_ARG, "null argument");
  const RenderTime r = render_time(t_ms);
  const wm::Vec2 c = w->wind->current(x, y, r.n, r.f);
  if (cx) *cx = c.x;
  if (cy) *cy = c.y;
  return WM_OK;
}

wm_status wm_world_wind_state(wm_world* w, double t_ms, wm_wind_state* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::WindSettings& s = w->wind->settings();
  out->base_speed = s.base_speed;
  out->base_from = s.base_from;
  out->global_from = wind_render(w, t_ms).global_from;
  out->puff_tile = s.puffs.tile;
  out->cap_up = s.puffs.cap_up;
  out->cap_down = s.puffs.cap_down;
  out->puffs = s.puffs_enabled ? 1 : 0;
  return WM_OK;
}

uint32_t wm_world_time_ms(const wm_world* w) { return w != nullptr ? w->world->t_ms() : 0; }

double wm_world_render_time_ms(const wm_world* w, float alpha) {
  if (w == nullptr) return 0.0;
  const std::uint32_t n = w->world->tick();
  if (n == 0) return 0.0;
  const double a = std::isnan(alpha) ? 1.0 : static_cast<double>(wm::clamp(alpha, 0.0f, 1.0f));
  return 50.0 * (static_cast<double>(n - 1) + a);
}

wm_status wm_world_sea_exposure_grid(const wm_world* w, wm_exposure_grid* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  std::memset(out, 0, sizeof *out);
  const wm::SeaField* sea = w->world->sea();
  out->exposure_default = sea != nullptr ? sea->exposure_default() : 1.0f;
  const wm::VenueExposure* e = sea != nullptr ? sea->exposure_grid() : nullptr;
  if (e == nullptr) return fail(WM_ERR_ABSENT, "no exposure grid");
  out->x0 = e->grid.x0;
  out->y0 = e->grid.y0;
  out->dx = e->grid.dx;
  out->dy = e->grid.dy;
  out->nx = e->grid.nx;
  out->ny = e->grid.ny;
  out->e = e->e.data();
  return WM_OK;
}

float wm_world_sea_height_at(wm_world* w, float x, float y, double t_ms) {
  if (w == nullptr || w->world->sea() == nullptr) return 0.0f;
  const RenderTime r = render_time(t_ms);
  if (r.f == 0.0 && r.n == w->world->t_ms()) return wm_world_sea_height(w, x, y);
  const double key = static_cast<double>(r.n) + r.f;
  if (w->sea_t_any != key) {
    w->sea_tick_any = wm::SeaTick(w->world->sea(), r.n, r.f);
    w->sea_t_any = key;
  }
  return w->sea_tick_any.sea_height(x, y);
}

float wm_world_sea_height(wm_world* w, float x, float y) {
  if (w == nullptr) return 0.0f;
  const wm::SeaTick* s = sea_now(w);
  return s != nullptr ? s->sea_height(x, y) : 0.0f;
}

wm_status wm_world_sea_slope(wm_world* w, float x, float y, float* dx, float* dy) {
  if (w == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::SeaTick* s = sea_now(w);
  const wm::SeaSlope sl = s != nullptr ? s->sea_slope(x, y) : wm::SeaSlope{0.0f, 0.0f};
  if (dx) *dx = sl.dx;
  if (dy) *dy = sl.dy;
  return WM_OK;
}

float wm_world_sea_exposure(const wm_world* w, float x, float y) {
  if (w == nullptr || w->world->sea() == nullptr) return 1.0f;
  return w->world->sea()->exposure(x, y);
}

int32_t wm_world_sea_components(const wm_world* w, wm_sea_component* out, int32_t cap) {
  if (w == nullptr || w->world->sea() == nullptr) return 0;
  const auto& c = w->world->sea()->components();
  for (std::size_t i = 0; out != nullptr && i < c.size() && static_cast<int32_t>(i) < cap; ++i)
    out[i] = {c[i].a, c[i].kx, c[i].ky, c[i].c, c[i].T};
  return static_cast<int32_t>(c.size());
}

// ---- venue --------------------------------------------------------------------------------------------------

namespace {
const wm::VenueLand* venue_land(const wm_world* w, int32_t i) {
  if (w == nullptr || w->venue == nullptr || i < 0 || static_cast<std::size_t>(i) >= w->venue->land.size())
    return nullptr;
  return &w->venue->land[static_cast<std::size_t>(i)];
}
const wm::VenueObstacle* venue_obstacle(const wm_world* w, int32_t i) {
  if (w == nullptr || w->venue == nullptr || i < 0 || static_cast<std::size_t>(i) >= w->venue->obstacles.size())
    return nullptr;
  return &w->venue->obstacles[static_cast<std::size_t>(i)];
}
wm_status polygon_point(const std::vector<wm::Vec2>& p, int32_t k, float* x, float* y) {
  if (x == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (k < 0 || static_cast<std::size_t>(k) >= p.size()) return fail(WM_ERR_ARG, "bad point index");
  *x = p[static_cast<std::size_t>(k)].x;
  if (y) *y = p[static_cast<std::size_t>(k)].y;
  return WM_OK;
}
}  // namespace

int32_t wm_world_land_count(const wm_world* w) {
  return w == nullptr || w->venue == nullptr ? 0 : static_cast<int32_t>(w->venue->land.size());
}

wm_status wm_world_land(const wm_world* w, int32_t i, wm_land* out) {
  if (out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::VenueLand* l = venue_land(w, i);
  if (l == nullptr) return fail(WM_ERR_ARG, "bad land index");
  out->id = l->id.c_str();
  out->point_count = static_cast<int32_t>(l->points.size());
  return WM_OK;
}

wm_status wm_world_land_point(const wm_world* w, int32_t i, int32_t k, float* x, float* y) {
  const wm::VenueLand* l = venue_land(w, i);
  if (l == nullptr) return fail(WM_ERR_ARG, "bad land index");
  return polygon_point(l->points, k, x, y);
}

int32_t wm_world_obstacle_count(const wm_world* w) {
  return w == nullptr || w->venue == nullptr ? 0 : static_cast<int32_t>(w->venue->obstacles.size());
}

wm_status wm_world_obstacle(const wm_world* w, int32_t i, wm_obstacle* out) {
  if (out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const wm::VenueObstacle* o = venue_obstacle(w, i);
  if (o == nullptr) return fail(WM_ERR_ARG, "bad obstacle index");
  out->id = o->id.c_str();
  out->kind = o->is_circle ? WM_OBSTACLE_CIRCLE : WM_OBSTACLE_POLYGON;
  out->point_count = o->is_circle ? 0 : static_cast<int32_t>(o->polygon.size());
  out->cx = o->is_circle ? o->c.x : 0.0f;
  out->cy = o->is_circle ? o->c.y : 0.0f;
  out->r = o->is_circle ? o->r : 0.0f;
  return WM_OK;
}

wm_status wm_world_obstacle_point(const wm_world* w, int32_t i, int32_t k, float* x, float* y) {
  const wm::VenueObstacle* o = venue_obstacle(w, i);
  if (o == nullptr) return fail(WM_ERR_ARG, "bad obstacle index");
  return polygon_point(o->polygon, k, x, y);
}

// ---- course -------------------------------------------------------------------------------------------------

namespace {
wm_status need_race(const wm_world* w, const void* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  if (!w->world->race_created()) return fail(WM_ERR_STATE, "no race");
  return WM_OK;
}
}  // namespace

wm_status wm_world_course(const wm_world* w, wm_course_info* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::ResolvedCourse& c = w->world->course();
  out->id = c.id.c_str();
  out->twd_c = c.twd_c;
  out->k = c.k;
  out->mark_count = static_cast<int32_t>(c.marks.size());
  out->step_count = static_cast<int32_t>(c.steps.size());
  out->laps = c.laps;
  out->boundary_count = c.has_boundary ? static_cast<int32_t>(c.boundary.size()) : 0;
  out->zone_lengths = w->world->race().zone_lengths();
  return WM_OK;
}

wm_status wm_world_course_mark(const wm_world* w, int32_t mark, wm_mark* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::ResolvedCourse& c = w->world->course();
  if (mark < 0 || static_cast<std::size_t>(mark) >= c.marks.size()) return fail(WM_ERR_ARG, "bad mark index");
  const wm::ResolvedMark& m = c.marks[static_cast<std::size_t>(mark)];
  out->id = c.mark_ids[static_cast<std::size_t>(mark)].c_str();
  out->type = static_cast<int32_t>(m.type);
  out->x = m.pos.x;
  out->y = m.pos.y;
  out->radius = m.radius;
  out->heading = m.heading;
  out->length = m.length;
  out->beam = m.beam;
  out->zone_r = m.radius;  // the bounding radius of a committee or mark boat, as the rules use (rules.md §7.4)
  for (const wm::CourseObject& o : c.objects) {
    if (o.mark == mark) out->zone_r = o.r;
  }
  return WM_OK;
}

wm_status wm_world_course_step(const wm_world* w, int32_t step, wm_step* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::ResolvedCourse& c = w->world->course();
  if (step < 0 || static_cast<std::size_t>(step) >= c.steps.size()) return fail(WM_ERR_ARG, "bad step index");
  const wm::CourseStep& st = c.steps[static_cast<std::size_t>(step)];
  out->kind = static_cast<int32_t>(st.kind);
  out->marks[0] = st.marks[0];
  out->marks[1] = st.marks[1];
  out->sides[0] = static_cast<int32_t>(st.sides[0]);
  out->sides[1] = static_cast<int32_t>(st.sides[1]);
  out->gate_cross = st.gate_mode == wm::GateMode::cross ? 1 : 0;
  out->lap = st.lap;
  out->leg_in_lap = st.leg_in_lap;
  out->ref_x = st.ref.x;
  out->ref_y = st.ref.y;
  return WM_OK;
}

wm_status wm_world_course_boundary(const wm_world* w, int32_t i, float* x, float* y) {
  if (wm_status s = need_race(w, x)) return s;
  const wm::ResolvedCourse& c = w->world->course();
  if (!c.has_boundary || i < 0 || static_cast<std::size_t>(i) >= c.boundary.size())
    return fail(WM_ERR_ARG, "bad boundary index");
  *x = c.boundary[static_cast<std::size_t>(i)].x;
  if (y) *y = c.boundary[static_cast<std::size_t>(i)].y;
  return WM_OK;
}

// ---- race ---------------------------------------------------------------------------------------------------

wm_status wm_world_race(const wm_world* w, wm_race_info* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::Race& r = w->world->race();
  out->state = static_cast<int32_t>(r.state());
  out->race_type = static_cast<int32_t>(r.race_type());
  out->sequence = static_cast<int32_t>(r.sequence());
  out->prep_flag = static_cast<int32_t>(r.prep_flag());
  out->n_created = r.n_created();
  out->n_gun = r.n_gun();
  out->race_time = r.race_time(w->world->tick());
  out->general_recalls = r.general_recalls();
  out->x_flag = r.x_flag() ? 1 : 0;
  out->rules_live = r.rules_live() ? 1 : 0;
  out->twd_mean = r.twd_mean();
  out->L_max = r.L_max();
  out->boat_count = static_cast<int32_t>(r.boat_count());
  out->start_limit_s = r.settings().start_limit_s;
  return WM_OK;
}

wm_status wm_world_race_boat(const wm_world* w, int32_t boat, wm_race_boat* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::Race& r = w->world->race();
  if (boat < 0 || static_cast<std::size_t>(boat) >= r.boat_count()) return fail(WM_ERR_ARG, "bad boat index");
  const std::size_t i = static_cast<std::size_t>(boat);
  const wm::RaceBoat& b = r.boat(i);
  out->started = b.started ? 1 : 0;
  out->t_start = b.t_start;
  out->ocs = b.ocs ? 1 : 0;
  out->ocs_i = b.ocs_i ? 1 : 0;
  out->ocs_scored = b.ocs_scored ? 1 : 0;
  out->returning = r.returning(i) ? 1 : 0;
  out->next = b.next;
  out->last_rounded = b.last_rounded;
  out->finished = b.finished ? 1 : 0;
  out->t_finish_us = b.t_finish_us;
  out->place = b.place;
  out->ghost = b.ghost ? 1 : 0;
  out->ghost_reason = static_cast<int32_t>(b.ghost_reason);
  out->retired = b.retired ? 1 : 0;
  out->dsq = b.dsq ? 1 : 0;
  out->code = static_cast<int32_t>(b.code);
  out->D = b.D;
  out->rank = b.rank;
  return WM_OK;
}

int32_t wm_world_race_order(const wm_world* w, int32_t* out, int32_t cap) {
  if (w == nullptr || !w->world->race_created()) return 0;
  const auto& o = w->world->race().order();
  for (std::size_t i = 0; out != nullptr && i < o.size() && static_cast<int32_t>(i) < cap; ++i) out[i] = o[i];
  return static_cast<int32_t>(o.size());
}

int32_t wm_world_result_count(const wm_world* w) {
  if (w == nullptr || !w->world->race_created()) return 0;
  return static_cast<int32_t>(w->world->race().results().size());
}

wm_status wm_world_result(const wm_world* w, int32_t i, wm_result* out) {
  if (wm_status s = need_race(w, out)) return s;
  const auto& rs = w->world->race().results();
  if (i < 0 || static_cast<std::size_t>(i) >= rs.size()) return fail(WM_ERR_ARG, "bad result index");
  const wm::ResultRow& r = rs[static_cast<std::size_t>(i)];
  out->boat = r.boat;
  out->place = r.place;
  out->code = static_cast<int32_t>(r.code);
  out->points = r.points;
  out->t_finish_us = r.t_finish_us;
  out->projected = r.projected ? 1 : 0;
  return WM_OK;
}

wm_status wm_world_race_split(const wm_world* w, int32_t boat, int32_t step, float* t) {
  if (wm_status s = need_race(w, t)) return s;
  const wm::Race& r = w->world->race();
  if (boat < 0 || static_cast<std::size_t>(boat) >= r.boat_count()) return fail(WM_ERR_ARG, "bad boat index");
  const wm::RaceBoat& b = r.boat(static_cast<std::size_t>(boat));
  if (step < 0 || static_cast<std::size_t>(step) >= w->world->course().steps.size())
    return fail(WM_ERR_ARG, "bad step index");
  const std::size_t k = static_cast<std::size_t>(step);
  // splits hold -1 until the step is completed (race times of completions are after the gun)
  if (step == 0 ? !b.started : (k >= b.splits.size() || b.splits[k] < 0.0f))
    return fail(WM_ERR_ABSENT, "step not completed");
  *t = step == 0 ? b.t_start : b.splits[k];
  return WM_OK;
}

wm_status wm_world_race_start_status(const wm_world* w, int32_t boat, wm_start_status* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::Race& r = w->world->race();
  if (boat < 0 || static_cast<std::size_t>(boat) >= r.boat_count()) return fail(WM_ERR_ARG, "bad boat index");
  const std::size_t i = static_cast<std::size_t>(boat);
  const wm::ResolvedCourse& c = w->world->course();
  const wm::Vec2 A = c.end_a(c.start()), B = c.end_b(c.start()), C = c.steps[1].ref;
  *out = wm_start_status{};
  out->ax = A.x;
  out->ay = A.y;
  out->bx = B.x;
  out->by = B.y;
  const wm::Vec2 bw = r.bow(i);
  out->s_bow = r.start_s(bw);
  out->u_bow = r.start_u(bw);
  out->pre_start = 1;
  for (const wm::Vec2 p : r.boat(i).hull) {
    const float s = r.start_s(p), u = r.start_u(p);
    if (s > 0.0f) {
      out->course_side = 1;
      out->pre_start = 0;
      if (u >= 0.0f && u <= 1.0f) out->in_band = 1;
    }
    const float d1 = wm::side_left(p, A, B), d2 = wm::side_left(p, B, C), d3 = wm::side_left(p, C, A);
    const bool neg = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
    const bool pos = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
    if (!(neg && pos)) out->in_triangle = 1;
  }
  switch (r.prep_flag()) {
    case wm::PrepFlag::P: out->over = out->in_band; break;
    case wm::PrepFlag::I: out->over = out->course_side; break;
    default: out->over = out->in_triangle; break;
  }
  return WM_OK;
}

const char* wm_score_code_name(int32_t code) {
  static std::string names[10];
  if (code < 0 || code > WM_SCORE_DSQ) return "";
  std::string& n = names[code];
  if (n.empty()) n = std::string(wm::score_code_name(static_cast<wm::ScoreCode>(code)));
  return n.c_str();
}

// ---- rules --------------------------------------------------------------------------------------------------

const char* wm_rule_code_name(int32_t rule) {
  static std::string names[WM_RULE_SI_BOUNDARY + 1];
  if (rule < 0 || rule > WM_RULE_SI_BOUNDARY) return "";
  std::string& n = names[rule];
  if (n.empty()) n = std::string(wm::rule_code_str(static_cast<wm::RuleCode>(rule)));
  return n.c_str();
}

wm_status wm_world_boat_rules(const wm_world* w, int32_t boat, wm_boat_rules* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::Rules& r = w->world->rules();
  if (boat < 0 || static_cast<std::size_t>(boat) >= r.boat_count()) return fail(WM_ERR_ARG, "bad boat index");
  const wm::BoatRules& b = r.boat(static_cast<std::size_t>(boat));
  out->tack = b.tack;
  out->tacking = b.tacking ? 1 : 0;
  out->turning_for_penalty = b.turning_for_penalty ? 1 : 0;
  out->turn_progress = b.turn_progress;
  out->turn_tacks = b.turn_tacks;
  out->turn_gybes = b.turn_gybes;
  out->turn_in_zone = b.turn_in_zone ? 1 : 0;
  out->turn_reset = static_cast<int32_t>(b.turn_reset);
  out->turn_reset_tick = b.turn_reset_tick;
  out->pending = static_cast<int32_t>(b.pending.size());
  out->served = b.served;
  out->received = b.received;
  out->deadline_s = b.deadline_s;
  out->returning_to_start = b.returning_to_start ? 1 : 0;
  out->dsq = b.dsq ? 1 : 0;
  out->out_of_bounds = b.out_of_bounds ? 1 : 0;
  return WM_OK;
}

wm_status wm_world_boat_penalty(const wm_world* w, int32_t boat, int32_t i, wm_penalty* out) {
  if (wm_status s = need_race(w, out)) return s;
  const wm::Rules& r = w->world->rules();
  if (boat < 0 || static_cast<std::size_t>(boat) >= r.boat_count()) return fail(WM_ERR_ARG, "bad boat index");
  const auto& p = r.boat(static_cast<std::size_t>(boat)).pending;
  if (i < 0 || static_cast<std::size_t>(i) >= p.size()) return fail(WM_ERR_ARG, "bad penalty index");
  const wm::Penalty& q = p[static_cast<std::size_t>(i)];
  out->rule = static_cast<int32_t>(q.rule);
  out->other = q.other;
  out->tick = q.tick;
  out->count = q.count;
  return WM_OK;
}

int32_t wm_world_pair_count(const wm_world* w) {
  if (w == nullptr || !w->world->race_created()) return 0;
  return static_cast<int32_t>(w->world->rules().pairs().size());
}

wm_status wm_world_pair(const wm_world* w, int32_t i, wm_pair* out) {
  if (wm_status s = need_race(w, out)) return s;
  const auto& ps = w->world->rules().pairs();
  if (i < 0 || static_cast<std::size_t>(i) >= ps.size()) return fail(WM_ERR_ARG, "bad pair index");
  const wm::PairRecord& p = ps[static_cast<std::size_t>(i)];
  out->i = p.i;
  out->j = p.j;
  out->relation = static_cast<int32_t>(p.relation);
  out->kc_giver = p.kc_giver;
  out->kc_holder = p.kc_holder;
  out->kc_rule = static_cast<int32_t>(p.kc_rule);
  out->kc_state = static_cast<int32_t>(p.kc_state);
  out->room_entitled = p.room_entitled;
  out->room_giver = p.room_giver;
  out->room_rule = static_cast<int32_t>(p.room_rule);
  out->room_mark = p.room_mark;
  out->room_state = static_cast<int32_t>(p.room_state);
  out->rule17_holder = p.rule17_holder;
  out->incident = p.incident ? 1 : 0;
  out->incident_culprit = p.incident_culprit;
  out->incident_rule = static_cast<int32_t>(p.incident_rule);
  out->incident_tick = p.incident_tick;
  out->gap = p.gap;
  out->ttc = p.ttc;
  return WM_OK;
}

// ---- events -------------------------------------------------------------------------------------------------

int32_t wm_world_race_event_count(const wm_world* w) {
  return w != nullptr ? static_cast<int32_t>(w->world->events().race.size()) : 0;
}

wm_status wm_world_race_event(const wm_world* w, int32_t i, wm_race_event* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const auto& ev = w->world->events().race;
  if (i < 0 || static_cast<std::size_t>(i) >= ev.size()) return fail(WM_ERR_ARG, "bad event index");
  const wm::RaceEvent& e = ev[static_cast<std::size_t>(i)];
  out->kind = static_cast<int32_t>(e.kind);
  out->tick = e.tick;
  out->boat = e.boat;
  out->signal = static_cast<int32_t>(e.signal);
  out->flag = static_cast<int32_t>(e.flag);
  out->step = e.step;
  out->buoy = e.buoy;
  out->t = e.t;
  out->t_us = e.t_us;
  out->place = e.place;
  out->block = static_cast<int32_t>(e.block);
  out->ghost = static_cast<int32_t>(e.ghost);
  out->value = e.value;
  return WM_OK;
}

int32_t wm_world_rules_event_count(const wm_world* w) {
  return w != nullptr ? static_cast<int32_t>(w->world->events().rules.size()) : 0;
}

wm_status wm_world_rules_event(const wm_world* w, int32_t i, wm_rules_event* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const auto& ev = w->world->events().rules;
  if (i < 0 || static_cast<std::size_t>(i) >= ev.size()) return fail(WM_ERR_ARG, "bad event index");
  const wm::RulesEvent& e = ev[static_cast<std::size_t>(i)];
  out->kind = static_cast<int32_t>(e.kind);
  out->tick = e.tick;
  out->boat = e.boat;
  out->other = e.other;
  out->rule = static_cast<int32_t>(e.rule);
  out->count = e.count;
  out->contact = e.contact ? 1 : 0;
  out->mark = e.mark;
  out->deadline = e.deadline;
  return WM_OK;
}

int32_t wm_world_contact_event_count(const wm_world* w) {
  return w != nullptr ? static_cast<int32_t>(w->world->events().contacts.size()) : 0;
}

wm_status wm_world_contact_event(const wm_world* w, int32_t i, wm_contact_event* out) {
  if (w == nullptr || out == nullptr) return fail(WM_ERR_ARG, "null argument");
  const auto& ev = w->world->events().contacts;
  if (i < 0 || static_cast<std::size_t>(i) >= ev.size()) return fail(WM_ERR_ARG, "bad event index");
  const wm::ContactEvent& e = ev[static_cast<std::size_t>(i)];
  out->tick = e.tick;
  out->boat = e.boat;
  out->other_kind = static_cast<int32_t>(e.other_kind);
  out->other = e.other;
  out->point_x = e.point.x;
  out->point_y = e.point.y;
  out->normal_x = e.normal.x;
  out->normal_y = e.normal.y;
  out->depth = e.depth;
  out->closing_speed = e.closing_speed;
  out->impulse = e.impulse;
  out->begin = e.begin ? 1 : 0;
  return WM_OK;
}

}  // extern "C"
