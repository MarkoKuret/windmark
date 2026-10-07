class_name CoreSimSource
extends SimSource
## SimSource over the Windmark core: the CoreSim class of the GDExtension (game/native, over the C API of
## core/include/windmark.h). A drop-in replacement for FakeSim: the same SimSource calls, the same add_boat and
## sea clock helpers, plus what the sea renderer and the wakes read (sea_components, sea_exposure, wind_state,
## current_at: the SeaEnvSource calls, straight from the core, so drawn puffs are the puffs the boats sail in).
##
## The extension is optional for the rest of the project: this script refers to CoreSim only by name, so it
## parses when game/bin has no library (available() is then false and create() fails).
##
## Clock: the world's tick 0 is the environment clock's zero, so tick n is at sea_time_ms(n) = 50 n, and a
## render pose at alpha is at sea_time_ms(tick() - 1 + alpha) (render_time_ms(alpha) gives the same from the core).

## Sail types in the order of the C API's WM_SAIL_* values, as SailInfo.type names them.
const SAIL_TYPES := ["main", "jib", "genoa", "code_zero", "spinnaker_sym", "spinnaker_asym"]

## Field orders of the PackedFloat32Array records of CoreSim (the C structs' order).
const STATE_FIELDS := [
	"pos_x", "pos_y", "z", "psi", "v", "sway", "h", "yaw_rate", "phi", "phi_rate", "theta", "theta_rate",
	"wobble_phase", "contact_vx", "contact_vy", "contact_yaw_rate", "twd_from", "awd_from", "tws", "twa", "aws", "awa",
	"v_filt", "sog_filt_x", "sog_filt_y",
]
const OUTPUT_FIELDS := [
	"target_speed", "polar_speed", "heel_target", "turn_rate", "vmg", "sog", "cog", "man_coef", "trim_speed",
	"trim_heel", "heel_coef", "surf_coef", "wind_speed_clean",
]
const POSE_FIELDS := ["pos_x", "pos_y", "z", "psi", "theta", "phi", "h", "twa", "twd_from"]
const ENV_FIELDS := [
	"wind_speed", "wind_from", "wind_speed_clean", "wind_from_clean", "current_x", "current_y", "shadow_loss",
	"shadow_header", "shadow_source",
]

## AI levels by name, in the C API's order (WM_AI_*, ai.md §13)
const AI_LEVELS := ["easy", "intermediate", "expert", "pro"]

## the CoreSim object (untyped: see above); null until create()
var core: Object = null
## world settings used by the next create(), CoreSim.default_settings() keys (race_seed, wind_speed, wind_from,
## shift_preset, puffs, oscillation, sea, sea_scale, shadows, race and rules settings)
var settings := {}
## the drawn sea's clock offset is always 0 here; kept for FakeSim callers
var sea_t0_ms := 0.0

## called before every step() (rules scenarios: ScenarioRun.pilot steers its hold boats here); empty: none
var before_step := Callable()

var _err := ""
var _info := {}  # class id -> ClassInfo
var _ai_level := {}  # boat -> AI level name of add_ai
var _fixed := {}  # records fixed for the world's life: the course, its labels
var _boat_class: Array[String] = []
## records of the last tick, by integer key: K_* * KIND + boat (the per-boat records) or K_* (the others)
var _cache := {}
## render poses of the last tick by alpha: alpha -> Array of RenderPose by boat (one CoreSim call per alpha)
var _poses := {}

const KIND := 4096
const K_STATE := 1
const K_CONTROLS := 2
const K_OUTPUTS := 3
const K_SAILS := 4
const K_RACE_BOAT := 5
const K_START := 6
const K_RULES := 7
const K_RACE := 8
const K_ORDER := 9
const K_RESULTS := 10
const K_PAIRS := 11
const K_RACE_EVENTS := 12
const K_RULES_EVENTS := 13
const K_CONTACT_EVENTS := 14
## distinct alphas kept per tick (the frame's, the radar's, 1.0)
const POSE_ALPHAS := 4


