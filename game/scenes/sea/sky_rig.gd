@tool
class_name SkyRig
extends Node3D
## Sky and lighting preset (WM-016.03, WM-080): the sky shader, the sun light, exposure, tone mapping, glow, fog and
## reflections, from one set of parameters, so the water's crest light (water_render.md §4.2) and the reflections
## use the same sky and sun. Colours are linear. Children: WorldEnvironment (environment with the sky material) and Sun
## (DirectionalLight3D). Four light presets (water_render.md §4.5): clear, fair-weather cumulus (the default), hazy
## and late afternoon. The venue's look file or the race picks one with `preset`; single values can still be set
## after it. Each preset also sets its colour grade (LookFx).

enum Preset { CLEAR, FAIR, HAZY, LATE }

## water_render.md §4.5: sun energy and colour, sky ramp, cloud cover, camera exposure, distance haze.
const PRESETS := {
	Preset.CLEAR: {
		"sun_energy": 3.6, "sun_color": Color(1.0, 0.92, 0.80), "horizon": Color(0.50, 0.74, 1.10),
		"zenith": Color(0.05, 0.18, 0.62), "cloud_cover": 0.0, "exposure": 0.50,
		"haze_begin": 300.0, "haze_end": 16000.0, "haze_max": 0.45, "haze_curve": 0.42,
	},
	Preset.FAIR: {
		"sun_energy": 3.6, "sun_color": Color(1.0, 0.92, 0.80), "horizon": Color(0.50, 0.74, 1.10),
		"zenith": Color(0.05, 0.18, 0.62), "cloud_cover": 0.40, "exposure": 0.50,
		"haze_begin": 200.0, "haze_end": 14000.0, "haze_max": 0.60, "haze_curve": 0.40,
	},
	Preset.HAZY: {
		"sun_energy": 2.8, "sun_color": Color(1.0, 0.95, 0.88), "horizon": Color(0.80, 0.88, 1.00),
		"zenith": Color(0.24, 0.40, 0.74), "cloud_cover": 0.25, "exposure": 0.55,
		"haze_begin": 150.0, "haze_end": 10000.0, "haze_max": 0.80, "haze_curve": 0.40,
	},
	Preset.LATE: {
		"sun_energy": 3.8, "sun_color": Color(1.0, 0.72, 0.44), "horizon": Color(0.60, 0.70, 0.94),
		"zenith": Color(0.05, 0.17, 0.58), "cloud_cover": 0.30, "exposure": 0.60,
		"haze_begin": 200.0, "haze_end": 14000.0, "haze_max": 0.65, "haze_curve": 0.40,
		"sun_elevation_deg": 17.0, "sun_azimuth_deg": 250.0,
	},
}
## The sun's place for a preset that does not set its own.
const PRESET_SUN := {"sun_elevation_deg": 38.0, "sun_azimuth_deg": 200.0}
const PRESET_NAMES := {"clear": Preset.CLEAR, "fair": Preset.FAIR, "hazy": Preset.HAZY, "late": Preset.LATE}

## Glow on the brightest highlights only (the sun disc and its glints on the water), per quality tier
## (water_render.md §4.5): off on L, the coarse levels on M, one finer level more on H. Godot's levels 1 to 7.
const GLOW_LEVELS := {0: [], 1: [3, 4, 5], 2: [2, 3, 4, 5]}
## Linear radiance before the exposure above which a pixel blooms: over the sunlit white hulls and sails (about 2.5)
## and the clouds, under the sun disc and the glints.
const GLOW_THRESHOLD := 4.0
const GLOW_INTENSITY := 0.5

## Weather preset; setting it sets the values below.
@export var preset := Preset.FAIR:
	set(v):
		preset = v
		var p: Dictionary = PRESET_SUN.merged(PRESETS[v], true)
		for k in p:
			set(k, p[k])
		_apply()
		LookFx.apply_grade(environment(), v)
@export_range(0.0, 90.0) var sun_elevation_deg := 38.0:
	set(v):
		sun_elevation_deg = v
		_apply()
## Compass bearing of the sun, clockwise from north.
@export_range(0.0, 360.0) var sun_azimuth_deg := 200.0:
	set(v):
		sun_azimuth_deg = v
		_apply()
@export var sun_color := Color(1.0, 0.92, 0.80):
	set(v):
		sun_color = v
		_apply()
## Sun and sky in their clear-day proportion: the sun gives about four fifths of the light on a level surface, the
## sky the rest (a white deck in sun about three times as bright as the horizon sky); the camera exposure brings the
## whole back to screen range.
@export var sun_energy := 3.6:
	set(v):
		sun_energy = v
		_apply()
@export var horizon := Color(0.50, 0.74, 1.10):
	set(v):
		horizon = v
		_apply()
@export var zenith := Color(0.05, 0.18, 0.62):
	set(v):
		zenith = v
		_apply()
@export_range(0.0, 1.0) var cloud_cover := 0.40:
	set(v):
		cloud_cover = v
		_apply()
@export var cloud_offset := Vector2(3.7, 1.3):
	set(v):
		cloud_offset = v
		_apply()
## Camera exposure (the environment's tonemap exposure).
@export var exposure := 0.50:
	set(v):
		exposure = v
		_apply()
## Distance haze (water_render.md §4.5): Godot's depth fog toward the horizon colour, the share of it at a distance d
## haze_max * smoothstep(haze_begin, haze_end, d)^haze_curve: none on the near water, rising from a few hundred
## metres, haze_max at the horizon. The sky is not fogged (it has its own horizon haze).
@export var haze_begin := 200.0:
	set(v):
		haze_begin = v
		_apply()
@export var haze_end := 14000.0:
	set(v):
		haze_end = v
		_apply()
@export_range(0.0, 1.0) var haze_max := 0.60:
	set(v):
		haze_max = v
		_apply()
## Below 1 the haze rises early and flattens toward the horizon.
@export var haze_curve := 0.40:
	set(v):
		haze_curve = v
		_apply()


func _ready() -> void:
	_apply()
	LookFx.apply_grade(environment(), preset)


## The preset for a name ("clear", "fair", "hazy", "late"); unknown names keep the current one. Returns whether it was known.
func set_preset_name(name: String) -> bool:
	if not PRESET_NAMES.has(name):
		return false
	preset = PRESET_NAMES[name]
	return true


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


## The sun's shadows (water_render.md §4.6), the glow and the contact shading (§4.5) for a quality tier; the Sea
## calls it when its tier is set.
func apply_quality(tier: int) -> void:
	SeaQuality.apply_shadows(sun(), tier as SeaQuality.Tier)
	apply_glow(environment(), tier)
	LookFx.apply_quality(environment(), tier)


## Glow for a tier: only what is brighter than GLOW_THRESHOLD blooms (the sun and its glints).
static func apply_glow(env: Environment, tier: int) -> void:
	if env == null:
		return
	var levels: Array = GLOW_LEVELS.get(tier, [])
	env.glow_enabled = not levels.is_empty()
	for k in range(1, 8):
		env.set_glow_level(k - 1, 1.0 if levels.has(k) else 0.0)
	env.glow_normalized = true
	env.glow_intensity = GLOW_INTENSITY
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0


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
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = haze_max
	env.fog_depth_begin = haze_begin
	env.fog_depth_end = haze_end
	env.fog_depth_curve = haze_curve
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = exposure
