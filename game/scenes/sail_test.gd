extends Node3D
## Sail test scene: one generated boat sailing freely on the example bay, with the cameras, the controls, the
## minimal HUD, the sea, its wakes and the daytime sky. Frame order: read input, controls, ticks (stamp, step,
## HUD values, sail snapshots), sea render time, render pose, boat, sails and wakes, cameras, HUD; the Sea and
## SeaWakes nodes draw after. Headless tests drive it with `scripted_input` and step_frame().
##
## The simulation (`sim_kind`): the Windmark core through CoreSimSource (the GDExtension, game/native/build.sh)
## on the venue `venue` without a race (free sailing, place_boat), or the FakeSim placeholder. AUTO takes the
## core when the extension is loaded and falls back to FakeSim otherwise. With `race_mode` (the core only) the
## boat races alone on `course` from the core's spawn through the start sequence (CoreSimSource.create_race).
##
## The venue's land and obstacles are drawn by a VenueView from the core's shapes (the venue file on FakeSim),
## and the cameras keep out of them through CamTypes.Target.ground. In race mode a CourseView draws the marks,
## committee and mark boats, flags, lines and laylines from the core's course and race state, with a line of
## race status text until the race HUD exists. The reset key (controls.md §2 `reset_boat`) re-places the boat
## at its start point when free sailing, and restarts the race in race mode.
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
## core only: race alone on `course` (game/data/courses/<venue>/<id>) instead of free sailing
@export var race_mode := false
@export var course := "example_bay/example_wl"
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
var venue_view: VenueView
## race mode: the course drawn from the core
var course_view: CourseView
var target := CamTypes.Target.new()
var viewed := 0
## tests: when set, used instead of the devices every frame
var scripted_input: RawInput = null

var _chat: LineEdit
var _paused_label: Label
var _race_label: Label
var _banner := ""
var _banner_t := 0.0
## the own boat's sail states of the last two ticks (render interpolation)
var _sails_prev: SimSource.SailsView
var _sails_cur: SimSource.SailsView


func _ready() -> void:
	_user_args()
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
	venue_view = VenueView.new()
	venue_view.name = "Venue"
	add_child(venue_view)
	venue_view.build(VenueShapes.from_core((sim as CoreSimSource).core) if on_core else VenueShapes.from_file(venue))
	target.ground = venue_view.ground_height
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
	_race_label = Label.new()
	_race_label.name = "RaceStatus"
	_race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_label.add_theme_font_size_override("font_size", 22)
	_race_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_race_label.add_theme_constant_override("outline_size", 6)
	_race_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_race_label.visible = false
	layer.add_child(_race_label)
	_build_course()
	runner.ticked.connect(_on_tick)
	hud.tick(sim, viewed)
	_sails_cur = sim.sails(runner.boat)
	_update_sea_time(0.0)
	_update_target(0.0)
	set_process(auto_process)


## Command line after `--`: `--class=wm12`, `--fake` (FakeSim), `--core`, `--race` (race mode on `course`),
## `--course=<venue>/<id>`.
func _user_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class="):
			class_id = a.trim_prefix("--class=")
		elif a == "--race":
			race_mode = true
		elif a.begins_with("--course="):
			course = a.trim_prefix("--course=")
			race_mode = true
		elif a == "--fake":
			sim_kind = SimKind.FAKE
		elif a == "--core":
			sim_kind = SimKind.CORE


## extra world settings for the core (tests: a shorter free-sailing time before the warning signal)
var core_settings := {}


## The core world on the venue: free sailing (no race), the boat placed at the start point, or in race mode
## the race on `course` with the boat at its spawn; the Sea on the core's environment. Returns the boat
## index, -1 on failure (FakeSim is then used instead).
func _setup_core() -> int:
	var cs := _make_core()
	if cs == null:
		on_core = false
		race_mode = false
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
	return 0


## A new core world with the player's boat (index 0), placed or racing. null on failure.
func _make_core() -> CoreSimSource:
	var cs := CoreSimSource.new()
	cs.settings = {"wind_speed": wind_speed_kn * HudFormat.KNOT, "wind_from": deg_to_rad(wind_from_deg),
		"puffs": puffs, "shift_preset": shift_preset, "race_seed": world_seed}
	cs.settings.merge(core_settings, true)
	var ok := cs.create(venue)
	var b := cs.add_entry(class_id, {"human": true}) if ok else -1
	if b >= 0:
		if race_mode:
			ok = cs.create_race(course)
		else:
			ok = cs.place_boat(b, start_x, start_y, _start_psi())
	if not ok or b != 0:
		push_warning("sail test: the core did not start (%s); using FakeSim" % cs.last_error())
		return null
	return cs


func _start_psi() -> float:
	return Frames.wrap_2pi(deg_to_rad(wind_from_deg) - deg_to_rad(start_twa_deg))


