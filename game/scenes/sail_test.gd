extends Node3D
## Sail test scene: one generated boat sailing freely on the example bay, with the cameras, the controls, the
## minimal HUD, the sea, its wakes, the daytime sky and the sound (GameAudio). Frame order: read input, controls,
## ticks (stamp, step, HUD values, audio inputs, sail snapshots), sea render time, render pose, boat, sails and
## wakes (and the drawn boat shadows), cameras, HUD, audio; the Sea, SeaWakes and BoatShadows nodes draw after.
## A PerfMonitor (hud.md §17) times each part. Headless tests drive it with `scripted_input` and step_frame().
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
## With `scenario` (`--scenario=<id>`, GameSetup mode scenario) the race is a rules scenario (race.md §14,
## ScenarioRun): the file sets class, course, wind, seed and boats; the player watches unless boat 0 has helm
## player, the cameras start on its `view` boat, the simulation pauses at the clip's end and reset restarts it.
## Spectating (spectate_next / prev / leader) steps through the boats when not racing (`racing` off, `watch`)
## or once the player has finished, retired or left the race (cameras.md §1).
##
## The venue's land and obstacles are drawn by a VenueView from the core's shapes (the venue file on FakeSim),
## and the cameras keep out of them through CamTypes.Target.ground. In race mode a CourseView draws the marks,
## committee and mark boats, flags, lines and laylines from the core's course and race state, and the Hud shows
## the race HUD (hud.md; it reads the race through the sim it is ticked with). The reset key (controls.md §2
## `reset_boat`) re-places the boat at its start point when free sailing, and restarts the race in race mode.
##
## On the core, everything drawn comes from the core world: the Sea's source is a CoreEnvSource (wave
## components, exposure, live puffs, current), the Sea's clock is the core's render_time_ms of the frame, the
## wakes use CoreSimSource.wake_state and the HUD reads the core's boat records. On FakeSim the sea is the
## example bay as the core writes it (SeaEnvSource CORE_SAMPLES, game/generated/sea, written by
## tests/run_water_test.sh) or the placeholder sea built from wind_speed_kn and wind_from_deg; the fake sim runs
## on the same SeaModel the Sea draws (FakeSim.use_sea) and the Sea's clock follows the sim ticks.

const PAUSE_MENU := "res://scenes/menu/pause_menu.tscn"
const SETTINGS_SCRIPT := "res://scripts/settings.gd"

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
## the player's livery id (data_format.md §8); "": the class default. The AI boats get theirs by the fleet rule
@export var livery := ""
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
## the pause menu of scenes/menu as a child (it applies the player's settings); without it, `apply_settings`
## applies them at start
@export var with_pause_menu := true
@export var apply_settings := true
## FakeSim only. AUTO: the core's example bay samples when they exist, otherwise the placeholder sea
@export var sea_source: SeaSource = SeaSource.AUTO
## FakeSim only: core sample scenario (CORE_SAMPLES); its wind replaces wind_speed_kn and wind_from_deg
@export var sea_scenario := "example_bay_10kn"
@export var sea_quality: SeaQuality.Tier = SeaQuality.Tier.M

@onready var sea: Sea = $Sea
@onready var wakes: SeaWakes = $Wakes
## the boats' shadows drawn on the water where the sea takes none (water_render.md §4.7)
@onready var shadows: BoatShadows = $BoatShadows
## `--no-boat-shadows` (measuring): the boats cast no sun shadows
var no_boat_shadows := false
## `--no-drawn-shadows` (measuring): no boat shadows drawn on the water (tiers L and M)
var no_drawn_shadows := false
## `--no-hud` (measuring): the HUD hidden from the start, as the hud_hide key does
var no_hud := false
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
## a rules scenario id or .scenario.json path (race.md §14); "": none
var scenario := ""
## the running scenario (core only), null without one
var scenario_run: ScenarioRun
var venue_view: VenueView
## race mode: the course drawn from the core
var course_view: CourseView
## the race's sound (audio.md): boat, wind, signals, ambience, course objects
var audio: GameAudio
var target := CamTypes.Target.new()
var viewed := 0
## tests: when set, used instead of the devices every frame
var scripted_input: RawInput = null
## the frame-time overlay and log (hud.md §17, PerfMonitor): F9 shows it; --perf shows it from the start,
## --perf-log=PATH writes the per-second CSV, --perf-seconds=N quits after N seconds
var perf: PerfMonitor
var perf_overlay := false
var perf_log := ""
var perf_seconds := 0.0
## µs spent in the tick callbacks' HUD, audio and course parts this frame (taken out of `sim`)
var _tick_usec := 0

