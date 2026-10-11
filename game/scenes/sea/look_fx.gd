@tool
class_name LookFx
extends CanvasLayer
## The finishing look over the 3-D image (water_render.md §4.5 "Colour grade", "Vignette", "Contact shading";
## cameras.md §9 "Depth of field"): a film grade through the environment's colour correction (a 3-D LUT built here
## from the light's grade, Daylight), the vignette (this node: one full-screen multiply under the HUD, no screen
## read), the contact shading (SSAO, tier H) and the depth of field of the long lens and mark clip cameras. SkyRig
## applies the grade with its light and the SSAO with the tier; CameraRig owns a LookFx for the vignette and the
## depth of field of its camera. Presentation only.

## LUT edge length: 33³ RGBA8 (144 kB), sampled once per pixel in Godot's tonemap pass.
const LUT_SIZE := 33
## LUTs kept for reuse (a light and strength each); the oldest goes first.
const LUT_CACHE := 12
## water_render.md §4.5 grade strength range (the look panel's row, `--grade=`).
const STRENGTH_MAX := 1.5
## Rec. 709 luma weights, used on the sRGB values as a grading weight.
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

## water_render.md §4.5 vignette: corner darkening (display-referred multiply) per camera kind; it starts at
## VIGNETTE_INNER of the half diagonal and reaches its strength in the corners.
const VIGNETTE_REGULAR := 0.30
const VIGNETTE_CLIP := 0.42
const VIGNETTE_INNER := 0.40
## Under every other 2-D layer: the HUD (layer 1), the pause menu (60) and the frame-time overlay (128) draw over it.
const VIGNETTE_LAYER := -1

## water_render.md §4.5 contact shading (SSAO) per tier: on H only. Ambient light only (light affect 0, AO channel
## affect 0); Godot takes the minimum of it and the boats' baked AO, so nothing is darkened twice.
const SSAO := {
	SeaQuality.Tier.L: {},
	SeaQuality.Tier.M: {},
	SeaQuality.Tier.H: {"radius": 0.8, "intensity": 1.6, "power": 1.5, "detail": 0.5, "horizon": 0.06,
		"sharpness": 0.98, "quality": RenderingServer.ENV_SSAO_QUALITY_MEDIUM, "half_size": true,
		"blur_passes": 2, "fade_from": 40.0, "fade_to": 150.0},
}

## cameras.md §9 depth of field: per tier the bokeh quality (none: off).
const DOF_QUALITY := {
	SeaQuality.Tier.L: -1,
	SeaQuality.Tier.M: RenderingServer.DOF_BLUR_QUALITY_LOW,
	SeaQuality.Tier.H: RenderingServer.DOF_BLUR_QUALITY_MEDIUM,
}

