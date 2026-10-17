// Water surface functions shared by the sea shaders (water_l/m/h.gdshader) and the offline preview renderer
// (tests/water_preview.py): water_render.md §3 and §4. Written in the common subset of Godot's shading language
// and GLSL 3.30: explicit float literals, no Godot built-ins, no uniform hints. The including file declares
// `TIER` (1 = L, 2 = M, 3 = H) and the samplers `expo_tex`, `land_tex`, `detail_tex`, `foam_tex`, `wake_tex` first,
// and with `WM_WHITECAPS` defined (the sea surface only) also `caps_tex`.
//
// Scene axes (conventions.md §11): X = east, Y = up, Z = south; a water point (x, y) is drawn at (x, eta, -y).
// Positions `xl` are camera-relative world metres (x - ox, y - oy), as the mesh is centred on the camera.

const float WM_TWO_PI = 6.28318530718;
const float WM_KNOT = 0.514444470;

// §2 per-frame sea data
uniform int n_comp = 0;
uniform vec4 comp[22];                 // (a, kx, ky, d') per component, kx, ky in cycles per metre
uniform float comp_lam[22];            // wavelength 1/|k| (m) per component; comp is sorted by it, longest first
uniform float sum_a = 0.0;
uniform vec2 sea_origin = vec2(0.0);   // (ox, oy): the camera on the water plane (world, for the exposure grid)

// §6 exposure grid: expo_tex is nx x ny, R32F, texel (i, j) = node (i, j)
uniform vec4 expo_grid = vec4(0.0, 0.0, 1.0, 1.0);   // x0, y0, dx, dy
uniform ivec2 expo_size = ivec2(0, 0);               // nx, ny; below 2 = no grid (E = 1)
uniform float expo_default = 1.0;

// §4.3 wind on the water
uniform int n_puff = 0;
uniform vec4 puff[16];                 // (px - ox, py - oy, R, e*s), unwrapped centres
uniform float puff_tile = 1000.0;
uniform float puff_cap_lo = 0.6;
uniform float puff_cap_hi = 1.25;
uniform float base_speed = 7.2;        // m/s
uniform float land_factor = 1.0;       // extra scalar speed factor (Sea.set_land_factor), 1 by default
// §4.3 venue land-effect speed factor (wind.md §8): land_tex is nx x ny, RG32F, R = sector k0, G = sector k1
// around the current wind direction, blended with land_tw
uniform vec4 land_grid = vec4(0.0, 0.0, 1.0, 1.0);   // x0, y0, dx, dy
uniform ivec2 land_size = ivec2(0, 0);               // nx, ny; below 2 = no field (f = 1)
uniform float land_tw = 0.0;

// §4.1 detail normals: per layer (scale*cos, scale*sin, offset u, offset v) in the detail frame (downwind, across)
uniform vec2 detail_dir = vec2(0.0, 1.0);   // world (east, north) unit vector the median wind blows toward
uniform vec4 detail_layer[5];               // [0..3] detail layers, [4] the fine glint layer (§4.1)
uniform float wake_extent = 400.0;          // m, side of the camera-centred wake normal buffer
uniform float wake_strength = 0.0;          // 0 when the buffer is off (tier L)
// §4.1.1 wind roughness: the slope variance the sea's waves carry, sum (2 pi a / lam)^2 / 2, and the normal map's
// mean |rg*2 - 1|^2 (one layer)
uniform float geo_var = 0.0;
uniform float detail_var = 0.118;

// sky ramp and sun (the sky preset sets them)
uniform vec3 sky_horizon = vec3(0.60, 0.72, 0.85);
uniform vec3 sky_zenith = vec3(0.12, 0.30, 0.62);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.866);      // scene axes, toward the sun
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);

// §4.2 colours (linear)
uniform vec3 col_deep = vec3(0.006, 0.042, 0.115);
uniform vec3 col_shallow = vec3(0.012, 0.100, 0.155);
uniform vec3 col_sss = vec3(0.03, 0.33, 0.40);
uniform vec3 col_foam = vec3(0.86, 0.90, 0.92);
uniform float puff_k = 1.0;                  // §4.3 a factor on the puffs' darkening (the conditions')

// §6 overlays: line segments (ax, ay, bx, by camera-relative) and circles (cx, cy, r, 0), colour (rgb, width m)
uniform int n_ov_line = 0;
uniform vec4 ov_line[8];
uniform vec4 ov_line_col[8];
uniform int n_ov_circle = 0;
uniform vec4 ov_circle[4];
uniform vec4 ov_circle_col[4];
uniform float ov_px_angle = 0.0015;         // rad per pixel of the camera, widens far lines

