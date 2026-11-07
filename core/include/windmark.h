/* Windmark core: the C API.
 *
 * A stable C interface over the simulation world (core/src/world): load boat classes, venues and courses, create a
 * world, add boats, create a race (or sail freely without one), set controls, step the 50 ms tick, and read the
 * boat, sail, wind, sea, race and rules state, this tick's events and the state checksum. The server and the engine
 * bindings (the Godot extension in game/native) use only this header.
 *
 * Conventions (docs/specs/conventions.md): SI units, world ENU metres (x east, y north, z up), compass angles in
 * radians clockwise from north, signed angles positive to starboard, one tick = 50 ms. Field names are the core's
 * (boat.md §3, sails.md §3 and §7, race.md §11, rules.md §11).
 *
 * ABI rules
 * - C only: opaque handles, plain structs of fixed-width types, int32 status codes. No C++ types cross it.
 * - Every function that can fail returns a wm_status; wm_last_error() gives the message of the last failure on
 *   the calling thread. Readers that cannot fail return their value directly.
 * - Structs passed in are filled by the caller after a *_init() call that sets the defaults; structs passed out
 *   are written whole. WM_API_VERSION changes whenever a struct or a signature changes; a binding checks
 *   wm_api_version() at load.
 * - Handles are reference counted internally: a world keeps the classes, venue and course it was given alive, so
 *   the caller may free its own handles at any time after passing them.
 * - A world is not thread-safe; distinct worlds may be used from distinct threads.
 * - Determinism: the library is built under the float rules of conventions.md §5. Hosts must not enable
 *   flush-to-zero or change the rounding mode around wm_world_step() (debug builds check it).
 * - Pointers returned by the library (strings, arrays) stay valid until the next call that changes the object
 *   they belong to (for a world: the next wm_world_step, add or create call).
 */
#ifndef WINDMARK_H
#define WINDMARK_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(WINDMARK_CAPI_BUILD)
#define WM_API __declspec(dllexport)
#else
#define WM_API __declspec(dllimport)
#endif
#elif defined(__GNUC__)
#define WM_API __attribute__((visibility("default")))
#else
#define WM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define WM_API_VERSION 8

/* ---- status ------------------------------------------------------------------------------------------------ */

typedef int32_t wm_status;
enum {
  WM_OK = 0,
  WM_ERR_ARG = 1,     /* null pointer, bad index or value out of range */
  WM_ERR_LOAD = 2,    /* a data file did not load or validate (the message has the file, JSON path and reason) */
  WM_ERR_STATE = 3,   /* not allowed in this state (e.g. create_race twice, place_boat after the race exists) */
  WM_ERR_FULL = 4,    /* the race takes no more boats (race.md §3.5) */
  WM_ERR_ABSENT = 5   /* an optional table or record is absent; the output is NaN or zeroed */
};

WM_API int32_t wm_api_version(void);
/* The message of the last failed call on this thread ("" if none). */
WM_API const char* wm_last_error(void);

/* ---- data: boat classes, venues, courses ------------------------------------------------------------------- */

typedef struct wm_perf wm_perf;     /* a windmark.perf/1 performance file (data_format.md §4) */
typedef struct wm_venue wm_venue;   /* a windmark.venue/1 venue physics file (data_format.md §6) */
typedef struct wm_course wm_course; /* a windmark.course/1 course file (courses.md) */

WM_API wm_status wm_perf_load(const char* path, wm_perf** out);
WM_API wm_status wm_perf_parse(const char* json, size_t len, const char* name, wm_perf** out);
WM_API void wm_perf_free(wm_perf* p);
WM_API wm_status wm_venue_load(const char* path, wm_venue** out);
WM_API wm_status wm_venue_parse(const char* json, size_t len, const char* name, wm_venue** out);
WM_API void wm_venue_free(wm_venue* v);
WM_API wm_status wm_course_load(const char* path, wm_course** out);
WM_API wm_status wm_course_parse(const char* json, size_t len, const char* name, wm_course** out);
WM_API void wm_course_free(wm_course* c);

/* Sail types (data_format.md §4.4). */
enum { WM_SAIL_MAIN = 0, WM_SAIL_JIB, WM_SAIL_GENOA, WM_SAIL_CODE_ZERO, WM_SAIL_SPINNAKER_SYM,
       WM_SAIL_SPINNAKER_ASYM };

typedef struct wm_class_info {
  const char* class_id;
  const char* file_sha256;       /* lowercase hex of the perf file */
  float loa, lwl, bwl;           /* m */
  float rudder_max;              /* rad */
  int32_t sail_count;
  int32_t main_sail;             /* sail index of the main */
  int32_t start_front_sail;      /* -1 = none */
} wm_class_info;

typedef struct wm_sail_info {
  const char* id;
  int32_t type;                  /* WM_SAIL_* */
  float sheet_min, sheet_max;    /* rad */
} wm_sail_info;

WM_API wm_status wm_perf_info(const wm_perf* p, wm_class_info* out);
WM_API wm_status wm_perf_sail(const wm_perf* p, int32_t sail, wm_sail_info* out);
/* boat.md §9 polar speed (m/s) at `tws` (m/s) and `twa` (rad, signed) for a front sail (-1 = main only). */
WM_API float wm_perf_polar(const wm_perf* p, float tws, float twa, int32_t front_sail);
/* race.md §7.2: best VMG up and down over every sail config. Speeds m/s, angles rad. */
WM_API wm_status wm_perf_polar_vmg(const wm_perf* p, float tws, float* up_speed, float* up_twa, float* down_speed,
                                   float* down_twa);
/* sails.md §6: the trim_speed table of the config flown with `front_sail` (-1 = main only) at a hypothetical trim
 * error `eps` (rad). WM_ERR_ABSENT and *out = NaN when that config has no trim_speed table. */
WM_API wm_status wm_perf_trim_speed(const wm_perf* p, int32_t front_sail, float tws, float awa_abs, float eps,
                                    float* out);