## controls.md §7 capture: clean pause, slow motion, world tags (CaptureMode)
var capture := CaptureMode.new()
## an online session (not built yet): the capture actions and the clip cameras are offline only
var online := false

var _chat: LineEdit
var _paused_label: Label
## the capture rate note (hud.md §16.6): on the overlay layer, so it shows with the HUD hidden too
var _rate_note: Label
## the own boat's sail states of the last two ticks (render interpolation)
var _sails_prev: SimSource.SailsView
var _sails_cur: SimSource.SailsView
## every boat's sail states of the last two ticks, by boat index
var _sails_prev_all: Array = []
var _sails_cur_all: Array = []


func _ready() -> void:
	_apply_setup()
	_user_args()
	_load_scenario()
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
	rig.clip_allowed = not online
	capture.allowed = not online
	sea.camera = rig.camera
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = Hud.new()
	hud.camera_rig = rig  # world tags and the penalty turn (hud.md §16.4)
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
	_rate_note = _make_rate_note()
	layer.add_child(_rate_note)
	_build_course()
	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(sim, boat_views, viewed)
	hud.hud_event.connect(audio.on_hud_event)
	runner.ticked.connect(_on_tick)
	hud.tick(sim, viewed)
	_snapshot_sails(true)
	_update_sea_time(0.0)
	_update_target(0.0)
	set_process(auto_process)
	_add_pause_menu()
	if Settings.render_scale_override > 0.0 or Settings.upscaler_override != "":
		Settings.current().apply_render_scale(get_tree().root)
	if no_hud:
		hud.toggle_hidden()
	shadows.enabled = not no_drawn_shadows
	if no_boat_shadows:
		for v in boat_views:
			for g in v.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if scenario_run != null:
		view_boat(scenario_run.scenario.view)
	perf = PerfMonitor.new()
	perf.name = "Perf"
	perf.scene = self
	perf.overlay = perf_overlay
	perf.log_path = perf_log
	perf.seconds = perf_seconds
	add_child(perf)


## The pause menu (scenes/menu, menus.md §2): it follows the scene's pause key, holds the controls while open and
## applies the player's settings (Settings.apply_to_scene) at start and after the settings screen. Without it
## (`with_pause_menu` off, or a build without the menus) the settings are applied here at start. Loaded by path
## so the scene runs where the menus are not there.
func _add_pause_menu() -> void:
	if with_pause_menu and ResourceLoader.exists(PAUSE_MENU):
		add_child((load(PAUSE_MENU) as PackedScene).instantiate())
	elif apply_settings and ResourceLoader.exists(SETTINGS_SCRIPT):
		var settings: Variant = load(SETTINGS_SCRIPT)
		settings.current().apply_to_scene(self)


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
	livery = gs.livery
	if gs.mode == "scenario":
		scenario = gs.scenario


