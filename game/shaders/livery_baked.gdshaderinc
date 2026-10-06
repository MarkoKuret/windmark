// Baked liveries (data_format.md §8.5, sail_visuals.md §11.2): what boat_atlas.gdshader and sail_baked.gdshader
// share, and the offline preview (tests/livery_preview.py) compiles too: normal mapping without mesh tangents, and
// the per-boat overlay of the boat's name and sail number from its text texture (livery_text.gdshaderinc, included
// before this file), one texture sample per side. Common subset of Godot's shading language and GLSL 4.1.

// ---- hull: the boat name aft and the sail number forward, as cut vinyl in the generator's livery panels
uniform int ov_on = 0;
uniform vec3 ov_color = vec3(0.8, 0.8, 0.8);    // linear
// text boxes on the uv1 atlas (u0, v0, u1, v1) and their rectangles in the text texture: 0 starboard name,
// 1 starboard number, 2 port name, 3 port number
uniform vec4 ov_box[4];
uniform vec4 ov_tex[4];

// ---- sails: the nation letters and the sail number in the slots of the class's sail layout
uniform int sn_rows = 0;                        // rows per side, top down (0 to 2)
uniform vec2 sn_axis = vec2(1.0, 0.0);          // reading axis along the foot, in the flat plan
uniform vec2 sn_up = vec2(0.0, 1.0);
uniform vec2 sn_tack = vec2(0.0, 0.0);
uniform vec3 sn_color = vec3(0.0, 0.0, 0.0);    // linear
// boxes (centre along, centre up, half width, half height), m from the tack: rows 0, 1 port, 2, 3 starboard
uniform vec4 sn_box[4];
uniform vec4 sn_tex[4];

// A tangent-space normal from a normal map's texel c: x and y from red and green, z rebuilt. Godot imports a texture
// sampled with hint_normal as two-channel RGTC, whose blue reads 0, so the blue channel is never used.
vec3 wm_normal_texel(vec3 c) {
	vec2 xy = c.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Perturbs the unit normal n by the tangent-space normal m (OpenGL convention in an image's own axes) sampled at
// the texture coordinates uv, p the position (both in one space): the tangent and bitangent are the surface
// gradients of uv from screen-space derivatives (Mikkelsen 2010), so the mesh needs no tangents. up_sign: +1 when
// the image's top lies toward +uv.y, -1 when toward -uv.y.
vec3 wm_perturb(vec3 n, vec3 p, vec2 uv, vec3 m, float up_sign) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 du1 = dFdx(uv);
	vec2 du2 = dFdy(uv);
	vec3 r1 = cross(dp2, n);
	vec3 r2 = cross(n, dp1);
	float s = dot(dp1, r1) < 0.0 ? -1.0 : 1.0;
	vec3 gu = (r1 * du1.x + r2 * du2.x) * s;
	vec3 gv = (r1 * du1.y + r2 * du2.y) * (s * up_sign);
	vec3 t = gu * inversesqrt(max(dot(gu, gu), 1e-30));
	vec3 b = gv * inversesqrt(max(dot(gv, gv), 1e-30));
	return normalize(m.x * t + m.y * b + max(m.z, 0.05) * n);
}

// The raw text coverage (0..1, filtered) at the box coordinates q and its sharpened coverage (x), for an edge line.
vec2 wm_text_cov2(vec2 q, vec4 rect) {
	vec2 qc = clamp(q, vec2(0.0), vec2(1.0));
	float c = texture(livery_text, mix(rect.xy, rect.zw, qc)).r;
	float w = max(fwidth(c), 1e-3);
	float s = clamp((c - 0.5) / (2.0 * w) + 0.5, 0.0, 1.0);
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	return vec2(mix(s, c, clamp(2.0 * w - 0.5, 0.0, 1.0)) * inside, c * inside);
}

// The name or number on the hull at the atlas point uv2: (coverage, edge band of the vinyl), one sample.
vec2 wm_ov_hull(vec2 uv2) {
	int k = uv2.y < 0.5 ? (uv2.x < 0.5 ? 0 : 1) : (uv2.x > 0.5 ? 2 : 3);
	vec4 b = ov_box[k];
	vec2 q = (uv2 - b.xy) / max(b.zw - b.xy, vec2(1e-6));
	vec2 c = wm_text_cov2(q, ov_tex[k]);
	return vec2(c.x, c.y * (1.0 - c.y) * 4.0);
}

// The sail number rows of one side (0 port, 1 starboard) at the flat plan point p: (coverage, edge band). The row is
// picked by height (the rows of a stack never overlap), so one sample.
vec2 wm_sn_cov(vec2 p, float side) {
	if (sn_rows == 0) {
		return vec2(0.0);
	}
	vec2 f = vec2(dot(p - sn_tack, sn_axis), dot(p - sn_tack, sn_up));
	int base = side > 0.5 ? 2 : 0;
	int r = base;
	if (sn_rows > 1 && f.y < sn_box[base].y - sn_box[base].w) {
		r = base + 1;
	}
	vec4 b = sn_box[r];
	float qx = side > 0.5 ? (b.x + b.z - f.x) : (f.x - (b.x - b.z));
	vec2 q = vec2(qx / max(2.0 * b.z, 1e-4), (b.y + b.w - f.y) / max(2.0 * b.w, 1e-4));
	vec2 c = wm_text_cov2(q, sn_tex[r]);
	return vec2(c.x, c.y * (1.0 - c.y) * 4.0);
}
