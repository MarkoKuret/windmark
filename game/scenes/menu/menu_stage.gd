class_name MenuStage
extends Node
## The main menu's live backdrop (menus.md §4): the sail scene racing a few AI boats on the example venue with no
## HUD, no pause menu, no course guides, no player input and no sound of its own (the menu plays a quiet bed,
## MenuAmbience), filmed by a slow cinematic drift. build()
## returns false when the sail scene is not there or does not load; the menu then draws the painted backdrop.
## On the Boat step of the setup (menus.md §4.1) show_boat() puts a showcase boat of the chosen class on the water,
## heeled and trimmed, and the camera circles it instead.

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
## the showcase boat (menus.md §4.1): where it sits (ENU m, east of the course), its heading (compass, rad: NW,
## the backdrop's north wind on the starboard bow), heel (starboard tack: port side down), the apparent wind its
## sails are trimmed for, the camera's orbit (rate, distance and height by the REFERENCE mast height, the tallest
## in the fleet, the aim up that mast: the camera stays put when the class changes, so a sportsboat looks small
## beside where the classic yacht stood) and the bearing it starts from (the leeward bow quarter)
const SHOW_POS := Vector2(700.0, 0.0)
const SHOW_PSI := deg_to_rad(315.0)
const SHOW_HEEL := deg_to_rad(-12.0)
const SHOW_AWA := deg_to_rad(30.0)
const SHOW_AWS := 7.5
const SHOW_TWS := 6.0
const SHOW_ORBIT := deg_to_rad(2.5)
const SHOW_DIST := 1.9
const SHOW_DIST_ADD := 2.0
const SHOW_HEIGHT := 0.35
const SHOW_AIM := 0.33
const SHOW_START_BEARING := deg_to_rad(265.0)

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
## the showcase boat (menus.md §4.1), null when the stage shows the fleet
var showcase: BoatView
var showcase_class := ""
var showcase_livery := ""
## where on the screen the followed point sits, 0 the left edge to 1 the right (menus.md §4.1: the boat centred in
## the room beside the page); below 0 the drift's FRAME_OFFSET
var frame_x := -1.0
var _show_sails: SimSource.SailsView
## the camera's reference mast (m): the fleet's tallest (menus.md §4.1), at least half this class's length
var _show_mast := 10.0
var _show_bearing := SHOW_START_BEARING


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


## One frame of the drift (or of the showcase, menus.md §4.1); also restarts the race after the finish.
func frame(dt: float) -> void:
	if showcase != null and is_instance_valid(showcase):
		_showcase_frame(dt)
		_showcase_camera(dt)
		_restart_check(dt)
		return
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


## The showcase boat of a class in a livery (menus.md §4.1): made when the class changes, repainted when only the
## livery does. Nothing without the live scene.
func show_boat(class_id: String, livery_id: String) -> void:
	if scene == null:
		return
	if showcase != null and class_id == showcase_class:
		if livery_id != showcase_livery:
			_paint(livery_id)
		return
	var fresh := showcase == null
	hide_boat()
	var data := BoatClassData.load_class(class_id)
	if data == null:
		return
	showcase = BoatView.create(data.info, data.info.rudder_max)
	showcase.name = "Showcase_" + class_id
	showcase.full_rate = true
	showcase.own = true
	scene.add_child(showcase)
	showcase_class = class_id
	_show_mast = reference_mast(class_id, data.info.loa)
	_show_sails = showcase_sails(data, SHOW_AWA, SHOW_AWS, SHOW_TWS)
	_paint(livery_id)
	if fresh:
		_show_bearing = SHOW_START_BEARING  # a class swap keeps the bearing: only the boat changes
	_started = false
	frame(0.0)


## The showcase camera's reference mast height (m, menus.md §4.1): the tallest mast in the fleet, so every class
## is seen from the same place at its true size; at least this class's own mast and half its length.
static func reference_mast(class_id: String, loa: float) -> float:
	var own := maxf(float(MenuData.class_facts(class_id)["mast_height"]), 0.5 * loa)
	return maxf(MenuData.tallest_mast(), own)


func _paint(livery_id: String) -> void:
	showcase_livery = livery_id
	var list := Livery.load_class(showcase_class)
	if list.is_empty():
		return
	var lv: Livery = list[0]
	for l in list:
		if l.id == livery_id:
			lv = l
	showcase.set_livery(lv)


## Frees the showcase boat; the drift cuts back to the fleet.
func hide_boat() -> void:
	if showcase == null:
		return
	if is_instance_valid(showcase):
		showcase.queue_free()
	showcase = null
	showcase_class = ""
	showcase_livery = ""
	_show_sails = null
	_started = false


