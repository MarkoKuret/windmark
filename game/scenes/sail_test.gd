extends Node3D
## Sail test scene: one generated boat sailing freely on the example bay, with the cameras, the controls, the
## minimal HUD, the sea, its wakes and the daytime sky. Frame order: read input, controls, ticks (stamp, step,
## HUD values, sail snapshots), sea render time, render pose, boat, sails and wakes, cameras, HUD; the Sea and
## SeaWakes nodes draw after. Headless tests drive it with `scripted_input` and step_frame().
##
## The simulation (`sim_kind`): the Windmark core through CoreSimSource (the GDExtension, game/native/build.sh)
## on the venue `venue` without a race (free sailing, place_boat), or the FakeSim placeholder. AUTO takes the
## core when the extension is loaded and falls back to FakeSim otherwise.
##
## On the core, everything drawn comes from the core world: the Sea's source is a CoreEnvSource (wave
## components, exposure, live puffs, current), the Sea's clock is the core's render_time_ms of the frame, the
## wakes use CoreSimSource.wake_state and the HUD reads the core's boat records. On FakeSim the sea is the
## example bay as the core writes it (SeaEnvSource CORE_SAMPLES, game/generated/sea, written by
## tests/run_water_test.sh) or the placeholder sea built from wind_speed_kn and wind_from_deg; the fake sim runs
## on the same SeaModel the Sea draws (FakeSim.use_sea) and the Sea's clock follows the sim ticks.

enum SimKind { AUTO, CORE, FAKE }
enum SeaSource { AUTO, CORE_SAMPLES, PLACEHOLDER }

## AUTO: the core when the GDExtension is loaded, else FakeSim
@export var sim_kind: SimKind = SimKind.AUTO
@export_enum("wm7", "wm12") var class_id := "wm7"
## core: the venue (data/venues/<venue>.venue.json) and the start point (world ENU m)
@export var venue := "example_bay"
@export var start_x := 0.0
@export var start_y := -300.0
@export var wind_speed_kn := 12.0
@export var wind_from_deg := 0.0
## core: puffs and lulls, the wind shift preset (the C API's WM_SHIFT_*: -1 the wind.md default, 0 steady,
## 1 stable, 2 oscillating, 3 shifty, 4 unstable) and the world seed
@export var puffs := true
@export var shift_preset := -1
@export var world_seed := 1
## start heading relative to the wind: + = starboard tack
@export var start_twa_deg := 45.0
@export var racing := true
@export var auto_process := true
## FakeSim only. AUTO: the core's example bay samples when they exist, otherwise the placeholder sea
@export var sea_source: SeaSource = SeaSource.AUTO
## FakeSim only: core sample scenario (CORE_SAMPLES); its wind replaces wind_speed_kn and wind_from_deg
@export var sea_scenario := "example_bay_10kn"
@export var sea_quality: SeaQuality.Tier = SeaQuality.Tier.M

@onready var sea: Sea = $Sea
@onready var wakes: SeaWakes = $Wakes
@onready var env_source: SeaEnvSource = $EnvSource
@onready var sky: SkyRig = $SkyDay

## CoreSimSource or FakeSim
var sim: SimSource
## the sim is the core (CoreSimSource)
var on_core := false
## the Sea's source on the core, null on FakeSim
var core_env: CoreEnvSource
var controls: PlayerControls
var runner: SimRunner
var reader: InputReader
var rig: CameraRig
var hud: Hud
var boat_view: BoatView
var target := CamTypes.Target.new()
var viewed := 0
## tests: when set, used instead of the devices every frame
var scripted_input: RawInput = null

var _chat: LineEdit
var _paused_label: Label
## the own boat's sail states of the last two ticks (render interpolation)
var _sails_prev: SimSource.SailsView
var _sails_cur: SimSource.SailsView


