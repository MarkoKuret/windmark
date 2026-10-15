class_name SeaWhitecaps
extends RefCounted
## Whitecaps that ride the waves (water_render.md §4.4): the per-component foam weights and the foam texture frame
## the Sea uploads, and a CPU mirror of the shader's foam intensity (wm_caps_intensity in sea_common.gdshaderinc)
## for the tests. The constants here and in the shader are the spec's; change both together.

const KNOT := 0.51444447
## no caps under GATE_KN.x knots of local wind, full from GATE_KN.y
const GATE_KN := Vector2(8.0, 10.0)
## measured whitecap cover W(U) = MONAHAN_A · U^MONAHAN_B (U in m/s, fraction of the surface)
const MONAHAN_A := 3.84e-6
const MONAHAN_B := 3.41
## the covers the thresholds are calibrated at: COVER_0 · 4^k, k = 0..3 (0.05, 0.2, 0.8, 3.2 %)
const COVER_0 := 0.0005
## steepness above the threshold for full foam intensity
const S_W := 0.035
## wave-group envelope: the foam noise's coarse channel over GROUP_TILE metres, drifting at half the dominant
## wave's phase speed; it scales the steepness sum by 1 + GROUP_AMP·(G − mean)/sd (at least 0)
const GROUP_TILE := 600.0
const GROUP_AMP := 0.5
## short-crestedness: the same channel over BREAK_TILE metres (along the dominant wave, across), riding it at its
## phase speed, passes a crest's foam only where it is above BREAK_LO (fully above BREAK_HI), so a cap is a few
## metres long, not a crest-long bar; BREAK_FEATURE is its feature size, for the pixel footprint
const BREAK_TILE := Vector2(30.0, 15.0)
const BREAK_LO := 0.55
const BREAK_HI := 0.8
const BREAK_FEATURE := 6.0
const BREAK_FAR := 0.6
## wave age: a component is wind sea (forced by the wind, can break) when its phase speed is at most WIND_SEA_AGE
## times the wind speed; slower than that it is a swell and never carries foam
const WIND_SEA_AGE := 1.2
## calibration sample: points over a CAL_SIZE square
const CAL_POINTS := 32768
const CAL_SIZE := 600.0
## crest window half widths, cycles, ahead of the crest (front) and behind it (back), each at least the width in
## metres below over the wavelength
const SIGMA_FRONT := 0.08
const SIGMA_BACK := 0.15
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


## The components as the whitecaps see them (water_render.md §4.4): the swell, every component faster than
## WIND_SEA_AGE·u (u: the base wind, m/s), set to amplitude 0, so it carries no foam and is never the dominant wave.
## Sea order and indices are kept.
static func wind_sea_only(components: Array, u: float) -> Array:
	var out := []
	for c in components:
		var speed := 9.81 * (float(c[4]) * 0.001) / TAU   # deep water: c = g T / 2 pi
		if speed <= WIND_SEA_AGE * u:
			out.append(c)
		else:
			out.append([0.0, c[1], c[2], c[3], c[4]])
	return out


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


## The largest-amplitude component (of the wind sea after wind_sea_only), -1 for none.
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


## The measured whitecap cover at a local wind of u m/s (fraction of the surface).
static func cover_law(u: float) -> float:
	return MONAHAN_A * pow(maxf(u, 0.1), MONAHAN_B)


## Breaking threshold for a local wind of u m/s from the sea's calibrated thresholds thr (caps_thr): piecewise
## linear in x = log2(W(u)/COVER_0)/2, extrapolated beyond the ends.
static func threshold(u: float, thr: Vector4) -> float:
	var x := 0.5 * log(cover_law(u) / COVER_0) / log(2.0)
	if x < 1.0:
		return lerpf(thr.x, thr.y, x)
	if x < 2.0:
		return lerpf(thr.y, thr.z, x - 1.0)
	return lerpf(thr.z, thr.w, x - 2.0)


## The group envelope's noise value at a texture coordinate (the coarse channel G of the foam noise, bilinear).
static func group_noise(uv: Vector2) -> float:
	var img := SeaTextures.foam_image()
	var n := img.get_width()
	var x := uv.x * n - 0.5
	var y := uv.y * n - 0.5
	var i := int(floorf(x))
	var j := int(floorf(y))
	var tx := x - i
	var ty := y - j
	var g00 := img.get_pixel(posmod(i, n), posmod(j, n)).g
	var g10 := img.get_pixel(posmod(i + 1, n), posmod(j, n)).g
	var g01 := img.get_pixel(posmod(i, n), posmod(j + 1, n)).g
	var g11 := img.get_pixel(posmod(i + 1, n), posmod(j + 1, n)).g
	return lerpf(lerpf(g00, g10, tx), lerpf(g01, g11, tx), ty)


