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
## the steepness above the threshold for full foam intensity, as a share of the threshold (round 7: relative, so that
## a sea whose breaking events leave most of the water at zero still ramps over the same share)
const S_W := 0.35
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
## the shorter components' crests bent by the breakup noise, CREST_BEND cycles per unit of noise
const CREST_BEND := 0.5
## crest segments: the same channel over SEG_TILE metres (along the dominant wave, across), riding the crests at the
## dominant wave's phase speed, passes a crest's foam only where above SEG_LO (fully above SEG_HI): a crest breaks
## over one or two peak wavelengths and its neighbours do not break in step; SEG_FEATURE is its feature size across
## the crests, for the pixel footprint
const SEG_TILE := Vector2(45.0, 120.0)
const SEG_LO := 0.5
const SEG_HI := 0.7
const SEG_FEATURE := 9.0
const SEG_FAR := 0.45
## the event: a patch's phase is the same channel over EVENT_TILE metres (stretched across the crests) times EVENT_SLOW periods, so the
## phases spread evenly over the cycle across the sea (no sea-wide pulsing) while neighbouring crests differ; each
## point joins its patch's event after a delay (event_delay, up to EVENT_SPREAD periods) from the local noise pn (the
## channel in the segments' frame offset by EVENT_OFS), so a break starts at one point and spreads
const EVENT_OFS := Vector2(0.37, 0.61)
const EVENT_SPREAD := 0.06
## the breakup noise adds up to EVENT_SPREAD_BRK periods of delay, and parts stop up to EVENT_EARLY periods early (the
## segments' fine channel): ragged starts and ends, and a ragged outline to the foam left behind
const EVENT_SPREAD_BRK := 0.15
const EVENT_EARLY := 0.22
const EVENT_TILE := Vector2(270.0, 900.0)
const EVENT_SLOW := 2.0
## the slow part's lookup warped by the local part (its nearly straight contours bent)
const EVENT_WARP := 0.02
## the residual foam's lace and erosion-blob tiles (m along, across); a patch keeps the blobs above
## RESID_ERODE + RESID_ERODE_AGE * age (age 0..1 over the e-folding RESID_TAU twice)
const GLOW_MAX := 0.1
const RESID_LACE_TILE := Vector2(5.0, 3.0)
const RESID_BLOB_TILE := Vector2(16.0, 10.0)
const RESID_ERODE := 0.4
const RESID_ERODE_AGE := 0.3
## the breaking event (round 7): each patch breaks once per EVENT_PERIODS dominant wave periods for 0.4 of a period
## (event()); where the pixel cannot resolve it, EVENT_FAR
const EVENT_PERIODS := 0.9
const EVENT_FAR := 0.15
## the active breaking of an event, in event periods: each point rises over EVENT_RISE after its delay, the patch
## ends at EVENT_LIFE (0.4 T_p), falling over the last EVENT_FALL
const EVENT_RISE := 0.15
const EVENT_LIFE := 0.444
const EVENT_FALL := 0.133
## residual foam: e-folding time (s), and how far it is evaluated (m)
const RESID_TAU := 3.5
const RESID_DIST := 400.0
## the foam a crest leaves at a point: the event at any time within +- RESID_WIDE s of the crest's passing
const RESID_WIDE := 0.25
## the trail's streaks: the foam noise's streak channel over STREAK_TILE metres (along the dominant wave, across)
const STREAK_TILE := Vector2(14.0, 1.6)
## wave age: a component is wind sea (forced by the wind, can break) when its phase speed is at most WIND_SEA_AGE
## times the wind speed; slower than that it is a swell and never carries foam
const WIND_SEA_AGE := 1.2
## calibration sample: points over a CAL_SIZE square
const CAL_POINTS := 65536
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
		s += exp(-q * q) * (1.0 - smoothstep(0.3, 0.5, absf(d)))
	return s / n


