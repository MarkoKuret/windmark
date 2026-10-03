extends SceneTree
## Dumps the race HUD for the offline previews (tests/race_hud_preview.py draws it over a frame). No window opens.
##   - scene shots: scenes/sail_test.tscn in race mode on the core, run and framed as tests/course_preview_dump.gd
##     frames its shots (the same seconds and cameras), so the world tags sit where the course preview frame has
##     the marks and boats; each at the instrument densities listed, at 1280 x 720, for the Deck 1280 x 800 and,
##     for the portrait capture preset (hud.md §16.5), 1080 x 1920;
##   - a scripted incident on RaceStubSim (rules line, penalty panel and the turn on the water, radar colours, a
##     selected boat's tag, protest prompt) seen from a camera above (the backdrop is not the same scene);
##   - the results of a short race on the core.
## Portrait shots end in _portrait. Every shot prints the block overlaps HudLayoutCheck finds ("no overlaps").
##   godot --headless --path game -s res://tests/race_hud_preview_dump.gd [-- shot ...]
## Writes generated/race_hud_preview/<name>.json: the size, the backdrop and every HudCanvas's primitives.

const OUT := "res://generated/race_hud_preview"
const DT := 0.1
const WIDE := Vector2(1280, 720)
const DECK := Vector2(1280, 800)
const PORTRAIT := Vector2(1080, 1920)
const G := Hud.Density.GLANCE
const R := Hud.Density.RACE
const D := Hud.Density.DATA

## name, course preview shot (the backdrop), seconds, camera (as course_preview_dump.gd), [[density, screen], ...]
const SHOTS := [
	["start", "start_line", 185.0, ["look_boat", Vector3(-150, -330, 7), 0.0, 50.0],
		[[R, WIDE], [G, PORTRAIT], [D, PORTRAIT]]],
	["upwind", "windward", 330.0, ["look_mark", "w", Vector3(-50, -170, 45), 50.0],
		[[G, WIDE], [R, WIDE], [D, WIDE], [G, DECK], [G, PORTRAIT], [R, PORTRAIT]]],
	["aerial", "race_aerial", 262.0, ["aerial", 700.0], [[R, WIDE], [G, PORTRAIT]]],
]

var _only: PackedStringArray = OS.get_cmdline_user_args()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await process_frame
	for s in SHOTS:
		if _only.is_empty() or _only.has(s[0]):
			await _scene_shot(s)
	if _only.is_empty() or _only.has("incident"):
		await _incident()
	if _only.is_empty() or _only.has("results"):
		await _results()
	quit(0)


func _level(d: int) -> String:
	return ["glance", "race", "data"][d]


func _suffix(screen: Vector2) -> String:
	if screen == DECK:
		return "_deck"
	return "_portrait" if screen == PORTRAIT else ""


# ---- scene shots -------------------------------------------------------------------------------------------------

