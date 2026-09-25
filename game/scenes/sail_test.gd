extends Node3D
## Sail test scene: one generated boat sailing freely on the example bay, with the cameras, the controls, the
## minimal HUD, the sea, its wakes and the daytime sky. Frame order: read input, controls, ticks (stamp, step,
## HUD values, sail snapshots), sea render time, render pose, boat, sails and wakes, cameras, HUD; the Sea and
## SeaWakes nodes draw after. Headless tests drive it with `scripted_input` and step_frame().
##
## The simulation (`sim_kind`): the Windmark core through CoreSimSource (the GDExtension, game/native/build.sh)
## on the venue `venue` without a race (free sailing, place_boat), or the FakeSim placeholder. AUTO takes the
## core when the extension is loaded and falls back to FakeSim otherwise. With `race_mode` (the core only) the
## player races on `course` from the core's spawn through the start sequence (CoreSimSource.create_race) against
## `fleet_size - 1` AI boats of `ai_level` (the core's AI skippers, ai.md), every boat drawn by its own BoatView
## (hull, rig, sails at the distance update rates of sail_visuals.md §11, wakes). The player is boat 0.
##
## Set-up: the scene's exports, replaced by GameSetup.current() when the menus have written one (GameSetup.next
## set) or `setup` is given, then by the command-line flags (see _user_args). Seed 0 picks one from the clock.
## Spectating (spectate_next / prev / leader) steps through the boats when not racing (`racing` off, `watch`)
## or once the player has finished, retired or left the race (cameras.md §1).
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
## core only: race on `course` (game/data/courses/<venue>/<id>) instead of free sailing
@export var race_mode := false
@export var course := "example_bay/example_wl"
## race mode: boats in the race including the player (the rest are AI), the AI level (CoreSimSource.AI_LEVELS),
## "speed only" levels (ai.md §13), and `watch`: an AI sails the player's boat too and spectating is on
@export_range(1, 40) var fleet_size := 1
@export_enum("easy", "intermediate", "expert", "pro") var ai_level := "intermediate"
@export var ai_speed_only := false
@export var watch := false
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
## the player's boat node (boat_views[runner.boat])
var boat_view: BoatView
## one BoatView per boat, by boat index
var boat_views: Array[BoatView] = []
## the session set-up to apply instead of GameSetup.next (tests); null: GameSetup.next when the menus wrote one
var setup: GameSetup = null
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
## every boat's sail states of the last two ticks, by boat index
var _sails_prev_all: Array = []
var _sails_cur_all: Array = []


func _ready() -> void:
	_apply_setup()
	_user_args()
	if world_seed == 0:
		world_seed = 1 + (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0)) % 2000000000
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
	_build_views()
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
	_snapshot_sails(true)
	_update_sea_time(0.0)
	_update_target(0.0)
	set_process(auto_process)


## GameSetup (the menus' session set-up) onto the scene's settings: `setup`, else GameSetup.current() when the
## menus have written one. Without either the exports stand (free sailing, what GameSetup's defaults describe).
func _apply_setup() -> void:
	var gs := setup
	if gs == null and GameSetup.next != null:
		gs = GameSetup.current()
	if gs == null:
		return
	race_mode = gs.mode == "race"
	class_id = gs.class_id
	venue = gs.venue
	course = gs.course
	fleet_size = clampi(gs.fleet_size, 1, 40) if race_mode else 1
	ai_level = gs.ai_level
	wind_speed_kn = gs.wind_kn
	wind_from_deg = gs.wind_from_deg
	world_seed = gs.seed


## Command line after `--` (over GameSetup): `--race` (race mode on `course`; the fleet of GameSetup when no
## `--fleet`), `--free`, `--fleet=10`, `--level=expert` (easy, intermediate, expert, pro), `--speed-only`,
## `--watch` (an AI sails the player's boat too, spectating on), `--class=wm12`, `--venue=<id>`,
## `--course=<venue>/<id>` (race mode), `--seed=<n>` (0: from the clock), `--wind=<kn>`, `--wind-from=<deg>`,
## `--fake` (FakeSim), `--core`.
func _user_args() -> void:
	var fleet_given := false
	var race_flag := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class="):
			class_id = a.trim_prefix("--class=")
		elif a == "--race":
			race_mode = true
			race_flag = true
		elif a == "--free":
			race_mode = false
			fleet_size = 1
		elif a.begins_with("--course="):
			course = a.trim_prefix("--course=")
			race_mode = true
			race_flag = true
		elif a.begins_with("--fleet="):
			fleet_size = clampi(a.trim_prefix("--fleet=").to_int(), 1, 40)
			fleet_given = true
		elif a.begins_with("--level="):
			ai_level = a.trim_prefix("--level=").to_lower()
		elif a == "--speed-only":
			ai_speed_only = true
		elif a == "--watch":
			watch = true
		elif a.begins_with("--venue="):
			venue = a.trim_prefix("--venue=")
		elif a.begins_with("--seed="):
			world_seed = a.trim_prefix("--seed=").to_int()
		elif a.begins_with("--wind="):
			wind_speed_kn = a.trim_prefix("--wind=").to_float()
		elif a.begins_with("--wind-from="):
			wind_from_deg = a.trim_prefix("--wind-from=").to_float()
		elif a == "--fake":
			sim_kind = SimKind.FAKE
		elif a == "--core":
			sim_kind = SimKind.CORE
	if race_flag and not fleet_given and fleet_size < 2:
		fleet_size = GameSetup.new().fleet_size
	if watch:
		racing = false


