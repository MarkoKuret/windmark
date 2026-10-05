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
## The race end (menus.md §5, hud.md §13.1 to §13.3): offline the player's boat has the finished-boat autopilot
## (race.md §6.2), so she sails clear after her finish; when her race is over the camera eases into the finish view
## (cameras.md §9.1) and the results screen of scenes/menu (ResultsScreen, a child like the pause menu) takes over
## from the HUD's own results table; it offers Race again (session_setup with a new seed), Change setup and Main
## menu. retire() is the pause menu's Retire (race.md §6.4).
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
const RESULTS_SCREEN := "res://scenes/menu/results_screen.gd"
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
## the results screen of scenes/menu (menus.md §5) in a quick race (not watching, not a scenario)
@export var with_results := true
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
## measured runs only (game/README.md "Measuring performance"): `--skip=S` fast-forwards the new race world S s
## before the first frame; `measure_off` holds the parts a run-only `--no-<part>` flag switches off ("venue",
## "boats", "wakes", "sky", "water", "post", "course", "audio", "sim"); nothing of it is saved
var skip_s := 0.0
var measure_off := {}
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
## the livery (sail number, boat name) of each boat, by boat index (null where none was assigned)
var boat_liveries: Array = []
## the results screen (menus.md §5), null without one
var results: Node = null
## the player's race is over and the camera has eased into the finish view (cameras.md §9.1)
var _race_over_seen := false
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
## the frame-time overlay and log (hud.md §17, PerfMonitor): Shift+F9 shows it; --perf shows it from the start,
## --perf-log=PATH writes the per-second CSV, --perf-seconds=N quits after N seconds
var perf: PerfMonitor
var perf_overlay := false
var perf_log := ""
var perf_seconds := 0.0
## µs spent in the tick callbacks' HUD, audio and course parts this frame (taken out of `sim`)
var _tick_usec := 0
## the developer look panel (hud.md §18, LookPanel): F9
var look_panel: LookPanel
## the chase camera breathes (cameras.md §2.1); `--breathing=off` and the look panel turn it off (DevLook)
var chase_breathing := true
## the scene is built: DevLook's setters apply at once from here on (before, the flags only store their values)
var built := false

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
## the wake state of every boat (CoreSimSource.wake_state_into), kept so a frame makes no Dictionary
var _wake_states: Array = []

## Ticks ahead on the core's thread and the tick's work spread over the frames (game/README.md "The simulation on a
## second core"): on while the scene processes itself (auto_process), off for the tests that drive step_frame.
var threaded := false
enum TickWork { HUD, AUDIO, COURSE }
## the last tick's HUD, audio and course work not yet run (one part per frame, the rest before the next tick)
var _tick_due: Array[int] = []
var _in_advance := false
var _ticked_this_frame := false


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
	venue_view.apply_quality(sea.quality)
	sea.quality_changed.connect(venue_view.apply_quality)  # water_render.md §4.6: no tree shadows on L
	venue_view.build(VenueShapes.from_core((sim as CoreSimSource).core) if on_core else VenueShapes.from_file(venue))
	target.ground = venue_view.ground_height
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.camera.current = true
	rig.chase.breathing = chase_breathing
	rig.clip_allowed = not online
	capture.allowed = not online
	sea.camera = rig.camera
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = Hud.new()
	hud.camera_rig = rig  # world tags and the penalty turn (hud.md §16.4)
	layer.add_child(hud)
	_name_boats()
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
	threaded = auto_process
	if threaded:
		var late := _EndOfFrame.new()
		late.name = "EndOfFrame"
		late.scene = self
		add_child(late)
	_add_pause_menu()
	_add_results()
	if Settings.render_scale_override > 0.0 or Settings.upscaler_override != "" or Settings.aa_override != "":
		Settings.current().apply_render_scale(get_tree().root)
	if no_hud:
		hud.toggle_hidden()
	DevLook.apply_built(self)  # the look flags (shadows, grade, breathing) on the built scene
	_apply_measure_off()
	if scenario_run != null:
		view_boat(scenario_run.scenario.view)
	perf = PerfMonitor.new()
	perf.name = "Perf"
	perf.scene = self
	perf.overlay = perf_overlay
	perf.log_path = perf_log
	perf.seconds = perf_seconds
	add_child(perf)
	look_panel = LookPanel.new()
	look_panel.scene = self
	add_child(look_panel)
	built = true


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


