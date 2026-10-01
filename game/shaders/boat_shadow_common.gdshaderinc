// Drawn boat shadows on the water (water_render.md §4.7), shared by boat_shadow.gdshader and the offline preview
// (tests/water_preview.py). Include after sea_common.gdshaderinc. Same subset of the shading language as
// sea_common: explicit float literals, no Godot built-ins, no uniform hints. The including file declares the
// sampler `shadow_tex` first.
//
// Every boat's shadow is one row of `shadow_tex` (RGBA32F, BoatShadows.ROW_WIDTH texels, read with texelFetch):
//   0                 (origin x, y0, origin z, strength): the boat's (x, z) and its heave (the plane), the fade
//   1                 (sun x, y, z, polygons): toward the sun (scene, unit), the polygon count
//   2                 (footprint edges, 0, 0, 0)
//   WM_SH_POLY + i    (end edge index, half penumbra m, 0, 0) of polygon i (at most 8)
//   WM_SH_BOUND + i   (cx, cz, radius, 0): a circle around polygon i, relative to the origin
//   WM_SH_PLANE + j   (nx, nz, c, 0): edge line j, inside where n . r - c <= 0 (at most 96)
//   WM_SH_EXCL + j    the hull footprint's edge lines (at most 40): water under the hull is never darkened
// The casters' shadows are convex polygons on the horizontal plane at the boat's heave, in the scene's (x, z)
// relative to the origin.

const float WM_SHADOW_PI = 3.14159265;
const int WM_SH_POLY = 3;
const int WM_SH_BOUND = 11;
const int WM_SH_PLANE = 19;
const int WM_SH_EXCL = 115;
// fitted against the real shadow of the offline preview (water_render.md §4.7): the water albedo scale (it stands
// for crests and foam), the glitter lobe width (GGX alpha) and its weight
#ifndef WM_SHADOW_ALBEDO_K
#define WM_SHADOW_ALBEDO_K 1.3
#endif
#ifndef WM_SHADOW_GLINT_K
#define WM_SHADOW_GLINT_K 0.1
#endif
#ifndef WM_SHADOW_GLINT
#define WM_SHADOW_GLINT 0.3
#endif

vec4 wm_shadow_texel(int row, int i) {
	return texelFetch(shadow_tex, ivec2(i, row), 0);
}

// The sun direction of a boat's row (scene, unit, toward the sun).
vec3 wm_shadow_sun(int row) {
	return wm_shadow_texel(row, 1).xyz;
}

// Shadow coverage 0..1 at the water point P (scene) for the boat of `row`; px: the pixel footprint on the water, m.
float wm_boat_shadow(vec3 P, float px, int row) {
	vec4 o = wm_shadow_texel(row, 0);
	vec4 sun = wm_shadow_texel(row, 1);
	vec2 q = P.xz - o.xz;
	vec2 r = q + sun.xz * ((o.y - P.y) / max(sun.y, 0.05));
	float s = 0.0;
	int k = WM_SH_PLANE;
	int n_poly = int(sun.w + 0.5);
	for (int i = 0; i < n_poly; i++) {
		vec4 pl = wm_shadow_texel(row, WM_SH_POLY + i);
		int j_end = WM_SH_PLANE + int(pl.x + 0.5);
		float f = pl.y + px;
		vec4 b = wm_shadow_texel(row, WM_SH_BOUND + i);
		if (length(r - b.xy) - b.z < f) {
			float d = -1.0e6;
			for (int j = k; j < j_end; j++) {
				vec4 e = wm_shadow_texel(row, j);
				d = max(d, dot(e.xy, r) - e.z);
			}
			s = max(s, 1.0 - smoothstep(-f, f, d));
		}
		k = j_end;
	}
	int n_excl = int(wm_shadow_texel(row, 2).x + 0.5);
	if (s > 0.0 && n_excl > 0) {
		float d = -1.0e6;
		for (int j = 0; j < n_excl; j++) {
			vec4 e = wm_shadow_texel(row, WM_SH_EXCL + j);
			d = max(d, dot(e.xy, q) - e.z);
		}
		s *= smoothstep(-0.04, 0.0, d);
	}
	return s * o.w;
}


// Sky colour seen in direction d (scene, unit), the horizon-to-zenith ramp of the sky uniforms: the reflected light a
// shadow leaves on the water (the sea itself reflects Godot's sky, which this approximates)
vec3 wm_shadow_sky(vec3 d) {
	float h = clamp(d.y, 0.0, 1.0);
	return mix(sky_horizon, sky_zenith, pow(h, 0.45));
}


// Schlick Fresnel of the water surface: F0 0.026 as the sea shader's specular 0.40 (water_render.md §4.2)
float wm_shadow_schlick(float cos_t) {
	float k = 1.0 - clamp(cos_t, 0.0, 1.0);
	return 0.026 + 0.974 * k * k * k * k * k;
}


// The share of the water's light a real shadow keeps (§4.7): the sky reflection, the sky's diffuse light and the
// light through the crests stay, the sun's diffuse share and its glitter (GGX on a level surface with a lobe as
// wide as the wave and detail slopes) go. V: toward the camera, L: toward the sun (scene, unit).
vec3 wm_shadow_keep(vec3 V, vec3 L) {
	float nv = max(V.y, 0.02);
	float nl = max(L.y, 0.0);
	float fe = wm_shadow_schlick(nv);
	vec3 refl = wm_shadow_sky(vec3(-V.x, V.y, -V.z)) * fe;
	vec3 a_w = mix(col_deep, col_shallow, 0.2) * WM_SHADOW_ALBEDO_K;
	vec3 amb = a_w * mix(sky_horizon, sky_zenith, 0.5) * (1.0 - fe);
	vec3 e = 0.02 * col_sss;
	vec3 H = normalize(L + V);
	float nh = max(H.y, 0.0);
	float a = WM_SHADOW_GLINT;
	float a2 = a * a;
	float dd = nh * nh * (a2 - 1.0) + 1.0;
	float D = a2 / (WM_SHADOW_PI * dd * dd);
	float kv = a * 0.5;
	float vis = 0.25 / ((nl * (1.0 - kv) + kv) * (nv * (1.0 - kv) + kv));
	float F = wm_shadow_schlick(max(dot(L, H), 0.0));
	vec3 sun = sun_color * nl * (a_w * (1.0 - F) + WM_SHADOW_GLINT_K * WM_SHADOW_PI * D * vis * F);
	vec3 stay = refl + amb + e;
	return stay / max(stay + sun, vec3(1.0e-4));
}
