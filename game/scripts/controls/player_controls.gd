class_name PlayerControls
extends RefCounted
## The player's boat controls (controls.md §1, §5-§7): read every rendered frame from a RawInput with update(),
## stamped into an InputFrame at each tick boundary with stamp(). Controls set targets only; the simulation
## moves the rudder and the sails.

enum HelmMode { SET_AND_HOLD, HOLD_TO_STEER }
enum Source { KEYS, STICK }

const STICK_SAT := 0.95
const FINE_LIMIT := 0.35
## set and hold (controls.md §5.2): a held key moves h_cmd linearly at KEY_RATE per second (full helm from the
## centre in about 1.18 s), the centring key eases it back at the same rate; helm_fine divides it by KEY_FINE_DIV
const KEY_RATE := 0.85
const KEY_FINE_DIV := 3.0
const STICK_HANDOVER := 0.5  # s inside the dead zone before the keys take over
const RAMP_T := 0.8
const MSG_AUTO_TRIM_REFUSED := "Auto trim is not allowed in this race"

## ---- options (controls.md §6) ----
var helm_mode := HelmMode.SET_AND_HOLD
var stick_dead_zone := 0.10
var stick_gamma := 1.6
var sheet_rate_scale := 1.0
var let_fly_toggle := false
var helm_fine_toggle := false
var sheet_turns_auto_trim_off := false
## lobby assist preset allows auto-trim (hud.md §14)
var auto_trim_allowed := true

## ---- context ----
var sim: SimSource
var boat := 0
## rules hooks (hud.md §11); the placeholder sim has no rules, so nothing is available
var hail_available: Callable = func() -> bool: return false
var hailed: Callable = func() -> bool: return false
var protest_prompt: Callable = func() -> bool: return false

## ---- state ----
var h_cmd := 0.0
var sheet_cmd := 0.0
var auto_trim := true
var let_fly := false
var helm_fine := false
var helm_source := Source.KEYS
## gamepad sail strip highlight (slot index), -1 until first used
var sail_highlight := -1
## chat line open (controls.md §7): buttons and keys blocked, sticks and triggers work
var text_focus := false
var window_focused := true
## pause menu open: the boat keeps its last helm, sheet and let-fly
var menu_open := false
## the free camera takes the boat's helm and sheet keys and the left stick (controls.md §3 note)
var free_camera := false
## HUD feedback since the last read: messages, and a sail press that matched no row (flash the change)
var messages: Array[String] = []
var busy_flash := false

var _stick_dz_time := INF
var _prev_held := {}
var _hold_dir := 0
var _hold_t := 0.0
## set and hold: the direction of the helm keys, and the easing back to the centre
var _key_dir := 0
var _centring := false
var _sheet_dir := 0
var _sheet_e := 0.0
var _last_sheet_axis := NAN
var _sail_presses: Array[int] = []
var _hail := false
var _reply := false
var _protest := false


func bind(source: SimSource, boat_index: int) -> void:
	sim = source
	boat = boat_index
	var c := sim.controls(boat)
	if c:
		h_cmd = c.h_cmd
		sheet_cmd = c.sheet_cmd
		auto_trim = c.auto_trim
		let_fly = c.let_fly


## controls.md §5.1
static func stick_curve(x: float, dz := 0.10, gamma := 1.6, fine := false) -> float:
	var m := clampf((absf(x) - dz) / (STICK_SAT - dz), 0.0, 1.0)
	return signf(x) * pow(m, gamma) * (FINE_LIMIT if fine else 1.0)


## controls.md §5.3 key rate r(e) integrated from 0 to e (so a frame adds R(e + dt) - R(e), at any frame rate)
static func sheet_key_integral(e: float) -> float:
	if e < 0.1:
		return 0.06 * e
	if e <= 1.0:
		var x := e - 0.1
		return 0.006 + 0.06 * x + 0.39 * x * x / (2.0 * 0.9)
	return 0.2355 + 0.45 * (e - 1.0)


static func trigger_curve(t: float) -> float:
	return pow(clampf((t - 0.05) / 0.95, 0.0, 1.0), 1.5)