## The crest window at phase f (cycles, crest at 0, ahead of the crest positive) for a caps_w entry w.
static func window(f: float, w: Vector4) -> float:
	var fr := f - floorf(f)
	var d := fr - (1.0 if fr >= 0.5 else 0.0)
	var q := d * (w.x if d >= 0.0 else w.y)
	return exp(-q * q) * (1.0 - smoothstep(0.3, 0.5, absf(d)))   # tapered to 0 at the trough (no straight edge)


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
	var duty_k := PackedFloat32Array()
	duty_k.resize(CAL_POINTS)
	var side := int(sqrt(float(CAL_POINTS)))
	for k in CAL_POINTS:
		# a jittered grid: every part of the square sampled, so the rare high values are counted steadily
		var cell := Vector2(k % side + rng.randf(), k / side + rng.randf()) / float(side) - Vector2(0.5, 0.5)
		var x := cell * CAL_SIZE
		var s := rest
		for j in sel.size():
			s += ck[j].w * window(ck[j].x * x.x + ck[j].y * x.y + ck[j].z, cw[j])
		var q := Vector2(x.dot(e), x.dot(Vector2(-e.y, e.x)))
		var g := group_noise(q / GROUP_TILE + Vector2(0.37, 0.61))
		var br := group_noise(q / BREAK_TILE + Vector2(0.13, 0.29))
		var sg := group_noise(q / SEG_TILE + Vector2(0.71, 0.11))
		var pn := group_noise(q / SEG_TILE + Vector2(0.71, 0.11) + EVENT_OFS)
		tot[k] = s * maxf(0.0, 1.0 + amp * (g - gs.x)) * breakup(br, 0.0) * segment(sg, 0.0)
		# the share of the cycle this point's event is on (its delay and early end come from the same noise as the
		# breakup and segments, so the share is counted with the steepness, not as an independent duty)
		var sr := foam_noise(q / SEG_TILE + Vector2(0.71, 0.11), 0)
		var dl := event_delay(pn, br)
		var ee := event_early(sr)
		var n_on := 0
		for j in 32:
			n_on += 1 if event((j + 0.5) / 32.0, dl, ee) >= 0.5 else 0
		duty_k[k] = n_on / 32.0
	# sorted by the steepness, the cover above a threshold is the sum of the on-shares above it
	var order := range(CAL_POINTS)
	order.sort_custom(func(a, b): return tot[a] < tot[b])
	var sorted_tot := PackedFloat32Array()
	sorted_tot.resize(CAL_POINTS)
	var above := PackedFloat32Array()   # above[i]: the summed on-shares of the points from i up
	above.resize(CAL_POINTS + 1)
	for i in CAL_POINTS:
		sorted_tot[i] = tot[order[i]]
	above[CAL_POINTS] = 0.0
	for i in range(CAL_POINTS - 1, -1, -1):
		above[i] = above[i + 1] + duty_k[order[i]]
	tot = sorted_tot
	var lm := level_means()
	var thr := PackedFloat32Array()
	for k in 4:
		var want := COVER_0 * pow(4.0, k)
		var lo := tot[0]
		var hi := tot[CAL_POINTS - 1] * 1.01 + 1e-6
		for it in 40:
			var mid := 0.5 * (lo + hi)
			var a := above[tot.bsearch(mid * (1.0 + 0.5 * S_W), false)]
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
	var b := 0.2 + 0.8 * clampf((g - BREAK_LO) / (BREAK_HI - BREAK_LO), 0.0, 1.0)
	if px <= 0.0:
		return b
	return lerpf(BREAK_FAR, b, smoothstep(2.0, 4.0, BREAK_FEATURE / px))


## The crest-segment factor of a noise value g at a pixel footprint px (m), as breakup.
static func segment(g: float, px: float) -> float:
	var b := clampf((g - SEG_LO) / (SEG_HI - SEG_LO), 0.0, 1.0)
	if px <= 0.0:
		return b
	return lerpf(SEG_FAR, b, smoothstep(2.0, 4.0, SEG_FEATURE / px))


