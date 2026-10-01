// Sail livery (sail_visuals.md §11.2): the panel design and the sail numbers and insignia, in the flat plan of
// sail_cloth.gdshaderinc (included before this file). Included by shaders/sail.gdshader and the offline preview
// (tests/livery_preview.py); common subset of Godot's shading language and GLSL 4.1.
//
// Text frame: the reading axis sl_axis along the foot (tack to clew) and sl_up square to it toward the head,
// origin at the tack. The port layer reads along +sl_axis, the starboard layer along -sl_axis. Rows 0..2 of
// sl_box and sl_tex are the port stack, 3..5 the starboard stack: (centre along, centre up, half width, half
// height) in metres, and the text texture rectangle.

#include "res://shaders/livery_text.gdshaderinc"

uniform int sl_on = 0;
uniform int sl_layer_n = 0;                     // rows * cols: vertex indices from here are the starboard layer
uniform int sl_design = 0;                      // 0 plain, 1 bands, 2 head, 3 panels, 4 diagonal, 5 gores
uniform vec3 sl_c0 = vec3(0.0, 0.0, 0.0);       // design colours, linear
uniform vec3 sl_c1 = vec3(0.0, 0.0, 0.0);
uniform vec4 sl_dp = vec4(0.0, 0.0, 0.0, 0.0);  // design parameters
uniform vec2 sl_axis = vec2(1.0, 0.0);
uniform vec2 sl_up = vec2(0.0, 1.0);
uniform float sl_height = 10.0;                 // head above the foot along sl_up, m
uniform vec3 sl_text_color = vec3(0.0, 0.0, 0.0);
uniform int sl_rows = 0;
uniform vec4 sl_box[6];
uniform vec4 sl_tex[6];

// Text coverage of one side's stack (side 0 port, 1 starboard) at the plan point p.
float wm_sail_text(vec2 p, float side) {
	vec2 f = vec2(dot(p - cloth_tack, sl_axis), dot(p - cloth_tack, sl_up));
	float cov = 0.0;
	for (int k = 0; k < 3; k++) {
		if (k >= sl_rows) {
			break;
		}
		int r = side > 0.5 ? k + 3 : k;
		vec4 b = sl_box[r];
		if (b.z <= 0.0) {
			continue;
		}
		float qx = side > 0.5 ? (b.x + b.z - f.x) : (f.x - (b.x - b.z));
		vec2 q = vec2(qx / (2.0 * b.z), (b.y + b.w - f.y) / (2.0 * b.w));
		cov = max(cov, wm_text_cov(q, sl_tex[r]));
	}
	return cov;
}

// The cloth colour (linear) of the design at the plan point p; pid: the cloth panel index of wm_cloth.
vec3 wm_sail_design(vec3 base, vec2 p, float pid, float px) {
	vec2 f = vec2(dot(p - cloth_tack, sl_axis), dot(p - cloth_tack, sl_up));
	float hf = f.y / max(sl_height, 0.1);
	vec3 c = base;
	float luff = length(cloth_head - cloth_tack);
	if (sl_design == 1) {
		float hpx = px / max(sl_height, 0.1);
		c = mix(c, sl_c0, wm_lv_inside(sl_dp.x - hf, hpx));
		c = mix(c, sl_c1, wm_lv_inside(sl_dp.y - hf, hpx) * step(sl_dp.x, sl_dp.y) * step(0.5, sl_dp.z));
	} else if (sl_design == 2) {
		c = mix(c, sl_c0, wm_lv_inside(length(p - cloth_head) - sl_dp.x * luff, px));
		float rc = sl_dp.y * luff;
		float corner = max(wm_lv_inside(length(p - cloth_tack) - rc, px), wm_lv_inside(length(p - cloth_clew) - rc, px));
		c = mix(c, sl_c1, corner * step(1e-3, rc));
	} else if (sl_design == 3) {
		float n = max(sl_dp.x, 2.0);
		float k = mod(pid, n);
		c = k < 0.5 ? c : (k < 1.5 ? sl_c0 : sl_c1);
	} else if (sl_design == 4) {
		vec2 a = cloth_tack + (cloth_head - cloth_tack) * sl_dp.x;
		vec2 b = cloth_clew + (cloth_head_aft - cloth_clew) * sl_dp.y;
		vec2 dl = normalize(b - a);
		vec2 nl = vec2(-dl.y, dl.x);
		if (dot(cloth_head - a, nl) < 0.0) {
			nl = -nl;
		}
		float sd = dot(p - a, nl);
		c = mix(c, sl_c0, wm_lv_inside(-sd, px));
		c = mix(c, sl_c1, wm_lv_band(sd, 0.5 * sl_dp.z, px) * step(0.5, sl_dp.w));
	} else if (sl_design == 5) {
		vec2 q = p - cloth_head;
		vec2 t = normalize(cloth_tack - cloth_head);
		vec2 k = normalize(cloth_clew - cloth_head);
		float spread = acos(clamp(dot(t, k), -1.0, 1.0));
		float ang = acos(clamp(dot(normalize(q + vec2(1e-5, 0.0)), t), -1.0, 1.0));
		float g = floor(ang / max(spread / max(sl_dp.x, 1.0), 1e-3));
		float m = mod(g, max(sl_dp.y, 2.0));
		c = m < 0.5 ? c : (m < 1.5 ? sl_c0 : sl_c1);
	}
	return c;
}