/* Any table of the config flown with `front_sail` (-1 = main only), by its perf file name (data_format.md §4.3):
 * "polar", "heel", "accel", "accel_rest", "trim_speed", "trim_heel", "weather_helm", "fall_off", "flog_drag",
 * "optimal_main", "optimal_front". Arguments in the table's axis order (x, then y, then w; the unused ones are
 * ignored), e.g. flog_drag(aws, awa_abs). *rank (may be null) receives the table's number of axes.
 * WM_ERR_ABSENT and *out = NaN for an optional table the config does not have, WM_ERR_ARG for an unknown name. */
WM_API wm_status wm_perf_table(const wm_perf* p, int32_t front_sail, const char* name, float x, float y, float w,
                               float* out, int32_t* rank);

/* ---- world set-up ------------------------------------------------------------------------------------------ */

typedef struct wm_world wm_world;

/* Wind shift presets (wind.md §1). */
enum { WM_SHIFT_DEFAULT = -1, WM_SHIFT_STEADY = 0, WM_SHIFT_STABLE, WM_SHIFT_OSCILLATING, WM_SHIFT_SHIFTY,
       WM_SHIFT_UNSTABLE };
/* Puff presets (wind.md §6.1). */
enum { WM_PUFFS_DEFAULT = -1, WM_PUFFS_NONE = 0, WM_PUFFS_LIGHT, WM_PUFFS_STANDARD, WM_PUFFS_GUSTY };
/* Weather modes (race.md §2.1), for wm_world_settings_resolve. */
enum { WM_WEATHER_LOCAL = 0, WM_WEATHER_RANDOM = 1, WM_WEATHER_CUSTOM = 2 };

/* wind.md §6.1 puff field parameters. */
typedef struct wm_puff_params {
  float tile;                    /* m */
  int32_t puff_count, lull_count;
  float diameter_min, diameter_max;            /* m */
  float puff_strength_min, puff_strength_max;
  float lull_strength_min, lull_strength_max;
  uint32_t life_min_ms, life_max_ms;
  float cap_up, cap_down;
} wm_puff_params;

/* sea.md §2 one swell. */
typedef struct wm_swell {
  float hs, tp, from;            /* m, s, rad compass */
} wm_swell;

/* Race settings (race.md §2); -1 = the course default, then the race type's default. */
enum { WM_RACE_FLEET = 0, WM_RACE_MATCH = 1 };
enum { WM_SEQUENCE_5410 = 0, WM_SEQUENCE_3210 = 1, WM_SEQUENCE_MATCH = 2 };
enum { WM_FLAG_P = 0, WM_FLAG_I, WM_FLAG_Z, WM_FLAG_U, WM_FLAG_BLACK };
enum { WM_RULES_NONE = 0, WM_RULES_BASIC, WM_RULES_FULL };
enum { WM_PENALTY_ONE_TURN = 0 };  /* the only kind: every penalty is one 360 turn (rules.md §9.2) */
enum { WM_UMPIRE_STANDARD = 0, WM_UMPIRE_CONTACT_ONLY, WM_UMPIRE_PROTEST };

typedef struct wm_world_settings {
  uint64_t race_seed;            /* conventions.md §7 */
  /* wind (wind.md §1); the venue's wind and current fields are applied on top */
  float wind_speed;              /* base speed at 10 m, m/s */
  float wind_from;               /* base direction, rad compass */
  int32_t shift_preset;          /* WM_SHIFT_*; DEFAULT keeps the wind.md defaults */
  float shift_trend_rate;        /* rad/s */
  int32_t puffs;                 /* bool */
  int32_t oscillation;           /* bool */
  float current_speed;           /* m/s, uniform current (a venue current field replaces it) */
  float current_to;              /* rad compass */
  /* sea (sea.md): the wind sea grows from the base wind and the venue fetch */
  int32_t sea;                   /* bool; 0 = flat water */
  float sea_scale;               /* 1 = as grown */
  int32_t shadows;               /* bool, wind shadows (wind_shadow.md) */
  int32_t weather_helm;          /* bool, boat.md §2: the sail plan's helm balance turns the boat with the helm
                                    centred (0, the default: every boat holds her heading with the helm centred) */
  /* race (race.md §2) */
  int32_t race_type;             /* WM_RACE_* or -1 */
  int32_t sequence;              /* WM_SEQUENCE_* or -1 */
  int32_t prep_flag;             /* WM_FLAG_* or -1 */
  float free_sailing_s;          /* free sailing before the warning signal, s */
  int32_t general_recall;        /* bool */
  int32_t rules_level;           /* WM_RULES_* */
  int32_t penalty;               /* WM_PENALTY_* */
  int32_t umpire;                /* WM_UMPIRE_* */
  float time_limit_s;            /* 0 = from the course */
  int32_t finish_window;         /* bool */
  float start_limit_s;           /* race.md §4.4 */
  /* the rest of the wind (wind.md §1): used as given when shift_preset / puff_preset are DEFAULT */
  float shift_amplitude;         /* rad */
  uint32_t shift_hold_max_ms, shift_hold_min_ms;
  float shift_trend_max;         /* rad */
  float osc_amplitude;           /* rad */
  float osc_time_scale;          /* s */
  int32_t puff_preset;           /* WM_PUFFS_*; DEFAULT: `puffs` with `puff` */
  wm_puff_params puff;
  float tide_scale;              /* wind.md §7, on the venue's current field */
  uint32_t tide_period_ms, tide_phase_ms;
  /* the rest of the sea (sea.md §2) */
  int32_t swell_count;           /* 0 to 4 */
  wm_swell swells[4];
  /* weather mode (race.md §2.1), read by wm_world_settings_resolve only */
  int32_t weather;               /* WM_WEATHER_*; custom reads wind_speed, wind_from, shift_preset, puff_preset */
} wm_world_settings;

/* Fills the spec defaults (wind.md, sea.md, race.md §2). */
WM_API void wm_world_settings_init(wm_world_settings* s);