## The crest-segment frame (caps_seg) for a camera at (ox, oy) at t_ms, riding the dominant wave at its phase speed.
static func segment_frame(components: Array, ox: float, oy: float, t_ms: float) -> Vector4:
	var p := dominant_index(components)
	if p < 0:
		return Vector4.ZERO
	var c: Array = components[p]
	var kap := Vector2(c[1], c[2]).length()
	var e := Vector2(c[1], c[2]) / kap
	var speed := (1.0 / kap) / (float(c[4]) * 0.001)
	var su := (ox * e.x + oy * e.y - speed * t_ms * 0.001) / SEG_TILE.x + 0.71
	var sv := (-ox * e.y + oy * e.x) / SEG_TILE.y + 0.11
	# zw: the event phase's frame over EVENT_TILE metres
	var eu := (ox * e.x + oy * e.y - speed * t_ms * 0.001) / EVENT_TILE.x + 0.23
	var ev := (-ox * e.y + oy * e.x) / EVENT_TILE.y + 0.47
	return Vector4(su - floorf(su), sv - floorf(sv), eu - floorf(eu), ev - floorf(ev))


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


## The streak frame (caps_str) for a camera at (ox, oy) at t_ms: foam left on the water drifts with the surface,
## about 3 % of the wind speed u (m/s), along the dominant wave (in double, mod 1).
static func streak_frame(components: Array, ox: float, oy: float, t_ms: float, u := 0.0) -> Vector2:
	var p := dominant_index(components)
	if p < 0:
		return Vector2.ZERO
	var c: Array = components[p]
	var kap := Vector2(c[1], c[2]).length()
	var e := Vector2(c[1], c[2]) / kap
	var speed := 0.03 * u
	var su := (ox * e.x + oy * e.y - speed * t_ms * 0.001) / STREAK_TILE.x + 0.21
	var sv := (-ox * e.y + oy * e.x) / STREAK_TILE.y + 0.47
	return Vector2(su - floorf(su), sv - floorf(sv))


## The foam noise channel ch (0 R streaks, 1 G coarse) at a texture coordinate, bilinear.
static func foam_noise(uv: Vector2, ch: int) -> float:
	var img := SeaTextures.foam_image()
	var n := img.get_width()
	var x := uv.x * n - 0.5
	var y := uv.y * n - 0.5
	var i := int(floorf(x))
	var j := int(floorf(y))
	var tx := x - i
	var ty := y - j
	var a: float = img.get_pixel(posmod(i, n), posmod(j, n))[ch]
	var b: float = img.get_pixel(posmod(i + 1, n), posmod(j, n))[ch]
	var c: float = img.get_pixel(posmod(i, n), posmod(j + 1, n))[ch]
	var d: float = img.get_pixel(posmod(i + 1, n), posmod(j + 1, n))[ch]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## CPU mirror of the drawn foam of wm_apply_caps: f the field (x, dm, gate, xr) with the gate times the fade, res the
## residual (resid, tau), L the lace texture sample, st the streak noise, nb the wandering lace noise, lam0 the heaviest
## component's wavelength. Returns (opacity, active core, residual opacity).
## CPU mirror of wm_caps_solid: the solid-white share of the core (a thin broken band at the crest).
static func solid_share(xj: float, dm: float, lam0: float, st: float) -> float:
	var band := 0.5 if dm == 0.0 else (1.0 - smoothstep(0.0, 0.03 * lam0, -dm)) * (1.0 - smoothstep(0.0, 0.03 * lam0, dm))
	return smoothstep(1.5, 2.5, xj) * band * smoothstep(0.55, 0.75, st)


