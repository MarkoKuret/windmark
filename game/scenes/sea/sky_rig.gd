@tool
class_name SkyRig
extends Node3D
## Sky and lighting (WM-016.03, WM-080, WM-124): the sky shader, the sun light, exposure, tone mapping, glow, fog and
## reflections, from one set of parameters, so the water's crest light (water_render.md §4.2) and the reflections
## use the same sky and sun. Colours are linear. Children: WorldEnvironment (environment with the sky material) and Sun
## (DirectionalLight3D). Two inputs set every value (water_render.md §4.5, Daylight): the time of day `hour` (local
## clock) and the `conditions` (clear, fair, hazy, overcast), on the venue's `site` (latitude, longitude, UTC
## offset, date; set_site). The venue's look file or the race picks them; single values can still be set after.
## Each light also sets its colour grade (LookFx). The light is fixed unless `light_advance` lets the clock run.

## The old light preset names (`--sky=`), Daylight.ALIASES.
const PRESET_NAMES := ["clear", "fair", "hazy", "late"]
## With light_advance: at most one step of the light per this much real time (s), and only once the hour has moved
## by STEP_MIN_H; the grade's LUT is rebuilt once the hour has moved by GRADE_STEP_H (water_render.md §4.5 Updates).
const STEP_REAL_S := 5.0
const STEP_MIN_H := 1.0 / 60.0
const GRADE_STEP_H := 0.25

## Glow on the brightest highlights only (the sun disc and its glints on the water), per quality tier
## (water_render.md §4.5): off on L, the coarse levels on M, one finer level more on H. Godot's levels 1 to 7.
const GLOW_LEVELS := {0: [], 1: [3, 4, 5], 2: [2, 3, 4, 5]}
## The sky shaders per tier (water_render.md §7): tier L draws the cumulus in the half-resolution pass; the
## same uniforms, so the rig only swaps the shader (apply_quality).
const SKY_SHADER := "res://shaders/sky.gdshader"
const SKY_SHADER_L := "res://shaders/sky_l.gdshader"
## Linear radiance before the exposure above which a pixel blooms: over the sunlit white hulls and sails (about 2.5)
## and the clouds, under the sun disc and the glints.
const GLOW_THRESHOLD := 4.0
const GLOW_INTENSITY := 0.5

## Time of day: the local clock hour (clamped to the hours with the sun at least Daylight.MIN_SUN high).
@export_range(0.0, 24.0, 0.25) var hour := VenueLook.DEFAULT_TIME:
	set(v):
		hour = v
		_resolve()
## Conditions: clear, fair, hazy or overcast (Daylight.CONDITIONS).
@export_enum("clear", "fair", "hazy", "overcast") var conditions := "fair":
	set(v):
		conditions = v if Daylight.is_condition(v) else "fair"
		_resolve()
## Game hours per real hour the clock runs during a race (0: fixed, 1: real time; `--light-advance=`).
var light_advance := 0.0:
	set(v):
		light_advance = maxf(v, 0.0)
		set_process(light_advance > 0.0 and not Engine.is_editor_hint())
## The sun formula's site (Daylight.sun_position): lat, lon, utc_offset_h, day.
var site: Dictionary = Daylight.DEFAULT_SITE.duplicate()
## The light last resolved (Daylight.light), the drawn boat shadows' factor and the grade it set.
var light := {}
var shadow_strength := 1.0
var grade := {}
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
## The overcast deck's diffuse lighting in the sky shader (0 sunlit cumulus, 1 a grey deck; water_render.md §4.5).
@export_range(0.0, 1.0) var cloud_diffuse := 0.0:
	set(v):
		cloud_diffuse = v
		_apply()
## A factor on the sun shadows' blur (water_render.md §4.6: a diffuse sun gives soft shadows).
var shadow_blur_k := 1.0:
	set(v):
		shadow_blur_k = maxf(v, 0.0)
		_apply()
## The sea body colour's saturation and value and the puffs' darkening under these conditions (water_render.md
## §4.2, §4.3): the Sea reads them through sea_colors() and puff_k.
var sea_saturation := 1.0
var sea_value := 1.0
var puff_k := 1.0
## Development (`--haze=`, the look panel): a factor on the light's haze_max, kept when the hour or conditions change.
var haze_scale := 1.0:
	set(v):
		haze_scale = maxf(v, 0.0)
		_apply()


var _batch := false
var _grade_hour := -100.0
var _grade_key := ""
var _advance_real := 0.0
var _advance_hours := 0.0


func _ready() -> void:
	set_process(light_advance > 0.0 and not Engine.is_editor_hint())
	_resolve()


## The venue's site (VenueLook.site()): the light is resolved again at the same hour and conditions.
func set_site(s: Dictionary) -> void:
	site = Daylight.DEFAULT_SITE.merged(s, true)
	_resolve()


## Time of day and conditions together, one resolve.
func set_light(h: float, c: String) -> void:
	_batch = true
	hour = h
	conditions = c
	_batch = false
	_resolve()