/* race.md §2.1: resolves the venue's conditions (data_format.md §6.7) for `s->weather` and `s->race_seed` into the
 * explicit wind, current and sea fields of `s` (shift_preset and puff_preset become DEFAULT, every value written
 * out), once, before wm_world_create. `course` gives the start signal's time (the tide phase) with the race fields of `s` (null:
 * free sailing). In custom mode wind_speed and wind_from are the player's, and shift_preset / puff_preset the
 * chosen presets (DEFAULT: the venue's). A venue without conditions takes custom only (WM_ERR_ARG otherwise). */
WM_API wm_status wm_world_settings_resolve(wm_world_settings* s, const wm_venue* venue, const wm_course* course);

/* A world on `venue` (may be null: open water, no land, no race possible). Its tick 0 is the environment clock's
 * zero (race.md §0). Without wm_world_create_race it is a free-sailing world: boats, wind, sea, shadows and
 * collisions, no race or rules. */
WM_API wm_status wm_world_create(const wm_world_settings* s, const wm_venue* venue, wm_world** out);
WM_API void wm_world_free(wm_world* w);

typedef struct wm_boat_entry {
  const wm_perf* perf;           /* required */
  int32_t human;                 /* bool */
  int32_t ai;                    /* bool: protest mode, protests on its own (rules.md §10) */
  float performance_scale;       /* boat.md §2; 1 for humans */
  int32_t auto_trim;             /* bool */
  int32_t front_sail;            /* sail index, -1 = none, -2 = the class's start front sail */
} wm_boat_entry;

WM_API void wm_boat_entry_init(wm_boat_entry* e, const wm_perf* perf);

/* Adds a boat; *index receives its boat index. Before wm_world_create_race the boat is an entry (placed by the
 * race, or by wm_world_place_boat for free sailing); after it a joiner placed at once in the first free slot,
 * until the preparatory signal (WM_ERR_FULL after it). */
WM_API wm_status wm_world_add_boat(wm_world* w, const wm_boat_entry* e, int32_t* index);
/* Free sailing: places a boat at (x, y) on heading psi at 60 % of its polar speed, sails up and trimmed. Only
 * before wm_world_create_race (WM_ERR_STATE after). */
WM_API wm_status wm_world_place_boat(wm_world* w, int32_t boat, float x, float y, float psi);
/* Scenario set-up (rules scenarios, tests, tools; not a control, never sent online): puts a boat at (x, y) on
 * heading psi at speed v (m/s, >= 0) between ticks, before or after wm_world_create_race, as a spawn does (boat.md
 * §6.6: sails up and trimmed, the wind triangle evaluated at once). `front_sail`: the sail index to have up, -1 none,
 * -2 the front sail she has up now. Auto trim and performance_scale stay as they are. The race sees the move as the
 * boat's track in the next step (a move across the start line after the gun starts her, race.md §4.2). */
WM_API wm_status wm_world_scenario_place(wm_world* w, int32_t boat, float x, float y, float psi, float v,
                                         int32_t front_sail);
/* race.md §3.1: lays the course, checks it on the venue, creates the race and the rules, spawns every boat. */
WM_API wm_status wm_world_create_race(wm_world* w, const wm_course* course);
/* courses.md §6.4 free sail: lays the course with no race (the axis on the median wind now), checks it on the venue,
 * builds its collision objects and places every boat as a race spawns them, the slots nearest the start line's
 * middle first. Once, before any race; wm_world_place_boat still works after it. The course readers below then
 * answer without a race. Not part of the world snapshot. */
WM_API wm_status wm_world_lay_course(wm_world* w, const wm_course* course);

/* ---- controls ---------------------------------------------------------------------------------------------- */

/* networking.md §4.1 input frame, decoded. */
enum { WM_SAIL_REQ_NONE = 0, WM_SAIL_REQ_DROP_FRONT = 255 }; /* 1..15: hoist sail index + 1 */
enum { WM_INPUT_LET_FLY = 1, WM_INPUT_AUTO_TRIM = 2, WM_INPUT_HAIL = 4, WM_INPUT_HAIL_REPLY = 8,
       WM_INPUT_PROTEST = 16 };

typedef struct wm_input_frame {
  float h_cmd;                   /* [-1, 1], + turns the bow to starboard */
  float sheet_cmd;               /* [0, 1]: 0 sheeted hard in, 1 fully eased; ignored while auto trim */
  uint8_t sail_req;              /* WM_SAIL_REQ_* or hoist index + 1 */
  uint8_t flags;                 /* WM_INPUT_* */
} wm_input_frame;

/* The 6-byte wire encoding of networking.md §4.1 (int16 h_cmd, u16 sheet_cmd, u8 sail_req, u8 flags, little
 * endian). The server and every client apply the decoded frame, so both see the same quantised values. */
WM_API void wm_input_encode(const wm_input_frame* f, uint8_t out[6]);
WM_API void wm_input_decode(const uint8_t in[6], wm_input_frame* out);

enum { WM_REQUEST_NONE = -1, WM_REQUEST_ACCEPTED = 0, WM_REQUEST_REJECTED = 1 };

/* Applies an input frame to a boat for the next tick (step 2 of conventions.md §4.1): helm, sheet, let fly, auto
 * trim, the sail request, and the protest flag (rules.md §10). Hail flags are accepted and not yet used.
 * *request (may be null) receives the sail request result, WM_REQUEST_*: sails.md §4.2 decides it on the sail
 * state after the last tick, which is the state step 2 applies it to, so the answer is exact. */
WM_API wm_status wm_world_apply_input(wm_world* w, int32_t boat, const wm_input_frame* f, int32_t* request);

/* Single controls, queued like the frame's fields. */
WM_API wm_status wm_world_set_helm(wm_world* w, int32_t boat, float h_cmd);
WM_API wm_status wm_world_set_sheet(wm_world* w, int32_t boat, float sheet_cmd);
WM_API wm_status wm_world_set_auto_trim(wm_world* w, int32_t boat, int32_t on);
WM_API wm_status wm_world_set_let_fly(wm_world* w, int32_t boat, int32_t on);
WM_API wm_status wm_world_hoist(wm_world* w, int32_t boat, int32_t sail, int32_t* request);
WM_API wm_status wm_world_drop_front(wm_world* w, int32_t boat, int32_t* request);
WM_API wm_status wm_world_retire(wm_world* w, int32_t boat);  /* race.md §6.4 */
WM_API wm_status wm_world_protest(wm_world* w, int32_t boat); /* rules.md §10 */