## The results screen (menus.md §5) in a quick race the player sails (not --watch, not a rules scenario); the HUD's own
## results table is off then. Loaded by path so the scene runs where the menus are not there.
func _add_results() -> void:
	if not with_results or not is_quick_race() or not ResourceLoader.exists(RESULTS_SCREEN):
		return
	results = (load(RESULTS_SCREEN) as GDScript).new()
	results.name = "Results"
	add_child(results)
	hud.results_table = false


## A quick race: whether this session is one (the results screen and Race again apply).
func is_quick_race() -> bool:
	return on_core and race_mode and not watch and scenario_run == null


## This session as a GameSetup (menus.md §5 Race again and Change setup): the quick race's class, sail number,
## venue, course, fleet, AI level and wind, with the seed it runs on.
func session_setup() -> GameSetup:
	var g := GameSetup.new()
	g.mode = "race" if race_mode else "free"
	g.class_id = class_id
	g.livery = livery
	g.venue = venue
	g.course = course
	g.fleet_size = fleet_size
	g.ai_level = ai_level
	g.wind_kn = wind_speed_kn
	g.wind_from_deg = wind_from_deg
	g.seed = world_seed
	return g


## race.md §6.4: the player retires (the pause menu's Retire); false when she cannot (can_retire).
func retire() -> bool:
	if not can_retire():
		return false
	return (sim as CoreSimSource).retire(runner.boat)


## Whether the player's boat can retire now: a quick race from the warning signal until her race is over.
func can_retire() -> bool:
	if not is_quick_race() or not (sim as CoreSimSource).core.has_race():
		return false
	var st := int((sim as CoreSimSource).race().get("state", 0))
	return st >= RaceText.RaceState.SEQUENCE and st <= RaceText.RaceState.CLOSING and not hud.race.race_over


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
## the look flags of DevLook.apply_flag (the look panel's rows, hud.md §18): `--sky=clear|fair|hazy|late` (the
## light preset, SkyRig; fair by default), `--look=off` (no colour grade, vignette, contact shading or depth of
## field, to compare), `--ssao=on|off|tier` (contact shading over the tier), `--dof=off`, `--haze=<factor>`,
## `--caps=off`, `--drawn-wind=<kn>`, `--breathing=off`, `--aa=off|fxaa|smaa`, `--quality=L|M|H`,
## `--render-scale=0.67`, `--no-boat-shadows`, `--no-drawn-shadows`;
## `--course=<venue>/<id>` (race mode), `--seed=<n>` (0: from the clock), `--livery=<id>` (the player's livery),
## `--wind=<kn>`, `--wind-from=<deg>`,
## `--fake` (FakeSim), `--core`; measuring (hud.md §17): `--perf` (the frame-time overlay), `--perf-log=PATH`,
## `--perf-seconds=N`, `--upscaler=fsr|bilinear|metalfx`, `--no-vsync`,
## `--shadow-splits=0|1|2|4`, `--shadow-atlas=N`, `--shadow-distance=M`, `--shadow-soft=0..5`, `--no-wake-buffer`,
## `--sea-grid=RINGSxSEGMENTS`, `--water-shader=l|m|h` and `--no-hud` (this run only, not saved);
## `--scenario=<id>` (a rules scenario of game/data/scenarios, or a .scenario.json path; race.md §14).
func _user_args() -> void:
	var fleet_given := false
	var race_flag := false
	for a in OS.get_cmdline_user_args():
		if DevLook.apply_flag(self, a):
			continue
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
		elif a.begins_with("--upscaler="):
			Settings.upscaler_override = a.trim_prefix("--upscaler=").to_lower()
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
		elif a == "--no-hud":
			no_hud = true
		elif a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
		else:
			_measure_flag(a)
	if race_flag and not fleet_given and fleet_size < 2:
		fleet_size = GameSetup.new().fleet_size
	if watch:
		racing = false


