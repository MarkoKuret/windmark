class_name Sea
extends Node3D
## The drawn sea (water_render.md): a camera-centred radial grid whose vertex shader evaluates the core's
## sea_height from the wave components, shaded with detail normals, puffs and lulls, whitecaps and wakes.
##
## Inputs (all optional, set before or during play):
##   source        a node with sea_components(), sea_exposure(), wind_state(t_ms) (see sea_env_source.gd and
##                 CoreEnvSource), and optionally venue_wind_field() (the venue's land-effect field, wind.md §8)
##   sky           a SkyRig (colours of the sky ramp and the sun for the slope contrast and the crest light)
##   camera        the camera the grid follows (default: the viewport's current camera)
##   render_time_ms  the environment clock at this frame (fractional ms); advanced by delta when
##                 use_internal_clock is on, otherwise set by the owner every frame before _process
## Or push data directly with set_sea() and set_wind().

signal quality_changed(tier: int)

const DETAIL_SCALE := [1.0 / 13.0, 1.0 / 22.0, 1.0 / 48.0, 1.0 / 70.0]
const DETAIL_DRIFT := [1.4, 1.0, 0.9, 0.6]
const DETAIL_ANGLE := [0.0, 0.35, -0.6, 0.95]
const FOAM_STREAK_SCALE := Vector2(1.0 / 23.0, 1.0 / 5.0)
const FOAM_BREAKUP_SCALE := 1.0 / 61.0

@export var quality: SeaQuality.Tier = SeaQuality.Tier.M:
	set = set_quality
@export var source_path: NodePath
@export var sky_path: NodePath
@export var camera_path: NodePath
@export var use_internal_clock := true
@export var render_time_ms := 0.0

var model := SeaModel.new()
var wind: Dictionary = {}
var source: Node
var sky: Node
var camera: Camera3D
## Camera-relative origin of the last frame (world ENU metres).
var origin := Vector2.ZERO
var material: ShaderMaterial

var _mesh_instance: MeshInstance3D
var _overlay_lines: Array = []
var _overlay_circles: Array = []
var _wake_texture: Texture2D
var _wake_strength := 0.0
var _land_factor := 1.0
## the sector pair of the land texture uploaded last (wind.md §8), -1 = none
var _land_k0 := -1
var _land_image: Image
var _land_texture: ImageTexture


func _ready() -> void:
	if source == null and not source_path.is_empty():
		source = get_node_or_null(source_path)
	if sky == null and not sky_path.is_empty():
		sky = get_node_or_null(sky_path)
	if camera == null and not camera_path.is_empty():
		camera = get_node_or_null(camera_path) as Camera3D
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Surface"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	_build()
	if source:
		set_sea(source.sea_components(), source.sea_exposure())


func set_quality(tier: SeaQuality.Tier) -> void:
	quality = tier
	if is_inside_tree():
		_build()
		quality_changed.emit(tier)


func get_tier() -> Dictionary:
	return SeaQuality.get_tier(quality)


## The sea of the race: the core's components and exposure grid (sea.md §7.1). Fixed for a race.
## The venue wind field of the source is taken too when the source offers one (venue_wind_field()).
func set_sea(components: Array, exposure: Dictionary) -> void:
	model.set_components(components)
	model.set_exposure(exposure)
	if source and source.has_method("venue_wind_field"):
		model.set_wind_field(source.venue_wind_field())
	_land_k0 = -1
	if material:
		_apply_static()


## The venue's land-effect wind field (data_format.md §6.2: {grid, sectors}), {} for none. Its speed factor for
## the current wind direction multiplies the drawn wind (water_render.md §4.3). Fixed for a race.
func set_wind_field(field: Dictionary) -> void:
	model.set_wind_field(field)
	_land_k0 = -1
	if material:
		_apply_static()


## The wind state at the render time (wind.md §9): base_speed, base_from, global_from, puff_tile, cap_up,
## cap_down, patches.
func set_wind(state: Dictionary) -> void:
	wind = state


## An extra uniform speed factor on the drawn wind, on top of the venue field (set_wind_field); 1 by default.
func set_land_factor(f: float) -> void:
	_land_factor = f


## Wake normal buffer (water_render.md §5): a camera-centred texture over `extent` metres.
func set_wake_buffer(tex: Texture2D, extent: float, strength: float) -> void:
	_wake_texture = tex
	_wake_strength = strength if tex else 0.0
	if material:
		material.set_shader_parameter("wake_tex", tex)
		material.set_shader_parameter("wake_extent", extent)
		material.set_shader_parameter("wake_strength", _wake_strength)


## §6 overlays: lines [{a: Vector2, b: Vector2 (world ENU), color: Color, width: float (m)}], at most 8.
func set_overlay_lines(lines: Array) -> void:
	_overlay_lines = lines.slice(0, 8)


