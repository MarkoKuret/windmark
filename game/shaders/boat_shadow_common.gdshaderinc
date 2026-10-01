// Drawn boat shadows on the water (water_render.md §4.7), shared by boat_shadow.gdshader and the offline preview
// (tests/water_preview.py). Include after sea_common.gdshaderinc. Same subset of the shading language as
// sea_common: explicit float literals, no Godot built-ins, no uniform hints.
//
// One boat per material: its casters' shadows as convex polygons on the horizontal plane at the boat's heave,
// each kept as edge lines (n, c) in the scene's (x, z) relative to `shadow_origin`, inside where n . r - c <= 0
// for every edge.

const float WM_SHADOW_PI = 3.14159265;
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

uniform vec3 shadow_origin = vec3(0.0);        // scene: the boat's (x, z) and its heave y0 (the plane)
uniform vec3 shadow_sun = vec3(0.0, 1.0, 0.0);  // scene, unit, toward the sun
uniform int shadow_n_poly = 0;
uniform vec4 shadow_poly[8];      // (end edge index, half penumbra m, 0, 0)
uniform vec4 shadow_bound[8];     // (cx, cz, radius, 0): a circle around the polygon, relative to the origin
uniform vec4 shadow_plane[96];    // (nx, nz, c, 0)
uniform int shadow_n_excl = 0;    // edges of the hull footprint (water under the hull is never darkened)
uniform vec4 shadow_excl[40];
uniform float shadow_strength = 1.0;   // the distance fade

// Shadow coverage 0..1 at the water point P (scene), px: the pixel footprint on the water, m.
float wm_boat_shadow(vec3 P, float px) {
	vec2 q = P.xz - shadow_origin.xz;
	vec2 r = q + shadow_sun.xz * ((shadow_origin.y - P.y) / max(shadow_sun.y, 0.05));
	float s = 0.0;
	int k = 0;
	for (int i = 0; i < shadow_n_poly; i++) {
		int j_end = int(shadow_poly[i].x + 0.5);
		float f = shadow_poly[i].y + px;
		vec4 b = shadow_bound[i];
		if (length(r - b.xy) - b.z < f) {
			float d = -1.0e6;
			for (int j = k; j < j_end; j++) {
				vec4 e = shadow_plane[j];
				d = max(d, dot(e.xy, r) - e.z);
			}
			s = max(s, 1.0 - smoothstep(-f, f, d));
		}
		k = j_end;
	}
	if (s > 0.0 && shadow_n_excl > 0) {
		float d = -1.0e6;
		for (int j = 0; j < shadow_n_excl; j++) {
			vec4 e = shadow_excl[j];
			d = max(d, dot(e.xy, q) - e.z);
		}
		s *= smoothstep(-0.04, 0.0, d);
	}
	return s * shadow_strength;
}

// The share of the water's light a real shadow keeps (§4.7): the sky reflection, the sky's diffuse light and the
// light through the crests stay, the sun's diffuse share and its glitter (GGX on a level surface with a lobe as
// wide as the wave and detail slopes) go. V: toward the camera, L: toward the sun (scene, unit).
vec3 wm_shadow_keep(vec3 V, vec3 L) {
	float nv = max(V.y, 0.02);
	float nl = max(L.y, 0.0);
	float fe = wm_schlick(nv);
	vec3 refl = wm_sky_ramp(vec3(-V.x, V.y, -V.z)) * fe;
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
	float F = wm_schlick(max(dot(L, H), 0.0));
	vec3 sun = sun_color * nl * (a_w * (1.0 - F) + WM_SHADOW_GLINT_K * WM_SHADOW_PI * D * vis * F);
	vec3 stay = refl + amb + e;
	return stay / max(stay + sun, vec3(1.0e-4));
}
