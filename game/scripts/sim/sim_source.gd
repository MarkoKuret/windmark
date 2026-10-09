class_name SimSource
extends RefCounted
## What the front end reads from and sends to the simulation. Everything behind it (the placeholder FakeSim now,
## CoreSimSource over the core binding) keeps this interface, so cameras, controls and HUD do not change.
##
## Field names and units are the core's (boat.md §3, sails.md §3 and §7, wind.md): world ENU metres, radians,
## compass angles clockwise from north, m/s. One tick is DT = 50 ms. The records below are copies taken after
## the last tick; changing them changes nothing in the simulation.

const DT := 0.05

enum Phase { DOWN = 0, PREPARE_HOIST = 1, HOISTING = 2, UP = 3, PREPARE_DROP = 4, DROPPING = 5 }
enum Motion { IDLE = 0, SHEETING = 1, EASING = 2 }
## apply_input() result for the frame's sail request
enum Request { NONE = -1, ACCEPTED = 0, REJECTED = 1 }


## One sail of the class, in sail order (the perf file's order: the main, then the front sails).
class SailInfo:
	var name := ""
	var type := ""  # main, jib, genoa, code_zero, spinnaker_sym, spinnaker_asym
	var sheet_min := 0.0  # rad
	var sheet_max := 0.0  # rad


## Class numbers the front end needs (class file, perf file, boatgen physics sidecar).
class ClassInfo:
	var id := ""
	var name := ""
	var loa := 0.0
	var beam_max := 0.0
	## waterline length and beam of the perf file (the values the core's hull points use), m
	var lwl := 0.0
	var bwl := 0.0
	## class file transom width, m (the stern wake)
	var transom_width := 0.0
	## perf dynamics rudder_max, rad
	var rudder_max := 0.6
	var steering := "tiller"  # tiller or wheel
	var sails: Array[SailInfo] = []
	var main_sail := 0
	## sail indices of the front sails in class order: HUD strip and sail keys slot k -> front_sails[k]
	var front_sails := PackedInt32Array()
	## the boatgen physics sidecar (rig points, sails), {} when not generated
	var physics := {}


## boat.md §3
class BoatState:
	var pos_x := 0.0
	var pos_y := 0.0
	var z := 0.0
	var psi := 0.0
	var v := 0.0
	var sway := 0.0
	var h := 0.0
	var yaw_rate := 0.0
	var phi := 0.0
	var phi_rate := 0.0
	var theta := 0.0
	var theta_rate := 0.0
	var wobble_phase := 0.0
	var contact_vx := 0.0
	var contact_vy := 0.0
	var contact_yaw_rate := 0.0
	var twd_from := 0.0
	var awd_from := 0.0
	var tws := 0.0
	var twa := 0.0
	var aws := 0.0
	var awa := 0.0
	var v_filt := 0.0
	var sog_filt_x := 0.0
	var sog_filt_y := 0.0


## boat.md §2 controls as the boat holds them
class BoatControls:
	var h_cmd := 0.0
	var sheet_cmd := 0.0
	var auto_trim := true
	var let_fly := false
	var performance_scale := 1.0


## boat.md §3 derived outputs
class BoatOutputs:
	var target_speed := 0.0
	var polar_speed := 0.0
	var heel_target := 0.0
	var turn_rate := 0.0
	var vmg := 0.0
	var sog := 0.0
	var cog := 0.0
	var man_coef := 1.0
	var trim_speed := 1.0
	var trim_heel := 1.0
	var heel_coef := 1.0
	var surf_coef := 1.0
	var wind_speed_clean := 0.0


## sails.md §3.1
class SailState:
	var phase := 0
	var progress := 0.0
	var beta := 0.0
	var pole := 0.0


## sails.md §7
class SailOutput:
	var k_h := 0.0
	var m_opt := 0.0
	var beta_opt := 0.0
	var beta_t := 0.0
	var trim_error := 0.0
	var luff_shiver := 0.0
	var motion := 0
	var backed := false


## sails.md §3.2 one step of a change
class SailStep:
	var sail := 0
	var phase := 0
	var reversed := false

	func _init(s: int = 0, p: int = 0, r: bool = false) -> void:
		sail = s
		phase = p
		reversed = r


## sails.md §3.2 per boat, plus every sail's state and output
class SailsView:
	var front := -1
	## the boat's apparent and true wind at this tick (boat.md §3), for drawing the sails (sail_visuals.md §2)
	var awa := 0.0
	var aws := 0.0
	var tws := 0.0
	var queue: Array[SailStep] = []
	var queue_len := 0
	var queue_pos := 0
	var queue_progress := 0.0
	var sails: Array[SailState] = []
	var out: Array[SailOutput] = []

	func busy() -> bool:
		return queue_pos < queue_len

	## the running step, null when idle
	func running() -> SailStep:
		return queue[queue_pos] if busy() else null

	## boat.md §5.4: the front sail if one is up, else the main
	func driving_sail(main_sail: int) -> int:
		return front if front >= 0 else main_sail


## The render pose between two ticks (networking.md §6): what cameras and the boat node draw.
class RenderPose:
	var pos_x := 0.0
	var pos_y := 0.0
	var z := 0.0
	var psi := 0.0
	var theta := 0.0
	var phi := 0.0
	var h := 0.0
	var twa := 0.0
	var twd_from := 0.0


## ---- interface: override every function below ----

## ticks stepped so far; the next step() simulates tick `tick()`
func tick() -> int:
	return 0