## §6 overlays: circles [{c: Vector2 (world ENU), r: float, color: Color, width: float}], at most 4.
func set_overlay_circles(circles: Array) -> void:
	_overlay_circles = circles.slice(0, 4)


## CPU sea height at a world point (sea.md §7.2, every component, double precision). For wakes and tests until
## the core binding provides sea_height.
func height_at(x: float, y: float, t_ms: float = NAN) -> float:
	return model.height(x, y, render_time_ms if is_nan(t_ms) else t_ms)


## Grid spacing ratio q of the current tier (water_render.md §3.1).
func grid_ratio() -> float:
	return SeaRadialGrid.ratio(get_tier()["rings"])


func _build() -> void:
	if _mesh_instance == null:
		return
	var t := get_tier()
	_mesh_instance.mesh = SeaRadialGrid.build(t["rings"], t["segments"])
	material = ShaderMaterial.new()
	material.shader = load(t["shader"])
	_mesh_instance.material_override = material
	material.set_shader_parameter("detail_tex", SeaTextures.detail())
	material.set_shader_parameter("foam_tex", SeaTextures.foam())
	set_wake_buffer(_wake_texture, 400.0, _wake_strength)
	_apply_static()
	if sky and sky.has_method("apply_quality"):
		sky.apply_quality(quality)


func _apply_static() -> void:
	material.set_shader_parameter("n_comp", model.components.size())
	material.set_shader_parameter("sum_a", model.sum_a)
	var g := model.exposure
	material.set_shader_parameter("expo_tex", SeaTextures.exposure_texture(g))
	if g.is_empty():
		material.set_shader_parameter("expo_size", Vector2i(0, 0))
	else:
		material.set_shader_parameter("expo_grid", Vector4(g["x0"], g["y0"], g["dx"], g["dy"]))
		material.set_shader_parameter("expo_size", Vector2i(g["nx"], g["ny"]))
		material.set_shader_parameter("expo_default", g["default"])
	var wf := model.wind_field
	if wf.is_empty():
		material.set_shader_parameter("land_size", Vector2i(0, 0))
		material.set_shader_parameter("land_tex", SeaTextures.exposure_texture({}))
	else:
		material.set_shader_parameter("land_grid", Vector4(wf["x0"], wf["y0"], wf["dx"], wf["dy"]))
		material.set_shader_parameter("land_size", Vector2i(wf["nx"], wf["ny"]))
	_land_k0 = -1
	var h := 2.0 * model.hs_eff + 1.0
	var r := SeaRadialGrid.R_MAX
	_mesh_instance.custom_aabb = AABB(Vector3(-r, -h, -r), Vector3(2.0 * r, 2.0 * h, 2.0 * r))


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if use_internal_clock:
		render_time_ms += delta * 1000.0
	var cam := camera if camera else get_viewport().get_camera_3d()
	update_frame(cam.global_position if cam else Vector3.ZERO, cam)
	PerfStats.add(&"sea", Time.get_ticks_usec() - t0)


## Per-frame uniforms (water_render.md §2) for a camera at scene position `cam_pos`.
func update_frame(cam_pos: Vector3, cam: Camera3D = null) -> void:
	if material == null:
		return
	if source:
		wind = source.wind_state(render_time_ms)
	# The grid follows the camera, not rotated; the origin is the camera on the water plane (scene Z = -y).
	var ox := float(cam_pos.x)
	var oy := -float(cam_pos.z)
	origin = Vector2(ox, oy)
	global_transform = Transform3D(Basis.IDENTITY, Vector3(ox, 0.0, -oy))
	var t := render_time_ms
	var ph := model.phases(t, ox, oy)
	var comp := PackedVector4Array()
	comp.resize(SeaModel.MAX_COMPONENTS)
	for i in model.components.size():
		var c: Array = model.components[i]
		comp[i] = Vector4(c[0], c[1], c[2], ph[i])
	material.set_shader_parameter("comp", comp)
	material.set_shader_parameter("sea_origin", origin)

	var tile: float = wind.get("puff_tile", 1000.0)
	var puffs := SeaModel.pack_puffs(wind.get("patches", []), ox, oy, tile)
	var n_puff := puffs.size()
	puffs.resize(SeaModel.MAX_PUFFS)
	material.set_shader_parameter("puff", puffs)
	material.set_shader_parameter("n_puff", n_puff)
	material.set_shader_parameter("puff_tile", tile)
	material.set_shader_parameter("puff_cap_lo", 1.0 - wind.get("cap_down", 0.4))
	material.set_shader_parameter("puff_cap_hi", 1.0 + wind.get("cap_up", 0.25))
	material.set_shader_parameter("base_speed", wind.get("base_speed", 7.2))
	material.set_shader_parameter("land_factor", _land_factor)
	_update_land(wind.get("global_from", wind.get("base_from", 0.0)))

	# Detail frame: the median wind (base_from), so the pattern does not swirl when the wind shifts.
	var to: float = wind.get("base_from", 0.0) + PI
	var dir := Vector2(sin(to), cos(to))
	var perp := Vector2(-dir.y, dir.x)
	material.set_shader_parameter("detail_dir", dir)
	var t_s := t * 0.001
	var qa := ox * dir.x + oy * dir.y
	var qc := ox * perp.x + oy * perp.y
	var layers := PackedVector4Array()
	for k in 4:
		var sc: float = DETAIL_SCALE[k]
		var c: float = cos(DETAIL_ANGLE[k]) * sc
		var s: float = sin(DETAIL_ANGLE[k]) * sc
		var a: float = qa - DETAIL_DRIFT[k] * t_s
		var u: float = c * a - s * qc
		var v: float = s * a + c * qc
		layers.append(Vector4(c, s, u - floor(u), v - floor(v)))
	material.set_shader_parameter("detail_layer", layers)
	var fu := (qa - 0.8 * t_s) * FOAM_STREAK_SCALE.x
	var fv := qc * FOAM_STREAK_SCALE.y
	var bu := (qa - 0.5 * t_s) * FOAM_BREAKUP_SCALE
	var bv := qc * FOAM_BREAKUP_SCALE
	material.set_shader_parameter("foam_layer", Vector4(fu - floor(fu), fv - floor(fv), bu - floor(bu), bv - floor(bv)))

	if sky:
		material.set_shader_parameter("sky_horizon", sky.horizon_linear())
		material.set_shader_parameter("sky_zenith", sky.zenith_linear())
		material.set_shader_parameter("sun_dir", sky.sun_direction())
		material.set_shader_parameter("sun_color", sky.sun_radiance())

	_update_overlays(ox, oy, cam)