## The sails of a boat on a beat (menus.md §4.1): the main and the headsail up at their optimal angles for the
## apparent wind, the other sails down; the sign of the angles from the wind's side (sail_visuals.md §2).
static func showcase_sails(data: BoatClassData, awa: float, aws: float, tws: float) -> SimSource.SailsView:
	var sv := SimSource.SailsView.new()
	sv.awa = awa
	sv.aws = aws
	sv.tws = tws
	var fi := data.start_front
	if fi < 0:
		for i in data.info.sails.size():
			if data.info.sails[i].type in ["jib", "genoa"] and fi < 0:
				fi = i
	var cfg: Dictionary = data.configs.get(fi, data.configs.get(-1, {}))
	for i in data.info.sails.size():
		var st := SimSource.SailState.new()
		var si: SimSource.SailInfo = data.info.sails[i]
		if i == data.info.main_sail or i == fi:
			st.phase = SimSource.Phase.UP
			var opt: PerfTable = cfg.get("optimal", {}).get(i)
			var m: float = opt.at(tws, absf(awa)) if opt != null else si.sheet_min
			st.beta = -Frames.sgn(awa) * clampf(m, si.sheet_min, si.sheet_max)
		sv.sails.append(st)
		sv.out.append(SimSource.SailOutput.new())
	sv.front = fi
	return sv


## The showcase boat on the water this frame: the sea's height under it, pitch and roll from the sea's slope over
## the hull, the fixed heel; its sails placed.
func _showcase_frame(dt: float) -> void:
	var info := showcase.info
	var sea: Variant = scene.get("sea")
	var fwd := Vector2(sin(SHOW_PSI), cos(SHOW_PSI))
	var stb := Vector2(cos(SHOW_PSI), -sin(SHOW_PSI))
	var half_l := 0.5 * maxf(info.lwl, 1.0)
	var half_b := 0.5 * maxf(info.bwl, 0.5)
	var h := 0.0
	var theta := 0.0
	var roll := 0.0
	if sea != null and sea.has_method("height_at"):
		h = sea.height_at(SHOW_POS.x, SHOW_POS.y)
		var hb: float = sea.height_at(SHOW_POS.x + fwd.x * half_l, SHOW_POS.y + fwd.y * half_l)
		var hs: float = sea.height_at(SHOW_POS.x - fwd.x * half_l, SHOW_POS.y - fwd.y * half_l)
		var hp: float = sea.height_at(SHOW_POS.x - stb.x * half_b, SHOW_POS.y - stb.y * half_b)
		var hst: float = sea.height_at(SHOW_POS.x + stb.x * half_b, SHOW_POS.y + stb.y * half_b)
		theta = atan2(hb - hs, 2.0 * half_l)
		roll = atan2(hp - hst, 2.0 * half_b)
	var pose := SimSource.RenderPose.new()
	pose.pos_x = SHOW_POS.x
	pose.pos_y = SHOW_POS.y
	pose.z = h
	pose.psi = SHOW_PSI
	pose.theta = theta
	pose.phi = SHOW_HEEL + roll
	pose.twd_from = 0.0
	pose.twa = -SHOW_AWA
	showcase.apply(pose)
	showcase.apply_sails(_show_sails, _show_sails, 1.0, maxf(dt, 0.0))


## The camera round the showcase boat (menus.md §4.1): a three-quarter view circling slowly.
func _showcase_camera(dt: float) -> void:
	var rate := 1.0 / 3.0 if reduced_motion else 1.0
	_show_bearing = wrapf(_show_bearing + SHOW_ORBIT * rate * dt, 0.0, TAU)
	var focus := Frames.enu_to_scene(SHOW_POS.x, SHOW_POS.y, showcase.position.y + SHOW_AIM * _show_mast)
	var dist := SHOW_DIST * _show_mast + SHOW_DIST_ADD
	var eye := focus + Vector3(sin(_show_bearing) * dist, 0.0, -cos(_show_bearing) * dist)
	eye.y = maxf(SHOW_HEIGHT * _show_mast, 2.5)
	var cam: Camera3D = scene.rig.camera
	cam.global_position = eye
	cam.look_at(focus, Vector3.UP)
	cam.rotate_object_local(Vector3.UP, frame_offset(cam))
	_started = true


## The yaw that puts the followed point at `frame_x` of the screen width (menus.md §4.1), the drift's FRAME_OFFSET
## without one.
func frame_offset(cam: Camera3D) -> float:
	if frame_x < 0.0:
		return FRAME_OFFSET
	var vp := cam.get_viewport()
	var sz := vp.get_visible_rect().size if vp != null else Vector2(16, 9)
	var aspect := sz.x / maxf(sz.y, 1.0)
	return atan((2.0 * frame_x - 1.0) * tan(deg_to_rad(cam.fov) * 0.5) * aspect)