/* Called in step 2 of every tick before the queued controls are applied, after the AI skippers: scripts read
 * the state (and step 1's race and rules results) and set controls here. Null removes it. */
typedef void (*wm_controller_fn)(wm_world* w, void* user);
WM_API void wm_world_set_controller(wm_world* w, wm_controller_fn fn, void* user);

/* ---- AI skippers (ai.md) ----------------------------------------------------------------------------------- */

/* Every world has one set of AI skippers. They decide in step 2 of every tick, before the callback of
 * wm_world_set_controller (which may read or override what they set) and after the controls the host queued
 * between ticks, so an AI boat's own controls win over queued ones: hosts send no input for a boat an AI sails.
 * Deterministic: they read only the world and draw from the AI RNG streams with the race seed. */

/* ai.md §13 levels. */
enum { WM_AI_EASY = 0, WM_AI_INTERMEDIATE, WM_AI_EXPERT, WM_AI_PRO };
/* ai.md §15 tactic reasons, in the spec's order. */
enum { WM_AI_TACTIC_NONE = 0, WM_AI_TACTIC_START, WM_AI_TACTIC_ROUNDING, WM_AI_TACTIC_KEEP_CLEAR,
       WM_AI_TACTIC_EMERGENCY, WM_AI_TACTIC_BAD_AIR, WM_AI_TACTIC_COVER, WM_AI_TACTIC_SHIFT, WM_AI_TACTIC_PRESSURE,
       WM_AI_TACTIC_LAYLINE, WM_AI_TACTIC_CORRIDOR, WM_AI_TACTIC_PENALTY_TURN, WM_AI_TACTIC_LAND };
#define WM_AI_TACTIC_COUNT 13
WM_API const char* wm_ai_tactic_name(int32_t tactic);
/* ai.md §13 the performance_scale of a level (the one physical difference between the levels). */
WM_API float wm_ai_performance_scale(int32_t level);

/* An entry for an AI boat of this level (ai.md §13): not human, protests on its own, the level's
 * performance_scale; auto trim and the class's start sail. */
WM_API void wm_ai_entry_init(wm_boat_entry* e, const wm_perf* perf, int32_t level);
/* Adds a boat from wm_ai_entry_init and has an AI of `level` sail it (wm_world_ai_add). `speed_only`: the
 * decisions of Intermediate with the level's performance_scale (ai.md §13). Same rules as wm_world_add_boat. */
WM_API wm_status wm_world_add_ai_boat(wm_world* w, const wm_perf* perf, int32_t level, int32_t speed_only,
                                      int32_t* index);
/* Boat `boat` is sailed by an AI of this level from the next step on (any boat already added). */
WM_API wm_status wm_world_ai_add(wm_world* w, int32_t boat, int32_t level, int32_t speed_only);
/* ai.md §14: an AI at Intermediate decisions takes a boat over as it is (a disconnected human; its
 * performance_scale stays), and release hands it back to its host. */
WM_API wm_status wm_world_ai_take_over(wm_world* w, int32_t boat);
WM_API wm_status wm_world_ai_release(wm_world* w, int32_t boat);
/* race.md §6.2: only the finished-boat autopilot for this boat (an offline human boat after its finish). */
WM_API wm_status wm_world_ai_add_autopilot(wm_world* w, int32_t boat);
/* 1 when an AI sails the boat now (added or taken over, not released; the autopilot alone does not count). */
WM_API int32_t wm_world_ai_has(const wm_world* w, int32_t boat);
/* The number of boats an AI sails now. */
WM_API int32_t wm_world_ai_count(const wm_world* w);

/* ai.md §15 per boat and race. */
typedef struct wm_ai_telemetry {
  int32_t tacks, gybes, penalties, ocs;
  int32_t activations[WM_AI_TACTIC_COUNT];  /* by WM_AI_TACTIC_* */
  float stuck_s;                 /* below 0.3 m/s in spells longer than 5 s after the start */
  float min_gap;                 /* smallest hull gap to a racing boat within 20 L after the warning, m (1e9: none) */
  int32_t sail_changes;
  int32_t bad_air_count;         /* records, wm_world_ai_bad_air */
  float start_delay;             /* s after the gun (< 0: not started) */
} wm_ai_telemetry;

/* What the AI decided in the last tick, for tests and a debug overlay. */
typedef struct wm_ai_debug {
  int32_t tactic;                /* WM_AI_TACTIC_* */
  float psi_target;              /* rad */
  float d;                       /* smoothed wind deficit */
  float twd_ref, twd_f, tws_f;   /* the AI's filtered wind */
  int32_t leg;                   /* 0 beat, 1 reach, 2 run */
  int32_t manoeuvre;
  float aim_x, aim_y;            /* where it steers to */
  float spot_x, spot_y;          /* its start spot */
} wm_ai_debug;

/* WM_ERR_ABSENT (zeroed record) for a boat no AI ever sailed. */
WM_API wm_status wm_world_ai_telemetry(const wm_world* w, int32_t boat, wm_ai_telemetry* out);
WM_API wm_status wm_world_ai_debug(const wm_world* w, int32_t boat, wm_ai_debug* out);
/* ai.md §15 one bad-air record: the tick of the trigger, the deficit then and 20 s later (< 0: not yet). */
WM_API wm_status wm_world_ai_bad_air(const wm_world* w, int32_t boat, int32_t i, uint32_t* tick, float* d_at,
                                     float* d_after);

/* ---- snapshots (conventions.md §9.1, ai.md §16) ------------------------------------------------------------ */

/* The world snapshot between ticks: *data points at the bytes (valid until the next save or step of this world)
 * and *size receives their count. */
WM_API wm_status wm_world_save(wm_world* w, const uint8_t** data, size_t* size);
/* Resumes a saved world in a world created with the same settings and venue and the same boats added in the same
 * order (wm_world_add_boat or wm_world_add_ai_boat, joiners included), whatever it has run before: the world is
 * reset first, so it can take any number of loads (resync, replay scrubbing). `course` is the course the race was
 * created with (null when the snapshot has no race). It then continues bit for bit. WM_ERR_LOAD with the reason
 * when the snapshot does not match or is damaged; the world is then unchanged. The controller callback and the AI
 * skippers stay installed; load the skippers' memory with wm_world_ai_load before the next step. */
