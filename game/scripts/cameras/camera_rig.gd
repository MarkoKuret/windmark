class_name CameraRig
extends Node3D
## The in-race cameras (cameras.md): chase, onboard, aerial and free, switching, presets, shake, and the water
## clearance through the sea height hook of the target. Free and aerial are available in every mode, ranked
## included (cameras.md §5, networking.md §12). The clip cameras (cameras.md §9: start line, mark, long lens,
## helicopter) are offline only (`clip_allowed`), chosen with camera_clip, outside the camera_next cycle; the
## start line and mark shots need `course` (ClipCourse, set by the scene). Presentation only.

enum Mode { CHASE, ONBOARD, AERIAL, FREE, START_LINE, MARK, LONG_LENS, HELICOPTER }

const CLIP_MODES: Array[int] = [Mode.START_LINE, Mode.MARK, Mode.LONG_LENS, Mode.HELICOPTER]

const BLEND_TIME := 0.4
const PRESET_COUNT := 8
const MAX_DT := 0.1

var mode := Mode.CHASE
var options := CamTypes.Options.new()
var chase := ChaseCamera.new()
var onboard := OnboardCamera.new()
var aerial := AerialCamera.new()
var free := FreeCamera.new()
var start_line := StartLineCamera.new()
var mark := MarkCamera.new()
var long_lens := LongLensCamera.new()
var helicopter := HelicopterCamera.new()
## offline: camera_clip selects the clip cameras (online it does nothing)
var clip_allowed := true
## the course inputs of the start line and mark shots; null without a race
var course: ClipCourse = null
## 8 slots of {"mode": Mode, "params": Dictionary}
var presets: Array[Dictionary] = []
var shake := CameraShake.new()
var camera: Camera3D
## the last view applied (for tests)
var view := CamTypes.View.new()

var _free_used := false
var _blend_from := -1
var _blend_t := 0.0
var _prev_mode := Mode.CHASE
var _first := true
## the clip camera used last (camera_clip from a regular camera goes back to it)
var _clip_last := Mode.START_LINE
## the last regular camera (saved as the profile's mode)
var _regular := Mode.CHASE


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	factory_presets(24.5)


func cam(m: int) -> RefCounted:
	match m:
		Mode.ONBOARD:
			return onboard
		Mode.AERIAL:
			return aerial
		Mode.FREE:
			return free
		Mode.START_LINE:
			return start_line
		Mode.MARK:
			return mark
		Mode.LONG_LENS:
			return long_lens
		Mode.HELICOPTER:
			return helicopter
	return chase


static func is_clip(m: int) -> bool:
	return m >= Mode.START_LINE


## cameras.md §9: whether a clip camera can be placed now (start line and mark need the course)
func clip_available(m: int) -> bool:
	match m:
		Mode.START_LINE:
			return course != null and course.has_line
		Mode.MARK:
			return course != null and course.has_mark
		Mode.LONG_LENS, Mode.HELICOPTER:
			return true
	return false


## camera_clip: the next clip camera that can be placed (from a regular camera the one used last first).
func next_clip(t: CamTypes.Target) -> void:
	if not clip_allowed:
		return
	var from := CLIP_MODES.find(mode) + 1 if is_clip(mode) else CLIP_MODES.find(_clip_last)
	for i in CLIP_MODES.size():
		var m := CLIP_MODES[(from + i) % CLIP_MODES.size()]
		if clip_available(m):
			if m != mode:
				select_mode(m, t)
			_clip_last = m
			return


## cameras.md §6 factory presets: chase at 1.6 R0, el 13.5 deg, az every 45 deg
func factory_presets(r0: float) -> void:
	presets.clear()
	for i in PRESET_COUNT:
		presets.append({"mode": Mode.CHASE, "params": {"R": 1.6 * r0, "el": ChaseCamera.EL_DEFAULT,
			"az": Frames.wrap_pi(deg_to_rad(45.0 * i)), "fov": ChaseCamera.FOV_DEFAULT,
			"tau_yaw": 0.35, "tau_heave": 0.3, "lift": 1.0}})


func store_preset(slot: int) -> void:
	if is_clip(mode):
		return  # presets hold the regular cameras only (cameras.md §6)
	presets[slot] = {"mode": mode, "params": cam(mode).params().duplicate(true)}


func recall_preset(slot: int, t: CamTypes.Target) -> void:
	var p: Dictionary = presets[slot]
	select_mode(p["mode"], t)
	cam(mode).set_params(p["params"].duplicate(true))


