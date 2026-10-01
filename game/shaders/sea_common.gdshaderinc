// Water surface functions shared by the sea shaders (water_l/m/h.gdshader) and the offline preview renderer
// (tests/water_preview.py): water_render.md §3 and §4. Written in the common subset of Godot's shading language
// and GLSL 3.30: explicit float literals, no Godot built-ins, no uniform hints. The including file declares
// `TIER` (1 = L, 2 = M, 3 = H) and the samplers `expo_tex`, `land_tex`, `detail_tex`, `foam_tex`, `wake_tex` first.
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
uniform vec4 puff[10];                 // (px - ox, py - oy, R, e*s), unwrapped centres
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
uniform vec4 detail_layer[4];
uniform vec4 foam_layer = vec4(0.0);        // streaks: offset (u, v); breakup: offset (u, v)
uniform float wake_extent = 400.0;          // m, side of the camera-centred wake normal buffer
uniform float wake_strength = 0.0;          // 0 when the buffer is off (tier L)

// sky ramp and sun (the sky preset sets them)
uniform vec3 sky_horizon = vec3(0.60, 0.72, 0.85);
uniform vec3 sky_zenith = vec3(0.12, 0.30, 0.62);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.866);      // scene axes, toward the sun
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);

// §4.2 colours (linear)
uniform vec3 col_deep = vec3(0.010, 0.048, 0.085);
uniform vec3 col_shallow = vec3(0.02, 0.11, 0.14);
uniform vec3 col_sss = vec3(0.04, 0.40, 0.38);
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

// Two-colour horizon-to-zenith ramp of the sky (scene axes, y up); matches sky_common's base gradient.
vec3 wm_sky_ramp(vec3 d) {
	float h = clamp(d.y, 0.0, 1.0);
	return mix(sky_horizon, sky_zenith, pow(h, 0.45));
}

float wm_schlick(float cos_t) {
	float k = 1.0 - clamp(cos_t, 0.0, 1.0);
	return 0.02 + 0.98 * k * k * k * k * k;
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
	float foam;
	float m;           // puff factor
};

// §4 shading inputs at a pixel. xl: camera-relative position; eta: height (after the exposure); n_geo: the
// geometric normal (scene axes); view: unit vector from the surface to the camera (scene axes); dist: horizontal
// distance to the camera, m; wake: wake normal disturbance (world east, north); land: the venue speed factor
// (wm_land, sampled per vertex).
WmSurface wm_surface(vec2 xl, float eta, vec3 n_geo, vec3 view, float dist, vec2 wake, float land) {
	WmSurface S;
	float m = wm_puff_factor(xl) * land * land_factor;
	S.m = m;
	vec3 along = wm_scene(detail_dir);
	vec3 across = wm_scene(vec2(-detail_dir.y, detail_dir.x));

	// §4.1 normal
	float wind = m * base_speed;
	float glassy = smoothstep(0.5, 1.5, wind);
	float k_detail = 0.25 * clamp(wind / 7.2, 0.15, 1.6) * (1.0 - smoothstep(300.0, 3000.0, dist)) * glassy;
	vec2 dn = wm_detail(xl);
	vec3 n = n_geo + k_detail * (dn.x * along + dn.y * across);
	n += wake_strength * vec3(wake.x, 0.0, -wake.y);
	n = normalize(n);
	S.normal = n;

	// §4.2 colour, roughness
	float crest = clamp(eta / max(sum_a, 1e-3), 0.0, 1.0);
	vec3 albedo = mix(col_deep, col_shallow, 0.55 * crest);
	float fade_far = smoothstep(500.0, 4000.0, dist);
	float rough = 0.06 + 0.05 * clamp(m - 1.0, -0.4, 0.25) / 0.25 + 0.18 * fade_far;

	// §4.3 puffs darker, lulls brighter
	albedo *= 1.0 - 0.25 * clamp((m - 1.0) / 0.25, 0.0, 1.0) + 0.15 * clamp((1.0 - m) / 0.4, 0.0, 1.0);

	// §4.4 whitecaps
	float tws_kn = wind / WM_KNOT;
	float caps = smoothstep(8.0, 24.0, tws_kn);
	vec2 qs = vec2(dot(xl, detail_dir), dot(xl, vec2(-detail_dir.y, detail_dir.x)));
	float n1 = texture(foam_tex, qs * vec2(1.0 / 23.0, 1.0 / 5.0) + foam_layer.xy).r;
	float n2 = texture(foam_tex, qs * (1.0 / 61.0) + foam_layer.zw).g;
	// covers about 0.2 % of the sea at 15 kn, 1.4 % at 20 kn, 2.5 % at 25 kn (near the measured whitecap cover)
	float th = 0.62 - 0.30 * caps;
	float foam = smoothstep(th, th + 0.1, crest * (0.45 + 0.75 * n1)) * smoothstep(0.25, 0.65, n2) * (0.2 + 0.8 * caps);
	foam *= 1.0 - smoothstep(900.0, 1300.0, dist);
	foam = clamp(foam, 0.0, 1.0);
	albedo = mix(albedo, col_foam, 0.8 * foam);
	rough = mix(rough, 0.65, foam);
	S.foam = foam;

	// §4.2 light through the crests, and the zero-mean slope contrast
	vec3 emission = col_sss * crest * pow(max(0.0, dot(-view, sun_dir)), 3.0) * 0.3 * sun_color + col_sss * crest * 0.05;
	vec3 r_n = reflect(-view, n);
	vec3 r_up = reflect(-view, vec3(0.0, 1.0, 0.0));
	float F = wm_schlick(dot(view, n));
	emission += (wm_sky_ramp(r_n) - wm_sky_ramp(r_up)) * F * (1.0 - foam);

	S.albedo = albedo;
	S.roughness = rough;
	S.specular = 0.35;   // Godot F0 = 0.16 * specular^2 = 0.02, water at normal incidence
	S.emission = max(emission, vec3(0.0));
	return S;
}

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