WM_API wm_status wm_world_load(wm_world* w, const wm_course* course, const uint8_t* data, size_t size);
/* ai.md §16 the AI skippers' memory, a block of its own taken with the world snapshot (same moment, between
 * ticks); valid until the next save or step. */
WM_API wm_status wm_world_ai_save(wm_world* w, const uint8_t** data, size_t* size);
/* Replaces the skippers with the saved ones, after wm_world_load of the same snapshot and before the next step.
 * WM_ERR_LOAD (the skippers unchanged) for a block of another tick, race seed or fleet, or a damaged one. */
WM_API wm_status wm_world_ai_load(wm_world* w, const uint8_t* data, size_t size);

/* ---- stepping ---------------------------------------------------------------------------------------------- */

/* One tick (conventions.md §4.1). It takes no checksum: ask wm_world_checksum when one is needed. */
WM_API void wm_world_step(wm_world* w);
/* The checksum of the current state (conventions.md §9): taken on request, it hashes the whole world snapshot, so
 * take it only when it is needed (the world hash every few seconds, replays, tests), not every tick. */
WM_API uint64_t wm_world_checksum(const wm_world* w);
/* The next tick to run (ticks stepped so far); its time is 50 * tick ms on the environment clock. */
WM_API uint32_t wm_world_tick(const wm_world* w);
WM_API int32_t wm_world_boat_count(const wm_world* w);
WM_API int32_t wm_world_has_race(const wm_world* w);
WM_API int32_t wm_world_has_course(const wm_world* w); /* a race's course or a laid one (wm_world_lay_course) */

/* ---- boats ------------------------------------------------------------------------------------------------- */

/* boat.md §3, in snapshot order. */
typedef struct wm_boat_state {
  float pos_x, pos_y, z, psi, v, sway, h, yaw_rate;
  float phi, phi_rate, theta, theta_rate, wobble_phase;
  float contact_vx, contact_vy, contact_yaw_rate;
  float twd_from, awd_from, tws, twa, aws, awa;
  float v_filt, sog_filt_x, sog_filt_y;
} wm_boat_state;

/* boat.md §2 as the boat holds them (queued controls apply at the next step). */
typedef struct wm_boat_controls {
  float h_cmd, sheet_cmd;
  int32_t auto_trim, let_fly;
  float performance_scale;
} wm_boat_controls;

/* boat.md §3 derived outputs of the last tick. */
typedef struct wm_boat_outputs {
  float target_speed, polar_speed, heel_target, turn_rate, vmg, sog, cog;
  float man_coef, trim_speed, trim_heel, heel_coef, surf_coef, wind_speed_clean;
} wm_boat_outputs;

/* wind_shadow.md §5: the environment the boat stepped in during the last tick. */
typedef struct wm_boat_env {
  float wind_speed, wind_from;               /* after the other boats' shadows */
  float wind_speed_clean, wind_from_clean;
  float current_x, current_y;
  float shadow_loss, shadow_header;
  int32_t shadow_source;                     /* boat index, -1 = clear air */
} wm_boat_env;

WM_API const wm_perf* wm_world_boat_perf(const wm_world* w, int32_t boat);
WM_API wm_status wm_world_boat_state(const wm_world* w, int32_t boat, wm_boat_state* out);
WM_API wm_status wm_world_boat_controls(const wm_world* w, int32_t boat, wm_boat_controls* out);
WM_API wm_status wm_world_boat_outputs(const wm_world* w, int32_t boat, wm_boat_outputs* out);
WM_API wm_status wm_world_boat_env(const wm_world* w, int32_t boat, wm_boat_env* out);

/* The render pose between the state before and after the last tick (networking.md §6): alpha 0 = the previous
 * tick, 1 = the last one (clamped). Positions, heave, pitch, heel and helm are linear; heading and true wind
 * direction take the short way round (angle_lerp); twa is interpolated as a signed angle. Before the first step
 * both ends are the placed state. */
typedef struct wm_render_pose {
  float pos_x, pos_y, z, psi, theta, phi, h, twa, twd_from;
} wm_render_pose;
WM_API wm_status wm_world_render_pose(const wm_world* w, int32_t boat, float alpha, wm_render_pose* out);

/* sails.md §6 via the boat's current config (the front sail flown now): the trim_speed table at a hypothetical
 * trim error. For the HUD trim tolerance (hud.md §5). WM_ERR_ABSENT and NaN without a table. */
WM_API wm_status wm_world_trim_speed_at(const wm_world* w, int32_t boat, float tws, float awa_abs, float eps,
                                        float* out);

/* ---- sails ------------------------------------------------------------------------------------------------- */

enum { WM_PHASE_DOWN = 0, WM_PHASE_PREPARE_HOIST, WM_PHASE_HOISTING, WM_PHASE_UP, WM_PHASE_PREPARE_DROP,
       WM_PHASE_DROPPING };
enum { WM_MOTION_IDLE = 0, WM_MOTION_SHEETING, WM_MOTION_EASING };

typedef struct wm_sail_step {
  int32_t sail, phase, reversed;
} wm_sail_step;

#define WM_SAIL_QUEUE_MAX 6

/* sails.md §3.2 per boat. */
typedef struct wm_sails {
  int32_t front;                 /* front sail up, -1 = none */
  int32_t sail_count;
  int32_t queue_len, queue_pos;  /* busy while queue_pos < queue_len */
  float queue_progress;
  wm_sail_step queue[WM_SAIL_QUEUE_MAX];
} wm_sails;

/* sails.md §3.1 state and §7 outputs of one sail. */
typedef struct wm_sail {
  int32_t phase;                 /* WM_PHASE_* */
  float progress, beta, pole;
  float k_h, m_opt, beta_opt, beta_t, trim_error, luff_shiver;
  int32_t motion;                /* WM_MOTION_* */
  int32_t backed;
} wm_sail;