## CPU mirror of the bubble glow of wm_apply_caps: the mix toward green-blue (at most GLOW_MAX).
static func glow(f: Vector4, L: Color, lam0: float) -> float:
	if f.x <= -1.5:
		return 0.0
	var xj := f.x + 1.2 * (L.g - 0.5)
	var behind := (1.0 - smoothstep(0.0, 1.5, f.y)) * (0.0 if f.y == 0.0 else smoothstep(-0.4 * lam0, -0.15 * lam0, f.y))
	var near_cap := smoothstep(-0.8, 0.4, xj) * smoothstep(0.0, 0.7, f.w)
	return GLOW_MAX * near_cap * behind * f.w * f.w * L.b * f.z


static func drawn(f: Vector4, res: Vector2, L: Color, st: float, Lr: Color, blob: float, lam0: float) -> Vector3:
	var g := f.z
	var a := 0.0
	var ra := 0.0
	if res.x > 0.0:
		var u := 2.0 * (1.0 - exp(-res.y / (2.0 * RESID_TAU)))
		var cov := lerpf(Lr.b, Lr.g, u) if u < 1.0 else lerpf(Lr.g, Lr.r, u - 1.0)
		var th := RESID_ERODE + RESID_ERODE_AGE * (1.0 - exp(-res.y / (2.0 * RESID_TAU)))
		ra = 0.6 * res.x * smoothstep(th, th + 0.2, blob) * g   # the patch (its lace aside)
		a = ra * cov
	var core := 0.0
	if f.x > -1.5:
		var xj := f.x + 1.2 * (L.g - 0.5)
		var front := smoothstep(-4.0, -1.0, f.y) * (1.0 - smoothstep(0.25 * lam0, 0.45 * lam0, f.y))
		core = smoothstep(0.0, 3.0, xj) * smoothstep(0.0, 0.7, f.w) * front * g
		var solid := solid_share(xj, f.y, lam0, st)
		var dense := lerpf(L.g, L.b, smoothstep(2.0, 5.0, xj))   # the lace net at the edges, dense foam inside
		a = maxf(a, clampf(core * lerpf(0.85 * dense, 0.95 * L.a, solid), 0.0, 1.0))
	return Vector3(a, core, ra)


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


## The breaking event pulse at an event phase ph in [0, 1) (wm_caps_event).
static func event(ph: float, delay := 0.0, early := 0.0) -> float:
	return smoothstep(delay, delay + EVENT_RISE, ph) \
			* (1.0 - smoothstep(EVENT_LIFE - EVENT_FALL - early, EVENT_LIFE - early, ph))


## A point's delay into its patch's event (periods) from the local event noise pn and the breakup noise br: the break
## spreads from their lows.
static func event_delay(pn: float, br: float) -> float:
	return EVENT_SPREAD * clampf((pn - 0.35) / 0.3, 0.0, 1.0) + EVENT_SPREAD_BRK * clampf((br - 0.3) / 0.4, 0.0, 1.0)


## How early a point stops breaking (periods) from the segments' fine channel sr: a ragged end.
static func event_early(sr: float) -> float:
	return EVENT_EARLY * clampf((sr - 0.3) / 0.4, 0.0, 1.0)


## The event frame (caps_ev) at t_ms: (fract(t / T_ev), 1 / T_ev, c_p, RESID_TAU), T_ev = EVENT_PERIODS T_p of the
## dominant wave.
static func event_frame(components: Array, t_ms: float) -> Vector4:
	var p := dominant_index(components)
	if p < 0:
		return Vector4(0.0, 0.0, 0.0, RESID_TAU)
	var c: Array = components[p]
	var tp := float(c[4]) * 0.001
	var tev := EVENT_PERIODS * tp
	var ph := fposmod(t_ms * 0.001 / tev, 1.0)
	var cp := (1.0 / Vector2(c[1], c[2]).length()) / tp
	return Vector4(ph, 1.0 / tev, cp, RESID_TAU)