## Whether the GDExtension is loaded.
static func available() -> bool:
	return ClassDB.class_exists(&"CoreSim")


## The world settings of the C API with their spec defaults (wm_world_settings_init), {} without the extension.
static func default_settings() -> Dictionary:
	return ClassDB.instantiate(&"CoreSim").default_settings() if available() else {}


## The venue file of a bare venue id (data/venues/<id>.venue.json); a path stays as it is.
static func venue_file(venue: String) -> String:
	if venue != "" and not venue.contains("/"):
		return BoatClassData.repo_path("data/venues/%s.venue.json" % venue)
	return venue


## The course file of "<venue>/<id>" (game/data/courses/<venue>/<id>.course.json); a .json path stays as it is.
static func course_file(course: String) -> String:
	if course == "" or course.ends_with(".json"):
		return course
	return BoatClassData.repo_path("game/data/courses/%s.course.json" % course)


## race.md §2.1: `settings` (CoreSim keys, with `weather`: 0 local, 1 random, 2 custom) with the venue's conditions
## resolved for the seed into every wind, current and sea setting, once before create(); `course` gives the tide's
## timing ("" free sailing). {} on failure, with the reason appended to `why`.
static func resolve_settings(s: Dictionary, venue: String, course := "", why := []) -> Dictionary:
	if not available():
		why.append("the Windmark GDExtension is not loaded")
		return {}
	var c: Object = ClassDB.instantiate(&"CoreSim")
	var r: Dictionary = c.resolve_settings(s, venue_file(venue), course_file(course))
	if r.is_empty():
		why.append(c.last_error())
	return r


## the venue file the world was created on ("" for open water)
var venue_path := ""
## the course file of the race ("" without one)
var course_path := ""


## Creates the world from `settings` on the venue file (data/venues/<venue>.venue.json when a bare name, "" for
## open water). Returns false with last_error() on failure.
func create(venue := "") -> bool:
	if not available():
		_err = "the Windmark GDExtension is not loaded (build it with game/native/build.sh)"
		return false
	if core != null:
		_err = "the world exists already"
		return false
	core = ClassDB.instantiate(&"CoreSim")
	var path := venue_file(venue)
	if not core.create(settings, path):
		_err = core.last_error()
		core = null
		return false
	venue_path = path
	return true


func last_error() -> String:
	return _err


## FakeSim's call: adds a boat of class `id` and places it for free sailing at (pos_x, pos_y) on heading psi.
## The core starts it at 60 % of its polar speed (boat.md §6.6), so `v` is not used. Creates an open-water
## world first when none exists. Returns the boat index, -1 on failure.
func add_boat(id: String, pos_x := 0.0, pos_y := 0.0, psi := 0.0, _v := 0.0, auto_trim := true) -> int:
	if core == null and not create():
		push_error("CoreSimSource: " + _err)
		return -1
	var b := add_entry(id, {"auto_trim": auto_trim})
	if b < 0:
		return -1
	if not core.place_boat(b, pos_x, pos_y, psi):
		_err = core.last_error()
		push_error("CoreSimSource: place boat %d: %s" % [b, _err])
		return -1
	return b


## Adds a race entry of class `id` (placed by create_race, or by place_boat for free sailing). `entry` keys:
## human, ai, performance_scale, auto_trim, front_sail (-2 = the class's start sail). Returns the boat index.
func add_entry(id: String, entry := {}) -> int:
	var b: int = core.add_boat(BoatClassData.repo_path("data/perf/%s.perf.json" % id), entry)
	if b < 0:
		_err = core.last_error()
		push_error("CoreSimSource: add boat %s: %s" % [id, _err])
		return -1
	while _boat_class.size() <= b:
		_boat_class.append("")
	_boat_class[b] = id
	_invalidate()
	return b


