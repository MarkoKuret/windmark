class_name CameraInput
extends RefCounted
## The camera actions of one frame (controls.md §2-§4) after dead zones and curves, in the units the cameras
## use: deflections -1..1, mouse pixels, wheel notches.

const STICK_DZ := 0.12
const STICK_SAT := 0.95

## orbit keys or right stick (chase, aerial): x + = azimuth clockwise, y + = up
var orbit := Vector2.ZERO
## the orbit keys alone (onboard look rate)
var keys := Vector2.ZERO
## right stick as a look (onboard: absolute, free: rate): x + = right, y + = up
var look := Vector2.ZERO
## mouse drag this frame, pixels: x + = right, y + = down
var mouse := Vector2.ZERO
var dragging := false
var zoom_notches := 0  # + = in
var zoom_held := 0.0  # + = in, per second
var fov_modifier := false
## free camera: x strafe right, y up, z forward, -1..1
var move := Vector3.ZERO
var boost := false
var recentre := false
var next := false
## camera_clip: the next clip camera (cameras.md §9)
var clip := false
## CameraRig.Mode to select, -1 none
var select := -1
var preset_recall := -1  # 0..7
var preset_store := -1


## controls.md §4 stick response: radial dead zone, ((|s| - 0.12) / (0.95 - 0.12))^1.5 along the stick
static func stick(s: Vector2) -> Vector2:
	var m := s.length()
	if m <= STICK_DZ:
		return Vector2.ZERO
	var k := pow(clampf((m - STICK_DZ) / (STICK_SAT - STICK_DZ), 0.0, 1.0), 1.5)
	return s / m * k


static func _axis(r: RawInput, neg: StringName, pos: StringName) -> float:
	return (1.0 if r.is_held(pos) else 0.0) - (1.0 if r.is_held(neg) else 0.0)


## From a RawInput. `free_camera` routes the boat keys and the left stick to the fly controls (controls.md §3).
static func from_raw(r: RawInput, free_camera: bool) -> CameraInput:
	var c := CameraInput.new()
	var rs := stick(r.right_stick)
	c.keys = Vector2(_axis(r, &"camera_orbit_left", &"camera_orbit_right"),
		_axis(r, &"camera_orbit_down", &"camera_orbit_up"))
	c.look = Vector2(rs.x, -rs.y)
	c.orbit = (c.keys + c.look).clampf(-1.0, 1.0)
	c.mouse = r.mouse_drag
	c.dragging = r.is_held(&"camera_orbit_drag")
	c.fov_modifier = r.is_held(&"camera_fov")
	c.zoom_notches = r.wheel
	var zin := r.is_held(&"camera_zoom_in")
	var zout := r.is_held(&"camera_zoom_out")
	# gamepad: RB zooms in, RB + LB held zooms out
	if zin and r.gamepad and r.is_held(&"helm_fine"):
		zin = false
		zout = true
	c.zoom_held = (1.0 if zin else 0.0) - (1.0 if zout else 0.0)
	c.boost = r.is_held(&"camera_boost")
	if free_camera:
		var ls := stick(r.left_stick)
		c.move = Vector3(_axis(r, &"helm_left", &"helm_right") + ls.x,
			c.zoom_held + r.trigger_in - r.trigger_out,
			_axis(r, &"sheet_out", &"sheet_in") - ls.y).clampf(-1.0, 1.0)
		c.zoom_held = 0.0
	c.recentre = r.was_pressed(&"camera_recentre")
	c.next = r.was_pressed(&"camera_next")
	c.clip = r.was_pressed(&"camera_clip")
	var modes := [&"camera_chase", &"camera_onboard", &"camera_aerial", &"camera_free"]
	for i in 4:
		if r.was_pressed(modes[i]):
			c.select = i
	var store := r.is_held(&"camera_preset_store")
	for i in 8:
		if r.was_pressed(StringName("camera_preset_%d" % (i + 1))):
			# F1..F4 also match Shift+F1..F4 (Godot's non-exact modifier match): Shift picks slots 5..8
			if i < 4 and r.is_held(&"helm_fine") and r.was_pressed(StringName("camera_preset_%d" % (i + 5))):
				continue
			if store:
				c.preset_store = i
			else:
				c.preset_recall = i
	return c