// §3.2 fade of the waves a grid of spacing s cannot carry
float wm_fade(float kx, float ky, float s) {
	float lam = 1.0 / max(length(vec2(kx, ky)), 1e-6);
	return s <= 0.0 ? 1.0 : smoothstep(2.0, 4.0, lam / s);
}

// §3.2 height and slope (d eta/dx, d eta/dy) at a camera-relative point, before the exposure, with the waves
// shorter than 2-4 grid spacings s faded (s = 0: every component, the core's sea_height).
void wm_sea_height(vec2 xl, float s, out float eta, out vec2 grad) {
	eta = 0.0;
	grad = vec2(0.0);
	for (int i = 0; i < n_comp; i++) {
		vec4 c = comp[i];
		float w = wm_fade(c.y, c.z, s);
		float f = fract(c.y * xl.x + c.z * xl.y + c.w);
		float ph = WM_TWO_PI * f;
		eta += w * c.x * cos(ph);
		grad += (w * c.x * WM_TWO_PI * -sin(ph)) * c.yz;
	}
}

// Per-pixel slope of the components the vertex grid faded (tiers M, H), themselves faded by the pixel footprint
// px (m) so they never alias: w = (1 - smoothstep(2, 4, lam/s)) * smoothstep(2, 4, lam/px), zero unless
// 2 px < lam < 4 s. The components are sorted by wavelength, longest first (water_render.md §3.2), so the loop
// skips those the grid carries (lam >= 4 s) and stops at the first the pixel cannot show (lam <= 2 px).
vec2 wm_faded_slope(vec2 xl, float s, float px) {
	vec2 grad = vec2(0.0);
	float hi = 4.0 * s;
	float lo = 2.0 * px;
	if (s <= 0.0 || n_comp < 1 || lo >= hi || comp_lam[n_comp - 1] >= hi) {
		return grad;
	}
	float inv_s = 1.0 / s;
	float inv_px = px > 0.0 ? 1.0 / px : 0.0;
	for (int i = 0; i < n_comp; i++) {
		float lam = comp_lam[i];
		if (lam >= hi) {
			continue;
		}
		if (lam <= lo) {
			break;
		}
		vec4 c = comp[i];
		float w = (1.0 - smoothstep(2.0, 4.0, lam * inv_s)) * (px > 0.0 ? smoothstep(2.0, 4.0, lam * inv_px) : 1.0);
		float f = fract(c.y * xl.x + c.z * xl.y + c.w);
		grad += (w * c.x * WM_TWO_PI * -sin(WM_TWO_PI * f)) * c.yz;
	}
	return grad;
}

// §6 (sea.md) exposure: the grid sampler of wind.md §8.1 on the node texture, exact bilinear weights.
float wm_exposure(vec2 p) {
	if (expo_size.x < 2 || expo_size.y < 2) {
		return 1.0;
	}
	float x1 = expo_grid.x + float(expo_size.x - 1) * expo_grid.z;
	float y1 = expo_grid.y + float(expo_size.y - 1) * expo_grid.w;
	if (p.x < expo_grid.x || p.y < expo_grid.y || p.x > x1 || p.y > y1) {
		return expo_default;
	}
	float u = (p.x - expo_grid.x) / expo_grid.z;
	float v = (p.y - expo_grid.y) / expo_grid.w;
	int i = min(int(u), expo_size.x - 2);
	int j = min(int(v), expo_size.y - 2);
	float tx = u - float(i);
	float ty = v - float(j);
	float e00 = texelFetch(expo_tex, ivec2(i, j), 0).r;
	float e10 = texelFetch(expo_tex, ivec2(i + 1, j), 0).r;
	float e01 = texelFetch(expo_tex, ivec2(i, j + 1), 0).r;
	float e11 = texelFetch(expo_tex, ivec2(i + 1, j + 1), 0).r;
	return mix(mix(e00, e10, tx), mix(e01, e11, tx), ty);
}