## Adds an AI boat of class `id` sailed by the core's AI skippers (ai.md) at `level` (an AI_LEVELS name or its
## index); `speed_only`: Intermediate decisions with the level's performance_scale. Returns the boat index.
func add_ai(id: String, level: Variant = "intermediate", speed_only := false) -> int:
	var lv := ai_level_index(level)
	var b: int = core.add_ai_boat(BoatClassData.repo_path("data/perf/%s.perf.json" % id), lv, speed_only)
	if b < 0:
		_err = core.last_error()
		push_error("CoreSimSource: add AI boat %s: %s" % [id, _err])
		return -1
	_ai_level[b] = AI_LEVELS[lv]
	while _boat_class.size() <= b:
		_boat_class.append("")
	_boat_class[b] = id
	_invalidate()
	return b


## The C API level of a name ("expert") or index; unknown names give intermediate.
static func ai_level_index(level: Variant) -> int:
	if level is int:
		return clampi(level, 0, AI_LEVELS.size() - 1)
	var i := AI_LEVELS.find(String(level).to_lower())
	return i if i >= 0 else 1


## ai.md §14: an AI takes over boat b as it is (a disconnected human), release hands it back.
func ai_take_over(b: int) -> bool:
	return core.ai_take_over(b)


## race.md §6.2: only the finished-boat autopilot for boat b (an offline human boat: it steers her from her finish)
func ai_add_autopilot(b: int) -> bool:
	return core.ai_add_autopilot(b)


## race.md §6.4: boat b retires (RET after her start, DNS before it)
func retire(b: int) -> bool:
	return core.retire(b)


func ai_release(b: int) -> bool:
	return core.ai_release(b)


## Whether an AI sails boat b now.
func ai_has(b: int) -> bool:
	return core != null and core.ai_has(b)


func ai_level(b: int) -> String:
	if not ai_has(b):
		return ""
	return String(_ai_level.get(b, "AI")).capitalize()


## ai.md §15 telemetry of an AI boat ({} for a boat no AI sailed): tacks, gybes, penalties, ocs, activations
## (tactic name -> count), stuck_s, min_gap, sail_changes, bad_air ([tick, d_at, d_after]), start_delay.
func ai_telemetry(b: int) -> Dictionary:
	return core.ai_telemetry(b)


## The AI's last decision: tactic, tactic_name, psi_target, d, twd_ref, twd_f, tws_f, leg, manoeuvre, aim, spot.
func ai_debug(b: int) -> Dictionary:
	return core.ai_debug(b)


## The world snapshot and the AI skippers' memory, taken between ticks (conventions.md §9.1, ai.md §16).
func save_snapshot() -> Dictionary:
	return {"world": core.save_world(), "ai": core.ai_save()}


## Resumes a save_snapshot() in this world, which must be new: created with the same settings and venue and the same
## boats added in the same order, no race. `course` as create_race takes it ("" when the save has no race).
func load_snapshot(snap: Dictionary, course := "") -> bool:
	var path := course
	if course != "" and not course.ends_with(".json"):
		path = BoatClassData.repo_path("game/data/courses/%s.course.json" % course)
	_invalidate()
	if not core.load_world(path, snap.get("world", PackedByteArray())):
		_err = core.last_error()
		return false
	if snap.has("ai") and not core.ai_load(snap["ai"]):
		_err = core.last_error()
		return false
	return true


## Fast-forward without rendering: n ticks, or fewer when the race closes first; returns the ticks stepped.
## Only the last tick's events stay readable.
func step_ticks(n: int, stop_when_closed := true) -> int:
	var k: int = core.step_ticks(n, stop_when_closed)
	_invalidate()
	return k


func place_boat(b: int, x: float, y: float, psi: float) -> bool:
	_invalidate()
	if core.place_boat(b, x, y, psi):
		return true
	_err = core.last_error()
	return false


