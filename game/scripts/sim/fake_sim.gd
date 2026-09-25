class_name FakeSim
extends SimSource
## Placeholder simulation behind SimSource until the core binding exists: FakeBoats in a uniform wind with an
## optional slow oscillation of its direction, on flat water, on a simple test swell (sum of three sines, for
## the camera clearance test) or on the drawn sea's own components (use_sea(): the SeaModel the Sea node draws,
## so boat and water agree). Replace with the binding; nothing else changes.

var boats: Array[FakeBoat] = []
var _tick := 0

var wind_speed := 7.2  # m/s
var wind_from := 0.0  # rad, compass
## peak direction oscillation (rad) and its period (s); 0 = steady
var wind_osc_amp := 0.0
var wind_osc_period := 120.0

## significant wave height of the test swell (m); 0 = flat sea
var swell_hs := 0.0
var _swell: Array = []  # [amplitude, kx, ky, omega, phase]
## the sea's wave components (sea.md §7.2), shared with the Sea node; null = the swell or flat water
var sea_model: SeaModel = null
## environment clock at tick 0 (ms): tick n is at sea_t0_ms + n * 50
var sea_t0_ms := 0.0


## Adds a boat of class `id` (data/classes, data/perf). Returns its index, -1 when the class does not load.
func add_boat(id: String, pos_x := 0.0, pos_y := 0.0, psi := 0.0, v := 0.0, auto_trim := true) -> int:
	var data := BoatClassData.load_class(id)
	if data == null:
		return -1
	var b := FakeBoat.new(data)
	b.reset(pos_x, pos_y, psi, v, data.start_front, auto_trim, wind_speed, _wind_from_now())
	boats.append(b)
	return boats.size() - 1


## Re-places boat b at (pos_x, pos_y) on heading psi at 2.5 m/s with its start sail, as add_boat does (the
## sail test's reset key).
func place_boat(b: int, pos_x: float, pos_y: float, psi: float) -> void:
	var fb: FakeBoat = boats[b]
	fb.reset(pos_x, pos_y, psi, 2.5, fb.d.start_front, fb.ctl.auto_trim, wind_speed, _wind_from_now())


## Test swell of significant height hs (the water only, the hulls stay level): three trains from the wind direction side, amplitudes chosen so that
## 4 * sqrt(sum a^2 / 2) = hs.
func set_swell(hs: float) -> void:
	swell_hs = hs
	_swell.clear()
	if hs <= 0.0:
		return
	var parts := [[1.0, 7.0, 0.0], [0.6, 5.0, 0.7], [0.4, 3.6, -1.1]]  # relative amplitude, period s, direction
	var sum2 := 0.0
	for p in parts:
		sum2 += p[0] * p[0]
	var scale := hs / (4.0 * sqrt(sum2 * 0.5))
	for p in parts:
		var omega: float = TAU / p[1]
		var k := omega * omega / 9.81
		var dir: float = wind_from + p[2]
		_swell.append([p[0] * scale, -k * sin(dir), -k * cos(dir), omega, p[2] * 3.0])


## Sea of the race from the drawn sea's model: sea_height is then SeaModel.height at the tick's time, the
## same function Sea.height_at evaluates. Replaces the test swell.
func use_sea(model: SeaModel, t0_ms := 0.0) -> void:
	sea_model = model
	sea_t0_ms = t0_ms


## Environment clock (ms) at a fractional tick count: the render time of a pose between ticks n - 1 and n is
## sea_time_ms(n - 1 + alpha).
func sea_time_ms(ticks: float) -> float:
	return sea_t0_ms + ticks * DT * 1000.0


func _wind_from_now() -> float:
	if wind_osc_amp == 0.0:
		return wind_from
	return Frames.wrap_2pi(wind_from + wind_osc_amp * sin(TAU * _tick * DT / wind_osc_period))


func tick() -> int:
	return _tick


func boat_count() -> int:
	return boats.size()


func class_info(boat: int) -> ClassInfo:
	return boats[boat].d.info


func state(boat: int) -> BoatState:
	return boats[boat].s


func controls(boat: int) -> BoatControls:
	return boats[boat].ctl


func outputs(boat: int) -> BoatOutputs:
	return boats[boat].out


func sails(boat: int) -> SailsView:
	var b := boats[boat]
	var v := SailsView.new()
	v.front = b.front
	v.queue = b.queue.duplicate()
	v.queue_len = b.queue.size()
	v.queue_pos = b.queue_pos
	v.queue_progress = b.queue_progress
	v.sails = b.sail_st
	v.out = b.sail_out
	return v


func render_pose(boat: int, alpha: float) -> RenderPose:
	return boats[boat].render_pose(clampf(alpha, 0.0, 1.0))


func wind_clean(_x: float, _y: float) -> Vector2:
	return Vector2(wind_speed, _wind_from_now())


func sea_height(x: float, y: float) -> float:
	return sea_height_at(x, y, _tick * DT)


## Sea height at time t (s since tick 0).
func sea_height_at(x: float, y: float, t: float) -> float:
	if sea_model != null:
		return sea_model.height(x, y, sea_t0_ms + t * 1000.0)
	var hgt := 0.0
	for c in _swell:
		hgt += c[0] * cos(c[1] * x + c[2] * y - c[3] * t + c[4])
	return hgt


func trim_speed_at(boat: int, tws: float, awa_abs: float, eps: float) -> float:
	var b := boats[boat]
	var cfg: Dictionary = b.d.configs.get(b.front, b.d.configs[-1])
	var t: PerfTable = cfg["trim_speed"]
	return t.at(tws, awa_abs, eps) if t else NAN


func apply_input(boat: int, frame: InputFrame) -> int:
	var b := boats[boat]
	b.ctl.h_cmd = clampf(frame.h_cmd, -1.0, 1.0)
	b.ctl.sheet_cmd = clampf(frame.sheet_cmd, 0.0, 1.0)
	b.ctl.let_fly = frame.let_fly()
	b.ctl.auto_trim = frame.auto_trim()
	if frame.sail_req == InputFrame.SAIL_DROP_FRONT:
		return b.drop_front()
	if frame.sail_req >= 1 and frame.sail_req <= 15:
		return b.hoist(frame.sail_req - 1)
	return Request.NONE


func step() -> void:
	var wf := _wind_from_now()
	# the boats sample the sea at the time of the tick they step to; the test swell leaves the hull level (the
	# camera clearance test wants the water to move under a steady boat)
	var t_next := (_tick + 1) * DT
	var sea := Callable()
	if sea_model != null:
		sea = func(x: float, y: float) -> float: return sea_height_at(x, y, t_next)
	for b in boats:
		b.step(wind_speed, wf, sea)
	_tick += 1