func _build_course() -> void:
	if course_view:
		course_view.queue_free()
		course_view = null
	if not (on_core and race_mode and (sim as CoreSimSource).core.has_race()):
		sea.set_overlay_lines([])
		sea.set_overlay_circles([])
		return
	course_view = CourseView.new()
	course_view.name = "Course"
	add_child(course_view)
	course_view.show_laylines = hud.assist != Hud.Assist.MINIMAL
	course_view.show_zone = hud.assist != Hud.Assist.MINIMAL
	course_view.bind(sim as CoreSimSource, runner.boat, sea, course)
	_race_label.visible = true


## controls.md §2 reset_boat: free sailing re-places the boat at its start point, sailing; race mode restarts
## the race from the spawn. The cameras cut to the boat.
func reset_boat() -> void:
	var b := runner.boat
	if on_core and race_mode:
		var cs := _make_core()
		if cs == null:
			return
		sim = cs
		runner.sim = cs
		controls.bind(cs, b)
		core_env.sim = cs
		sea.set_sea(cs.sea_components(), cs.sea_exposure())
		_build_course()
	elif on_core:
		(sim as CoreSimSource).place_boat(b, start_x, start_y, _start_psi())
	else:
		(sim as FakeSim).place_boat(b, 0.0, 0.0, Frames.wrap_2pi((sim as FakeSim).wind_from - deg_to_rad(start_twa_deg)))
	controls.h_cmd = 0.0
	controls.let_fly = false
	wakes.remove_boat(b)
	_sails_cur = sim.sails(b)
	_sails_prev = null
	hud.tick(sim, viewed)
	_update_target(runner.alpha())
	rig.retarget(target)


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
	if course_view:
		course_view.tick()
		_race_events()


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
	if course_view:
		course_view.frame(dt, rig.camera.global_position, target.pose)
		rig.aerial.next_mark = course_view.next_mark_scene()
		_race_status(dt)
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
	if r.was_pressed(&"reset_boat"):
		reset_boat()
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


# ---- race status (a stand-in until the race HUD, WM-016.11) ----------------------------------------------------

const SIGNAL_TEXT := {
	0: "Warning signal",
	1: "Preparatory signal",
	2: "One minute",
	3: "Start",
	4: "General recall",
	5: "Individual recall: X flag",
	6: "X flag down",
}
const PREP_TEXT := ["P flag: be behind the line at the start", "I flag: over in the last minute means round an end",
	"Z flag: in the triangle in the last minute is a scoring penalty",
	"U flag: in the triangle in the last minute is a disqualification", "Black flag: in the triangle in the last minute is a disqualification"]
const PREP_NAME := ["P", "I", "Z", "U", "black"]


func _race_events() -> void:
	for e in (sim as CoreSimSource).core.race_events():
		if int(e["kind"]) != 0:
			continue
		var k := int(e["signal"])
		_banner = SIGNAL_TEXT.get(k, "")
		if k == 1:
			_banner += ", " + PREP_TEXT[clampi(int(e["flag"]), 0, 4)]
		_banner_t = 3.0


func _race_status(dt: float) -> void:
	var cv := course_view
	var race: Dictionary = (sim as CoreSimSource).core.race()
	var rb: Dictionary = (sim as CoreSimSource).core.race_boat(runner.boat)
	var t: float = race.get("race_time", 0.0)
	var state: int = race.get("state", 0)
	var tw := cv.warning_time()
	var line := ""
	if state <= CourseView.RACE_FREE:
		line = "Warning in %s" % HudFormat.countdown(-t - tw)
	elif state == CourseView.RACE_SEQUENCE:
		line = "Start in %s" % HudFormat.countdown(-t)
		if t >= -(tw - 60.0) and t < -60.0:
			line += "  ·  %s flag" % PREP_NAME[clampi(int(race.get("prep_flag", 1)), 0, 4)]
		if cv.start_line_state == "red":
			line += "  ·  OVER"
	elif bool(rb.get("finished", false)):
		line = "Finished  ·  %s" % HudFormat.clock(float(rb.get("t_finish_us", 0)) * 1e-6)
	else:
		line = "Race %s" % HudFormat.clock(t)
		if bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false)):
			line += "  ·  OCS: return %s" % ("around an end" if bool(rb.get("ocs_i", false)) else "behind the line")
		elif not bool(rb.get("started", false)):
			line += "  ·  Cross the line to start"
	var nk := cv.next_step()
	if nk > 0 and nk < cv.course["steps"].size() and not bool(rb.get("finished", false)):
		var st: Dictionary = cv.course["steps"][nk]
		var kind := int(st["kind"])
		var what := "Finish"
		if kind == CourseView.STEP_MARK:
			what = "%s, leave to %s" % [cv.label(int(st["marks"][0])), "port" if int(st["sides"][0]) == 0 else "starboard"]
		elif kind == CourseView.STEP_GATE:
			what = "Gate %s / %s" % [cv.label(int(st["marks"][0])), cv.label(int(st["marks"][1]))]
		line += "\nNext: %s  ·  %s  ·  Lap %d/%d" % [what, HudFormat.distance(cv.distance_to_next(target.pose)),
			int(st["lap"]), int(cv.course.get("laps", 1))]
		if cv.leg != "":
			line += "  ·  %s" % cv.leg.capitalize()
	if _banner_t > 0.0:
		_banner_t -= dt
		line += "\n" + _banner
	_race_label.text = line
