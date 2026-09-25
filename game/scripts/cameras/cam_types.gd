class_name CamTypes
extends RefCounted
## Shared records of the cameras (cameras.md §1).


## What one camera produces for a frame.
class View:
	var xform := Transform3D.IDENTITY
	var fov := 40.0  # vertical, degrees
	var near := 0.5
	var far := 30000.0


## The viewed boat and the world, per frame.
class Target:
	var pose := SimSource.RenderPose.new()
	var loa := 7.2
	var beam_max := 2.5
	var geometry: BoatGeometry
	## sea.md §7 height: (x east, y north) -> m (the sail test sets Sea.height_at); flat by default
	var sea_height: Callable = func(_x: float, _y: float) -> float: return 0.0

	## cameras.md §2 default distance
	func r0() -> float:
		return maxf(loa + 16.0, beam_max + 22.0)

	## the hull reference point in the scene at heave z
	func point(z: float) -> Vector3:
		return Frames.enu_to_scene(pose.pos_x, pose.pos_y, z)

	func sea_at(p: Vector3) -> float:
		return sea_height.call(p.x, -p.z)


## Player options that touch the cameras (controls.md §4, §6).
class Options:
	var speed := 1.0
	var invert_orbit_x := false
	var invert_orbit_y := false
	var invert_look_x := false
	var invert_look_y := false
	var reduced_motion := false
	var onboard_look_stays := false
	var smooth_switch := false
	var auto_recentre := false
	var follow_waves := false


## cameras.md §7 water clearance with the decaying correction
class Clearance:
	const C_W := 1.0
	const TAU := 0.25
	var corr := 0.0

	func apply(eye: Vector3, t: Target, dt: float) -> Vector3:
		var floor_y := t.sea_at(eye) + C_W
		corr = maxf(maxf(floor_y - eye.y, corr * exp(-dt / TAU)), 0.0)
		return Vector3(eye.x, eye.y + corr, eye.z)

	func reset() -> void:
		corr = 0.0


## cameras.md §7 near plane away from onboard
static func near_for(eye_y: float) -> float:
	return 0.5 + 119.5 * clampf((eye_y - 80.0) / 2000.0, 0.0, 1.0)


## a transform at `eye` looking at `at` with the given up hint
static func look(eye: Vector3, at: Vector3, up := Vector3.UP) -> Transform3D:
	return Transform3D(Basis.IDENTITY, eye).looking_at(at, up)