## wind.md §8 for the current direction: the two sector grids around it in one RG32F texture, uploaded again
## only when the pair changes (a whole sector, 45 deg), and the blend weight every frame.
func _update_land(global_from: float) -> void:
	var wf := model.wind_field
	if wf.is_empty():
		return
	var s := SeaModel.land_sectors(global_from)
	material.set_shader_parameter("land_tw", s[2])
	if s[0] == _land_k0:
		return
	_land_k0 = s[0]
	var nx: int = wf["nx"]
	var ny: int = wf["ny"]
	var a: PackedFloat32Array = wf["f"][s[0]]
	var b: PackedFloat32Array = wf["f"][s[1]]
	var rg := PackedFloat32Array()
	rg.resize(2 * nx * ny)
	for n in nx * ny:
		rg[2 * n] = a[n]
		rg[2 * n + 1] = b[n]
	var img := Image.create_from_data(nx, ny, false, Image.FORMAT_RGF, rg.to_byte_array())
	if _land_texture and _land_image and _land_image.get_size() == img.get_size():
		_land_texture.update(img)
	else:
		_land_texture = ImageTexture.create_from_image(img)
	_land_image = img
	material.set_shader_parameter("land_tex", _land_texture)


## The land texture's sector pair [k0, k1] and its RG32F data (tests and the offline preview), [] without a field.
func land_upload() -> Array:
	if _land_image == null or model.wind_field.is_empty():
		return []
	return [_land_k0, (_land_k0 + 1) & 7, _land_image.get_data()]


func _update_overlays(ox: float, oy: float, cam: Camera3D) -> void:
	var lines := PackedVector4Array()
	var lcol := PackedVector4Array()
	for l in _overlay_lines:
		lines.append(Vector4(l["a"].x - ox, l["a"].y - oy, l["b"].x - ox, l["b"].y - oy))
		var c: Color = l.get("color", Color.WHITE)
		lcol.append(Vector4(c.r, c.g, c.b, l.get("width", 0.3)))
	var n_l := lines.size()
	lines.resize(8)
	lcol.resize(8)
	var circles := PackedVector4Array()
	var ccol := PackedVector4Array()
	for o in _overlay_circles:
		circles.append(Vector4(o["c"].x - ox, o["c"].y - oy, o["r"], 0.0))
		var c: Color = o.get("color", Color.WHITE)
		ccol.append(Vector4(c.r, c.g, c.b, o.get("width", 0.3)))
	var n_c := circles.size()
	circles.resize(4)
	ccol.resize(4)
	material.set_shader_parameter("n_ov_line", n_l)
	material.set_shader_parameter("ov_line", lines)
	material.set_shader_parameter("ov_line_col", lcol)
	material.set_shader_parameter("n_ov_circle", n_c)
	material.set_shader_parameter("ov_circle", circles)
	material.set_shader_parameter("ov_circle_col", ccol)
	if cam and n_l + n_c > 0:
		var h := 720.0
		var vp := get_viewport()
		if vp:
			h = float(vp.get_visible_rect().size.y)
		material.set_shader_parameter("ov_px_angle", deg_to_rad(cam.fov) / maxf(h, 1.0))