WM_API wm_status wm_world_sails(const wm_world* w, int32_t boat, wm_sails* out);
WM_API wm_status wm_world_sail(const wm_world* w, int32_t boat, int32_t sail, wm_sail* out);
/* sails.md §7 phase events of the last tick, in the order they happened. */
WM_API int32_t wm_world_sail_event_count(const wm_world* w, int32_t boat);
WM_API wm_status wm_world_sail_event(const wm_world* w, int32_t boat, int32_t i, int32_t* sail, int32_t* phase);

/* ---- wind and sea ------------------------------------------------------------------------------------------ */

/* wind.md §2 clean wind (no shadows) at a world point at the world's current time (50 * tick ms). */
WM_API wm_status wm_world_wind_clean(wm_world* w, float x, float y, float* speed, float* from);
/* wind.md §3 the race-wide direction (from) at the current time. */
WM_API float wm_world_wind_global_from(wm_world* w);
/* wind.md §7 current at a point, m/s east and north. */
WM_API wm_status wm_world_current(wm_world* w, float x, float y, float* cx, float* cy);
/* wind.md §9 live puff and lull patches at the current time: fills up to `cap`, returns the count available.
 * Each patch: px, py, R, s, e (repeat every puff tile). */
typedef struct wm_puff {
  float px, py, R, s, e;
} wm_puff;
WM_API int32_t wm_world_puffs(wm_world* w, wm_puff* out, int32_t cap);
WM_API float wm_world_puff_tile(const wm_world* w);

/* The same at any time t_ms of the environment clock, fractional: renderers draw between ticks (wind.md §9 render
 * time; NaN and negative times are 0). The wind is a pure function of (seed, t, position), so at a whole
 * millisecond these give the bits the simulation sees. */
WM_API int32_t wm_world_puffs_at(wm_world* w, double t_ms, wm_puff* out, int32_t cap);
WM_API wm_status wm_world_current_at(wm_world* w, float x, float y, double t_ms, float* cx, float* cy);

/* wind.md §1, §3, §6 what a renderer needs besides the patches. */
typedef struct wm_wind_state {
  float base_speed, base_from;   /* m/s, rad compass */
  float global_from;             /* at the given time */
  float puff_tile;               /* m */
  float cap_up, cap_down;        /* puff factor caps */
  int32_t puffs;                 /* bool: puffs enabled */
} wm_wind_state;
WM_API wm_status wm_world_wind_state(wm_world* w, double t_ms, wm_wind_state* out);  /* t_ms as wm_world_puffs_at */

/* The environment clock: tick 0 of the world is its zero (race.md §0), so the state after the last step is at
 * 50 * tick ms and a render pose at alpha is at 50 * (tick - 1 + alpha) ms (0 before the first step). */
WM_API uint32_t wm_world_time_ms(const wm_world* w);
WM_API double wm_world_render_time_ms(const wm_world* w, float alpha);

/* sea.md §4 height (m) and slope at a point at the current time; 0 on flat water. */
WM_API float wm_world_sea_height(wm_world* w, float x, float y);
WM_API wm_status wm_world_sea_slope(wm_world* w, float x, float y, float* dx, float* dy);
/* sea.md §6 exposure at a point (1 without a sea). */
WM_API float wm_world_sea_exposure(const wm_world* w, float x, float y);
/* sea.md §7.1 the wave components for renderers: fills up to `cap`, returns the count. */
typedef struct wm_sea_component {
  float a, kx, ky, c;            /* m, cycles per metre (travel direction), phase cycles */
  uint32_t T;                    /* period, ms */
} wm_sea_component;
WM_API int32_t wm_world_sea_components(const wm_world* w, wm_sea_component* out, int32_t cap);
/* sea.md §6 the venue's exposure grid (data_format.md §6.4): WM_ERR_ABSENT without one (exposure is then
 * `exposure_default` everywhere). `e` holds nx * ny values, x fastest; valid while the world lives. */
typedef struct wm_exposure_grid {
  float x0, y0, dx, dy;
  uint32_t nx, ny;
  float exposure_default;
  const float* e;
} wm_exposure_grid;
WM_API wm_status wm_world_sea_exposure_grid(const wm_world* w, wm_exposure_grid* out);
/* sea.md §4, §7.2 height at any time of the environment clock, fractional ms (renderers, cameras between ticks;
 * NaN and negative times are 0). */
WM_API float wm_world_sea_height_at(wm_world* w, float x, float y, double t_ms);

/* ---- venue ------------------------------------------------------------------------------------------------- */

/* data_format.md §6.5 the venue's land polygons and obstacles, in file order: the shapes the collisions use
 * (collisions.md §2.2), for renderers and cameras. Counts are 0 on open water. */
enum { WM_OBSTACLE_POLYGON = 0, WM_OBSTACLE_CIRCLE };

typedef struct wm_land {
  const char* id;
  int32_t point_count;           /* counter-clockwise, interior = land */
} wm_land;

typedef struct wm_obstacle {
  const char* id;
  int32_t kind;                  /* WM_OBSTACLE_* */
  int32_t point_count;           /* polygon: convex, counter-clockwise; 0 for a circle */
  float cx, cy, r;               /* circle: centre and radius, m; 0 for a polygon */
} wm_obstacle;

WM_API int32_t wm_world_land_count(const wm_world* w);
WM_API wm_status wm_world_land(const wm_world* w, int32_t i, wm_land* out);
WM_API wm_status wm_world_land_point(const wm_world* w, int32_t i, int32_t k, float* x, float* y);
WM_API int32_t wm_world_obstacle_count(const wm_world* w);
WM_API wm_status wm_world_obstacle(const wm_world* w, int32_t i, wm_obstacle* out);
WM_API wm_status wm_world_obstacle_point(const wm_world* w, int32_t i, int32_t k, float* x, float* y);

/* ---- course ------------------------------------------------------------------------------------------------ */

