class_name SimSource
extends RefCounted
## What the front end reads from and sends to the simulation. Everything behind it (the placeholder FakeSim now,
## the core binding of WM-016.01 later) keeps this interface, so cameras, controls and HUD do not change.
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
	var h := 0.0
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