## An old light preset name (clear, fair, hazy, late; Daylight.ALIASES): its conditions at the hour of its
## afternoon sun on this site. Unknown names change nothing; returns whether it was known.
func set_preset_name(name: String) -> bool:
	if not Daylight.ALIASES.has(name):
		return false
	var a: Dictionary = Daylight.ALIASES[name]
	set_light(Daylight.hour_for_sun(site, a["sun"]), a["conditions"])
	return true


## The old preset name the light matches now (its conditions at its hour, within a minute), else "".
func preset_name() -> String:
	for n in PRESET_NAMES:
		var a: Dictionary = Daylight.ALIASES[n]
		if conditions == a["conditions"] and absf(hour - Daylight.hour_for_sun(site, a["sun"])) < 1.0 / 60.0:
			return n
	return ""


## The hours the light can take on this site: [first, last] with the sun at least Daylight.MIN_SUN high.
func hour_range() -> Vector2:
	return Daylight.hour_range(site)


## Every value from the hour and the conditions (Daylight.light), applied in one pass; the grade too unless
## `grade_too` is false and the hour has moved less than GRADE_STEP_H since the last grade (the clock steps).
func _resolve(grade_too := true) -> void:
	if _batch:
		return
	light = Daylight.light(site, hour, conditions)
	_batch = true
	hour = light["hour"]
	for k in ["sun_elevation_deg", "sun_azimuth_deg", "sun_color", "sun_energy", "horizon", "zenith", "cloud_cover",
			"exposure", "haze_begin", "haze_end", "haze_max", "haze_curve"]:
		set(k, light[k])
	shadow_strength = light["shadow"]
	for k in ["shadow_blur_k", "sea_saturation", "sea_value", "puff_k"]:
		set(k, light[k])
	cloud_diffuse = light["diffuse"]
	_batch = false
	_apply()
	if grade_too or absf(hour - _grade_hour) >= GRADE_STEP_H:
		grade = light["grade"]
		_grade_hour = hour
		apply_grade()


## The light's grade on the environment at LookFx.grade_strength (again after the strength or --look change).
func apply_grade() -> void:
	if grade.is_empty():
		grade = Daylight.light(site, hour, conditions)["grade"]
	LookFx.apply_grade(environment(), grade)


## light_advance: the clock runs; the light steps at most every STEP_REAL_S of real time and only once it has
## moved by STEP_MIN_H (Godot redraws the sky's radiance map only when a value changes).
func _process(dt: float) -> void:
	if light_advance <= 0.0:
		return
	_advance_real += dt
	_advance_hours += dt * light_advance / 3600.0
	if _advance_real < STEP_REAL_S or _advance_hours < STEP_MIN_H:
		return
	var h := hour + _advance_hours
	_advance_real = 0.0
	_advance_hours = 0.0
	advance_to(h)


## One step of the running clock to hour h (the grade only every GRADE_STEP_H).
func advance_to(h: float) -> void:
	_batch = true
	hour = h
	_batch = false
	_resolve(false)


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


## The sea body colours (water_render.md §4.2) under these conditions: the shader's defaults with their saturation
## and value scaled about their luminance; {col_deep, col_shallow, col_sss} as linear Vector3.
func sea_colors() -> Dictionary:
	return Daylight.sea_colors(sea_saturation, sea_value)


func sun() -> DirectionalLight3D:
	return get_node_or_null("Sun") as DirectionalLight3D


## The sun's shadows (water_render.md §4.6), the glow and the contact shading (§4.5) for a quality tier; the Sea
## calls it when its tier is set.
func apply_quality(tier: int) -> void:
	SeaQuality.apply_shadows(sun(), tier as SeaQuality.Tier)
	apply_sky_shader(environment(), tier)
	_apply()  # the conditions' shadow blur on the tier's, and the sky's uniforms on the tier's shader
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


## The tier's sky shader on the environment's sky material (SKY_SHADER_L on L, SKY_SHADER elsewhere); a material
## with any other shader (the sail test's --no-sky gradient) is left alone. Returns whether the shader changed.
static func apply_sky_shader(env: Environment, tier: int) -> bool:
	if env == null or env.sky == null or not (env.sky.sky_material is ShaderMaterial):
		return false
	var m := env.sky.sky_material as ShaderMaterial
	var want := SKY_SHADER_L if tier == SeaQuality.Tier.L else SKY_SHADER
	var have := m.shader.resource_path if m.shader != null else ""
	if have == want or (have != SKY_SHADER and have != SKY_SHADER_L):
		return false
	m.shader = load(want)
	return true


func environment() -> Environment:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	return we.environment if we else null


func _apply() -> void:
	if _batch or not is_inside_tree():
		return
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var d := sun_direction()
	if sun:
		var up := Vector3.UP if absf(d.y) < 0.999 else Vector3.FORWARD
		sun.global_basis = Basis.looking_at(-d, up)
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_blur = SeaQuality.SHADOW_BLUR * shadow_blur_k
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
		m.set_shader_parameter("cloud_diffuse", cloud_diffuse)
	# Environment colours are sRGB-encoded Color values; the fog goes to the horizon colour.
	env.fog_light_color = horizon.linear_to_srgb()
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = haze_max * haze_scale
	env.fog_depth_begin = haze_begin
	env.fog_depth_end = haze_end
	env.fog_depth_curve = haze_curve
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = exposure