const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode blend_mul, unshaded;
uniform float strength = 0.30;
uniform float inner = 0.40;
void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 d = (SCREEN_UV - 0.5) * size;
	float r = length(d) / (0.5 * length(size));
	float v = smoothstep(inner, 1.0, r);
	COLOR = vec4(vec3(1.0 - strength * v), 1.0);
}
"""

## The tier the look was last applied for (SkyRig.apply_quality); the cameras read it for the depth of field.
static var tier := SeaQuality.Tier.M
## Development runs (`--look=off`): no grade, vignette, SSAO or depth of field, to compare.
static var enabled := true
## Development runs (`--ssao=on|off`): over the tier's SSAO (-1: the tier's).
static var ssao_override := -1
## Development runs (`--dof=off`, the look panel): no depth of field on the clip cameras.
static var dof_enabled := true
## water_render.md §4.5 grade strength (0 to 1.5, 0 off; `--grade=`, the look panel) and vignette strength (a
## factor on the camera's vignette, 0 off; `--vignette=`).
static var grade_strength := 1.0
static var vignette_scale := 1.0
static var _luts := {}
static var _lut_order: Array[String] = []

var strength := VIGNETTE_REGULAR:
	set = set_strength
var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	name = "LookFx"
	layer = VIGNETTE_LAYER
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("inner", VIGNETTE_INNER)
	_rect = ColorRect.new()
	_rect.name = "Vignette"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	add_child(_rect)
	set_strength(strength)


func set_strength(s: float) -> void:
	strength = s if enabled else 0.0
	if _mat:
		_mat.set_shader_parameter("strength", strength)
	if _rect:
		_rect.visible = strength > 0.0


## The vignette strength for a camera mode (CameraRig.Mode): the clip cameras' broadcast frame, the regular one on
## the rest, times the vignette strength.
static func vignette_for(clip: bool) -> float:
	return (VIGNETTE_CLIP if clip else VIGNETTE_REGULAR) * vignette_scale


## The vignette factor at screen uv (0..1) for a screen `size` in pixels: the shader's formula.
static func vignette_at(uv: Vector2, size: Vector2, s: float) -> float:
	var d := (uv - Vector2(0.5, 0.5)) * size
	var r := d.length() / (0.5 * size.length())
	return 1.0 - s * smoothstep(VIGNETTE_INNER, 1.0, r)


# ---- colour grade ------------------------------------------------------------------------------------------------

## water_render.md §4.5 grade of one display colour (sRGB-encoded, 0..1) with a grade {contrast, warm, cool,
## saturation, white_keep} (Daylight.light()["grade"], scaled by its strength).
static func grade(c: Vector3, g: Dictionary) -> Vector3:
	var k: float = g["contrast"]
	var y := Vector3(
		lerpf(c.x, c.x * c.x * (3.0 - 2.0 * c.x), k),
		lerpf(c.y, c.y * c.y * (3.0 - 2.0 * c.y), k),
		lerpf(c.z, c.z * c.z * (3.0 - 2.0 * c.z), k))
	var l := c.dot(LUMA)
	var chroma := maxf(c.x, maxf(c.y, c.z)) - minf(c.x, minf(c.y, c.z))
	var w_lo := (1.0 - smoothstep(0.05, 0.45, l)) * smoothstep(0.0, 0.08, l)
	var w_hi := smoothstep(0.25, 0.55, l) * (1.0 - smoothstep(0.80, 0.97, l))
	w_hi *= 1.0 - smoothstep(0.02, 0.20, c.z - c.x)
	w_hi *= 1.0 - float(g.get("white_keep", 0.0)) * (1.0 - smoothstep(0.03, 0.12, chroma)) * smoothstep(0.40, 0.60, l)
	y += (g["cool"] as Vector3) * w_lo + (g["warm"] as Vector3) * w_hi
	var ly := y.dot(LUMA)
	y = Vector3(ly, ly, ly).lerp(y, g["saturation"])
	return y.clamp(Vector3.ZERO, Vector3.ONE)


## A grade at a strength k (0 to 1.5): contrast, warm and cool times k, saturation 1 + (s - 1) k.
static func scaled(g: Dictionary, k: float) -> Dictionary:
	return {"contrast": float(g["contrast"]) * k, "warm": (g["warm"] as Vector3) * k,
		"cool": (g["cool"] as Vector3) * k, "saturation": 1.0 + (float(g["saturation"]) - 1.0) * k,
		"white_keep": g.get("white_keep", 0.0)}


## The LUT's input at texel i: Godot samples the LUT with the colour itself as the coordinate, so texel i is read
## exactly at (i + 0.5) / N; the end texels hold the ends, so black stays black and white stays white.
static func lut_coord(i: int, n := LUT_SIZE) -> float:
	if i == 0:
		return 0.0
	if i == n - 1:
		return 1.0
	return (i + 0.5) / n


## The LUT's slices (blue along the depth), RGBA8.
static func lut_images(g: Dictionary, n := LUT_SIZE) -> Array[Image]:
	var out: Array[Image] = []
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for b in n:
		var i := 0
		for gi in n:
			for r in n:
				var o := grade(Vector3(lut_coord(r, n), lut_coord(gi, n), lut_coord(b, n)), g)
				bytes[i] = int(o.x * 255.0 + 0.5)
				bytes[i + 1] = int(o.y * 255.0 + 0.5)
				bytes[i + 2] = int(o.z * 255.0 + 0.5)
				bytes[i + 3] = 255
				i += 4
		out.append(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes))
	return out


## The LUT as one image for the offline previews: the N slices side by side (blue across the slices).
static func lut_strip(g: Dictionary, n := LUT_SIZE) -> Image:
	var slices := lut_images(g, n)
	var strip := Image.create_empty(n * n, n, false, Image.FORMAT_RGBA8)
	for b in n:
		strip.blit_rect(slices[b], Rect2i(0, 0, n, n), Vector2i(b * n, 0))
	return strip


## The vignette constants for the offline previews (tests/cine_preview.py, daylight_preview.py).
static func look_constants() -> Dictionary:
	return {"lut_size": LUT_SIZE, "vignette_regular": VIGNETTE_REGULAR * vignette_scale,
		"vignette_clip": VIGNETTE_CLIP * vignette_scale, "vignette_inner": VIGNETTE_INNER}


## The LUT of a grade (already scaled), cached by its values.
static func lut(g: Dictionary) -> ImageTexture3D:
	var key := _key(g)
	if not _luts.has(key):
		var t := ImageTexture3D.new()
		t.create(Image.FORMAT_RGBA8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, lut_images(g))
		_luts[key] = t
		_lut_order.append(key)
		if _lut_order.size() > LUT_CACHE:
			_luts.erase(_lut_order.pop_front())
	return _luts[key]


static func _key(g: Dictionary) -> String:
	var w: Vector3 = g["warm"]
	var c: Vector3 = g["cool"]
	return "%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f" % [g["contrast"], w.x, w.y, w.z, c.x, c.y, c.z,
		g["saturation"], g.get("white_keep", 0.0)]


## The grade of a light (SkyRig) on the environment at grade_strength; none with --look=off or strength 0.
## Brightness, contrast and saturation stay at 1: everything is in the LUT.
static func apply_grade(env: Environment, g: Dictionary) -> void:
	if env == null:
		return
	env.adjustment_enabled = enabled and not g.is_empty() and grade_strength > 0.0
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.adjustment_color_correction = lut(scaled(g, grade_strength)) if env.adjustment_enabled else null


# ---- per tier ----------------------------------------------------------------------------------------------------

## SSAO and the depth of field quality for a tier (SkyRig.apply_quality, with the shadows and the glow).
static func apply_quality(env: Environment, t: int) -> void:
	tier = t as SeaQuality.Tier
	var s: Dictionary = ssao_settings(t)
	if env != null:
		env.ssao_enabled = not s.is_empty()
		if not s.is_empty():
			env.ssao_radius = s["radius"]
			env.ssao_intensity = s["intensity"]
			env.ssao_power = s["power"]
			env.ssao_detail = s["detail"]
			env.ssao_horizon = s["horizon"]
			env.ssao_sharpness = s["sharpness"]
			env.ssao_light_affect = 0.0
			env.ssao_ao_channel_affect = 0.0
			RenderingServer.environment_set_ssao_quality(s["quality"], s["half_size"], 0.5, s["blur_passes"],
				s["fade_from"], s["fade_to"])
	var q: int = DOF_QUALITY.get(t, -1)
	if q >= 0:
		RenderingServer.camera_attributes_set_dof_blur_quality(q as RenderingServer.DOFBlurQuality, false)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)


## The SSAO of a tier after the development override ({} when off).
static func ssao_settings(t: int) -> Dictionary:
	if not enabled or ssao_override == 0:
		return {}
	if ssao_override == 1:
		return SSAO[SeaQuality.Tier.H]
	return SSAO.get(t, {})


static func dof_allowed() -> bool:
	return enabled and dof_enabled and DOF_QUALITY.get(tier, -1) >= 0