## One rendered frame.
func update(raw: RawInput, dt: float) -> void:
	if menu_open:
		if not let_fly_toggle:
			let_fly = false
		if helm_mode == HelmMode.HOLD_TO_STEER and helm_source == Source.KEYS:
			h_cmd = 0.0
		_hold_dir = 0
		_key_dir = 0
		_centring = false
		_sheet_dir = 0
		_prev_held = {}
		return
	var r := raw
	if text_focus or not window_focused:
		r = raw.without_buttons()
	# modifiers and flags
	if helm_fine_toggle:
		if r.was_pressed(&"helm_fine"):
			helm_fine = not helm_fine
	else:
		helm_fine = r.is_held(&"helm_fine")
	if let_fly_toggle:
		if r.was_pressed(&"let_fly"):
			let_fly = not let_fly
	else:
		let_fly = r.is_held(&"let_fly")
	if r.was_pressed(&"auto_trim"):
		if auto_trim:
			_auto_trim_off()
		elif auto_trim_allowed:
			auto_trim = true
		else:
			messages.append(MSG_AUTO_TRIM_REFUSED)
	if not free_camera:
		_helm(r, dt)
		_sheet(r, dt)
	elif helm_mode == HelmMode.HOLD_TO_STEER and helm_source == Source.KEYS:
		h_cmd = 0.0  # a hold-to-steer key counts as released while it flies the camera
		_hold_dir = 0
	# sails
	for i in 9:
		if r.was_pressed(StringName("sail_%d" % (i + 1))):
			_sail_presses.append(i)
	if r.was_pressed(&"drop_front"):
		_sail_presses.append(SailRequests.DROP)
	var slots := _slot_count()
	if slots > 0:
		if r.was_pressed(&"sail_prev") or r.was_pressed(&"sail_next"):
			if sail_highlight < 0:
				sail_highlight = _default_highlight()
			var step := -1 if r.was_pressed(&"sail_prev") else 1
			sail_highlight = posmod(sail_highlight + step, slots)
		if r.was_pressed(&"sail_set"):
			if sail_highlight < 0:
				sail_highlight = _default_highlight()
			_sail_presses.append(sail_highlight)
	# hail, protest (the gamepad's D-pad up is both: the protest prompt takes it while it shows)
	var prompt: bool = protest_prompt.call()
	if r.was_pressed(&"protest") and prompt:
		_protest = true
	elif r.was_pressed(&"hail"):
		if hailed.call():
			_reply = true
		elif hail_available.call():
			_hail = true
	_prev_held = r.held.duplicate()


func _helm(r: RawInput, dt: float) -> void:
	var x := r.helm_stick
	if absf(x) > stick_dead_zone:
		helm_source = Source.STICK
		_stick_dz_time = 0.0
	else:
		_stick_dz_time += dt
	var left := r.is_held(&"helm_left")
	var right := r.is_held(&"helm_right")
	var centre := r.was_pressed(&"helm_centre")
	var was_left: bool = _prev_held.get(&"helm_left", false)
	var was_right: bool = _prev_held.get(&"helm_right", false)
	var left_edge := left and not was_left
	var right_edge := right and not was_right
	if helm_source == Source.STICK and _stick_dz_time >= STICK_HANDOVER and (left or right or centre):
		helm_source = Source.KEYS
		_hold_dir = 0
		left_edge = left
		right_edge = right
	if helm_source == Source.STICK:
		h_cmd = stick_curve(x, stick_dead_zone, stick_gamma, helm_fine)
		_key_dir = 0
		_centring = false
		return
	if helm_mode == HelmMode.SET_AND_HOLD:
		var dir := (1 if right else 0) - (1 if left else 0)
		_key_dir = dir
		if dir != 0:
			_centring = false
			var step := KEY_RATE * dt
			var nh := h_cmd + dir * (step / KEY_FINE_DIV if helm_fine else step)
			if helm_fine:  # moves no further out than the fine limit
				nh = minf(nh, maxf(h_cmd, FINE_LIMIT)) if dir > 0 else maxf(nh, minf(h_cmd, -FINE_LIMIT))
			h_cmd = clampf(nh, -1.0, 1.0)
		elif centre:
			_centring = true
		if _centring and dir == 0:
			# eased back to the centre at the key rate, not snapped (the rudder follows smoothly)
			h_cmd = move_toward(h_cmd, 0.0, KEY_RATE * dt)
			if h_cmd == 0.0:
				_centring = false
		return
	# hold to steer: the later key wins; releasing it hands over to the other one if still held
	if right_edge:
		_hold_dir = 1
		_hold_t = 0.0
	if left_edge:
		_hold_dir = -1
		_hold_t = 0.0
	if _hold_dir == 1 and not right:
		_hold_dir = -1 if left else 0
		_hold_t = 0.0
	elif _hold_dir == -1 and not left:
		_hold_dir = 1 if right else 0
		_hold_t = 0.0
	if _hold_dir != 0:
		_hold_t += dt
		var k := minf(1.0, 0.25 + 0.75 * _hold_t / RAMP_T)
		if helm_fine:
			k = minf(k, FINE_LIMIT)
		h_cmd = _hold_dir * k
	else:
		h_cmd = 0.0