// §4.3 venue land-effect speed factor f (wind.md §8): the grid sampler of §8.1 on the two sectors around the
// current direction, exact bilinear weights, 1 outside the grid; then lerp between the sectors.
float wm_land(vec2 p) {
	if (land_size.x < 2 || land_size.y < 2) {
		return 1.0;
	}
	float x1 = land_grid.x + float(land_size.x - 1) * land_grid.z;
	float y1 = land_grid.y + float(land_size.y - 1) * land_grid.w;
	if (p.x < land_grid.x || p.y < land_grid.y || p.x > x1 || p.y > y1) {
		return 1.0;
	}
	float u = (p.x - land_grid.x) / land_grid.z;
	float v = (p.y - land_grid.y) / land_grid.w;
	int i = min(int(u), land_size.x - 2);
	int j = min(int(v), land_size.y - 2);
	float tx = u - float(i);
	float ty = v - float(j);
	vec2 f00 = texelFetch(land_tex, ivec2(i, j), 0).rg;
	vec2 f10 = texelFetch(land_tex, ivec2(i + 1, j), 0).rg;
	vec2 f01 = texelFetch(land_tex, ivec2(i, j + 1), 0).rg;
	vec2 f11 = texelFetch(land_tex, ivec2(i + 1, j + 1), 0).rg;
	vec2 f = mix(mix(f00, f10, tx), mix(f01, f11, tx), ty);
	return mix(f.x, f.y, land_tw);
}

float wm_wrap_tile(float d) {
	return d - puff_tile * floor(d * (1.0 / puff_tile) + 0.5);
}

// §4.3 the puff factor m of wind.md §6.4 from the live patches.
float wm_puff_factor(vec2 xl) {
	float m = 1.0;
	for (int j = 0; j < n_puff; j++) {
		vec4 p = puff[j];
		float dx = wm_wrap_tile(xl.x - p.x);
		float dy = wm_wrap_tile(xl.y - p.y);
		float r2 = dx * dx + dy * dy;
		float R2 = p.z * p.z;
		if (r2 <= R2) {
			m *= 1.0 + p.w * (1.0 - r2 / R2);
		}
	}
	return clamp(m, puff_cap_lo, puff_cap_hi);
}

// Scene-space vectors of the detail frame: downwind and across (to the left of downwind).
vec3 wm_scene(vec2 world_dir) {
	return vec3(world_dir.x, 0.0, -world_dir.y);
}

// Detail normal disturbance in the water plane (downwind, across) from the tiling normal map layers.
vec2 wm_detail(vec2 xl) {
	vec2 q = vec2(dot(xl, detail_dir), dot(xl, vec2(-detail_dir.y, detail_dir.x)));
	vec2 n = vec2(0.0);
	for (int k = 0; k < WM_DETAIL_LAYERS; k++) {
		vec4 L = detail_layer[k];
		vec2 uv = vec2(L.x * q.x - L.y * q.y, L.y * q.x + L.x * q.y) + L.zw;
		n += texture(detail_tex, uv).rg * 2.0 - 1.0;
	}
	return n * (1.0 / float(WM_DETAIL_LAYERS));
}

struct WmSurface {
	vec3 albedo;
	float roughness;
	float specular;
	vec3 emission;
	vec3 normal;       // scene axes, unit
	float m;           // puff factor
	float foam;        // whitecap foam opacity (§4.4), 0 without
};