## Rules scenarios (race.md §14): puts boat b at a pose with speed v (m/s) and front sail (index, -1 none, -2 the one
## up now) at any time, before or after the race is created (wm_world_scenario_place).
func scenario_place(b: int, x: float, y: float, psi: float, v: float, front_sail := -2) -> bool:
	_invalidate()
	if core.scenario_place(b, x, y, psi, v, front_sail):
		return true
	_err = core.last_error()
	return false


## An AI skipper of `level` sails boat b from the next step on (wm_world_ai_add).
func ai_add(b: int, level: Variant = "intermediate", speed_only := false) -> bool:
	var lv := ai_level_index(level)
	if not core.ai_add(b, lv, speed_only):
		_err = core.last_error()
		return false
	_ai_level[b] = AI_LEVELS[lv]
	return true


## Creates the race on a course file (game/data/courses/<venue>/<course>.course.json when "venue/course").
func create_race(course: String) -> bool:
	var path := course_file(course)
	_invalidate()
	if core.create_race(path):
		course_path = path
		return true
	_err = core.last_error()
	return false


## Environment clock (ms) at a fractional tick count, as FakeSim.sea_time_ms.
func sea_time_ms(ticks: float) -> float:
	return sea_t0_ms + ticks * DT * 1000.0


## The core's render time of a pose at alpha (ms): 50 (tick - 1 + alpha), 0 before the first step.
func render_time_ms(alpha: float) -> float:
	return core.render_time_ms(alpha)


func checksum() -> int:
	return core.checksum() if core else 0


# ---- SimSource ----------------------------------------------------------------------------------------------

func tick() -> int:
	return core.tick() if core else 0


func boat_count() -> int:
	return core.boat_count() if core else 0


func class_info(boat: int) -> ClassInfo:
	var id := _boat_class[boat]
	if not _info.has(id):
		_info[id] = _build_info(boat, id)
	return _info[id]


func state(boat: int) -> BoatState:
	var k := K_STATE * KIND + boat
	var v: BoatState = _cache.get(k)
	if v == null:
		v = _state_of(core.boat_state(boat))
		_cache[k] = v
	return v


func controls(boat: int) -> BoatControls:
	var k := K_CONTROLS * KIND + boat
	var c: BoatControls = _cache.get(k)
	if c == null:
		var a: PackedFloat32Array = core.boat_controls(boat)
		c = BoatControls.new()
		c.h_cmd = a[0]
		c.sheet_cmd = a[1]
		c.auto_trim = a[2] != 0.0
		c.let_fly = a[3] != 0.0
		c.performance_scale = a[4]
		_cache[k] = c
	return c


func outputs(boat: int) -> BoatOutputs:
	var k := K_OUTPUTS * KIND + boat
	var v: BoatOutputs = _cache.get(k)
	if v == null:
		v = _fill(BoatOutputs.new(), OUTPUT_FIELDS, core.boat_outputs(boat))
		_cache[k] = v
	return v


func sails(boat: int) -> SailsView:
	var k := K_SAILS * KIND + boat
	var v: SailsView = _cache.get(k)
	if v == null:
		v = _build_sails(boat)
		_cache[k] = v
	return v


## One CoreSim call per alpha and tick for every boat's pose (render_poses); the poses are shared by the callers of
## the same alpha until the next tick, so they are read-only.
func render_pose(boat: int, alpha: float) -> RenderPose:
	return render_poses(alpha)[boat]


func render_poses(alpha: float) -> Array:
	var a := clampf(alpha, 0.0, 1.0)
	var list: Variant = _poses.get(a)
	if list != null:
		return list
	if _poses.size() >= POSE_ALPHAS:
		_poses.clear()
	var f: PackedFloat32Array = core.render_poses(a)
	var out := []
	var n := f.size() / POSE_FIELDS.size()
	out.resize(n)
	for b in n:
		var o := b * 9
		var p := RenderPose.new()
		p.pos_x = f[o]
		p.pos_y = f[o + 1]
		p.z = f[o + 2]
		p.psi = f[o + 3]
		p.theta = f[o + 4]
		p.phi = f[o + 5]
		p.h = f[o + 6]
		p.twa = f[o + 7]
		p.twd_from = f[o + 8]
		out[b] = p
	_poses[a] = out
	return out