## The run-only flags of measured runs (game/README.md "Measuring performance"); false for any other argument.
func _measure_flag(a: String) -> bool:
	if a.begins_with("--skip="):
		skip_s = a.trim_prefix("--skip=").to_float()
	elif a.begins_with("--lod="):
		BoatView.forced_lod = a.trim_prefix("--lod=").to_int()
	elif a.begins_with("--hide-parts="):
		for n in a.trim_prefix("--hide-parts=").split(",", false):
			BoatView.hidden_parts.append(n)
	elif a == "--no-sheets":
		BoatView.draw_sheets = false
	elif a == "--no-sails":
		BoatView.draw_sails = false
	elif a == "--static-sails":
		BoatView.animate_sails = false
	elif a in ["--no-venue", "--no-boats", "--no-wakes", "--no-sky", "--no-water", "--no-post", "--no-course",
			"--no-audio", "--no-sim"]:
		measure_off[a.trim_prefix("--no-")] = true
	else:
		return false
	return true


## The parts `measure_off` switches off, on the built scene (measured runs only).
func _apply_measure_off() -> void:
	if Settings.vsync_override == 0 and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # also where no settings apply (a menu stage)
	if measure_off.has("venue"):
		venue_view.visible = false
	if measure_off.has("boats"):
		for v in boat_views:
			v.visible = false
	if measure_off.has("wakes"):
		wakes.visible = false
		wakes.set_process(false)
	if measure_off.has("sky"):
		# a plain gradient sky shader instead of the clouds and sun disc; the sky still lights the scene
		var env := sky.environment()
		var sh := Shader.new()
		sh.code = "shader_type sky;\nvoid sky() { COLOR = mix(vec3(0.5, 0.74, 1.1), vec3(0.05, 0.18, 0.62), " \
				+ "clamp(EYEDIR.y, 0.0, 1.0)); }\n"
		var m := ShaderMaterial.new()
		m.shader = sh
		env.sky.sky_material = m
	if measure_off.has("water"):
		sea.visible = false
		var plane := MeshInstance3D.new()
		plane.name = "FlatWater"
		var pm := PlaneMesh.new()
		pm.size = Vector2(30000.0, 30000.0)
		plane.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.16, 0.25)
		mat.roughness = 0.2
		plane.material_override = mat
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plane)
	if measure_off.has("post"):
		DevLook.set_look(self, false)
		var env := sky.environment()
		env.glow_enabled = false
		env.adjustment_enabled = false
		env.adjustment_color_correction = null
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if measure_off.has("course") and course_view:
		course_view.visible = false
		sea.set_overlay_lines([])
		sea.set_overlay_circles([])
	if measure_off.has("audio"):
		audio.process_mode = Node.PROCESS_MODE_DISABLED
		AudioServer.set_bus_mute(0, true)
	if measure_off.has("sim"):
		runner.paused = true


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
		if no_boat_shadows:
			DevLook.set_boat_shadows(self, false)
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
		if boat_liveries.size() != boat_views.size():
			boat_liveries.resize(boat_views.size())
		for k in got.size():
			if got[k] != null:
				boat_views[by_class[id][k]].set_livery(got[k])
			boat_liveries[by_class[id][k]] = got[k]


## The race HUD's boat names and sail numbers from the liveries (the player stays "You"; the results screen shows
## her boat's name too).
func _name_boats() -> void:
	if hud == null:
		return
	for b in boat_liveries.size():
		var lv: Livery = boat_liveries[b]
		if lv == null:
			continue
		hud.race.sail_numbers[b] = lv.sail_number
		hud.race.boat_names[b] = lv.boat_name
		if b != runner.boat and scenario_run == null:
			hud.race.names[b] = lv.boat_name


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
	if skip_s > 0.0:
		cs.step_ticks(roundi(skip_s / SimSource.DT), false)
	sim = cs
	core_env = CoreEnvSource.new()
	core_env.name = "CoreEnv"
	core_env.sim = cs
	add_child(core_env)
	sea.source = core_env
	sea.set_sea(cs.sea_components(), cs.sea_exposure())
	sea.quality = sea_quality if Settings.quality_override < 0 else Settings.quality_override as SeaQuality.Tier
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
## the race from the spawn. `new_world` makes the core world again in free sailing too (a new wind). The cameras
## cut to the boat.
func reset_boat(new_world := false) -> void:
	var b := runner.boat
	capture.reset()
	if on_core and (race_mode or new_world):
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
		_wake_states.clear()
		viewed = b
		hud.local_commands = true
		_race_over_seen = false
		_name_boats()
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