## The residual foam frames (caps_res) for a camera at (ox, oy) at t_ms, both drifting with the surface at 3 % of the
## wind u along the dominant wave and wandering slowly, so that the foam changes shape: xy the lace (RESID_LACE_TILE),
## zw the erosion blobs (RESID_BLOB_TILE) that break a patch into fragments as it ages.
static func residual_frame(components: Array, ox: float, oy: float, t_ms: float, u := 0.0) -> Vector4:
	var e := _dir(components)
	var ts := t_ms * 0.001
	var a := ox * e.x + oy * e.y - 0.03 * u * ts
	var c := -ox * e.y + oy * e.x
	var su := a / RESID_LACE_TILE.x + 0.06 * sin(0.21 * ts) + 0.33
	var sv := c / RESID_LACE_TILE.y + 0.06 * cos(0.17 * ts) + 0.52
	var bu := a / RESID_BLOB_TILE.x + 0.02 * sin(0.13 * ts) + 0.71
	var bv := c / RESID_BLOB_TILE.y + 0.02 * cos(0.11 * ts) + 0.18
	return Vector4(su - floorf(su), sv - floorf(sv), bu - floorf(bu), bv - floorf(bv))


## CPU mirror of wm_caps_sum: (S, dm) tau seconds ago, env the group envelope; frames as in field.
static func sum_at(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		e: Vector2, env: float, brk: Vector2, seg: Vector4, ev: Vector4, tau: float, wide := 0.0) -> Vector3:
	var dm := 0.0
	var s := rest
	for i in range(n, ck.size()):
		s += ck[i].w * cw[i].z
	var q := Vector2(xl.dot(e), xl.dot(Vector2(-e.y, e.x)))
	var back := ev.z * tau
	var bu := q / BREAK_TILE + brk + Vector2(back / BREAK_TILE.x, 0.0)
	var br := group_noise(bu)
	for i in mini(n, ck.size()):
		var k := ck[i]
		var w := cw[i]
		var r := 1.0 if px <= 0.0 else smoothstep(2.0, 4.0, w.w / px)
		if wide > 0.0 and i > 0:
			r = 0.0
		var ph := k.x * xl.x + k.y * xl.y + k.z + (tau / sqrt(0.6405 * w.w) if w.w > 0.0 else 0.0)
		if i > 0:
			ph += CREST_BEND * (br - 0.5)   # the shorter crests bent by the breakup (no straight foam edges)
		s += k.w * lerpf(w.z, window(ph, w), r)
		if i == 0:
			var fr := ph - floorf(ph)
			dm = (fr - (1.0 if fr >= 0.5 else 0.0)) * w.w * r
	var su := q / SEG_TILE + Vector2(seg.x, seg.y) + Vector2(back / SEG_TILE.x, 0.0)
	var sg := group_noise(su)
	var rs := 1.0 if px <= 0.0 else smoothstep(2.0, 4.0, SEG_FEATURE / px)
	# ev.y = 0: no events (the steady caps of round 6, for comparison)
	var evp := 1.0
	if ev.y > 0.0:
		var pn := group_noise(su + EVENT_OFS)
		var eu := q / EVENT_TILE + Vector2(seg.z, seg.w) + Vector2(back / EVENT_TILE.x, 0.0) \
				+ Vector2.ONE * (EVENT_WARP * (pn - 0.5))
		var ph := fposmod(ev.x - tau * ev.y + EVENT_SLOW * group_noise(eu), 1.0)
		var dl := event_delay(pn, br)
		var ee := event_early(foam_noise(su, 0))
		var evv := event(ph, dl, ee)
		if wide > 0.0:
			evv = maxf(evv, maxf(event(fposmod(ph + wide * ev.y, 1.0), dl, ee), event(fposmod(ph - wide * ev.y, 1.0), dl, ee)))
		evp = lerpf(EVENT_FAR, evv, rs)
	var bf := 0.6 if wide > 0.0 else breakup(br, px)
	return Vector3(s * env * bf * segment(sg, px), dm, evp)   # the event gates the foam, not the steepness