func wind_clean(x: float, y: float) -> Vector2:
	return core.wind_clean(x, y)


func sea_height(x: float, y: float) -> float:
	return core.sea_height(x, y)


## Sea height at time t (s since tick 0), as FakeSim.sea_height_at (the core resolves whole milliseconds).
func sea_height_at(x: float, y: float, t: float) -> float:
	return core.sea_height_at(x, y, int(maxf(0.0, t * 1000.0)))


func trim_speed_at(boat: int, tws: float, awa_abs: float, eps: float) -> float:
	return core.trim_speed_at(boat, tws, awa_abs, eps)


## Applies the frame as the server sees it: the 6-byte wire form decoded (networking.md §4.1), so helm and sheet
## are the quantised values every peer applies.
func apply_input(boat: int, frame: InputFrame) -> int:
	var q := InputFrame.decode(frame.encode(), frame.tick)
	return core.apply_input(boat, q.h_cmd, q.sheet_cmd, q.sail_req, q.flags)


func step() -> void:
	if before_step.is_valid():
		before_step.call()
	core.step()
	_invalidate()


## The tick on the CoreSim's worker thread (game/README.md "The simulation on a second core"): step_begin() starts
## it, step_end() waits for it and drops the cached records. In between every CoreSim call waits for the tick
## first, and the records cached before it (the frame's) stay readable.
func can_step_async() -> bool:
	return core != null


func step_begin() -> void:
	if before_step.is_valid():
		before_step.call()
	if not core.step_begin():
		core.step()


func step_end() -> void:
	core.step_end()
	_invalidate()


# ---- race and rules (SimSource readers, cached until the next step) ------------------------------------------

## the records of the last tick by key (null: not read yet)
func _put(k: int, v: Variant) -> Variant:
	_cache[k] = v
	return v


func has_race() -> bool:
	return core != null and core.has_race()


func race() -> Dictionary:
	if core == null:
		return {}
	var v: Variant = _cache.get(K_RACE)
	return v if v != null else _put(K_RACE, core.race())


func race_boat(boat: int) -> Dictionary:
	if core == null:
		return {}
	var v: Variant = _cache.get(K_RACE_BOAT * KIND + boat)
	return v if v != null else _put(K_RACE_BOAT * KIND + boat, core.race_boat(boat))


func race_order() -> PackedInt32Array:
	if core == null:
		return PackedInt32Array()
	var v: Variant = _cache.get(K_ORDER)
	return v if v != null else _put(K_ORDER, core.race_order())


## the resolved course does not change during the race: cached for the world's life
func course() -> Dictionary:
	if core == null:
		return {}
	if not _fixed.has("course"):
		var c: Dictionary = core.course()
		if c.is_empty():
			return c
		_fixed["course"] = c
	return _fixed["course"]


func course_labels() -> Dictionary:
	if course_path == "":
		return {}
	if not _fixed.has("labels"):
		var d: Variant = BoatClassData._read_json(course_path)
		_fixed["labels"] = d.get("display", {}).get("labels", {}) if d is Dictionary else {}
	return _fixed["labels"]


func results() -> Array:
	if core == null:
		return []
	var v: Variant = _cache.get(K_RESULTS)
	return v if v != null else _put(K_RESULTS, core.results())


func race_split(boat: int, step_index: int) -> float:
	return core.race_split(boat, step_index) if core else NAN


func race_start_status(boat: int) -> Dictionary:
	if core == null:
		return {}
	var v: Variant = _cache.get(K_START * KIND + boat)
	return v if v != null else _put(K_START * KIND + boat, core.race_start_status(boat))


