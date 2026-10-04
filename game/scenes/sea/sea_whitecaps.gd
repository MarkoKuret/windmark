class_name SeaWhitecaps
extends RefCounted
## Whitecaps that ride the waves (water_render.md §4.4): the per-component foam weights and the foam texture frame
## the Sea uploads, and a CPU mirror of the shader's foam intensity (wm_caps_intensity in sea_common.gdshaderinc)
## for the tests. The constants here and in the shader are the spec's; change both together.

const KNOT := 0.51444447
## no caps under GATE_KN.x knots of local wind, full from GATE_KN.y
const GATE_KN := Vector2(8.0, 10.0)
## breaking threshold on the crest steepness sum: S_b = S_B0 + S_B1 * (U_REF_KN / U_kn)^3
const S_B0 := 0.0677
const S_B1 := 0.0208
const U_REF_KN := 15.0
## steepness above the threshold for full foam intensity
const S_W := 0.06
## crest window half widths, cycles, ahead of the crest (front) and behind it (back), each at least the width in
## metres below over the wavelength
const SIGMA_FRONT := 0.08
const SIGMA_BACK := 0.20
const WIDTH_FRONT_M := 0.6
const WIDTH_BACK_M := 1.2
## foam texture tile, metres along the dominant wave's travel and across it
const TILE := Vector2(4.5, 3.0)
## distance fade, m
const FADE := Vector2(1200.0, 2500.0)
const OPACITY := 0.92
## components with a smaller foam weight carry no foam
const MIN_WEIGHT := 0.004


## Foam components uploaded at most (the shader's WM_CAPS_N: 4 on tier L, 6 on M and H, heaviest first)
const MAX_CAPS := 6