## One BoatView per boat (the player's is boat_view), reused when the fleet keeps its size and classes.
func _build_views() -> void:
	var n := sim.boat_count()
	var same := boat_views.size() == n
	for b in mini(n, boat_views.size()):
		same = same and boat_views[b].info.id == sim.class_info(b).id
	if not same:
		for v in boat_views:
			v.queue_free()
		boat_views.clear()
		for b in n:
			var info := sim.class_info(b)
			var v := BoatView.create(info, info.rudder_max)
			v.name = "Boat%d_%s" % [b, info.id]
			add_child(v)
			boat_views.append(v)
	boat_view = boat_views[runner.boat]


## The sail states of every boat after a tick (`reset`: no previous ones).
func _snapshot_sails(reset := false) -> void:
	var n := sim.boat_count()
	if reset or _sails_cur_all.size() != n:
		_sails_prev_all.resize(n)
		_sails_prev_all.fill(null)
		_sails_cur_all.resize(n)
		for b in n:
			_sails_cur_all[b] = sim.sails(b)
	else:
		for b in n:
			_sails_prev_all[b] = _sails_cur_all[b]
			_sails_cur_all[b] = sim.sails(b)
	_sails_prev = _sails_prev_all[runner.boat] if runner else null
	_sails_cur = _sails_cur_all[runner.boat if runner else 0]


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
			for i in fleet_size - 1:
				if cs.add_ai(class_id, ai_level, ai_speed_only) < 0:
					break
			ok = cs.create_race(course)
			if ok and watch:
				cs.ai_take_over(b)
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
		_build_views()
		for i in boat_views.size():
			wakes.remove_boat(i)
		viewed = b
		hud.local_commands = true
		_build_course()
	elif on_core:
		(sim as CoreSimSource).place_boat(b, start_x, start_y, _start_psi())
	else:
		(sim as FakeSim).place_boat(b, 0.0, 0.0, Frames.wrap_2pi((sim as FakeSim).wind_from - deg_to_rad(start_twa_deg)))
	controls.h_cmd = 0.0
	controls.let_fly = false
	wakes.remove_boat(b)
	_snapshot_sails(true)
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
	_snapshot_sails()
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
	var n := mini(sim.boat_count(), boat_views.size())
	for b in n:
		var p := sim.render_pose(b, alpha)
		var v := boat_views[b]
		v.apply(p)
		v.apply_sails(_sails_prev_all[b] if b < _sails_prev_all.size() else null,
			_sails_cur_all[b] if b < _sails_cur_all.size() else null, alpha)
		wakes.update_boat(b, _wake_state(b, p))
		if b == viewed:
			target.pose = p


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
	if can_spectate():
		var n := sim.boat_count()
		var before := viewed
		if r.was_pressed(&"spectate_next"):
			viewed = (viewed + 1) % n
		if r.was_pressed(&"spectate_prev"):
			viewed = (viewed - 1 + n) % n
		if r.was_pressed(&"spectate_leader"):
			viewed = leader()
		if viewed != before:
			hud.local_commands = viewed == runner.boat
			_update_target(runner.alpha())
			rig.retarget(target)


## cameras.md §1: the player steps through the boats when not racing, or once their boat has finished, retired
## or left the race.
func can_spectate() -> bool:
	if sim.boat_count() < 2:
		return false
	if not racing:
		return true
	if on_core and race_mode and (sim as CoreSimSource).core.has_race():
		var rb: Dictionary = (sim as CoreSimSource).core.race_boat(runner.boat)
		return bool(rb.get("finished", false)) or int(rb.get("ghost", 0)) != 0 or bool(rb.get("retired", false))
	return false


## The boat ranked first (race.md §8), or boat 0 without a race.
func leader() -> int:
	if on_core and race_mode and (sim as CoreSimSource).core.has_race():
		var order: PackedInt32Array = (sim as CoreSimSource).core.race_order()
		if order.size() > 0:
			return order[0]
	return 0


## Views boat b (spectating) and cuts the cameras to it.
func view_boat(b: int) -> void:
	viewed = clampi(b, 0, sim.boat_count() - 1)
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