func boat_rules(boat: int) -> Dictionary:
	if core == null:
		return {}
	var v: Variant = _cache.get(K_RULES * KIND + boat)
	return v if v != null else _put(K_RULES * KIND + boat, core.boat_rules(boat))


func pairs() -> Array:
	if core == null:
		return []
	var v: Variant = _cache.get(K_PAIRS)
	return v if v != null else _put(K_PAIRS, core.pairs())


func race_events() -> Array:
	if core == null:
		return []
	var v: Variant = _cache.get(K_RACE_EVENTS)
	return v if v != null else _put(K_RACE_EVENTS, core.race_events())


func rules_events() -> Array:
	if core == null:
		return []
	var v: Variant = _cache.get(K_RULES_EVENTS)
	return v if v != null else _put(K_RULES_EVENTS, core.rules_events())


func contact_events() -> Array:
	if core == null:
		return []
	var v: Variant = _cache.get(K_CONTACT_EVENTS)
	return v if v != null else _put(K_CONTACT_EVENTS, core.contact_events())


func polar_vmg(boat: int, tws: float) -> Dictionary:
	return core.polar_vmg(boat, tws) if core else {}


func polar(boat: int, tws: float, twa: float, front_sail: int) -> float:
	return core.polar(boat, tws, twa, front_sail) if core else NAN


# ---- environment for the sea renderer (the SeaEnvSource calls) ---------------------------------------------

## sea.md §7.1 wave components: Array of [a, kx, ky, c, T]
func sea_components() -> Array:
	return core.sea_components() if core else []


## sea.md §6 exposure grid {x0, y0, dx, dy, nx, ny, default, e}, {} without one
func sea_exposure() -> Dictionary:
	return core.sea_exposure() if core else {}


## wind.md: {base_speed, base_from, global_from, puff_tile, cap_up, cap_down, puffs, patches: [[px, py, R, s, e]]}
## at environment time t_ms (whole ms)
func wind_state(t_ms: float) -> Dictionary:
	return core.wind_state(int(maxf(0.0, t_ms)))


## wind.md §7 current at a point and time, Vector2(east, north) m/s
func current_at(x: float, y: float, t_ms: float) -> Vector2:
	return core.current_at(x, y, int(maxf(0.0, t_ms)))


## wind_shadow.md §5 environment the boat stepped in: {wind_speed, wind_from, ..., shadow_source}
func boat_env(boat: int) -> Dictionary:
	var a: PackedFloat32Array = core.boat_env(boat)
	var d := {}
	for i in ENV_FIELDS.size():
		d[ENV_FIELDS[i]] = a[i]
	d["shadow_source"] = int(a[8])
	return d


## SeaWakes.update_boat state of a boat at a render pose: pose, class waterline and transom.
func wake_state(boat: int, p: RenderPose, own := false) -> Dictionary:
	return wake_state_into({}, boat, p, own)


## wake_state written into `d` (a Dictionary kept per boat, so a frame makes none): the class keys once, the pose
## every call. Returns d.
func wake_state_into(d: Dictionary, boat: int, p: RenderPose, own := false) -> Dictionary:
	if not d.has("lwl"):
		var info := class_info(boat)
		d["lwl"] = info.lwl
		d["bwl"] = info.bwl
		d["transom_width"] = info.transom_width
		d["bow_x"] = 0.5 * info.lwl
		d["stern_x"] = -0.5 * info.lwl
	d["x"] = p.pos_x
	d["y"] = p.pos_y
	d["z"] = p.z
	d["psi"] = p.psi
	d["heel"] = p.phi
	d["pitch"] = p.theta
	d["own"] = own
	return d


# ---- internals ----------------------------------------------------------------------------------------------

## The world changed: every record of the last tick is read again.
func _invalidate() -> void:
	_cache.clear()
	_poses.clear()