## Command line after `--` (over GameSetup): `--race` (race mode on `course`; the fleet of GameSetup when no
## `--fleet`), `--free`, `--fleet=10`, `--level=expert` (easy, intermediate, expert, pro), `--speed-only`,
## `--watch` (an AI sails the player's boat too, spectating on), `--class=wm12`, `--venue=<id>`,
## `--sky=clear|fair|hazy|late` (the light preset, SkyRig; fair by default), `--look=off` (no colour grade,
## vignette, contact shading or depth of field, to compare), `--ssao=on|off` (contact shading over the tier),
## `--course=<venue>/<id>` (race mode), `--seed=<n>` (0: from the clock), `--livery=<id>` (the player's livery),
## `--wind=<kn>`, `--wind-from=<deg>`,
## `--fake` (FakeSim), `--core`; measuring (hud.md §17): `--perf` (the frame-time overlay), `--perf-log=PATH`,
## `--perf-seconds=N`, `--render-scale=0.67`, `--upscaler=fsr|bilinear|metalfx`, `--quality=L|M|H`, `--no-vsync`,
## `--shadow-splits=0|2|4`, `--shadow-atlas=N`, `--shadow-distance=M`, `--shadow-soft=0..5`, `--no-wake-buffer`, `--no-boat-shadows`,
## `--no-drawn-shadows`, `--sea-grid=RINGSxSEGMENTS`, `--water-shader=l|m|h` and `--no-hud` (this run only, not saved);
## `--scenario=<id>` (a rules scenario of game/data/scenarios, or a .scenario.json path; race.md §14).
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
		elif a.begins_with("--sky="):
			if not sky.set_preset_name(a.trim_prefix("--sky=").to_lower()):
				push_warning("--sky: clear, fair, hazy or late")
		elif a.begins_with("--look="):
			LookFx.enabled = a.trim_prefix("--look=").to_lower() != "off"
			LookFx.apply_grade(sky.environment(), sky.preset)
		elif a.begins_with("--ssao="):
			LookFx.ssao_override = 1 if a.trim_prefix("--ssao=").to_lower() == "on" else 0
		elif a.begins_with("--livery="):
			livery = a.trim_prefix("--livery=")
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
		elif a == "--perf":
			perf_overlay = true
		elif a.begins_with("--perf-log="):
			perf_log = a.trim_prefix("--perf-log=")
		elif a.begins_with("--perf-seconds="):
			perf_seconds = a.trim_prefix("--perf-seconds=").to_float()
		elif a.begins_with("--render-scale="):
			var v := a.trim_prefix("--render-scale=").to_float()
			Settings.render_scale_override = v / 100.0 if v > 1.0 else v
		elif a.begins_with("--upscaler="):
			Settings.upscaler_override = a.trim_prefix("--upscaler=").to_lower()
		elif a.begins_with("--quality="):
			Settings.quality_override = "LMH".find(a.trim_prefix("--quality=").to_upper())
		elif a == "--no-vsync":
			Settings.vsync_override = 0
		elif a.begins_with("--shadow-splits="):
			SeaQuality.overrides["shadow_splits"] = a.trim_prefix("--shadow-splits=").to_int()
		elif a.begins_with("--shadow-atlas="):
			SeaQuality.overrides["shadow_atlas"] = a.trim_prefix("--shadow-atlas=").to_int()
		elif a.begins_with("--sea-grid="):
			var g := a.trim_prefix("--sea-grid=").split("x")
			SeaQuality.overrides["rings"] = g[0].to_int()
			SeaQuality.overrides["segments"] = g[1].to_int()
		elif a.begins_with("--water-shader="):
			SeaQuality.overrides["shader"] = "res://shaders/water_%s.gdshader" % a.trim_prefix("--water-shader=").to_lower()
		elif a.begins_with("--shadow-distance="):
			SeaQuality.overrides["shadow_distance"] = a.trim_prefix("--shadow-distance=").to_float()
		elif a.begins_with("--shadow-soft="):
			SeaQuality.overrides["shadow_soft"] = a.trim_prefix("--shadow-soft=").to_int()
		elif a == "--no-wake-buffer":
			SeaQuality.overrides["wake_buffer"] = false
		elif a == "--no-boat-shadows":
			no_boat_shadows = true
		elif a == "--no-drawn-shadows":
			no_drawn_shadows = true
		elif a == "--no-hud":
			no_hud = true
		elif a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
	if race_flag and not fleet_given and fleet_size < 2:
		fleet_size = GameSetup.new().fleet_size
	if watch:
		racing = false