## The foam weight of each component (Sea order): b = a·k·min(1, lam/lam_p)², its steepness weighted down for waves
## shorter than the dominant one (lam_p: the wavelength of the largest-amplitude component).
static func weights(components: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(components.size())
	var p := dominant_index(components)
	if p < 0:
		return out
	var lam_p := _lam(components[p])
	for i in components.size():
		var lam := _lam(components[i])
		var rl := minf(1.0, lam / lam_p)
		out[i] = components[i][0] * TAU / lam * rl * rl
	return out


## The components that carry foam: up to MAX_CAPS indices (Sea order) with b >= MIN_WEIGHT, heaviest first.
static func select(components: Array) -> PackedInt32Array:
	var b := weights(components)
	var order := range(components.size())
	order.sort_custom(func(i: int, j: int) -> bool: return b[i] > b[j] or (b[i] == b[j] and i < j))
	var out := PackedInt32Array()
	for i in order:
		if out.size() >= MAX_CAPS or b[i] < MIN_WEIGHT:
			break
		out.append(i)
	return out


## caps_w, once per sea: per selected component (1/sigma_front, 1/sigma_back, window mean, wavelength), padded
## to MAX_CAPS.
static func window_uniforms(components: Array, sel: PackedInt32Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_CAPS)
	for k in sel.size():
		var lam := _lam(components[sel[k]])
		var sf := maxf(SIGMA_FRONT, WIDTH_FRONT_M / lam)
		var sb := maxf(SIGMA_BACK, WIDTH_BACK_M / lam)
		out[k] = Vector4(1.0 / sf, 1.0 / sb, window_mean(sf, sb), lam)
	return out


## caps_rest, once per sea: the foam components not uploaded, each at its window mean (sum of b * mean).
static func rest_mean(components: Array, sel: PackedInt32Array) -> float:
	var b := weights(components)
	var s := 0.0
	for i in components.size():
		if sel.has(i) or b[i] <= 0.0:
			continue
		var lam := _lam(components[i])
		s += b[i] * window_mean(maxf(SIGMA_FRONT, WIDTH_FRONT_M / lam), maxf(SIGMA_BACK, WIDTH_BACK_M / lam))
	return s


## caps_k, every frame: per selected component (kx, ky, d', b) with the frame's phases d' (SeaModel.phases, Sea
## order), padded with b = 0.
static func wave_uniforms(components: Array, sel: PackedInt32Array, phases: PackedFloat64Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_CAPS)
	var b := weights(components)
	for k in sel.size():
		var c: Array = components[sel[k]]
		out[k] = Vector4(c[1], c[2], phases[sel[k]], b[sel[k]])
	return out


## The largest-amplitude component (the peak of the wind sea, or a swell when it is bigger), -1 for none.
static func dominant_index(components: Array) -> int:
	var best := -1
	for i in components.size():
		if components[i][0] > 0.0 and (best < 0 or components[i][0] > components[best][0]):
			best = i
	return best


## The foam texture frame (water_render.md §4.4) for a camera at (ox, oy) at t_ms: (e.x, e.y, u0, v0), e the unit
## travel direction of the dominant component (east, north) and (u0, v0) the camera-origin part of the texture
## coordinates, which drift along e at that component's phase speed (in double, mod 1).
static func uv_frame(components: Array, ox: float, oy: float, t_ms: float) -> Vector4:
	var p := dominant_index(components)
	if p < 0:
		return Vector4(0.0, 1.0, 0.0, 0.0)
	var c: Array = components[p]
	var kap := Vector2(c[1], c[2]).length()
	var e := Vector2(c[1], c[2]) / kap
	var speed := (1.0 / kap) / (float(c[4]) * 0.001)   # lam / T
	var u := (ox * e.x + oy * e.y - speed * t_ms * 0.001) / TILE.x
	var v := (-ox * e.y + oy * e.x) / TILE.y
	return Vector4(e.x, e.y, u - floorf(u), v - floorf(v))


## Mean of the crest window exp(-(d/sigma)^2) (sigma_front for d >= 0, sigma_back below) over one cycle.
static func window_mean(sf: float, sb: float) -> float:
	var n := 400
	var s := 0.0
	for k in n:
		var d := -0.5 + (k + 0.5) / n
		var q := d / (sf if d >= 0.0 else sb)
		s += exp(-q * q)
	return s / n


## The crest window at phase f (cycles, crest at 0, ahead of the crest positive) for a caps_w entry w.
static func window(f: float, w: Vector4) -> float:
	var fr := f - floorf(f)
	var d := fr - (1.0 if fr >= 0.5 else 0.0)
	var q := d * (w.x if d >= 0.0 else w.y)
	return exp(-q * q)


## Breaking threshold for a local wind of kn knots.
static func threshold(kn: float) -> float:
	var u := U_REF_KN / maxf(kn, 1.0)
	return S_B0 + S_B1 * u * u * u


## CPU mirror of wm_caps_intensity: the foam intensity F in [0, 1] at a camera-relative point xl (m) for the
## uniforms caps_k, caps_w, caps_rest and the tier's count n, a pixel footprint px (m; 0 = every component resolved), the
## exposure and the local wind (m/s, the puff factor times the base).
static func intensity(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		expo: float, wind: float) -> float:
	var kn := wind / KNOT
	var gate := smoothstep(GATE_KN.x, GATE_KN.y, kn)
	if gate <= 0.0 or expo <= 0.0:
		return 0.0
	var s := rest
	for i in range(n, ck.size()):
		s += ck[i].w * cw[i].z
	for i in mini(n, ck.size()):
		var k := ck[i]
		var w := cw[i]
		var r := 1.0 if px <= 0.0 else smoothstep(2.0, 4.0, w.w / px)
		s += k.w * lerpf(w.z, window(k.x * xl.x + k.y * xl.y + k.z, w), r)
	s *= expo
	return clampf((s - threshold(kn)) / S_W, 0.0, 1.0) * gate


## The foam coverage of intensity F on the four nested density levels L (r, g, b, a): F = 0.25 shows all of
## level r, 0.5 level g, 0.75 level b, 1 level a, blended linearly between them.
static func level_cover(f: float, L: Color) -> float:
	var x := 4.0 * f
	return L.r * clampf(x, 0.0, 1.0) + (L.g - L.r) * clampf(x - 1.0, 0.0, 1.0) \
			+ (L.b - L.g) * clampf(x - 2.0, 0.0, 1.0) + (L.a - L.b) * clampf(x - 3.0, 0.0, 1.0)


## CPU mirror of the drawn foam opacity of wm_apply_caps (before the distance fade): intensity F on the density
## levels L, thin foam translucent.
static func opacity(f: float, L: Color) -> float:
	return OPACITY * level_cover(f, L) * (0.3 + 0.7 * smoothstep(0.0, 0.6, f))


## The mean coverage of each density level of the foam texture (its smallest mip).
static func level_means() -> Color:
	var img := SeaTextures.caps_image()
	var n := img.get_width()
	var s := Color(0, 0, 0, 0)
	for y in n:
		for x in n:
			s += img.get_pixel(x, y)
	return s / float(n * n)


static func _lam(c: Array) -> float:
	return 1.0 / maxf(Vector2(c[1], c[2]).length(), 1e-9)