func _ready() -> void:
	on_core = sim_kind == SimKind.CORE or (sim_kind == SimKind.AUTO and CoreSimSource.available())
	var b := _setup_core() if on_core else _setup_fake()
	assert(b >= 0, "class %s did not load" % class_id)
	controls = PlayerControls.new()
	controls.bind(sim, b)
	runner = SimRunner.new(sim, controls, b)
	reader = InputReader.new()
	reader.name = "InputReader"
	add_child(reader)
	var info := sim.class_info(b)
	boat_view = BoatView.create(info, info.rudder_max)
	add_child(boat_view)
	target.loa = info.loa
	target.beam_max = info.beam_max
	target.geometry = BoatGeometry.onboard(info, boat_view.model)
	target.sea_height = sea.height_at
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.camera.current = true
	sea.camera = rig.camera
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	_chat = LineEdit.new()
	_chat.name = "Chat"
	_chat.placeholder_text = "Say something"
	_chat.visible = false
	_chat.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_chat.custom_minimum_size = Vector2(360, 0)
	_chat.text_submitted.connect(func(_t: String) -> void: _close_chat())
	layer.add_child(_chat)
	_paused_label = Label.new()
	_paused_label.name = "Paused"
	_paused_label.text = "Paused"
	_paused_label.visible = false
	_paused_label.add_theme_font_size_override("font_size", 32)
	_paused_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(_paused_label)
	runner.ticked.connect(_on_tick)
	hud.tick(sim, viewed)
	_sails_cur = sim.sails(runner.boat)
	_update_sea_time(0.0)
	_update_target(0.0)
	set_process(auto_process)


## The core world on the venue, free sailing (no race): the boat placed at the start point, the Sea on the
## core's environment. Returns the boat index, -1 on failure (FakeSim is then used instead).
func _setup_core() -> int:
	var cs := CoreSimSource.new()
	cs.settings = {"wind_speed": wind_speed_kn * HudFormat.KNOT, "wind_from": deg_to_rad(wind_from_deg),
		"puffs": puffs, "shift_preset": shift_preset, "race_seed": world_seed}
	var ok := cs.create(venue)
	var b := cs.add_entry(class_id, {"human": true}) if ok else -1
	if b >= 0:
		var psi := Frames.wrap_2pi(deg_to_rad(wind_from_deg) - deg_to_rad(start_twa_deg))
		ok = cs.place_boat(b, start_x, start_y, psi)
	if not ok or b < 0:
		push_warning("sail test: the core did not start (%s); using FakeSim" % cs.last_error())
		on_core = false
		return _setup_fake()
	sim = cs
	core_env = CoreEnvSource.new()
	core_env.name = "CoreEnv"
	core_env.sim = cs
	add_child(core_env)
	sea.source = core_env
	sea.set_sea(cs.sea_components(), cs.sea_exposure())
	sea.quality = sea_quality
	sea.use_internal_clock = false
	SeaQuality.apply_environment(sky.environment(), sea.quality)
	return b


func _setup_fake() -> int:
	var fs := FakeSim.new()
	sim = fs
	fs.wind_speed = wind_speed_kn * HudFormat.KNOT
	fs.wind_from = deg_to_rad(wind_from_deg)
	fs.wind_osc_amp = deg_to_rad(6.0)
	_setup_sea(fs)
	var psi := Frames.wrap_2pi(fs.wind_from - deg_to_rad(start_twa_deg))
	return fs.add_boat(class_id, 0.0, 0.0, psi, 2.5)


func _on_tick(_t: int) -> void:
	hud.tick(sim, viewed)
	_sails_prev = _sails_cur
	_sails_cur = sim.sails(runner.boat)


## FakeSim: the sea of the chosen source, shared with the sim; the sim's wind from the core scenario when there
## is one.
func _setup_sea(fs: FakeSim) -> void:
	var core := sea_source != SeaSource.PLACEHOLDER
	if sea_source == SeaSource.AUTO:
		core = FileAccess.file_exists(env_source.samples_path)
	env_source.mode = SeaEnvSource.Mode.CORE_SAMPLES if core else SeaEnvSource.Mode.PLACEHOLDER
	env_source.scenario = sea_scenario
	env_source.wind_kn = wind_speed_kn
	env_source.wind_from_deg = wind_from_deg
	env_source.rebuild()
	var t0 := 600000.0
	if env_source.mode == SeaEnvSource.Mode.CORE_SAMPLES:
		var times := env_source.core_puff_times()
		if not times.is_empty():
			t0 = float(times[0])
		var w := env_source.wind_state(t0)
		fs.wind_speed = w["base_speed"]
		fs.wind_from = w["base_from"]
	sea.set_sea(env_source.sea_components(), env_source.sea_exposure())
	sea.quality = sea_quality
	sea.use_internal_clock = false
	SeaQuality.apply_environment(sky.environment(), sea.quality)
	fs.use_sea(sea.model, t0)