func _sheet(r: RawInput, dt: float) -> void:
	var sin_ := r.is_held(&"sheet_in")
	var sout := r.is_held(&"sheet_out")
	var axis_moved := not is_nan(r.sheet_axis) and (is_nan(_last_sheet_axis) \
		or absf(r.sheet_axis - _last_sheet_axis) > 0.002)
	var active := sin_ or sout or r.trigger_in > 0.05 or r.trigger_out > 0.05 or axis_moved
	if auto_trim:
		if active and sheet_turns_auto_trim_off:
			_auto_trim_off()
		else:
			_sheet_dir = 0
			_sheet_e = 0.0
			_last_sheet_axis = r.sheet_axis
			return
	var u := sheet_cmd
	var dir := (1 if sout else 0) - (1 if sin_ else 0)
	if dir != _sheet_dir:
		_sheet_dir = dir
		_sheet_e = 0.0
	if dir != 0:
		var du := sheet_key_integral(_sheet_e + dt) - sheet_key_integral(_sheet_e)
		u += dir * du * sheet_rate_scale / (3.0 if helm_fine else 1.0)
		_sheet_e += dt
	u += (trigger_curve(r.trigger_out) - trigger_curve(r.trigger_in)) * 0.5 * dt
	if axis_moved:
		u = clampf(((r.sheet_axis + 1.0) * 0.5 - 0.02) / 0.96, 0.0, 1.0)
		_last_sheet_axis = r.sheet_axis
	sheet_cmd = clampf(u, 0.0, 1.0)


## controls.md §5.3: switching auto-trim off starts the sheet from the present trim, so nothing jumps.
func _auto_trim_off() -> void:
	auto_trim = false
	if sim == null:
		return
	var sv := sim.sails(boat)
	var info := sim.class_info(boat)
	if sv == null or info == null:
		return
	var i := sv.driving_sail(info.main_sail)
	var si: SimSource.SailInfo = info.sails[i]
	var span := si.sheet_max - si.sheet_min
	if span > 1e-6:
		sheet_cmd = clampf((sv.out[i].m_opt - si.sheet_min) / span, 0.0, 1.0)


func _slot_count() -> int:
	if sim == null or sim.class_info(boat) == null:
		return 0
	return sim.class_info(boat).front_sails.size()


## the slot after the front sail that is up (the HUD sail hint comes with the race HUD)
func _default_highlight() -> int:
	var info := sim.class_info(boat)
	var f := sim.sails(boat).front
	var k := info.front_sails.find(f)
	return 0 if k < 0 else posmod(k + 1, info.front_sails.size())


## The input frame for `tick` (controls.md §1): the latest state, clamped, with at most one latched sail press.
func stamp(tick: int) -> InputFrame:
	var f := InputFrame.new()
	f.tick = tick
	f.h_cmd = clampf(h_cmd, -1.0, 1.0)
	f.sheet_cmd = clampf(sheet_cmd, 0.0, 1.0)
	if let_fly:
		f.flags |= InputFrame.FLAG_LET_FLY
	if auto_trim:
		f.flags |= InputFrame.FLAG_AUTO_TRIM
	if _hail:
		f.flags |= InputFrame.FLAG_HAIL
	if _reply:
		f.flags |= InputFrame.FLAG_HAIL_REPLY
	if _protest:
		f.flags |= InputFrame.FLAG_PROTEST
	_hail = false
	_reply = false
	_protest = false
	if not _sail_presses.is_empty():
		var press: int = _sail_presses.pop_front()
		if sim != null:
			f.sail_req = SailRequests.map(press, sim.sails(boat), sim.class_info(boat))
		if f.sail_req == InputFrame.SAIL_NONE:
			busy_flash = true
	return f


## Chat focus (controls.md §7).
func set_text_focus(on: bool) -> void:
	text_focus = on


## Window focus (controls.md §7): held states are cleared.
func set_window_focus(on: bool) -> void:
	window_focused = on
	if not on:
		_prev_held = {}