func boat_count() -> int:
	return 0


func class_info(_boat: int) -> ClassInfo:
	return null


func state(_boat: int) -> BoatState:
	return null


func controls(_boat: int) -> BoatControls:
	return null


func outputs(_boat: int) -> BoatOutputs:
	return null


func sails(_boat: int) -> SailsView:
	return null


## pose interpolated between the last two ticks, alpha in [0, 1] (1 = the last tick)
func render_pose(_boat: int, _alpha: float) -> RenderPose:
	return null


## wind.md §2 clean wind at a world point for the last tick: Vector2(speed m/s, from rad)
func wind_clean(_x: float, _y: float) -> Vector2:
	return Vector2.ZERO


## sea.md §4 surface height (m, ENU z) at a world point and the render time of the last tick. The camera
## clearance and the boat drawing read the sea through this one hook.
func sea_height(_x: float, _y: float) -> float:
	return 0.0


## The config's trim_speed table (sails.md §6) at a hypothetical trim error, NAN when the config has none.
## For the HUD trim tolerance (hud.md §5).
func trim_speed_at(_boat: int, _tws: float, _awa_abs: float, _eps: float) -> float:
	return NAN


## The input frame stamped for the next tick (networking.md §4.1, controls.md §1). Returns the result of the
## frame's sail request (Request).
func apply_input(_boat: int, _frame: InputFrame) -> int:
	return Request.NONE


## one 50 ms tick
func step() -> void:
	pass


## A tick in two halves, for a sim that steps on another thread (CoreSimSource): step_begin() starts it and
## step_end() takes it in; in between the records read before it stay as they were. Here both halves are step().
func can_step_async() -> bool:
	return false


func step_begin() -> void:
	step()


func step_end() -> void:
	pass


## every boat's render_pose at alpha, by boat index
func render_poses(alpha: float) -> Array:
	var out := []
	for b in boat_count():
		out.append(render_pose(b, alpha))
	return out


# ---- race and rules (race.md, rules.md §11): the HUD's readers. A sim without a race (FakeSim, free sailing)
# returns the empty values below. Dictionaries carry the C API's field names (CoreSim, game/README.md).

## whether a race exists
func has_race() -> bool:
	return false


## race.md §3 race record: state, sequence, prep_flag, n_gun, race_time, x_flag, rules_live, twd_mean, ...
func race() -> Dictionary:
	return {}


## race.md §4 to §8 per boat: started, ocs, ocs_i, returning, next, last_rounded, finished, t_finish_us, place,
## ghost, retired, dsq, code, D, rank
func race_boat(_boat: int) -> Dictionary:
	return {}


## boat indices by live rank (race.md §8.3)
func race_order() -> PackedInt32Array:
	return PackedInt32Array()


## the resolved course: id, twd_c, laps, marks [{id, type, x, y, radius, ...}], steps [{kind, marks, sides,
## lap, leg_in_lap, ref}], boundary
func course() -> Dictionary:
	return {}


## display labels of the course file by mark id (courses.md §8), {} when none
func course_labels() -> Dictionary:
	return {}


## race.md §9 results (after the close): [{boat, place, code, code_name, points, t_finish_us, projected}]
func results() -> Array:
	return []


## race.md §8.4 race time (s) at which the boat completed step `step` (0: her start), NAN when not yet
func race_split(_boat: int, _step: int) -> float:
	return NAN


## race.md §3.3 the rules hull against the start line now: a, b (oriented ends), s_bow, u_bow, in_band,
## course_side, in_triangle, pre_start, over (under the race's prep flag); {} without a race
func race_start_status(_boat: int) -> Dictionary:
	return {}


## rules.md §11.2 per boat: tack, tacking, turning_for_penalty, turn_progress (rad), turn_tacks, turn_gybes,
## turn_in_zone, turn_reset (RaceText.TurnReset), turn_reset_tick,
## pending [{rule, rule_name, other, tick, count}], served, received, deadline_s (< 0 none), dsq, ...
func boat_rules(_boat: int) -> Dictionary:
	return {}


## rules.md §11.1 pair records of the boats in range
func pairs() -> Array:
	return []


## race.md §11 events of the last tick
func race_events() -> Array:
	return []


## rules.md §11.3 events of the last tick
func rules_events() -> Array:
	return []


## collisions.md §5 contact events of the last tick: {tick, boat, other_kind, other, point (Vector2), normal, depth,
## closing_speed, impulse, begin}; [] for a sim without collisions (the audio's contact sounds)
func contact_events() -> Array:
	return []


## rules.md §7.9 hail for room to tack: {available (a valid hail can be made now), hailed_by (boat index or -1)};
## {} while the core has no hail state
func hail_state(_boat: int) -> Dictionary:
	return {}


## the AI level sailing boat b ("Expert"; "AI" for a boat an AI took over), "" for a human
func ai_level(_boat: int) -> String:
	return ""


## ai.md §3.1 polar VMG optima at TWS: {up_twa, up_speed, down_twa, down_speed}, {} when unknown
func polar_vmg(_boat: int, _tws: float) -> Dictionary:
	return {}


## polar speed of a config (front sail index, -1 main only) at TWS and TWA, NAN when unknown
func polar(_boat: int, _tws: float, _twa: float, _front_sail: int) -> float:
	return NAN


## wind.md §7 current at a point and environment time (ms), Vector2(east, north) m/s
func current_at(_x: float, _y: float, _t_ms: float) -> Vector2:
	return Vector2.ZERO