enum { WM_MARK_BUOY = 0, WM_MARK_COMMITTEE_BOAT, WM_MARK_MARK_BOAT, WM_MARK_VIRTUAL };
enum { WM_SIDE_PORT = 0, WM_SIDE_STARBOARD };
enum { WM_STEP_START = 0, WM_STEP_MARK, WM_STEP_GATE, WM_STEP_FINISH };

typedef struct wm_course_info {
  const char* id;
  float twd_c;                   /* course axis, rad (courses.md §6.1) */
  float k;                       /* scale (courses.md §6.3) */
  int32_t mark_count, step_count, laps;
  int32_t boundary_count;        /* 0 = no boundary */
  float zone_lengths;            /* rules.md §7.1 zone in hull lengths of the race (2 in a match race; laid: the course's) */
} wm_course_info;

typedef struct wm_mark {
  const char* id;
  int32_t type;                  /* WM_MARK_* */
  float x, y, radius, heading, length, beam;
  float zone_r;                  /* rules.md §7.1: the zone is zone_lengths·L plus this, from the mark's centre */
} wm_mark;

/* One expanded step: start line, marks, gates, finish line (courses.md §4.4). */
typedef struct wm_step {
  int32_t kind;                  /* WM_STEP_* */
  int32_t marks[2];              /* mark: marks[0]; gate: both buoys; lines: ends A, B */
  int32_t sides[2];              /* WM_SIDE_* */
  int32_t gate_cross;            /* bool: crossing gate */
  int32_t lap, leg_in_lap;
  float ref_x, ref_y;
} wm_step;

/* The resolved course of the race or the laid course (WM_ERR_STATE without either). */
WM_API wm_status wm_world_course(const wm_world* w, wm_course_info* out);
WM_API wm_status wm_world_course_mark(const wm_world* w, int32_t mark, wm_mark* out);
WM_API wm_status wm_world_course_step(const wm_world* w, int32_t step, wm_step* out);
WM_API wm_status wm_world_course_boundary(const wm_world* w, int32_t i, float* x, float* y);

/* ---- race -------------------------------------------------------------------------------------------------- */

enum { WM_RACE_CREATED = 0, WM_RACE_FREE_SAILING, WM_RACE_SEQUENCE, WM_RACE_RACING, WM_RACE_CLOSING,
       WM_RACE_CLOSED, WM_RACE_ABANDONED };
enum { WM_SCORE_NONE = 0, WM_SCORE_ZFP, WM_SCORE_DNC, WM_SCORE_DNS, WM_SCORE_OCS, WM_SCORE_UFD, WM_SCORE_BFD,
       WM_SCORE_DNF, WM_SCORE_RET, WM_SCORE_DSQ };
enum { WM_GHOST_NONE = 0, WM_GHOST_FINISHED, WM_GHOST_RETIRED, WM_GHOST_DSQ, WM_GHOST_UFD, WM_GHOST_BFD,
       WM_GHOST_DNF, WM_GHOST_DNS, WM_GHOST_LEFT };

typedef struct wm_race_info {
  int32_t state;                 /* WM_RACE_* */
  int32_t race_type, sequence, prep_flag;
  uint32_t n_created;
  int64_t n_gun;                 /* tick of the start signal */
  float race_time;               /* s relative to the gun at the current tick (< 0 before it) */
  int32_t general_recalls;
  int32_t x_flag, rules_live;
  float twd_mean;
  float L_max;
  int32_t boat_count;
} wm_race_info;

/* race.md §4 to §8 per boat. */
typedef struct wm_race_boat {
  int32_t started;
  float t_start;
  int32_t ocs, ocs_i, ocs_scored, returning;
  int32_t next;                  /* next step; 0 = not started */
  int32_t last_rounded;
  int32_t finished;
  int64_t t_finish_us;
  int32_t place;
  int32_t ghost, ghost_reason;   /* WM_GHOST_* */
  int32_t retired, dsq;
  int32_t code;                  /* WM_SCORE_* */
  float D;                       /* distance to finish for the ranking, m */
  int32_t rank;
} wm_race_boat;

typedef struct wm_result {
  int32_t boat, place, code;
  float points;
  int64_t t_finish_us;
  int32_t projected;
} wm_result;

WM_API wm_status wm_world_race(const wm_world* w, wm_race_info* out);
WM_API wm_status wm_world_race_boat(const wm_world* w, int32_t boat, wm_race_boat* out);
/* Boat indices by rank: fills up to `cap`, returns the count. */
WM_API int32_t wm_world_race_order(const wm_world* w, int32_t* out, int32_t cap);
WM_API int32_t wm_world_result_count(const wm_world* w);
WM_API wm_status wm_world_result(const wm_world* w, int32_t i, wm_result* out);
WM_API const char* wm_score_code_name(int32_t code);
/* race.md §8.4 the race time (s after the gun) at which the boat completed step `step` (0: her start time):
 * WM_ERR_ABSENT when she has not completed it. */
WM_API wm_status wm_world_race_split(const wm_world* w, int32_t boat, int32_t step, float* t);

/* race.md §3.3 the boat's rules hull against the start line at the current tick (hud.md §9.2), whatever the race
 * state. The line ends A, B are oriented with the course side on the left of A -> B. */
typedef struct wm_start_status {
  float ax, ay, bx, by;          /* line ends A, B */
  float s_bow, u_bow;            /* the bow: signed distance (m, > 0 on the course side), position along A -> B */
  int32_t in_band;               /* some hull point has s > 0 and 0 <= u <= 1 */
  int32_t course_side;           /* some hull point has s > 0 */
  int32_t in_triangle;           /* some hull point is inside the start triangle */
  int32_t pre_start;             /* every hull point has s <= 0 */
  int32_t over;                  /* over under the race's prep flag: P in_band, I course_side, Z/U/black in_triangle */
} wm_start_status;
WM_API wm_status wm_world_race_start_status(const wm_world* w, int32_t boat, wm_start_status* out);

/* ---- rules ------------------------------------------------------------------------------------------------- */

