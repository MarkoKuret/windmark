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
	albedo *= 1.0 - 0.25 * clamp((m - 1.0) / 0.25, 0.0, 1.0) + 0.15 * clamp((1.0 - m) / 0.4, 0.0, 1.0);

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
const vec2 WM_STREAK_TILE = vec2(14.0, 1.6);
const float WM_GROUP_TILE = 600.0;
const vec2 WM_BREAK_TILE = vec2(30.0, 15.0);

const vec2 WM_CAPS_TILE = vec2(4.5, 3.0);     // m along e, across

// Foam intensity F in [0, 1]: the steepness-weighted crest windows of the components that pass a crest here,
// summed (crests meeting in a wave group make a cap), scaled by the wave-group envelope (the foam noise's coarse
// channel, drifting at the group speed) and the short-crest breakup, against the sea's threshold for the measured cover at the local wind (m/s).
// Components the pixel footprint px cannot show count with their window mean, so far caps never alias.
// (x, dm, gate): x = (S - S_b) / S_W before the clamp, dm the distance from the heaviest component's crest in metres
// (ahead positive; 0 where the pixel cannot resolve it), gate the wind gate (0: no caps).
vec3 wm_caps_field(vec2 xl, float px, float expo, float wind) {
	float kn = wind / WM_KNOT;
	float gate = smoothstep(8.0, 10.0, kn);
	if (gate <= 0.0 || expo <= 0.0) {
		return vec3(-1e3, 0.0, 0.0);
	}
	float dm = 0.0;
	float S = caps_rest;
	float inv_px = 1.0 / max(px, 1e-4);
	for (int i = WM_CAPS_N; i < 6; i++) {
		S += caps_k[i].w * caps_w[i].z;               // beyond the tier's count: the window mean
	}
	for (int i = 0; i < WM_CAPS_N; i++) {
		vec4 k = caps_k[i];
		vec4 w = caps_w[i];
		float f = fract(k.x * xl.x + k.y * xl.y + k.z);
		float d = f - step(0.5, f);                        // cycles from the crest, ahead positive
		float q = d * (d >= 0.0 ? w.x : w.y);
		float r = smoothstep(2.0, 4.0, w.w * inv_px);
		S += k.w * mix(w.z, exp(-q * q), r);
		if (i == 0) {
			dm = d * w.w * r;
		}
	}
	// the wave groups scale the crests' steepness, and the short-crest breakup lets only a few metres of each crest
	// break (multiplying: foam stays on the crests, never a sheet over a group)
	vec2 qd = vec2(dot(xl, caps_uv.xy), dot(xl, vec2(-caps_uv.y, caps_uv.x)));
	float env = max(0.0, 1.0 + caps_grp.x * (texture(foam_tex, qd / WM_GROUP_TILE + caps_grp.zw).g - caps_grp.y));
	float brk = clamp((texture(foam_tex, qd / WM_BREAK_TILE + caps_brk).g - 0.55) * 4.0, 0.0, 1.0);
	brk = mix(0.6, brk, smoothstep(2.0, 4.0, 6.0 * inv_px));
	S = S * expo * env * brk;
	// Monahan's cover W = 3.84e-6 U^3.41; x = log2(W / 0.0005) / 2 indexes the calibrated thresholds
	float x = 0.5 * log2(3.84e-6 * pow(max(wind, 0.1), 3.41) / 0.0005);
	float Sb = x < 1.0 ? mix(caps_thr.x, caps_thr.y, x) : (x < 2.0 ? mix(caps_thr.y, caps_thr.z, x - 1.0)
			: mix(caps_thr.z, caps_thr.w, x - 2.0));
	return vec3((S - Sb) * 28.5714, dm, gate);   // S_W = 0.035
}

float wm_caps_intensity(vec2 xl, float px, float expo, float wind) {
	vec3 f = wm_caps_field(xl, px, expo, wind);
	return clamp(f.x, 0.0, 1.0) * f.z;
}

// The whitecaps on a shaded surface (after wm_surface): xl camera-relative position, px pixel footprint (m), expo
// the exposure, dist the horizontal distance to the camera, n_geo the geometric normal.
void wm_apply_caps(inout WmSurface S, vec2 xl, float px, float expo, float dist, vec3 n_geo) {
	float fade = 1.0 - smoothstep(1200.0, 2500.0, dist);
	if (fade <= 0.0) {
		return;
	}
	vec3 cf = wm_caps_field(xl, px, expo, S.m * base_speed);
	float g = cf.z * fade;
	if (g <= 0.0) {
		return;
	}
	// the streak tap (R streaks, G their breakup), drifting with the surface: the trail's streaks and, between the
	// caps, wind-aligned foam lanes that thicken with the wind (§4.4)
	vec2 q = vec2(dot(xl, caps_uv.xy), dot(xl, vec2(-caps_uv.y, caps_uv.x)));
	vec2 stv = texture(foam_tex, q / WM_STREAK_TILE + caps_str).rg;
	float st = stv.x;
	float kn = S.m * base_speed / WM_KNOT;
	float dens = smoothstep(15.0, 32.0, kn);
	float a = 0.22 * dens * smoothstep(0.62, 0.82, st) * smoothstep(0.35, 0.7, stv.y) * fade;
	if (cf.x > -1.5) {
		// a breaking core on the crest and its forward face, lacy edges, a translucent streaky trail behind it
		vec4 L = texture(caps_tex, q / WM_CAPS_TILE + caps_uv.zw);
		float xj = cf.x + 1.2 * (L.g - 0.5) + 0.8 * (st - 0.5);
		float front = smoothstep(-4.0, -1.0, cf.y);
		// behind the crest, within the part of the wave's back a cap's foam trails over (never across the trough)
		float lam0 = caps_w[0].w;
		float behind = (1.0 - smoothstep(0.0, 1.5, cf.y)) * (cf.y == 0.0 ? 1.0 : smoothstep(-0.4 * lam0, -0.15 * lam0, cf.y));
		// the steep face ahead of a crest near breaking is darker; the bubble cloud under and behind it glows
		float near_cap = smoothstep(-0.8, 0.4, xj);
		S.albedo *= 1.0 - 0.22 * near_cap * (1.0 - behind) * (1.0 - smoothstep(0.5, 3.0, cf.y)) * g;
		S.albedo = mix(S.albedo, vec3(0.05, 0.20, 0.23), 0.35 * near_cap * behind * g);
		float core = smoothstep(0.0, 1.2, xj) * front * g;
		float trail = smoothstep(-1.0, 0.7, xj) * behind * smoothstep(0.3, 0.75, st) * g;
		float residual = 0.15 * smoothstep(12.0, 20.0, kn) * smoothstep(-1.5, -0.8, xj) * (1.0 - smoothstep(-0.8, 0.0, xj)) * behind
				* smoothstep(0.3, 0.75, st) * g;
		a = max(a, max(residual, clamp(0.95 * core * mix(L.b, L.a, smoothstep(1.0, 2.0, xj))
				+ 0.5 * trail * L.g * (1.0 - core), 0.0, 1.0)));
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