// §4 shading inputs at a pixel. xl: camera-relative position; eta: height (after the exposure); n_geo: the
// geometric normal (scene axes); view: unit vector from the surface to the camera (scene axes); dist: horizontal
// distance to the camera, m; px: the pixel footprint, m; wake: wake normal disturbance (world east, north); land:
// the venue speed factor (wm_land, sampled per vertex).
WmSurface wm_surface(vec2 xl, float eta, vec3 n_geo, vec3 view, float dist, float px, vec2 wake, float land) {
	WmSurface S;
	float m = wm_puff_factor(xl) * land * land_factor;
	S.m = m;
	vec3 along = wm_scene(detail_dir);
	vec3 across = wm_scene(vec2(-detail_dir.y, detail_dir.x));
	vec2 q = vec2(dot(xl, detail_dir), dot(xl, vec2(-detail_dir.y, detail_dir.x)));

	// §4.1.1 wind roughness (Cox and Munk): the mean square slope of the sea at the local wind, split between the
	// sea's waves (geo_var), the detail and glint layers and the roughness (the short waves, and what the layers
	// lose with distance and mip-mapping)
	float wind = m * base_speed;
	float glassy = smoothstep(0.5, 1.5, wind);
	float sig_all = 0.003 + 0.00512 * wind;
	float sig_long = min(0.008 + 0.00156 * wind, sig_all);
	float sig_d = max(sig_long - geo_var, 0.3 * sig_long);
	float far_d = 1.0 - smoothstep(300.0, 3000.0, dist);
	float near = 1.0 - smoothstep(30.0, 200.0, dist);
	float k_detail = sqrt(0.6 * sig_d * float(WM_DETAIL_LAYERS) / detail_var) * far_d * glassy;
	float k_glint = sqrt(0.4 * sig_d / detail_var) * near * glassy;
	float pq = px * 4.0;   // px / 0.25 m
	float vis = (0.6 * far_d + 0.4 * near) / (1.0 + pq * pq);
	// the short waves (0.3 m down to the capillaries' 4 mm) are smaller than the pixel only in part near the camera:
	// with a saturated slope spectrum each octave carries the same slope, so the share under the pixel is
	// log(2 px / 4 mm) / log(0.3 m / 4 mm); the rest sparkles in the glint layer
	float sub = clamp(log(px * 500.0) * 0.2316, 0.0, 1.0);
	float sig_s = sig_all - sig_long;
	k_glint = sqrt((0.4 * sig_d + sig_s * (1.0 - sub)) / detail_var) * near * glassy;
	float sig_r = (sig_s * (1.0 - (1.0 - sub) * near) + sig_d * (1.0 - vis)) * glassy;
	// Godot's environment BRDF dims a rough surface's sky reflection toward grazing far more than a measured rough
	// sea (about half the calm reflectance near the horizon): lower the lighting's roughness toward grazing
	float gz = 1.0 - max(dot(n_geo, view), 0.0);
	float gz3 = gz * gz * gz;
	float rough = clamp(sqrt(sqrt(sig_r)) * (1.0 - 0.6 * gz3 * gz3), 0.035, 0.6);

	// §4.1 normal: the detail layers, and the fine glint layer near the camera (the sun's glitter)
	vec2 dn = wm_detail(xl);
	vec4 G = detail_layer[4];
	vec2 gn = texture(detail_tex, vec2(G.x * q.x - G.y * q.y, G.y * q.x + G.x * q.y) + G.zw).rg * 2.0 - 1.0;
	vec3 n = n_geo + k_detail * (dn.x * along + dn.y * across) + k_glint * (gn.x * along + gn.y * across);
	n += wake_strength * vec3(wake.x, 0.0, -wake.y);
	n = normalize(n);
	S.normal = n;

	// §4.2 colour
	float crest = clamp(eta / max(sum_a, 1e-3), 0.0, 1.0);
	vec3 albedo = mix(col_deep, col_shallow, 0.55 * crest);

	// §4.3 puffs darker, lulls brighter
	albedo *= 1.0 - 0.25 * puff_k * clamp((m - 1.0) / 0.25, 0.0, 1.0) + 0.15 * clamp((1.0 - m) / 0.4, 0.0, 1.0);

	// §4.2 a strong breeze greys and darkens the water's body colour (from 12 kn of local wind)
	float gw = smoothstep(12.0, 30.0, wind / WM_KNOT);
	albedo = mix(albedo, dot(albedo, vec3(0.2126, 0.7152, 0.0722)) * vec3(0.75, 0.82, 0.88), 0.45 * gw);

	// §4.4 whitecaps: wm_apply_caps, after this function (the sea surface only)

	// §4.2 light through the crests
	vec3 emission = col_sss * (1.0 - 0.35 * gw) * crest * (pow(max(0.0, dot(-view, sun_dir)), 3.0) * 0.3 * sun_color + 0.05);

	S.albedo = albedo;
	S.roughness = rough;
	S.specular = 0.40;   // Godot F0 = 0.16 * specular^2 = 0.026: water's 0.02 a little lifted
	S.emission = emission;
	S.foam = 0.0;
	return S;
}

#ifdef WM_WHITECAPS
// §4.4 whitecaps that ride the waves. The CPU picks the WM_CAPS_N components with the largest foam weight b (the
// tier's count; at most 6, heaviest first) and uploads per component the wave (kx, ky, d', b), every frame with the
// phase d' of comp, and the crest window (1/sigma_front, 1/sigma_back, window mean, wavelength), once per sea; b = 0
// for unused entries. The components left out count with their window mean (caps_rest, and the uploaded ones
// beyond the tier's count), so a tier with fewer loses some variation but not the mean. And the foam texture frame (e.x, e.y, u0, v0): the dominant wave's travel direction and the
// camera-origin part of the texture coordinates, drifting at its phase speed.
#ifndef WM_CAPS_N
#define WM_CAPS_N 6
#endif
uniform vec4 caps_k[6];
uniform vec4 caps_w[6];
uniform float caps_rest = 0.0;   // the components not uploaded, each at its window mean: sum of b * mean
uniform vec4 caps_uv = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 caps_thr = vec4(1e3);              // breaking thresholds calibrated at the covers 0.05, 0.2, 0.8, 3.2 %
uniform vec4 caps_grp = vec4(0.0, 0.5, 0.0, 0.0);   // wave-group envelope: (amplitude / noise sd, noise mean, ug, vg)
uniform vec2 caps_brk = vec2(0.0);                  // short-crest breakup frame (ub, vb)
uniform vec2 caps_str = vec2(0.0);                  // the trail's streak frame (us, vs)
uniform vec4 caps_seg = vec4(0.0);                  // the crest-segment frame (ug, vg), and over 8 tiles (zw)
uniform vec4 caps_ev = vec4(0.0, 0.0, 0.0, 3.5);    // (fract(t / T_ev), 1 / T_ev, c_p, residual e-folding time s)
uniform vec4 caps_res = vec4(0.0);                  // the residual foam's lace (xy) and erosion (zw) frames (drifting)
uniform float caps_drift = 0.0;                     // the surface drift along the dominant wave, m/s (3 % of the wind)
const vec2 WM_SEG_TILE = vec2(45.0, 120.0);
const vec2 WM_STREAK_TILE = vec2(14.0, 1.6);
const float WM_GROUP_TILE = 600.0;
const vec2 WM_BREAK_TILE = vec2(30.0, 15.0);
const vec2 WM_EVENT_TILE = vec2(270.0, 900.0);