## CPU mirror of wm_caps_field: (x, dm, gate, ev) as intensity's arguments.
static func field(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		expo: float, wind: float, cal: Dictionary, grp: Vector4, e: Vector2, brk: Vector2, seg: Vector4, ev: Vector4) -> Vector4:
	var kn := wind / KNOT
	var gate := smoothstep(GATE_KN.x, GATE_KN.y, kn)
	if gate <= 0.0 or expo <= 0.0:
		return Vector4(-1e3, 0.0, 0.0, -1e3)
	var sd := sum_at(ck, cw, rest, n, xl, px, e, env_at(xl, e, grp), brk, seg, ev, 0.0)
	var s := sd.x * expo
	var sb := threshold(wind, cal["thr"])
	var xv := (s - sb) / maxf(S_W * sb, 1e-6)
	return Vector4(xv, sd.y, gate, sd.z)


## The group envelope at a camera-relative point.
static func env_at(xl: Vector2, e: Vector2, grp: Vector4) -> float:
	var q := Vector2(xl.dot(e), xl.dot(Vector2(-e.y, e.x)))
	return maxf(0.0, 1.0 + grp.x * (group_noise(q / GROUP_TILE + Vector2(grp.z, grp.w)) - grp.y))


## CPU mirror of the residual foam of wm_apply_caps: (resid, tau) at a point with the current field f (field()),
## px the footprint, dist the distance from the camera.
static func residual(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		expo: float, wind: float, cal: Dictionary, grp: Vector4, e: Vector2, brk: Vector2, seg: Vector4, ev: Vector4,
		f: Vector4, dist := 0.0, drift := 0.0) -> Vector2:
	var lam0 := cw[0].w
	if ev.y <= 0.0 or dist >= RESID_DIST or (px > 0.0 and lam0 / px <= 4.0) or f.z <= 0.0:
		return Vector2.ZERO
	var t0 := sqrt(0.6405 * lam0)
	var d0 := f.y / lam0
	var tau0 := (-d0 if d0 <= 0.0 else 1.0 - d0) * t0
	var env := env_at(xl, e, grp)
	var sb := threshold(wind, cal["thr"])
	var best := Vector2.ZERO
	for k in 2:
		var tau := tau0 + k * t0
		var xd := xl - e * (drift * tau)
		# the time since the crest passed where this foam fell (one fixed-point step)
		var fd := ck[0].x * xd.x + ck[0].y * xd.y + ck[0].z
		fd -= floorf(fd)
		var dd := fd - (1.0 if fd >= 0.5 else 0.0)
		tau = (-dd + floorf((tau + dd * t0) / t0 + 0.5)) * t0
		xd = xl - e * (drift * tau)
		var sd := sum_at(ck, cw, rest, n, xd, px, e, env, brk, seg, ev, tau, RESID_WIDE)
		var a := minf(clampf((sd.x * expo - sb) / maxf(S_W * sb, 1e-6), 0.0, 1.0), sd.z)
		var r := a * a * exp(-tau / ev.w) * smoothstep(0.0, 0.6, tau) * (1.0 - smoothstep(1.5 * t0, 2.0 * t0, tau)) \
				* (1.0 - smoothstep(300.0, RESID_DIST, dist))
		if r > best.x:
			best = Vector2(r, tau)
	return best


## CPU mirror of wm_caps_intensity: the active foam intensity F in [0, 1] (see field for the arguments).
static func intensity(ck: PackedVector4Array, cw: PackedVector4Array, rest: float, n: int, xl: Vector2, px: float,
		expo: float, wind: float, cal: Dictionary, grp: Vector4, e: Vector2, brk: Vector2, seg: Vector4, ev: Vector4) -> float:
	var f := field(ck, cw, rest, n, xl, px, expo, wind, cal, grp, e, brk, seg, ev)
	return minf(clampf(f.x, 0.0, 1.0), f.w) * f.z


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
