extends Node3D
## Sail test scene: one generated boat on the placeholder sim, with the cameras, the controls and the minimal
## HUD. Frame order: read input, controls, ticks (stamp, step, HUD values), render pose, boat, cameras, HUD.
## Headless tests drive it with `scripted_input` and step_frame(); the sea is a flat placeholder plane until
## the Sea node (game/scenes/sea/) takes its place and its height function.

@export var class_id := "wm7"
@export var wind_speed_kn := 12.0
@export var wind_from_deg := 0.0
## start heading relative to the wind: + = starboard tack
@export var start_twa_deg := 45.0
@export var racing := true
@export var auto_process := true

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
	target.sea_height = sim.sea_height
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.camera.current = true
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
	_update_target(0.0)
	set_process(auto_process)


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
	_update_target(runner.alpha())
	var cin := CameraInput.from_raw(raw if not controls.text_focus else raw.without_buttons(), controls.free_camera)
	rig.frame(target, cin, dt)
	hud.frame(dt, controls)


func _update_target(alpha: float) -> void:
	var own := sim.render_pose(runner.boat, alpha)
	boat_view.apply(own)
	target.pose = own if viewed == runner.boat else sim.render_pose(viewed, alpha)


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