const vec2 WM_CAPS_TILE = vec2(4.5, 3.0);     // m along e, across

// Foam intensity F in [0, 1]: the steepness-weighted crest windows of the components that pass a crest here,
// summed (crests meeting in a wave group make a cap), scaled by the wave-group envelope (the foam noise's coarse
// channel, drifting at the group speed) and the short-crest breakup, against the sea's threshold for the measured cover at the local wind (m/s).
// Components the pixel footprint px cannot show count with their window mean, so far caps never alias.
// §4.4 the breaking event of a patch: once per event period (T_ev = 0.9 T_p), at the patch's phase ph (event periods),
// for 0.4 T_p. Each point joins after its delay (0 to 0.06 periods from the local noise: the break starts at one point and spreads), rising
// over 0.15 periods (as long as the spread, so no sharp front rings a patch); the whole patch stops together, falling over the last 0.13 periods (an end by local phase left
// rings where the first points stopped while the later ones still broke), except that parts of it stop up to 0.22
// periods early (early, from metre-scale noise), so the end, and the foam it leaves, has a ragged outline.
float wm_caps_event(float ph, float delay, float early) {
	return smoothstep(delay, delay + 0.15, ph) * (1.0 - smoothstep(0.311 - early, 0.444 - early, ph));
}

// The breaking threshold S_b for the local wind (m/s): Monahan's cover W = 3.84e-6 U^3.41, x = log2(W / 0.0005) / 2
// indexes the calibrated thresholds.
float wm_caps_sb(float wind) {
	float x = 0.5 * log2(3.84e-6 * pow(max(wind, 0.1), 3.41) / 0.0005);
	return x < 1.0 ? mix(caps_thr.x, caps_thr.y, x) : (x < 2.0 ? mix(caps_thr.y, caps_thr.z, x - 1.0)
			: mix(caps_thr.z, caps_thr.w, x - 2.0));
}