## A rules scenario (race.md §14) onto the scene's settings: class, venue, course, fleet, wind and seed from the
## file, the core, race mode; the player watches unless boat 0 is the player's. A file that does not load leaves the
## scene as it was set up.
func _load_scenario() -> void:
	if scenario == "":
		return
	var why := []
	var s := Scenario.load_file(scenario, why)
	if s == null:
		push_error("scenario: %s" % (why[0] if not why.is_empty() else scenario))
		return
	scenario_run = ScenarioRun.new(s)
	sim_kind = SimKind.CORE
	race_mode = true
	class_id = s.class_id
	venue = s.venue
	course = s.course
	fleet_size = s.boats.size()
	world_seed = s.seed
	wind_speed_kn = s.wind_speed / HudFormat.KNOT
	wind_from_deg = rad_to_deg(s.wind_from)
	puffs = s.puffs
	shift_preset = s.shift_preset
	if not s.player_sails():
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
		_paint_fleet()
	boat_view = boat_views[runner.boat]


## Every boat in a livery of its class (data_format.md §8): the player's choice for the own boat, the others by
## the fleet rule from the world seed.
func _paint_fleet() -> void:
	var by_class := {}
	for b in boat_views.size():
		var id := boat_views[b].info.id
		if not by_class.has(id):
			by_class[id] = []
		by_class[id].append(b)
	for id in by_class:
		var list := Livery.load_class(id)
		var entries := []
		for b in by_class[id]:
			entries.append({"human": runner != null and b == runner.boat, "choice": livery})
			if scenario_run != null and scenario_run.scenario.boats[b].livery != "":
				entries[-1] = {"human": true, "choice": scenario_run.scenario.boats[b].livery}
		var got := Livery.assign(list, entries, world_seed)
		for k in got.size():
			if got[k] != null:
				boat_views[by_class[id][k]].set_livery(got[k])


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


## A new core world with the player's boat (index 0), placed or racing (or the rules scenario at clip time 0).
## null on failure.
func _make_core() -> CoreSimSource:
	if scenario_run != null:
		scenario_run.core_settings = core_settings
		var run_cs := scenario_run.make_core()
		if run_cs == null:
			push_warning("sail test: the scenario did not start (%s); using FakeSim" % scenario_run.error)
		return run_cs
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
	course_view.show_guides = capture.world_tags


## controls.md §2 reset_boat: free sailing re-places the boat at its start point, sailing; race mode restarts
## the race from the spawn. The cameras cut to the boat.
func reset_boat() -> void:
	var b := runner.boat
	capture.reset()
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
			shadows.remove_boat(i)
		viewed = b
		hud.local_commands = true
		_build_course()
		audio.restart(sim, boat_views)
		if scenario_run != null:
			runner.paused = false
			viewed = clampi(scenario_run.scenario.view, 0, sim.boat_count() - 1)
			hud.local_commands = viewed == b
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
	if scenario_run != null and scenario_run.finished(sim):
		runner.paused = true  # race.md §14: the clip ends paused; reset_boat runs it again
	var t0 := Time.get_ticks_usec()
	hud.tick(sim, viewed)
	var t1 := Time.get_ticks_usec()
	audio.tick()
	var t2 := Time.get_ticks_usec()
	_snapshot_sails()
	var t3 := Time.get_ticks_usec()
	if course_view:
		course_view.tick()
	var t4 := Time.get_ticks_usec()
	PerfStats.add(&"hud", t1 - t0)
	PerfStats.add(&"audio", t2 - t1)
	PerfStats.add(&"course", t4 - t3)
	_tick_usec += (t2 - t0) + (t4 - t3)


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