## The Sea's clock at the rendered pose: between ticks n - 1 and n at alpha (the core's render_time_ms).
func _update_sea_time(alpha: float) -> void:
	if on_core:
		sea.render_time_ms = (sim as CoreSimSource).render_time_ms(alpha)
	else:
		sea.render_time_ms = (sim as FakeSim).sea_time_ms(sim.tick() - 1 + alpha)


func _process(delta: float) -> void:
	step_frame(delta)


func _notification(what: int) -> void:
	if controls == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		controls.set_window_focus(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		controls.set_window_focus(true)


func step_frame(dt: float) -> void:
	var raw := scripted_input if scripted_input != null else reader.read()
	_ui_actions(raw)
	controls.free_camera = rig.mode == CameraRig.Mode.FREE
	controls.update(raw, dt)
	runner.advance(dt)
	_update_sea_time(runner.alpha())
	_update_target(runner.alpha())
	var cin := CameraInput.from_raw(raw if not controls.text_focus else raw.without_buttons(), controls.free_camera)
	rig.frame(target, cin, dt)
	hud.frame(dt, controls)


func _update_target(alpha: float) -> void:
	var own := sim.render_pose(runner.boat, alpha)
	boat_view.apply(own)
	boat_view.apply_sails(_sails_prev, _sails_cur, alpha)
	for b in sim.boat_count():
		var p := own if b == runner.boat else sim.render_pose(b, alpha)
		wakes.update_boat(b, _wake_state(b, p))
	target.pose = own if viewed == runner.boat else sim.render_pose(viewed, alpha)


## SeaWakes.update_boat state: the render pose and the class waterline (perf dynamics lwl, bwl).
func _wake_state(b: int, p: SimSource.RenderPose) -> Dictionary:
	if on_core:
		return (sim as CoreSimSource).wake_state(b, p, b == runner.boat)
	var dyn: Dictionary = (sim as FakeSim).boats[b].d.dyn
	var info := sim.class_info(b)
	var lwl := float(dyn.get("lwl", 0.9 * info.loa))
	var bwl := float(dyn.get("bwl", 0.75 * info.beam_max))
	return {
		"x": p.pos_x, "y": p.pos_y, "z": p.z, "psi": p.psi, "heel": p.phi, "pitch": p.theta, "lwl": lwl,
		"bwl": bwl, "transom_width": 0.6 * bwl, "bow_x": 0.5 * lwl, "stern_x": -0.5 * lwl,
		"own": b == runner.boat,
	}


func _ui_actions(r: RawInput) -> void:
	if controls.text_focus:
		if r.was_pressed(&"pause_menu"):
			_close_chat()
		return
	if r.was_pressed(&"chat"):
		_chat.visible = true
		_chat.grab_focus()
		controls.set_text_focus(true)
		return
	if r.was_pressed(&"hud_hide"):
		hud.toggle_hidden()
	if r.was_pressed(&"pause_menu"):
		runner.paused = not runner.paused  # offline: pause the simulation, the cameras still move
		_paused_label.visible = runner.paused
	if r.was_pressed(&"screenshot"):
		_screenshot()
	if not racing and sim.boat_count() > 1:
		var n := sim.boat_count()
		var before := viewed
		if r.was_pressed(&"spectate_next"):
			viewed = (viewed + 1) % n
		if r.was_pressed(&"spectate_prev"):
			viewed = (viewed - 1 + n) % n
		if r.was_pressed(&"spectate_leader"):
			viewed = 0  # ranking comes with the race layer
		if viewed != before:
			hud.local_commands = viewed == runner.boat
			_update_target(runner.alpha())
			rig.retarget(target)


func _close_chat() -> void:
	_chat.text = ""
	_chat.release_focus()
	_chat.visible = false
	controls.set_text_focus(false)


func _screenshot() -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	img.save_png("user://screenshots/windmark_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
