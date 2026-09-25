extends Node3D
## Sail test scene: one generated boat on the placeholder sim, with the cameras, the controls, the minimal
## HUD, the sea, its wakes and the daytime sky. Frame order: read input, controls, ticks (stamp, step, HUD
## values), sea render time, render pose, boat and wakes, cameras, HUD; the Sea and SeaWakes nodes draw after.
## Headless tests drive it with `scripted_input` and step_frame().
##
## The sea: the example bay as the core writes it (SeaEnvSource CORE_SAMPLES, game/generated/sea, written by
## tests/run_water_test.sh) or the placeholder sea built from wind_speed_kn and wind_from_deg. The fake sim runs
## on the same SeaModel the Sea draws (FakeSim.use_sea) and the Sea's clock follows the sim ticks, so the hull,
## the water and the cameras' clearance (Sea.height_at) see one surface.

enum SeaSource { AUTO, CORE_SAMPLES, PLACEHOLDER }

@export var class_id := "wm7"
@export var wind_speed_kn := 12.0
@export var wind_from_deg := 0.0
## start heading relative to the wind: + = starboard tack
@export var start_twa_deg := 45.0
@export var racing := true
@export var auto_process := true
## AUTO: the core's example bay samples when they exist, otherwise the placeholder sea
@export var sea_source: SeaSource = SeaSource.AUTO
## core sample scenario (CORE_SAMPLES); its wind replaces wind_speed_kn and wind_from_deg
@export var sea_scenario := "example_bay_10kn"
@export var sea_quality: SeaQuality.Tier = SeaQuality.Tier.M

@onready var sea: Sea = $Sea
@onready var wakes: SeaWakes = $Wakes
@onready var env_source: SeaEnvSource = $EnvSource
@onready var sky: SkyRig = $SkyDay

var sim: FakeSim
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


func _ready() -> void:
	sim = FakeSim.new()
	sim.wind_speed = wind_speed_kn * HudFormat.KNOT
	sim.wind_from = deg_to_rad(wind_from_deg)
	sim.wind_osc_amp = deg_to_rad(6.0)
	_setup_sea()
	var psi := Frames.wrap_2pi(sim.wind_from - deg_to_rad(start_twa_deg))
	var b := sim.add_boat(class_id, 0.0, 0.0, psi, 2.5)
	assert(b >= 0, "class %s did not load" % class_id)
	controls = PlayerControls.new()
	controls.bind(sim, b)
	runner = SimRunner.new(sim, controls, b)
	reader = InputReader.new()
	reader.name = "InputReader"
	add_child(reader)
	var info := sim.class_info(b)
	boat_view = BoatView.create(info, float(sim.boats[b].d.dyn.get("rudder_max", 0.6)))
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
	runner.ticked.connect(func(_t: int) -> void: hud.tick(sim, viewed))
	hud.tick(sim, viewed)
	_update_sea_time(0.0)
	_update_target(0.0)
	set_process(auto_process)


## The sea of the chosen source, shared with the sim; the sim's wind from the core scenario when there is one.
func _setup_sea() -> void:
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
		sim.wind_speed = w["base_speed"]
		sim.wind_from = w["base_from"]
	sea.set_sea(env_source.sea_components(), env_source.sea_exposure())
	sea.quality = sea_quality
	sea.use_internal_clock = false
	SeaQuality.apply_environment(sky.environment(), sea.quality)
	sim.use_sea(sea.model, t0)


## The Sea's clock at the rendered pose: between ticks n - 1 and n at alpha.
func _update_sea_time(alpha: float) -> void:
	sea.render_time_ms = sim.sea_time_ms(sim.tick() - 1 + alpha)


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
	for b in sim.boat_count():
		var p := own if b == runner.boat else sim.render_pose(b, alpha)
		wakes.update_boat(b, _wake_state(b, p))
	target.pose = own if viewed == runner.boat else sim.render_pose(viewed, alpha)


## SeaWakes.update_boat state: the render pose and the class waterline (perf dynamics lwl, bwl).
func _wake_state(b: int, p: SimSource.RenderPose) -> Dictionary:
	var dyn: Dictionary = sim.boats[b].d.dyn
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
