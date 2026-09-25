extends Node3D
## Water test scene (scenes/water_test.tscn): the example venue sea, the daytime sky, and a placeholder boat
## sailing a circle at a steady speed with its wake, seen from a chase or an aerial camera.
##
## Windowed capture (owner's OK needed, opens a window for a few seconds):
##   godot --path game res://scenes/water_test.tscn -- --capture=<dir> [--tier=L|M|H]
## writes <dir>/water_<camera>_<tier>.png for the chase, aerial, overview, sun and bow cameras and quits.

enum CameraMode { CHASE, AERIAL, OVERVIEW, SUN, BOW }

@export var camera_mode: CameraMode = CameraMode.CHASE:
	set(v):
		camera_mode = v
		_place_camera()
@export var boat_speed := 3.0
@export var circle_radius := 60.0
@export var circle_centre := Vector2(250.0, 1500.0)
## Start of the render clock, ms (a sampled puff time of the core data, so the puffs are the core's).
@export var start_time_ms := -1.0

@onready var sea: Sea = $Sea
@onready var wakes: SeaWakes = $Wakes
@onready var env_source: SeaEnvSource = $EnvSource
@onready var cam: Camera3D = $Camera
@onready var boat: Node3D = $Boat

var _capture_dir := ""
var _frames := 0
var _shots: Array = []
var _boat_state := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_dir = a.trim_prefix("--capture=")
		elif a.begins_with("--tier="):
			sea.quality = {"L": SeaQuality.Tier.L, "M": SeaQuality.Tier.M, "H": SeaQuality.Tier.H}.get(
					a.trim_prefix("--tier="), SeaQuality.Tier.M)
	if start_time_ms < 0.0:
		var times := env_source.core_puff_times()
		start_time_ms = float(times[0]) if not times.is_empty() else 600000.0
	sea.render_time_ms = start_time_ms
	SeaQuality.apply_environment($SkyDay.environment(), sea.quality)
	_build_boat()
	_update_boat(0.0)
	if not _capture_dir.is_empty():
		_shots = [[CameraMode.CHASE, "chase"], [CameraMode.AERIAL, "aerial"], [CameraMode.OVERVIEW, "overview"], [CameraMode.SUN, "sun"],
				[CameraMode.BOW, "bow"]]
		camera_mode = CameraMode.CHASE


func _build_boat() -> void:
	var glb := "res://generated/boats/wm7.glb"
	if ResourceLoader.exists(glb):
		var scene := load(glb) as PackedScene
		if scene:
			var model := scene.instantiate()
			BoatMaterials.apply(model)
			boat.add_child(model)
			return
	var hull := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(2.2, 0.9, 7.0)
	hull.mesh = m
	hull.position = Vector3(0.0, 0.25, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.9)
	hull.material_override = mat
	boat.add_child(hull)


## Placeholder boat on a circle (counter-clockwise seen from above), heave and pitch from the sea at the
## hull ends: stands in for the sim source until the boat node (WM-016.07) exists.
func _update_boat(t_s: float) -> void:
	var w := boat_speed / circle_radius
	var a := w * t_s
	var x := circle_centre.x + circle_radius * cos(a)
	var y := circle_centre.y + circle_radius * sin(a)
	var psi := fposmod(atan2(-sin(a), cos(a)), TAU)   # tangent (-sin a, cos a) as a compass heading
	var lwl := 6.8
	var f := Vector2(sin(psi), cos(psi))
	var hb := sea.height_at(x + f.x * 0.45 * lwl, y + f.y * 0.45 * lwl)
	var hs := sea.height_at(x - f.x * 0.45 * lwl, y - f.y * 0.45 * lwl)
	var hm := sea.height_at(x, y)
	var z := (hb + hs + 2.0 * hm) * 0.25
	var pitch := atan((hb - hs) / (0.9 * lwl))
	_boat_state = {
		"x": x, "y": y, "z": z, "psi": psi, "heel": deg_to_rad(12.0), "pitch": pitch, "lwl": lwl,
		"bwl": 2.0, "transom_width": 1.6, "bow_x": 0.5 * lwl, "stern_x": -0.5 * lwl, "own": true,
	}
	var basis := Basis(Vector3.UP, PI - psi) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, deg_to_rad(12.0))
	boat.global_transform = Transform3D(basis, Vector3(x, z, -y))
	wakes.update_boat(0, _boat_state)
	_place_camera()


func _place_camera() -> void:
	if cam == null or _boat_state.is_empty():
		return
	var p := Vector3(_boat_state["x"], 0.0, -_boat_state["y"])
	var psi: float = _boat_state["psi"]
	var fwd := Vector3(sin(psi), 0.0, -cos(psi))
	var eye: Vector3
	if camera_mode == CameraMode.CHASE:
		eye = p - fwd * 14.0 + Vector3(0.0, 4.5, 0.0) + fwd.cross(Vector3.UP) * 3.0
	elif camera_mode == CameraMode.AERIAL:
		eye = p - fwd * 70.0 + Vector3(0.0, 90.0, 0.0)
	elif camera_mode == CameraMode.OVERVIEW:
		eye = p - fwd * 450.0 + Vector3(0.0, 520.0, 0.0)
	elif camera_mode == CameraMode.BOW:
		# abeam of the bow, a little ahead: the bow wave and the mist on the near side
		var side := fwd.cross(Vector3.UP)
		eye = p + fwd * 7.0 - side * 9.0 + Vector3(0.0, 2.6, 0.0)
		cam.look_at_from_position(eye, p + fwd * 2.2 + Vector3(0.0, 0.4, 0.0), Vector3.UP)
		return
	else:
		# toward the sun: the boat against the glitter
		var sun: Vector3 = $SkyDay.sun_direction()
		var sh := Vector3(sun.x, 0.0, sun.z).normalized()
		eye = p - sh * 22.0 + Vector3(0.0, 3.5, 0.0)
		cam.look_at_from_position(eye, p + sh * 60.0 + Vector3(0.0, 20.0, 0.0), Vector3.UP)
		return
	cam.look_at_from_position(eye, p + Vector3(0.0, 1.0, 0.0) + fwd * 4.0, Vector3.UP)


func _process(_delta: float) -> void:
	_update_boat((sea.render_time_ms - start_time_ms) * 0.001)
	if _capture_dir.is_empty():
		return
	_frames += 1
	# Let the ribbon build up (4 s of wake) before the first shot, then one shot per camera.
	if _frames == 300 or (_frames > 300 and (_frames - 300) % 30 == 0):
		if _frames > 300:
			var done: Array = _shots.pop_front()
			var tier: String = sea.get_tier()["name"]
			var img := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(_capture_dir)
			img.save_png(_capture_dir.path_join("water_%s_%s.png" % [done[1], tier]))
		if _shots.is_empty():
			get_tree().quit()
		else:
			camera_mode = _shots[0][0]
