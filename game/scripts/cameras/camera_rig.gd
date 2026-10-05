class_name CameraRig
extends Node3D
## The in-race cameras (cameras.md): chase, onboard, aerial and free, switching, presets, shake, and the water
## clearance through the sea height hook of the target. Free and aerial are available in every mode, ranked
## included (cameras.md §5, networking.md §12). The clip cameras (cameras.md §9: start line, mark, long lens,
## helicopter) are offline only (`clip_allowed`), chosen with camera_clip, outside the camera_next cycle; the
## start line and mark shots need `course` (ClipCourse, set by the scene). The lens finish of the camera: the
## vignette (LookFx, under the HUD; stronger on the clip cameras) and the depth of field of the long lens and the
## mark shot (cameras.md §9). The finish view (cameras.md §9.1, FINISH) is entered with ease_to when the player's race
## is over; it is neither a regular nor a clip camera. Presentation only.

enum Mode { CHASE, ONBOARD, AERIAL, FREE, START_LINE, MARK, LONG_LENS, HELICOPTER, FINISH }

const CLIP_MODES: Array[int] = [Mode.START_LINE, Mode.MARK, Mode.LONG_LENS, Mode.HELICOPTER]

const BLEND_TIME := 0.4
## cameras.md §9.1: the ease into the finish view, s
const FINISH_EASE := 2.5
## cameras.md §9 depth of field per clip camera: the blur amount (Godot's practical units), the sharp zone either
## side of the subject (DOF_ZONE_LOA · loa + DOF_ZONE_M), the near and far blur ramps as shares of the focus
## distance, and the focus pull's smoothing. No other camera has depth of field.
const DOF := {
	Mode.LONG_LENS: {"amount": 0.08, "near_ramp": 0.25, "far_ramp": 0.5},
	Mode.MARK: {"amount": 0.06, "near_ramp": 0.3, "far_ramp": 0.6},
}
const DOF_ZONE_LOA := 0.6
const DOF_ZONE_M := 2.0
const DOF_TAU := 0.25
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
var finish := FinishCamera.new()
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
## the vignette over the 3-D image (water_render.md §4.5)
var look: LookFx
## the depth of field of the clip cameras: the camera's attributes while one is shown, else none
var dof := CameraAttributesPractical.new()
## the focus distance followed by the depth of field (m), 0 before the first clip frame
var focus := 0.0

var _free_used := false
var _blend_from := -1
var _blend_t := 0.0
var _blend_len := BLEND_TIME
var _prev_mode := Mode.CHASE
var _first := true
## the clip camera used last (camera_clip from a regular camera goes back to it)
var _clip_last := Mode.START_LINE
## the last regular camera (saved as the profile's mode)
var _regular := Mode.CHASE
var _dof_mode := -1


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	look = LookFx.new()
	add_child(look)
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
		Mode.FINISH:
			return finish
	return chase


static func is_clip(m: int) -> bool:
	return m in CLIP_MODES


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
	if is_clip(mode) or mode == Mode.FINISH:
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
	_blend_len = BLEND_TIME
	_prev_mode = mode
	mode = m
	if not is_clip(m) and m != Mode.FINISH:
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
	select_mode(Mode.CHASE if is_clip(mode) or mode == Mode.FINISH else (mode + 1) % 4, t)


## cameras.md §9.1: eases from the camera in use into `m` over `seconds` (the finish view starts on the side the
## camera is on now). A blend in progress is replaced; easing into the mode shown does nothing.
func ease_to(m: int, t: CamTypes.Target, seconds := FINISH_EASE) -> void:
	if m == mode:
		return
	if m == Mode.FINISH:
		finish.start_from(t, camera.transform.origin)
	else:
		cam(m).snap(t)
	_blend_from = mode
	_blend_t = 0.0
	_blend_len = maxf(seconds, 0.01)
	_prev_mode = mode
	mode = m
	if not is_clip(m) and m != Mode.FINISH:
		_regular = m


func recentre(t: CamTypes.Target) -> void:
	cam(mode).recentre(t)


## A contact begin of the viewed boat (collisions.md §5).
func contact(closing_speed: float) -> void:
	if not options.reduced_motion:
		shake.contact(closing_speed)


## Viewed boat changed: cut the smoothing to it.
func retarget(t: CamTypes.Target) -> void:
	for m in [Mode.CHASE, Mode.ONBOARD, Mode.AERIAL, Mode.START_LINE, Mode.MARK, Mode.LONG_LENS, Mode.HELICOPTER,
			Mode.FINISH]:
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
		var w := Frames.smoothstep01(_blend_t / _blend_len)
		var a: CamTypes.View = cam(_blend_from).update(t, options, dt)
		var bl := CamTypes.View.new()
		bl.xform = Transform3D(a.xform.basis.get_rotation_quaternion().slerp(
			v.xform.basis.get_rotation_quaternion(), w), a.xform.origin.lerp(v.xform.origin, w))
		bl.fov = lerpf(a.fov, v.fov, w)
		bl.near = minf(a.near, v.near)
		v = bl
		if _blend_t >= _blend_len:
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
	_lens(v, t, dt)
	return v


## The vignette for the camera kind and the depth of field of the long lens and the mark shot, focused on the
## subject (cameras.md §9); cuts take the new focus at once.
func _lens(v: CamTypes.View, t: CamTypes.Target, dt: float) -> void:
	look.strength = LookFx.vignette_for(is_clip(mode))
	var p: Dictionary = DOF.get(mode, {})
	if p.is_empty() or v.focus <= 0.0 or not LookFx.dof_allowed():
		camera.attributes = null
		focus = 0.0
		return
	focus = v.focus if focus <= 0.0 or mode != _dof_mode else focus + (v.focus - focus) * Frames.smooth_k(dt, DOF_TAU)
	_dof_mode = mode
	var zone := DOF_ZONE_LOA * t.loa + DOF_ZONE_M
	dof.dof_blur_near_enabled = true
	dof.dof_blur_near_distance = maxf(focus - zone, 0.5)
	dof.dof_blur_near_transition = p["near_ramp"] * focus
	dof.dof_blur_far_enabled = true
	dof.dof_blur_far_distance = focus + zone
	dof.dof_blur_far_transition = p["far_ramp"] * focus
	dof.dof_blur_amount = p["amount"]
	camera.attributes = dof


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
