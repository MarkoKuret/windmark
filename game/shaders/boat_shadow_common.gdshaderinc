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

const int WM_SH_POLY = 3;
const int WM_SH_BOUND = 11;
const int WM_SH_PLANE = 19;
const int WM_SH_EXCL = 115;

vec4 wm_shadow_texel(int row, int i) {
	return texelFetch(shadow_tex, ivec2(i, row), 0);
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


// §4.7: the share of the water's light a shadow on it keeps, matched in the engine to tier H's real shadow
uniform vec3 shadow_keep = vec3(0.76, 0.66, 0.70);