static var _g_stats := Vector2(-1.0, 0.0)


## Mean and standard deviation of the group noise.
static func group_stats() -> Vector2:
	if _g_stats.x < 0.0:
		var img := SeaTextures.foam_image()
		var n := img.get_width()
		var s := 0.0
		var s2 := 0.0
		for y in n:
			for x in n:
				var g := img.get_pixel(x, y).g
				s += g
				s2 += g * g
		var m := s / (n * n)
		_g_stats = Vector2(m, sqrt(maxf(s2 / (n * n) - m * m, 0.0)))
	return _g_stats


## Calibration, once per sea: {thr: caps_thr, amp: g_amp, mean: G_mean}. The steepness sum (every component
## resolved) times the group envelope and the short-crest breakup at CAL_POINTS fixed points; each threshold makes the
## foamed area (F at least 0.5, what a whitecap photograph counts) equal to its cover COVER_0·4^k.
static func calibrate(components: Array, sel: PackedInt32Array) -> Dictionary:
	var gs := group_stats()
	var out := {"thr": Vector4(1e3, 1e3, 1e3, 1e3), "amp": 0.0, "mean": gs.x}
	if sel.is_empty():
		return out
	var cw := window_uniforms(components, sel)
	var rest := rest_mean(components, sel)
	var ck := PackedVector4Array()
	ck.resize(MAX_CAPS)
	var b := weights(components)
	for k in sel.size():
		var c: Array = components[sel[k]]
		ck[k] = Vector4(c[1], c[2], c[3], b[sel[k]])
	var e := _dir(components)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98
	var tot := PackedFloat32Array()
	tot.resize(CAL_POINTS)
	var amp := GROUP_AMP / maxf(gs.y, 1e-4)
	for k in CAL_POINTS:
		var x := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * CAL_SIZE
		var s := rest
		for j in sel.size():
			s += ck[j].w * window(ck[j].x * x.x + ck[j].y * x.y + ck[j].z, cw[j])
		var q := Vector2(x.dot(e), x.dot(Vector2(-e.y, e.x)))
		var g := group_noise(q / GROUP_TILE + Vector2(0.37, 0.61))
		var br := group_noise(q / BREAK_TILE + Vector2(0.13, 0.29))
		tot[k] = s * maxf(0.0, 1.0 + amp * (g - gs.x)) * breakup(br, 0.0)
	tot.sort()
	# only the top of the distribution can pass a threshold for covers up to a few per cent
	var top := tot.slice(int(CAL_POINTS * 0.85))
	var lm := level_means()
	var thr := PackedFloat32Array()
	for k in 4:
		var want := COVER_0 * pow(4.0, k)
		var lo := tot[0]
		var hi := tot[CAL_POINTS - 1] + S_W
		for it in 40:
			var mid := 0.5 * (lo + hi)
			var a := 0.0
			for v in top:
				if v > mid + 0.5 * S_W:
					a += 1.0
			if a / CAL_POINTS > want:
				lo = mid
			else:
				hi = mid
		thr.append(0.5 * (lo + hi))
	out["thr"] = Vector4(thr[0], thr[1], thr[2], thr[3])
	out["amp"] = amp
	return out


## The short-crest breakup factor of a noise value g at a pixel footprint px (m): 0 below BREAK_LO, 1 above
## BREAK_HI; where the pixel cannot resolve the breakup's features it tends to BREAK_FAR.
static func breakup(g: float, px: float) -> float:
	var b := clampf((g - BREAK_LO) / (BREAK_HI - BREAK_LO), 0.0, 1.0)
	if px <= 0.0:
		return b
	return lerpf(BREAK_FAR, b, smoothstep(2.0, 4.0, BREAK_FEATURE / px))