// The breaking potential at the time tau seconds ago (tau >= 0) at a point: the steepness-weighted crest windows
// (each component's phase moved back by tau / T_j), times the short-crest breakup and the crest segments where they
// were then (they ride the crests at c_p), times the breaking event, times the group envelope env (slow: the current
// one). dm: the distance from the heaviest component's crest at that time, m (0 where unresolved).
float wm_caps_sum(vec2 xl, vec2 qd, float inv_px, float tau, float env, float wide, out float dm, out float ev_out) {
	dm = 0.0;
	float S = caps_rest;
	for (int i = WM_CAPS_N; i < 6; i++) {
		S += caps_k[i].w * caps_w[i].z;               // beyond the tier's count: the window mean
	}
	float back = caps_ev.z * tau;   // how far the crests have run since
	// the short-crest breakup (it also bends the shorter components' crests: straight crest lines drew straight foam
	// edges where they cut a cap)
	float bky = texture(foam_tex, qd / WM_BREAK_TILE + caps_brk + vec2(back / WM_BREAK_TILE.x, 0.0)).g;
	for (int i = 0; i < WM_CAPS_N; i++) {
		vec4 k = caps_k[i];
		vec4 w = caps_w[i];
		float f = fract(k.x * xl.x + k.y * xl.y + k.z + tau / sqrt(0.6405 * w.w)   // T = sqrt(2 pi lam / g)
				+ (i > 0 ? 0.5 * (bky - 0.5) : 0.0));
		float d = f - step(0.5, f);                        // cycles from the crest, ahead positive
		float q = d * (d >= 0.0 ? w.x : w.y);
		float r = smoothstep(2.0, 4.0, w.w * inv_px);
		if (wide > 0.0 && i > 0) {
			r = 0.0;   // the residual: the other crests at their mean (their coincidence lines swept along the wave
			           // read as streaks; the residual's own lace carries the detail)
		}
		// tapered to 0 at the trough: a broad back window cut there left a straight edge along the trough
		S += k.w * mix(w.z, exp(-q * q) * (1.0 - smoothstep(0.3, 0.5, abs(d))), r);
		if (i == 0) {
			dm = d * w.w * r;
		}
	}
	float brk = clamp((bky - 0.55) * 4.0, 0.0, 1.0);
	// the residual (wide > 0) takes the breakup's mean: the crest swept its fine detail into streaks along the wave
	brk = wide > 0.0 ? 0.6 : mix(0.6, 0.2 + 0.8 * brk, smoothstep(2.0, 4.0, 6.0 * inv_px));
	// crest segments
	vec2 sgt = texture(foam_tex, qd / WM_SEG_TILE + caps_seg.xy + vec2(back / WM_SEG_TILE.x, 0.0)).rg;
	float sgy = sgt.y;
	float rs = smoothstep(2.0, 4.0, 9.0 * inv_px);
	float seg = mix(0.45, clamp((sgy - 0.5) * 5.0, 0.0, 1.0), rs);
	// each breaking patch's event phase: smooth noise a few metres across, so an event starts at a point of the crest
	// and spreads along it (and the foam it leaves is a patch, not the fine noise swept into streaks)
	// (the segments' frame, another part of the noise)
	float pn = texture(foam_tex, qd / WM_SEG_TILE + caps_seg.xy + vec2(back / WM_SEG_TILE.x + 0.37, 0.61)).g;
	// the patch phase: a smooth field stretched across the crests (270 m along the wave, 900 m across): along a
	// crest it changes by about 0.01 periods per metre, so an event's edges are soft and no band of phase shows on a
	// cap, while from one crest to the next (0.03 per metre) it changes by most of a period, so neighbouring crests
	// do not break in step and the cover holds steady over any view
	// (warped by the local part: the contours of a slow field are nearly straight, and an event front along one
	// drew a straight edge)
	float pf = texture(foam_tex, qd / WM_EVENT_TILE + caps_seg.zw + vec2(back / WM_EVENT_TILE.x, 0.0)
			+ 0.02 * (pn - 0.5)).g;
	float ph = fract(caps_ev.x - tau * caps_ev.y + 2.0 * pf);
	// the point's delay (the break spreads from the lows of the local noise and of the breakup) and early end
	float dl = 0.06 * clamp((pn - 0.35) / 0.3, 0.0, 1.0) + 0.15 * clamp((bky - 0.3) / 0.4, 0.0, 1.0);
	float ee = 0.22 * clamp((sgt.x - 0.3) / 0.4, 0.0, 1.0);
	float evv = wm_caps_event(ph, dl, ee);
	if (wide > 0.0) {   // the foam a crest leaves: the event at any time within +- wide s of the crest's passing
		evv = max(evv, max(wm_caps_event(fract(ph + wide * caps_ev.y), dl, ee),
				wm_caps_event(fract(ph - wide * caps_ev.y), dl, ee)));
	}
	float ev = mix(0.15, evv, rs);
	ev_out = ev;
	return S * env * brk * seg;   // the steepness of the crests; the event gates the foam, not the steepness
}

// The group envelope at a point (qd: the point in the dominant wave's frame).
float wm_caps_env(vec2 qd) {
	return max(0.0, 1.0 + caps_grp.x * (texture(foam_tex, qd / WM_GROUP_TILE + caps_grp.zw).g - caps_grp.y));
}

// (x, dm, gate, ev): x = (S - S_b) / (0.35 S_b) before the clamp, dm the distance from the heaviest component's
// crest in metres (ahead positive; 0 where the pixel cannot resolve it), gate the wind gate (0: no caps), ev the
// breaking event's envelope now (the active foam's brightness follows it).
vec4 wm_caps_field(vec2 xl, float px, float expo, float wind) {
	float kn = wind / WM_KNOT;
	float gate = smoothstep(8.0, 10.0, kn);
	if (gate <= 0.0 || expo <= 0.0) {
		return vec4(-1e3, 0.0, 0.0, -1e3);
	}
	float inv_px = 1.0 / max(px, 1e-4);
	vec2 qd = vec2(dot(xl, caps_uv.xy), dot(xl, vec2(-caps_uv.y, caps_uv.x)));
	float dm;
	float ev;
	float S = wm_caps_sum(xl, qd, inv_px, 0.0, wm_caps_env(qd), 0.0, dm, ev) * expo;
	float Sb = wm_caps_sb(wind);
	float x = (S - Sb) / max(0.35 * Sb, 1e-6);   // S_W = 0.35 of the threshold
	return vec4(x, dm, gate, ev);
}

