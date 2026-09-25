@tool
class_name SkyRig
extends Node3D
## Sky and lighting preset (WM-016.03): the sky shader, the sun light, fog and reflections, from one set of
## parameters, so the water's slope contrast and crest light (water_render.md §4.2) use the same sky.
## Colours are linear. Children: WorldEnvironment (environment with the sky material) and Sun
## (DirectionalLight3D). One daytime preset is the default; a venue look file can set these later.

@export_range(0.0, 90.0) var sun_elevation_deg := 38.0:
	set(v):
		sun_elevation_deg = v
		_apply()
## Compass bearing of the sun, clockwise from north.
@export_range(0.0, 360.0) var sun_azimuth_deg := 200.0:
	set(v):
		sun_azimuth_deg = v
		_apply()
@export var sun_color := Color(1.0, 0.94, 0.86):
	set(v):
		sun_color = v
		_apply()
## Sun and sky in their real proportion on a clear day: the sun gives about four fifths of the light on a level
## surface, the sky the rest (a white deck in sun about three times as bright as the horizon sky); the camera
## exposure brings the whole back to screen range.
@export var sun_energy := 3.0:
	set(v):
		sun_energy = v
		_apply()
@export var horizon := Color(0.62, 0.74, 0.86):
	set(v):
		horizon = v
		_apply()
@export var zenith := Color(0.10, 0.26, 0.58):
	set(v):
		zenith = v
		_apply()
@export_range(0.0, 1.0) var cloud_cover := 0.3:
	set(v):
		cloud_cover = v
		_apply()
@export var cloud_offset := Vector2(3.7, 1.3):
	set(v):
		cloud_offset = v
		_apply()
## Camera exposure (the environment's tonemap exposure).
@export var exposure := 0.62:
	set(v):
		exposure = v
		_apply()
## Exponential fog density (1/m) toward the horizon colour.
@export var fog_density := 0.00005:
	set(v):
		fog_density = v
		_apply()


func _ready() -> void:
	_apply()


## Unit vector toward the sun, scene axes (X east, Y up, Z south).
func sun_direction() -> Vector3:
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)).normalized()


func horizon_linear() -> Vector3:
	return Vector3(horizon.r, horizon.g, horizon.b)


func zenith_linear() -> Vector3:
	return Vector3(zenith.r, zenith.g, zenith.b)


## Sun colour times energy, linear.
func sun_radiance() -> Vector3:
	return Vector3(sun_color.r, sun_color.g, sun_color.b) * sun_energy


func sun() -> DirectionalLight3D:
	return get_node_or_null("Sun") as DirectionalLight3D


## The sun's shadows for a quality tier (water_render.md §4.6); the Sea calls it when its tier is set.
func apply_quality(tier: int) -> void:
	SeaQuality.apply_shadows(sun(), tier as SeaQuality.Tier)


func environment() -> Environment:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	return we.environment if we else null


func _apply() -> void:
	if not is_inside_tree():
		return
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var d := sun_direction()
	if sun:
		var up := Vector3.UP if absf(d.y) < 0.999 else Vector3.FORWARD
		sun.global_basis = Basis.looking_at(-d, up)
		sun.light_color = sun_color
		sun.light_energy = sun_energy
	var env := environment()
	if env == null:
		return
	if env.sky and env.sky.sky_material is ShaderMaterial:
		var m := env.sky.sky_material as ShaderMaterial
		m.set_shader_parameter("sky_horizon", horizon_linear())
		m.set_shader_parameter("sky_zenith", zenith_linear())
		m.set_shader_parameter("sun_dir", d)
		m.set_shader_parameter("sun_color", sun_radiance())
		m.set_shader_parameter("cloud_cover", cloud_cover)
		m.set_shader_parameter("cloud_offset", cloud_offset)
	# Environment colours are sRGB-encoded Color values; the fog goes to the horizon colour.
	env.fog_light_color = horizon.linear_to_srgb()
	env.fog_density = fog_density
	env.tonemap_exposure = exposure