func _scene_shot(s: Array) -> void:
	var scene: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	scene.auto_process = false
	scene.sim_kind = scene.SimKind.CORE
	scene.race_mode = true
	scene.core_settings = {"free_sailing_s": 10.0}
	scene.puffs = true
	get_root().add_child(scene)
	scene.scripted_input = RawInput.new()
	var t := 0.0
	while t < s[2]:
		CoursePilot.steer(scene)
		scene.step_frame(DT)
		t += DT
	var kind := _place_camera(scene, s[3])
	var hud: Hud = scene.hud
	hud.race.names = {1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine", 5: "Ana"}
	for combo in s[4]:
		var screen: Vector2 = combo[1]
		var cam := _view_camera(scene.rig.camera, screen)
		hud.camera = cam
		hud.camera_kind = kind
		hud.screen_size = screen
		hud.density_auto = false
		hud.density = combo[0]
		var name: String = "%s_%s" % [s[0], _level(combo[0])] + _suffix(screen)
		await _shot(hud, name, s[1], screen)
		cam.get_parent().queue_free()
	scene.queue_free()
	await process_frame


## the course preview camera of the shot; returns the camera kind for the HUD
func _place_camera(scene: Node, c: Array) -> String:
	var cam: Camera3D = scene.rig.camera
	match c[0]:
		"aerial":
			scene.rig.select_mode(CameraRig.Mode.AERIAL, scene.target)
			scene.rig.aerial.H = c[1]
			scene.rig.aerial.framing = AerialCamera.Framing.BOAT_AND_MARK
			for i in 30:
				scene.step_frame(1.0 / 60.0)
			return "aerial"
		"look_boat":
			var p: SimSource.RenderPose = scene.target.pose
			_look(cam, c[1], Vector3(p.pos_x, p.pos_y, 1.5), c[3])
		"look_mark":
			var n: Node3D = scene.course_view.mark_node(c[1])
			var at := Frames.scene_to_enu(n.global_position)
			_look(cam, at + c[2], at + Vector3(0, 0, 2.0), c[3])
	return "chase"


func _look(cam: Camera3D, eye: Vector3, at: Vector3, fov: float) -> void:
	var e := Frames.enu_to_scene(eye.x, eye.y, eye.z)
	cam.global_transform = Transform3D(Basis.IDENTITY, e).looking_at(Frames.enu_to_scene(at.x, at.y, at.z), Vector3.UP)
	cam.fov = fov
	cam.near = 0.3


## a copy of the scene camera in a viewport of the preview's size (the headless root window is tiny)
func _view_camera(src: Camera3D, screen: Vector2) -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(screen)
	vp.world_3d = src.get_world_3d()
	get_root().add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.global_transform = src.global_transform
	cam.fov = src.fov
	cam.near = src.near
	cam.far = src.far
	return cam


# ---- incident on the stub ------------------------------------------------------------------------------------------

func _incident() -> void:
	var sim := RaceStubSim.new(5)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 212.0
	for b in 5:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.order = PackedInt32Array([2, 0, 1, 3, 4])
	for i in 5:
		sim.boats_d[sim.order[i]]["D"] = 1400.0 + 30.0 * i
	var th := deg_to_rad(42.0)
	sim.put(0, 120.0, 420.0, Frames.wrap_2pi(-th), 3.1)
	sim.put(1, 60.0, 470.0, th, 3.0)
	sim.put(2, 150.0, 460.0, Frames.wrap_2pi(-th), 3.2)
	sim.put(3, 90.0, 360.0, Frames.wrap_2pi(-th), 3.0)
	sim.put(4, 230.0, 380.0, th, 2.9)
	var RR := RaceText.Rule
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 1, "kc_holder": 0, "kc_rule": RR.R10, "kc_state": 1}),
		sim.pair(0, 2, {"kc_giver": 0, "kc_holder": 2, "kc_rule": RR.R12, "kc_state": 2}),
		sim.pair(0, 3, {"kc_giver": 3, "kc_holder": 0, "kc_rule": RR.R12})]
	sim.rules_d[0] = {"pending": [{"rule": RR.R12, "other": 2, "count": 1}], "turn_progress": deg_to_rad(210.0),
		"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 27.0, "received": 1, "turning_for_penalty": true}
	var hud := Hud.new()
	get_root().add_child(hud)
	hud.screen_size = WIDE
	hud.race.names = {1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine"}
	hud.race.ai_levels = {1: "Expert", 2: "Intermediate", 3: "Pro", 4: "Easy"}
	for i in 60:
		sim.step()
		hud.tick(sim, 0)
	sim.rules_ev = [{"kind": RaceText.Rev.PROTESTABLE, "boat": 1, "other": 0, "rule": RR.R10, "deadline": 8.0}]
	sim.step()
	hud.tick(sim, 0)
	sim.rules_ev = []
	for i in 30:
		sim.step()
		hud.tick(sim, 0)
	# a camera above and behind the boat, looking down at her
	var vp := SubViewport.new()
	vp.size = Vector2i(WIDE)
	get_root().add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 50.0
	var eye := Frames.enu_to_scene(120.0 + 40.0, 420.0 - 70.0, 90.0)
	cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(Frames.enu_to_scene(125.0, 440.0, 0.0), Vector3.UP)
	hud.camera = cam
	hud.camera_kind = "aerial"
	hud.selected = {2: true}
	hud.density_auto = false
	hud.density = R
	await _shot(hud, "incident_race", "race_aerial", WIDE)
	# the same incident in the portrait capture preset: the penalty panel and the rule text on top
	vp.size = Vector2i(PORTRAIT)
	hud.screen_size = PORTRAIT
	for lvl in [G, R]:
		hud.density = lvl
		await _shot(hud, "incident_%s_portrait" % _level(lvl), "race_aerial", PORTRAIT)
	hud.queue_free()
	vp.queue_free()


# ---- results of a short core race --------------------------------------------------------------------------------

func _results() -> void:
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": 20260925, "wind_speed": 11.0 * HudFormat.KNOT, "wind_from": 0.2, "shift_preset": 1,
		"free_sailing_s": 10.0}
	sim.create("example_bay")
	for i in 4:
		sim.add_entry("wm7", {"human": true})
	sim.create_race("example_bay/example_wl")
	var hud := Hud.new()
	get_root().add_child(hud)
	hud.screen_size = WIDE
	hud.race.names = {1: "Nora", 2: "Ivo", 3: "Maja"}
	hud.race.ai_levels = {1: "Expert", 2: "Intermediate", 3: "Pro"}
	var pilot := RacePilot.new(sim)
	var n := 0
	while n < 60000:
		pilot.steer()
		sim.step()
		hud.tick(sim, 0)
		n += 1
		if int(sim.race()["state"]) == RaceText.RaceState.CLOSED:
			for i in 30:
				hud.tick(sim, 0)
			hud.density_auto = false
			hud.density = R
			await _shot(hud, "results_race", "committee", WIDE)
			hud.screen_size = PORTRAIT
			await _shot(hud, "results_race_portrait", "committee", PORTRAIT)
			break
	hud.queue_free()


# ---- writing -------------------------------------------------------------------------------------------------------

func _shot(hud: Hud, name: String, backdrop: String, screen: Vector2) -> void:
	hud.frame(0.25)
	hud.refresh_text()
	hud.frame(0.0)
	var items := []
	for b in hud.blocks():
		var o := b.position
		var p: Node = b.get_parent()
		while p != null and p != hud:
			if p is Control:
				o += (p as Control).position
			p = p.get_parent()
		var prims := []
		for q in b.primitives():
			prims.append(_json(q))
		items.append({"name": String(b.name), "x": o.x, "y": o.y, "alpha": b.modulate.a, "prims": prims})
	var f := FileAccess.open("%s/%s.json" % [OUT, name], FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [screen.x, screen.y], "backdrop": backdrop, "items": items}))
	f.close()
	var bad := HudLayoutCheck.problems(hud, screen)
	print("race hud preview: %s (%d blocks): %s" % [name, items.size(),
		"no overlaps" if bad.is_empty() else "OVERLAPS " + str(bad)])
	await process_frame


static func _json(q: Dictionary) -> Dictionary:
	var d := {}
	for key in q:
		var v: Variant = q[key]
		if v is Color:
			d[key] = [v.r, v.g, v.b, v.a]
		elif v is Vector2:
			d[key] = [v.x, v.y]
		elif v is Rect2:
			d[key] = [v.position.x, v.position.y, v.size.x, v.size.y]
		elif v is PackedVector2Array:
			d[key] = Array(v).map(func(p: Vector2) -> Array: return [p.x, p.y])
		else:
			d[key] = v
	return d