// The solid-white share of the active core: a thin band at the crest (the tumbling water), broken along its length
// by the streak noise and feathered at its edges; dense lace elsewhere.
float wm_caps_solid(float xj, float dm, float lam0, float st) {
	float band = dm == 0.0 ? 0.5 : (1.0 - smoothstep(0.0, 0.03 * lam0, -dm)) * (1.0 - smoothstep(0.0, 0.03 * lam0, dm));
	return smoothstep(1.5, 2.5, xj) * band * smoothstep(0.55, 0.75, st);
}

// The bubble glow's mix toward green-blue around a breaking cap (at most 0.1).
float wm_caps_glow(float near_cap, float behind, float ev, float lace) {
	return 0.1 * near_cap * behind * ev * ev * lace;
}

float wm_caps_intensity(vec2 xl, float px, float expo, float wind) {
	vec4 f = wm_caps_field(xl, px, expo, wind);
	return min(clamp(f.x, 0.0, 1.0), f.w) * f.z;
}

// The whitecaps on a shaded surface (after wm_surface): xl camera-relative position, px pixel footprint (m), expo
// the exposure, dist the horizontal distance to the camera, n_geo the geometric normal.
void wm_apply_caps(inout WmSurface S, vec2 xl, float px, float expo, float dist, vec3 n_geo) {
	float fade = 1.0 - smoothstep(1200.0, 2500.0, dist);
	if (fade <= 0.0) {
		return;
	}
	vec4 cf = wm_caps_field(xl, px, expo, S.m * base_speed);
	float g = cf.z * fade;
	if (g <= 0.0) {
		return;
	}
	float kn = S.m * base_speed / WM_KNOT;
	vec2 q = vec2(dot(xl, caps_uv.xy), dot(xl, vec2(-caps_uv.y, caps_uv.x)));
	// §4.4 residual foam (stage B): what the last two crests left here when they broke, staying where it fell (it
	// drifts with the surface, not with the crests) and decaying, eroding from the inside
	float resid = 0.0;
	float tau_r = 0.0;
	float lam0 = caps_w[0].w;
	float inv_px = 1.0 / max(px, 1e-4);
	if (dist < 400.0 && lam0 * inv_px > 4.0) {
		float T0 = sqrt(0.6405 * lam0);
		float d0 = cf.y / lam0;
		float tau0 = (d0 <= 0.0 ? -d0 : 1.0 - d0) * T0;   // since the heaviest component's crest passed here
		float env = wm_caps_env(q);
		float Sb = wm_caps_sb(S.m * base_speed);
		for (int n = 0; n < 2; n++) {
			float tau = tau0 + float(n) * T0;
			float dmd;
			float evd;
			// the foam here now fell where the crest broke, upwind by the drift since; the time since the crest passed
			// there (one fixed-point step: the drift is slow against the crest)
			vec2 xd = xl - caps_uv.xy * (caps_drift * tau);
			float fd = fract(caps_k[0].x * xd.x + caps_k[0].y * xd.y + caps_k[0].z);
			float dd = fd - step(0.5, fd);
			tau = (-dd + floor((tau + dd * T0) / T0 + 0.5)) * T0;   // the passing nearest the first guess
			xd = xl - caps_uv.xy * (caps_drift * tau);
			vec2 qd0 = vec2(dot(xd, caps_uv.xy), dot(xd, vec2(-caps_uv.y, caps_uv.x)));
			float A = min(clamp((wm_caps_sum(xd, qd0, inv_px, tau, env, 0.25, dmd, evd) * expo - Sb) / max(0.35 * Sb, 1e-6), 0.0, 1.0), evd);
			float r = A * A * exp(-tau / caps_ev.w) * smoothstep(0.0, 0.6, tau) * (1.0 - smoothstep(1.5 * T0, 2.0 * T0, tau))
					* (1.0 - smoothstep(300.0, 400.0, dist));
			if (r > resid) {
				resid = r;
				tau_r = tau;
			}
		}
	}
	if (cf.x <= -1.5 && resid <= 0.0) {
		return;
	}
	float st = texture(foam_tex, q / WM_STREAK_TILE + caps_str).r;
	vec4 L = texture(caps_tex, q / WM_CAPS_TILE + caps_uv.zw);
	float a = 0.0;
	if (resid > 0.0) {
		// thinning and fragmenting: the foam lace in the drift frame (it drifts and wanders, so it changes shape),
		// dense foam when young, then the lace net, then sparse fizz
		// and eroding: blobs a few metres across, a threshold rising with age, break the patch into fragments
		vec4 Lr = texture(caps_tex, q / vec2(5.0, 3.0) + caps_res.xy);
		float blob = texture(foam_tex, q / vec2(16.0, 10.0) + caps_res.zw).g;
		float age = 1.0 - exp(-tau_r / (2.0 * caps_ev.w));
		float u = 2.0 * age;
		float cov = u < 1.0 ? mix(Lr.b, Lr.g, u) : mix(Lr.g, Lr.r, u - 1.0);
		float th = 0.4 + 0.3 * age;
		a = 0.6 * resid * cov * smoothstep(th, th + 0.2, blob) * g;
	}
	if (cf.x > -1.5) {
		// active breaking (stage A): a bright core on the crest and its forward face, lacy edges
		float xj = cf.x + 1.2 * (L.g - 0.5);   // the lace rides the crest with the core
		float xs = xj;
		// the crest and its forward face, back to 0 before the trough: dm jumps from +lam/2 to -lam/2 there, and a
		// factor that differs on the two sides drew a straight edge along the trough
		float front = smoothstep(-4.0, -1.0, cf.y) * (1.0 - smoothstep(0.25 * lam0, 0.45 * lam0, cf.y));
		float behind = (1.0 - smoothstep(0.0, 1.5, cf.y)) * (cf.y == 0.0 ? 0.0 : smoothstep(-0.4 * lam0, -0.15 * lam0, cf.y));
		// the steep face ahead of a breaking crest is darker; the bubble cloud under and behind it glows
		float near_cap = smoothstep(-0.8, 0.4, xs) * smoothstep(0.0, 0.7, cf.w);   // around a cap that is breaking
		S.albedo *= 1.0 - 0.22 * near_cap * (1.0 - behind) * (1.0 - smoothstep(0.5, 3.0, cf.y)) * g;
		// a slight green-blue lift, broken like the foam, fading faster than the foam (ev squared)
		S.albedo = mix(S.albedo, vec3(0.05, 0.20, 0.23), wm_caps_glow(near_cap, behind, cf.w, L.b) * g);
		float core = smoothstep(0.0, 3.0, xj) * smoothstep(0.0, 0.7, cf.w) * front * g;
		// solid white only on the crest's front, the tumbling water; dense lace behind it
		float solid = wm_caps_solid(xj, cf.y, lam0, st);
		float dense = mix(L.g, L.b, smoothstep(2.0, 5.0, xj));   // the lace net at the edges, dense foam inside
		// only the thin solid band is fully opaque; the dense foam stays a little translucent (at most 0.85)
		a = max(a, clamp(core * mix(0.85 * dense, 0.95 * L.a, solid), 0.0, 1.0));
	}
	if (a <= 0.0) {
		return;
	}
	S.albedo = mix(S.albedo, col_foam, a);
	S.roughness = mix(S.roughness, 0.55, a);
	S.emission *= 1.0 - a;
	S.normal = normalize(mix(S.normal, n_geo, 0.6 * a));
	S.foam = a;
}
#endif

// §6 overlays: colour and coverage at a pixel; width grows with distance so lines stay visible.
vec4 wm_overlays(vec2 xl, float dist) {
	vec4 o = vec4(0.0);
	float grow = dist * ov_px_angle * 1.5;
	for (int i = 0; i < n_ov_line; i++) {
		vec4 L = ov_line[i];
		vec2 ab = L.zw - L.xy;
		float t = clamp(dot(xl - L.xy, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		float d = length(xl - (L.xy + t * ab));
		float w = max(ov_line_col[i].w, grow);
		float a = 1.0 - smoothstep(0.5 * w, 0.5 * w + max(grow, 0.05), d);
		o = mix(o, vec4(ov_line_col[i].rgb, 1.0), a);
	}
	for (int i = 0; i < n_ov_circle; i++) {
		vec4 C = ov_circle[i];
		float d = abs(length(xl - C.xy) - C.z);
		float w = max(ov_circle_col[i].w, grow);
		float a = 1.0 - smoothstep(0.5 * w, 0.5 * w + max(grow, 0.05), d);
		o = mix(o, vec4(ov_circle_col[i].rgb, 1.0), a);
	}
	return o;
}