## The look panel's restart with a wind (hud.md §18): this race or free sail again with the wind of `kn`, every
## other setting kept. The core takes its wind when the world is made, so the world is made again (the sea's waves
## follow the new wind); on FakeSim the sim's wind and the placeholder sea change. A rules scenario keeps the wind
## of its file.
func restart_with_wind(kn: float) -> void:
	if scenario_run == null:
		wind_speed_kn = kn
	if not on_core:
		var fs := sim as FakeSim
		fs.wind_speed = wind_speed_kn * HudFormat.KNOT
		if env_source.mode == SeaEnvSource.Mode.PLACEHOLDER:
			env_source.wind_kn = wind_speed_kn
			env_source.rebuild()
			sea.set_sea(env_source.sea_components(), env_source.sea_exposure())
	reset_boat(true)


func _setup_fake() -> int:
	var fs := FakeSim.new()
	sim = fs
	fs.wind_speed = wind_speed_kn * HudFormat.KNOT
	fs.wind_from = deg_to_rad(wind_from_deg)
	fs.wind_osc_amp = deg_to_rad(6.0)
	_setup_sea(fs)
	var psi := Frames.wrap_2pi(fs.wind_from - deg_to_rad(start_twa_deg))
	return fs.add_boat(class_id, 0.0, 0.0, psi, 2.5)


## After every tick: the sail snapshots at once (the render interpolation), the HUD, audio and course work of the
## tick one part per frame when `threaded` (the rest before the next tick starts), else all of it now.
func _on_tick(_t: int) -> void:
	_ticked_this_frame = true
	_flush_tick_work()
	if scenario_run != null and scenario_run.finished(sim):
		runner.paused = true  # race.md §14: the clip ends paused; reset_boat runs it again
	_snapshot_sails()
	_tick_due = [TickWork.HUD, TickWork.AUDIO, TickWork.COURSE]
	if threaded:
		_run_tick_work(_tick_due.pop_front())
	else:
		_flush_tick_work()


func _flush_tick_work() -> void:
	while not _tick_due.is_empty():
		_run_tick_work(_tick_due.pop_front())


func _run_tick_work(w: int) -> void:
	var t0 := Time.get_ticks_usec()
	match w:
		TickWork.HUD:
			hud.tick(sim, viewed)
			if not _race_over_seen and hud.race.race_over and is_quick_race():
				_race_over_seen = true
				(sim as CoreSimSource).ai_add_autopilot(runner.boat)  # race.md §6.2: she sails clear by herself
				rig.ease_to(CameraRig.Mode.FINISH, target)  # cameras.md §9.1
			controls.rumble.tick(sim, runner.boat)
		TickWork.AUDIO:
			if not measure_off.has("audio"):
				audio.tick()
		TickWork.COURSE:
			if course_view:
				course_view.tick()
	var us := Time.get_ticks_usec() - t0
	PerfStats.add([&"hud", &"audio", &"course"][w], us)
	if _in_advance:
		_tick_usec += us


## The last node to process in a frame (while `threaded`): calls _end_of_frame.
class _EndOfFrame extends Node:
	var scene: Node

	func _ready() -> void:
		process_priority = 900  # after the scene's nodes, before the PerfMonitor (1000) that times the frame

	func _process(_dt: float) -> void:
		scene._end_of_frame()


## The end of the frame's game work (_EndOfFrame, while `threaded`): the tick's work left over, then the next tick
## started on the core's thread when the next frame steps it (SimRunner.prefetch), so it runs while this frame is
## drawn.
func _end_of_frame() -> void:
	if not is_processing() or not is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	if not _tick_due.is_empty() and runner.next_frame_ticks():
		_flush_tick_work()
	_in_advance = true
	runner.prefetch()
	_in_advance = false
	PerfStats.add(&"sim", Time.get_ticks_usec() - t0)


