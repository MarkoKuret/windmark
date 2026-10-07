class_name MenuStage
extends Node
## The main menu's live backdrop (menus.md §4): the sail scene racing a few AI boats on the example venue with no
## HUD, no pause menu, no course guides, no player input and no sound, filmed by a slow cinematic drift. build()
## returns false when the sail scene is not there or does not load; the menu then draws the painted backdrop.

const SAIL_SCENE := "res://scenes/sail_test.tscn"
const VENUE := "practice_waters"
const FLEET := 4
## tier L (menus.md §4): two boats, no sun shadows, at most 30 frames a second while the menu shows
const FLEET_L := 2
const FPS_L := 30
const AI_LEVEL := "expert"
const WIND_KN := 12.0
## the drift (menus.md §4): circling rate, distance and height ranges, the breathing period, the time on each
## boat and the easing time constant to the next
const ORBIT_RATE := deg_to_rad(1.5)
const DIST := Vector2(45.0, 70.0)
const HEIGHT := Vector2(5.0, 11.0)
const BREATH_S := 40.0
const HOLD_S := 35.0
const EASE_TAU := 1.4
## the boat sits this far right of centre (camera yaw, rad), clear of the menu on the left
const FRAME_OFFSET := deg_to_rad(9.0)
## restart the race this long after the first boat finishes
const RESTART_AFTER_S := 30.0

## the sail scene instance (null before build or after a failed one)
var scene: Node3D
## the boat followed
var boat := 0
var reduced_motion := false
var _t := 0.0
var _hold := 0.0
var _az := 0.0
var _focus := Vector3.ZERO
var _eye := Vector3.ZERO
var _started := false
var _finished_for := 0.0


## Loads the sail scene under `host` and starts the backdrop race. `path` replaces the scene (tests: a missing
## path is the fallback). False when it is not there or does not load.
func build(host: Node, path := SAIL_SCENE) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var sc := packed.instantiate() as Node3D
	if sc == null or not ("setup" in sc):
		if sc != null:
			sc.free()
		return false
	var g := GameSetup.new()
	g.mode = "race"
	g.venue = VENUE
	var courses := MenuData.courses(VENUE, g.class_id)
	if courses.is_empty():
		g.mode = "free"
	else:
		g.course = courses[0]["id"]
	g.fleet_size = fleet_for(Settings.current().effective_quality())
	g.ai_level = AI_LEVEL
	g.wind_kn = WIND_KN
	g.wind_from_deg = 0.0
	g.seed = 0
	sc.setup = g
	sc.watch = true  # the player's entry sails itself too
	sc.with_pause_menu = false
	sc.apply_settings = false
	sc.no_hud = true
	sc.scripted_input = RawInput.new()  # no player input reaches the scene
	sc.name = "Stage"
	scene = sc
	process_priority = 100  # after the scene's own frame: the drift has the last word on the camera
	host.add_child(sc)
	if not sc.get("built"):
		host.remove_child(sc)
		sc.queue_free()
		scene = null
		return false
	_quiet()
	apply_settings(Settings.current())
	_started = false
	return true


## No chrome and no sound (menus.md §4).
func _quiet() -> void:
	var cv: Variant = scene.get("course_view")
	if cv is Object and cv != null:
		cv.show_guides = false
		cv.show_laylines = false
		cv.show_zone = false
	var audio: Variant = scene.get("audio")
	if audio is Node:
		audio.audible = false
		for p in (audio as Node).find_children("*", "AudioStreamPlayer", true, false):
			(p as AudioStreamPlayer).stop()
		for p in (audio as Node).find_children("*", "AudioStreamPlayer3D", true, false):
			(p as AudioStreamPlayer3D).stop()
	for n in ["look_panel", "perf"]:
		var node: Variant = scene.get(n)
		if node is PerfMonitor and (node as PerfMonitor).log_path != "":
			continue  # a measured run of the menu (`--perf-log`) keeps its log
		if node is Node:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED


## The backdrop's fleet for a quality tier (menus.md §4): set when the menu opens.
static func fleet_for(tier: SeaQuality.Tier) -> int:
	return FLEET_L if tier == SeaQuality.Tier.L else FLEET