func select_mode(m: int, t: CamTypes.Target) -> void:
	if m == mode:
		return
	var pair := (mode == Mode.CHASE and m == Mode.AERIAL) or (mode == Mode.AERIAL and m == Mode.CHASE)
	_blend_from = mode if options.smooth_switch and pair else -1
	_blend_t = 0.0
	_prev_mode = mode
	mode = m
	if not is_clip(m):
		_regular = m
	match m:
		Mode.FREE:
			if not _free_used:
				free.recentre(t)
				_free_used = true
		_:
			if _blend_from < 0:
				cam(m).snap(t)


func next_mode(t: CamTypes.Target) -> void:
	select_mode(Mode.CHASE if is_clip(mode) else (mode + 1) % 4, t)


func recentre(t: CamTypes.Target) -> void:
	cam(mode).recentre(t)


## A contact begin of the viewed boat (collisions.md §5).
func contact(closing_speed: float) -> void:
	if not options.reduced_motion:
		shake.contact(closing_speed)


## Viewed boat changed: cut the smoothing to it.
func retarget(t: CamTypes.Target) -> void:
	for m in [Mode.CHASE, Mode.ONBOARD, Mode.AERIAL, Mode.START_LINE, Mode.MARK, Mode.LONG_LENS, Mode.HELICOPTER]:
		cam(m).snap(t)


## One rendered frame.
func frame(t: CamTypes.Target, c: CameraInput, dt_in: float) -> CamTypes.View:
	var dt := minf(dt_in, MAX_DT)
	if _first:
		factory_presets(t.r0())
		chase.recentre(t)
		_first = false
	start_line.course = course
	mark.course = course
	if c.next:
		next_mode(t)
	if c.clip:
		next_clip(t)
	if c.select >= 0:
		select_mode(c.select, t)
	if c.preset_store >= 0:
		store_preset(c.preset_store)
	if c.preset_recall >= 0:
		recall_preset(c.preset_recall, t)
	if c.recentre:
		recentre(t)
	cam(mode).handle_input(c, options, dt)
	var v: CamTypes.View = cam(mode).update(t, options, dt)
	if _blend_from >= 0:
		_blend_t += dt
		var w := Frames.smoothstep01(_blend_t / BLEND_TIME)
		var a: CamTypes.View = cam(_blend_from).update(t, options, dt)
		var bl := CamTypes.View.new()
		bl.xform = Transform3D(a.xform.basis.get_rotation_quaternion().slerp(
			v.xform.basis.get_rotation_quaternion(), w), a.xform.origin.lerp(v.xform.origin, w))
		bl.fov = lerpf(a.fov, v.fov, w)
		bl.near = minf(a.near, v.near)
		v = bl
		if _blend_t >= BLEND_TIME:
			_blend_from = -1
	if (mode == Mode.CHASE or mode == Mode.ONBOARD) and shake.active() and not options.reduced_motion:
		var s := shake.advance(dt)
		v.xform.origin += s[0]
		v.xform.basis = v.xform.basis * Basis.from_euler(s[1])
	view = v
	camera.transform = v.xform
	camera.fov = v.fov
	camera.near = v.near
	camera.far = v.far
	return v


## Every mode's parameters and the presets (saved in the player profile).
func to_dict() -> Dictionary:
	return {"mode": _regular, "chase": chase.params(), "onboard": onboard.params(), "aerial": aerial.params(),
		"free": free.params(), "presets": presets.duplicate(true), "up_default": aerial.up_default}


func from_dict(d: Dictionary) -> void:
	chase.set_params(d.get("chase", {}))
	onboard.set_params(d.get("onboard", {}))
	aerial.set_params(d.get("aerial", {}))
	aerial.up_default = d.get("up_default", aerial.up_default)
	if d.has("free"):
		free.set_params(d["free"])
		_free_used = true
	if d.has("presets"):
		presets.clear()
		for p in d["presets"]:
			presets.append(p)
	mode = d.get("mode", mode)
	if is_clip(mode) or mode < 0:
		mode = Mode.CHASE  # a session starts in a regular camera (cameras.md §6)
	_regular = mode


func save_profile(path := "user://cameras.cfg") -> Error:
	var cf := ConfigFile.new()
	cf.set_value("cameras", "state", to_dict())
	return cf.save(path)


func load_profile(path := "user://cameras.cfg") -> Error:
	var cf := ConfigFile.new()
	var err := cf.load(path)
	if err == OK:
		from_dict(cf.get_value("cameras", "state", {}))
		_first = false
	return err