/* rules.md §11.3 rule codes, in this order. */
enum { WM_RULE_NONE = 0, WM_RULE_10, WM_RULE_11, WM_RULE_12, WM_RULE_13, WM_RULE_14, WM_RULE_15, WM_RULE_16_1,
       WM_RULE_16_2, WM_RULE_17, WM_RULE_18_2, WM_RULE_18_3, WM_RULE_18_4, WM_RULE_19, WM_RULE_20, WM_RULE_21_1,
       WM_RULE_21_2, WM_RULE_31, WM_RULE_LATE, WM_RULE_C_PREP, WM_RULE_C_ENTRY, WM_RULE_SI_BOUNDARY };
WM_API const char* wm_rule_code_name(int32_t rule);

/* rules.md §9.3 why the last started penalty turn was reset. */
enum { WM_TURN_RESET_NONE = 0, WM_TURN_RESET_PAUSED, WM_TURN_RESET_REVERSED, WM_TURN_RESET_ZONE,
       WM_TURN_RESET_ROUNDED };

/* rules.md §11.2 per boat. */
typedef struct wm_boat_rules {
  int32_t tack;                  /* +1 starboard, -1 port */
  int32_t tacking, turning_for_penalty;
  float turn_progress;           /* rad, signed */
  int32_t turn_tacks, turn_gybes;
  int32_t turn_in_zone;          /* match: a penalty she may take now, inside a rounding mark's zone (no turn counts) */
  int32_t turn_reset;            /* WM_TURN_RESET_*: the last reset of a started turn */
  uint32_t turn_reset_tick;      /* the tick of that reset */
  int32_t pending;               /* penalties to serve */
  int32_t served, received;
  float deadline_s;              /* < 0: none */
  int32_t returning_to_start, dsq, out_of_bounds;
} wm_boat_rules;

typedef struct wm_penalty {
  int32_t rule, other;
  uint32_t tick;
  int32_t count;
} wm_penalty;

enum { WM_REL_NA = 0, WM_REL_I_ASTERN, WM_REL_I_AHEAD, WM_REL_OVERLAPPED, WM_REL_OVERLAPPED_VIA };
enum { WM_KC_CLEAR = 0, WM_KC_WARNING, WM_KC_BREACH };

/* rules.md §11.1 one pair of boats in range. */
typedef struct wm_pair {
  int32_t i, j, relation;
  int32_t kc_giver, kc_holder, kc_rule, kc_state;
  int32_t room_entitled, room_giver, room_rule, room_mark, room_state;
  int32_t rule17_holder;
  int32_t incident, incident_culprit, incident_rule;
  uint32_t incident_tick;
  float gap, ttc;
} wm_pair;

WM_API wm_status wm_world_boat_rules(const wm_world* w, int32_t boat, wm_boat_rules* out);
WM_API wm_status wm_world_boat_penalty(const wm_world* w, int32_t boat, int32_t i, wm_penalty* out);
WM_API int32_t wm_world_pair_count(const wm_world* w);
WM_API wm_status wm_world_pair(const wm_world* w, int32_t i, wm_pair* out);

/* ---- events of the last tick ------------------------------------------------------------------------------- */

enum { WM_EV_SIGNAL = 0, WM_EV_BOAT_OCS, WM_EV_BOAT_RETURNED, WM_EV_STARTED, WM_EV_ROUNDED, WM_EV_FINISH_BLOCKED,
       WM_EV_FINISHED, WM_EV_GHOSTED, WM_EV_RETIRED, WM_EV_JOINED, WM_EV_LEFT, WM_EV_WINDOW_WARNING,
       WM_EV_RACE_CLOSING, WM_EV_RACE_CLOSED, WM_EV_ABANDONED };
enum { WM_SIGNAL_WARNING = 0, WM_SIGNAL_PREP_UP, WM_SIGNAL_PREP_DOWN, WM_SIGNAL_START, WM_SIGNAL_GENERAL_RECALL,
       WM_SIGNAL_X_UP, WM_SIGNAL_X_DOWN };

/* race.md §11 */
typedef struct wm_race_event {
  int32_t kind;                  /* WM_EV_* */
  uint32_t tick;
  int32_t boat;
  int32_t signal;                /* WM_SIGNAL_* */
  int32_t flag;                  /* WM_FLAG_* */
  int32_t step, buoy;
  float t;                       /* race time, s */
  int64_t t_us;                  /* finish time after the gun */
  int32_t place;
  int32_t block;                 /* 0 penalty, 1 ocs */
  int32_t ghost;                 /* WM_GHOST_* */
  float value;
} wm_race_event;

enum { WM_REV_RULE_WARNING = 0, WM_REV_INCIDENT, WM_REV_PENALTY, WM_REV_PENALTY_SERVED, WM_REV_PENALTY_CANCELLED,
       WM_REV_PENALTY_LATE, WM_REV_MARK_TOUCH, WM_REV_PROTESTABLE, WM_REV_PROTESTED, WM_REV_DISQUALIFIED };

/* rules.md §11 */
typedef struct wm_rules_event {
  int32_t kind;                  /* WM_REV_* */
  uint32_t tick;
  int32_t boat, other, rule, count;
  int32_t contact;
  int32_t mark;
  float deadline;
} wm_rules_event;

enum { WM_CONTACT_BOAT = 0, WM_CONTACT_MARK, WM_CONTACT_COURSE_OBJECT, WM_CONTACT_OBSTACLE, WM_CONTACT_LAND };

/* collisions.md §5 */
typedef struct wm_contact_event {
  uint64_t tick;
  int32_t boat, other_kind, other;
  float point_x, point_y, normal_x, normal_y;
  float depth, closing_speed, impulse;
  int32_t begin;
} wm_contact_event;

WM_API int32_t wm_world_race_event_count(const wm_world* w);
WM_API wm_status wm_world_race_event(const wm_world* w, int32_t i, wm_race_event* out);
WM_API int32_t wm_world_rules_event_count(const wm_world* w);
WM_API wm_status wm_world_rules_event(const wm_world* w, int32_t i, wm_rules_event* out);
WM_API int32_t wm_world_contact_event_count(const wm_world* w);
WM_API wm_status wm_world_contact_event(const wm_world* w, int32_t i, wm_contact_event* out);

#ifdef __cplusplus
}
#endif

#endif /* WINDMARK_H */