## The player's quality tier on the sea and sky (on L without sun shadows), the frame cap, and reduced motion on
## the drift (the render scale is the window's, Settings.apply_display).
func apply_settings(s: Settings) -> void:
	if scene == null:
		return
	s.apply_sea(scene.sea, scene.sky)
	_sun_shadows(s)
	apply_frame_cap(s)
	reduced_motion = s.reduced_motion


## No sun shadows on tier L (menus.md §4); the tier's otherwise (Settings.apply_sea set them).
func _sun_shadows(s: Settings) -> void:
	var sun: DirectionalLight3D = (scene.sky as SkyRig).sun() if scene.sky is SkyRig else null
	if sun != null and s.effective_quality() == SeaQuality.Tier.L:
		sun.shadow_enabled = false


## Sun shadows on (tests): false on tier L.
func sun_shadows() -> bool:
	var sun: DirectionalLight3D = (scene.sky as SkyRig).sun() if scene != null and scene.sky is SkyRig else null
	return sun != null and sun.shadow_enabled


## The menu's frame rate (menus.md §4): on tier L at most FPS_L (or the player's lower limit), else the player's.
## Call after Settings.apply_display, which sets the player's.
func apply_frame_cap(s: Settings) -> void:
	Engine.max_fps = frame_cap(s.effective_quality(), s.fps_limit)


## Engine.max_fps for the menu on a tier with the player's limit (0 = none).
static func frame_cap(tier: SeaQuality.Tier, fps_limit: int) -> int:
	if tier != SeaQuality.Tier.L:
		return fps_limit
	return FPS_L if fps_limit <= 0 else mini(fps_limit, FPS_L)


## Leaving the menu: the player's frame rate limit back.
func _exit_tree() -> void:
	Engine.max_fps = Settings.current().fps_limit


func boat_count() -> int:
	return scene.boat_views.size() if scene != null else 0


func _boat_pos(b: int) -> Vector3:
	var views: Array = scene.boat_views
	if views.is_empty():
		return Vector3.ZERO
	return (views[clampi(b, 0, views.size() - 1)] as Node3D).global_position


func _process(dt: float) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	frame(dt)


## One frame of the drift; also restarts the race after the finish.
func frame(dt: float) -> void:
	var rate := 1.0 / 3.0 if reduced_motion else 1.0
	_t += dt * rate
	_hold += dt
	var n := boat_count()
	if n == 0:
		return
	if _hold >= HOLD_S and n > 1:
		_hold = 0.0
		boat = (boat + 1) % n
	var want := _boat_pos(boat) + Vector3(0, 2.0, 0)
	if not _started:
		_focus = want
		_az = randf() * TAU
	_az = wrapf(_az + ORBIT_RATE * rate * dt, 0.0, TAU)
	var breath := 0.5 - 0.5 * cos(TAU * _t / BREATH_S)
	var dist := lerpf(DIST.x, DIST.y, breath)
	var h := lerpf(HEIGHT.y, HEIGHT.x, breath)
	var k := 1.0 - exp(-dt / EASE_TAU)
	_focus = _focus.lerp(want, 1.0 if not _started else k)
	var eye := _focus + Vector3(sin(_az) * dist, 0.0, cos(_az) * dist)
	eye.y = maxf(h, 3.0)
	_eye = eye if not _started else _eye.lerp(eye, k)
	_started = true
	var cam: Camera3D = scene.rig.camera
	cam.global_position = _eye
	cam.look_at(_focus, Vector3.UP)
	cam.rotate_object_local(Vector3.UP, FRAME_OFFSET)
	_restart_check(dt)


func _restart_check(dt: float) -> void:
	if not scene.get("on_core") or not scene.get("race_mode"):
		return
	var cs: Variant = scene.sim
	if not (cs is CoreSimSource) or not cs.core.has_race():
		return
	var done := false
	for b in boat_count():
		done = done or bool(cs.core.race_boat(b).get("finished", false))
	_finished_for = _finished_for + dt if done else 0.0
	if _finished_for >= RESTART_AFTER_S:
		_finished_for = 0.0
		scene.reset_boat()
		_quiet()
		_sun_shadows(Settings.current())


## The camera the backdrop is seen through.
func camera() -> Camera3D:
	return scene.rig.camera if scene != null else null