## One frame; each part is timed into its PerfStats section (hud.md §17).
func step_frame(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var raw := scripted_input if scripted_input != null else reader.read()
	_ui_actions(raw)
	hud.ui_input(raw, dt)
	controls.free_camera = rig.mode == CameraRig.Mode.FREE
	controls.update(raw, dt)
	var t1 := Time.get_ticks_usec()
	PerfStats.add(&"input", t1 - t0)
	_tick_usec = 0
	runner.advance(capture.sim_dt(dt))  # slow motion and the clean pause (controls.md §7)
	var t2 := Time.get_ticks_usec()
	PerfStats.add(&"sim", t2 - t1 - _tick_usec)
	_update_sea_time(runner.alpha())
	PerfStats.add(&"sea", Time.get_ticks_usec() - t2)
	_update_target(runner.alpha())
	var t3 := Time.get_ticks_usec()
	if course_view:
		course_view.frame(dt, rig.camera.global_position, target.pose)
		rig.aerial.next_mark = course_view.next_mark_scene()
	var t4 := Time.get_ticks_usec()
	PerfStats.add(&"course", t4 - t3)
	var cin := CameraInput.from_raw(raw if not controls.text_focus else raw.without_buttons(), controls.free_camera)
	if course_view == null:
		rig.course = null
	elif CameraRig.is_clip(rig.mode) or cin.clip:
		rig.course = ClipCourse.from_race(course_view, viewed, target.loa)  # cameras.md §9
	rig.frame(target, cin, dt)
	var t5 := Time.get_ticks_usec()
	PerfStats.add(&"camera", t5 - t4)
	hud.frame(dt, controls)
	var t6 := Time.get_ticks_usec()
	PerfStats.add(&"hud", t6 - t5)
	audio.viewed = viewed
	audio.paused = runner.paused or (capture.allowed and capture.frozen)
	capture.frame(dt)
	_place_rate_note()
	audio.countdown_beeps = hud.assist == Hud.Assist.FULL
	audio.frame(dt, rig.camera, rig.mode == CameraRig.Mode.ONBOARD)
	PerfStats.add(&"audio", Time.get_ticks_usec() - t6)


func _make_rate_note() -> Label:
	var l := Label.new()
	l.name = "RateNote"
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudStyle.INK, 0.86)
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", HudStyle.PAPER)
	l.add_theme_font_override("font", HudStyle.font(600))
	return l


## The rate note (hud.md §16.6): its text, size and opacity this frame, top centre under the top margin.
func _place_rate_note() -> void:
	_rate_note.visible = capture.note != ""
	if not _rate_note.visible:
		return
	var sc := get_viewport().get_visible_rect().size
	var k := HudStyle.ui_k(sc)
	var sb := _rate_note.get_theme_stylebox("normal") as StyleBoxFlat
	sb.content_margin_left = 14.0 * k
	sb.content_margin_right = 14.0 * k
	sb.content_margin_top = 5.0 * k
	sb.content_margin_bottom = 5.0 * k
	_rate_note.add_theme_font_size_override("font_size", maxi(HudStyle.MIN_TEXT, int(roundf(16.0 * k))))
	_rate_note.text = capture.note
	_rate_note.size = Vector2.ZERO  # shrink to the text
	_rate_note.position = Vector2((sc.x - _rate_note.size.x) * 0.5, HudStyle.margins(sc).y + 24.0 * k)
	_rate_note.modulate.a = capture.note_alpha()


## Every boat node at its render pose: the boat (`boats`), its sails (`sails`) and its wake (`wakes`), timed into
## those PerfStats sections.
func _update_target(alpha: float) -> void:
	var n := mini(sim.boat_count(), boat_views.size())
	var us_boats := 0
	var us_sails := 0
	var us_wakes := 0
	for b in n:
		var ta := Time.get_ticks_usec()
		var p := sim.render_pose(b, alpha)
		var v := boat_views[b]
		v.apply(p)
		var tb := Time.get_ticks_usec()
		v.apply_sails(_sails_prev_all[b] if b < _sails_prev_all.size() else null,
			_sails_cur_all[b] if b < _sails_cur_all.size() else null, alpha)
		var tc := Time.get_ticks_usec()
		wakes.update_boat(b, _wake_state(b, p))
		if shadows.enabled:
			shadows.update_boat(b, v.shadow_state(b == runner.boat))
		var td := Time.get_ticks_usec()
		us_boats += tb - ta
		us_sails += tc - tb
		us_wakes += td - tc
		if b == viewed:
			target.pose = p
	PerfStats.add(&"boats", us_boats)
	PerfStats.add(&"sails", us_sails)
	PerfStats.add(&"wakes", us_wakes)


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
	if capture.handle(r):
		hud.world_tags = capture.world_tags
		if course_view:
			course_view.show_guides = capture.world_tags
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