static func _state_of(a: PackedFloat32Array) -> BoatState:
	var s := BoatState.new()
	s.pos_x = a[0]
	s.pos_y = a[1]
	s.z = a[2]
	s.psi = a[3]
	s.v = a[4]
	s.sway = a[5]
	s.h = a[6]
	s.yaw_rate = a[7]
	s.phi = a[8]
	s.phi_rate = a[9]
	s.theta = a[10]
	s.theta_rate = a[11]
	s.wobble_phase = a[12]
	s.contact_vx = a[13]
	s.contact_vy = a[14]
	s.contact_yaw_rate = a[15]
	s.twd_from = a[16]
	s.awd_from = a[17]
	s.tws = a[18]
	s.twa = a[19]
	s.aws = a[20]
	s.awa = a[21]
	s.v_filt = a[22]
	s.sog_filt_x = a[23]
	s.sog_filt_y = a[24]
	return s

static func _fill(obj: Object, fields: Array, a: PackedFloat32Array) -> Object:
	for i in fields.size():
		obj.set(fields[i], a[i])
	return obj


func _build_sails(boat: int) -> SailsView:
	var d: Dictionary = core.sails(boat)
	var v := SailsView.new()
	v.front = d["front"]
	var bs := state(boat)
	v.awa = bs.awa
	v.aws = bs.aws
	v.tws = bs.tws
	v.queue_len = d["queue_len"]
	v.queue_pos = d["queue_pos"]
	v.queue_progress = d["queue_progress"]
	for st in d["queue"]:
		v.queue.append(SailStep.new(st[0], st[1], st[2]))
	for i in int(d["sail_count"]):
		var a: PackedFloat32Array = core.sail(boat, i)
		var s := SailState.new()
		s.phase = int(a[0])
		s.progress = a[1]
		s.beta = a[2]
		s.pole = a[3]
		v.sails.append(s)
		var o := SailOutput.new()
		o.k_h = a[4]
		o.m_opt = a[5]
		o.beta_opt = a[6]
		o.beta_t = a[7]
		o.trim_error = a[8]
		o.luff_shiver = a[9]
		o.motion = int(a[10])
		o.backed = a[11] != 0.0
		v.out.append(o)
	return v


## Class numbers from the core (perf file) plus what only the class file and the boatgen sidecar hold (name,
## beam, steering, transom width, rig points).
func _build_info(boat: int, id: String) -> ClassInfo:
	var c: Dictionary = core.class_info(boat)
	var info := ClassInfo.new()
	info.id = c["class_id"]
	info.loa = c["loa"]
	info.lwl = c["lwl"]
	info.bwl = c["bwl"]
	info.rudder_max = c["rudder_max"]
	info.main_sail = c["main_sail"]
	for s in c["sails"]:
		var si := SailInfo.new()
		si.name = s["id"]
		si.type = SAIL_TYPES[int(s["type"])]
		si.sheet_min = s["sheet_min"]
		si.sheet_max = s["sheet_max"]
		if si.type != "main":
			info.front_sails.append(info.sails.size())
		info.sails.append(si)
	var cls: Variant = BoatClassData._read_json(BoatClassData.repo_path("data/classes/%s.boat.json" % id))
	var hull: Dictionary = cls.get("hull", {}) if cls is Dictionary else {}
	info.name = cls.get("name", id) if cls is Dictionary else id
	info.beam_max = float(hull.get("beam_max", info.bwl / 0.75))
	info.transom_width = float(hull.get("transom_width", 0.6 * info.bwl))
	if cls is Dictionary:
		info.steering = cls.get("visual", {}).get("deck", {}).get("steering", "tiller")
	var side: Variant = BoatClassData._read_json(
		ProjectSettings.globalize_path("res://generated/boats/%s.physics.json" % id))
	info.physics = side if side is Dictionary else {}
	return info