func _exit_tree() -> void:
	if runner != null:
		runner.settle()


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
	sea.quality = sea_quality if Settings.quality_override < 0 else Settings.quality_override as SeaQuality.Tier
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
	_tick_usec = 0
	_ticked_this_frame = false
	_in_advance = true
	runner.settle()  # the tick started ahead at the end of the last frame: in before anything reads the world
	_in_advance = false
	PerfStats.add(&"sim", Time.get_ticks_usec() - t0 - _tick_usec)
	t0 = Time.get_ticks_usec()
	var raw := scripted_input if scripted_input != null else reader.read()
	if look_panel != null and look_panel.blocks_input():
		raw = raw.without_buttons()  # the look panel has the keys (hud.md §18); the sim keeps running
	_ui_actions(raw)
	hud.pick_enabled = not runner.paused and not controls.text_focus  # not through the menu or chat (hud.md §16.4.1)
	hud.ui_input(raw, dt)
	controls.free_camera = rig.mode == CameraRig.Mode.FREE
	controls.update(raw, dt)
	controls.rumble.frame(dt, controls.let_fly, racing and not runner.paused and viewed == runner.boat)
	var t1 := Time.get_ticks_usec()
	PerfStats.add(&"input", t1 - t0)
	_tick_usec = 0
	_in_advance = true
	runner.advance(capture.sim_dt(dt))  # slow motion and the clean pause (controls.md §7)
	_in_advance = false
	var t2 := Time.get_ticks_usec()
	PerfStats.add(&"sim", t2 - t1 - _tick_usec)
	if not _ticked_this_frame and not _tick_due.is_empty():
		_run_tick_work(_tick_due.pop_front())  # a frame without a tick: one part of the last tick's work
	t2 = Time.get_ticks_usec()
	_update_sea_time(runner.alpha())
	PerfStats.add(&"sea", Time.get_ticks_usec() - t2)
	_update_target(runner.alpha())
	var t3 := Time.get_ticks_usec()
	if course_view and not measure_off.has("course"):
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
	if not measure_off.has("audio"):
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
## those PerfStats sections. The drawn shadows (water_render.md §4.7) are built only for the boats the tier draws.
func _update_target(alpha: float) -> void:
	var n := mini(sim.boat_count(), boat_views.size())
	var poses := sim.render_poses(alpha)
	var us_boats := 0
	var us_sails := 0
	var us_wakes := 0
	var draw_shadows := shadows.enabled
	var origins := PackedVector3Array()
	if draw_shadows:
		origins.resize(n)
	if _wake_states.size() != n:
		_wake_states.resize(n)
		for b in n:
			_wake_states[b] = {}
	BoatView.begin_frame()
	BoatView.near_interval = BoatView.NEAR_INTERVAL_L if sea.quality == SeaQuality.Tier.L else BoatView.NEAR_INTERVAL
	for b in n:
		var ta := Time.get_ticks_usec()
		var p: SimSource.RenderPose = poses[b]
		var v := boat_views[b]
		v.full_rate = b == viewed
		v.apply(p)
		var tb := Time.get_ticks_usec()
		v.apply_sails(_sails_prev_all[b] if b < _sails_prev_all.size() else null,
			_sails_cur_all[b] if b < _sails_cur_all.size() else null, alpha)
		var tc := Time.get_ticks_usec()
		wakes.update_boat(b, _wake_state(b, p))
		if draw_shadows:
			origins[b] = v.global_position
		var td := Time.get_ticks_usec()
		us_boats += tb - ta
		us_sails += tc - tb
		us_wakes += td - tc
		if b == viewed:
			target.pose = p
	if draw_shadows:
		var te := Time.get_ticks_usec()
		for b in shadows.choose(origins, runner.boat):
			shadows.update_boat(b, boat_views[b].shadow_state(b == runner.boat))
		us_wakes += Time.get_ticks_usec() - te
	PerfStats.add(&"boats", us_boats)
	PerfStats.add(&"sails", us_sails)
	PerfStats.add(&"wakes", us_wakes)


## SeaWakes.update_boat state: the render pose and the class waterline (perf dynamics lwl, bwl), in the boat's
## kept Dictionary.
func _wake_state(b: int, p: SimSource.RenderPose) -> Dictionary:
	if on_core:
		return (sim as CoreSimSource).wake_state_into(_wake_states[b], b, p, b == runner.boat)
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
		# Esc with a boat selected clears the selection first (hud.md §16.4.1)
		if runner.paused or not hud.clear_selection():
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