## The breakup frame for a camera at (ox, oy) at t_ms: the camera-origin part of the breakup's texture coordinates,
## riding the dominant wave at its phase speed (in double, mod 1).
static func break_frame(components: Array, ox: float, oy: float, t_ms: float) -> Vector2:
	var p := dominant_index(components)
	if p < 0:
		return Vector2.ZERO
	var c: Array = components[p]
	var kap := Vector2(c[1], c[2]).length()
	var e := Vector2(c[1], c[2]) / kap
	var speed := (1.0 / kap) / (float(c[4]) * 0.001)
	var u := (ox * e.x + oy * e.y - speed * t_ms * 0.001) / BREAK_TILE.x + 0.13
	var v := (-ox * e.y + oy * e.x) / BREAK_TILE.y + 0.29
	return Vector2(u - floorf(u), v - floorf(v))


static func _dir(components: Array) -> Vector2:
	var p := dominant_index(components)
	if p < 0:
		return Vector2(0.0, 1.0)
	var c: Array = components[p]
	return Vector2(c[1], c[2]).normalized()


## The group envelope frame for a camera at (ox, oy) at t_ms: (amp, mean, ug, vg), the camera-origin part of the
## envelope's texture coordinates drifting along the dominant wave at half its phase speed (in double, mod 1).
static func group_frame(components: Array, cal: Dictionary, ox: float, oy: float, t_ms: float) -> Vector4:
	var p := dominant_index(components)
	if p < 0:
		return Vector4(0.0, cal.get("mean", 0.5), 0.0, 0.0)
	var c: Array = components[p]
	var kap := Vector2(c[1], c[2]).length()
	var e := Vector2(c[1], c[2]) / kap
	var cg := 0.5 * (1.0 / kap) / (float(c[4]) * 0.001)
	var u := (ox * e.x + oy * e.y - cg * t_ms * 0.001) / GROUP_TILE + 0.37
	var v := (-ox * e.y + oy * e.x) / GROUP_TILE + 0.61
	return Vector4(cal["amp"], cal["mean"], u - floorf(u), v - floorf(v))


## CPU mirror of wm_caps_intensity: the foam intensity F in [0, 1] at a camera-relative point xl (m) for the
## uniforms caps_k, caps_w, caps_rest, caps_thr, caps_grp and caps_brk (cal: the calibration; grp: the group frame;
## brk: the breakup frame), the tier's
## count n, a pixel footprint px (m; 0 = every component resolved), the exposure and the local wind (m/s, the puff
## factor times the base).
static func intensity(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		expo: float, wind: float, cal: Dictionary, grp: Vector4, e: Vector2, brk: Vector2) -> float:
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
	var q := Vector2(xl.dot(e), xl.dot(Vector2(-e.y, e.x)))
	var g := group_noise(q / GROUP_TILE + Vector2(grp.z, grp.w))
	var br := group_noise(q / BREAK_TILE + brk)
	s = s * expo * maxf(0.0, 1.0 + grp.x * (g - grp.y)) * breakup(br, px)
	return clampf((s - threshold(wind, cal["thr"])) / S_W, 0.0, 1.0) * gate


## The foam coverage of intensity F on the four nested density levels L (r, g, b, a): F = 0.25 shows all of
## level r, 0.5 level g, 0.75 level b, 1 level a, blended linearly between them.
static func level_cover(f: float, L: Color) -> float:
	var x := 4.0 * f
	return L.r * clampf(x, 0.0, 1.0) + (L.g - L.r) * clampf(x - 1.0, 0.0, 1.0) \
			+ (L.b - L.g) * clampf(x - 2.0, 0.0, 1.0) + (L.a - L.b) * clampf(x - 3.0, 0.0, 1.0)


## CPU mirror of the drawn foam opacity of wm_apply_caps (before the distance fade): intensity F on the density
## levels L, thin foam translucent.
static func opacity(f: float, L: Color) -> float:
	return OPACITY * level_cover(0.8 * f, L) * (0.3 + 0.7 * smoothstep(0.0, 0.6, f))


static var _level_means := Color(-1, 0, 0, 0)


## The mean coverage of each density level of the foam texture (its smallest mip).
static func level_means() -> Color:
	if _level_means.r >= 0.0:
		return _level_means
	var img := SeaTextures.caps_image()
	var n := img.get_width()
	var s := Color(0, 0, 0, 0)
	for y in n:
		for x in n:
			s += img.get_pixel(x, y)
	_level_means = s / float(n * n)
	return _level_means


static func _lam(c: Array) -> float:
	return 1.0 / maxf(Vector2(c[1], c[2]).length(), 1e-9)
