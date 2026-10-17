// Sail panel designs (data_format.md §8.3) in a sail's flat plan: the cloth colour of a design at a plan point.
// Shared by the procedural sails (sail_livery.gdshaderinc) and the baked sails of a tinted livery
// (sail_baked.gdshader, §8.5), and compiled by the offline preview (tests/livery_preview.py). Needs wm_lv_inside and
// wm_lv_band (livery_text.gdshaderinc, included before this file); common subset of Godot's shading language and
// GLSL 4.1.
//   base: the cloth colour (linear); p: the plan point; pid: the cloth panel index of wm_cloth (0 when the sail
//   carries none: `panels` then draws plain); px: the pixel footprint in the plan (m); tack, clew, head, head_aft:
//   the plan corners; axis, up: the reading frame, along the foot and square to it toward the head, from the tack;
//   height: the head above the foot along up (m); design: 0 plain, 1 bands, 2 head, 3 panels, 4 diagonal,
//   5 gores; c0, c1: the design colours (linear); dp: the design's parameters (sail_livery.gdshaderinc).
vec3 wm_design(vec3 base, vec2 p, float pid, float px, vec2 tack, vec2 clew, vec2 head, vec2 head_aft, vec2 axis,
		vec2 up, float height, int design, vec3 c0, vec3 c1, vec4 dp) {
	vec2 f = vec2(dot(p - tack, axis), dot(p - tack, up));
	float hf = f.y / max(height, 0.1);
	vec3 c = base;
	float luff = length(head - tack);
	if (design == 1) {
		float hpx = px / max(height, 0.1);
		c = mix(c, c0, wm_lv_inside(dp.x - hf, hpx));
		c = mix(c, c1, wm_lv_inside(dp.y - hf, hpx) * step(dp.x, dp.y) * step(0.5, dp.z));
	} else if (design == 2) {
		c = mix(c, c0, wm_lv_inside(length(p - head) - dp.x * luff, px));
		float rc = dp.y * luff;
		float corner = max(wm_lv_inside(length(p - tack) - rc, px), wm_lv_inside(length(p - clew) - rc, px));
		c = mix(c, c1, corner * step(1e-3, rc));
	} else if (design == 3) {
		float n = max(dp.x, 2.0);
		float k = mod(pid, n);
		c = k < 0.5 ? c : (k < 1.5 ? c0 : c1);
	} else if (design == 4) {
		vec2 a = tack + (head - tack) * dp.x;
		vec2 b = clew + (head_aft - clew) * dp.y;
		vec2 dl = normalize(b - a);
		vec2 nl = vec2(-dl.y, dl.x);
		if (dot(head - a, nl) < 0.0) {
			nl = -nl;
		}
		float sd = dot(p - a, nl);
		c = mix(c, c0, wm_lv_inside(-sd, px));
		c = mix(c, c1, wm_lv_band(sd, 0.5 * dp.z, px) * step(0.5, dp.w));
	} else if (design == 5) {
		vec2 q = p - head;
		vec2 t = normalize(tack - head);
		vec2 k = normalize(clew - head);
		float spread = acos(clamp(dot(t, k), -1.0, 1.0));
		float ang = acos(clamp(dot(normalize(q + vec2(1e-5, 0.0)), t), -1.0, 1.0));
		float g = floor(ang / max(spread / max(dp.x, 1.0), 1e-3));
		float m = mod(g, max(dp.y, 2.0));
		c = m < 0.5 ? c : (m < 1.5 ? c0 : c1);
	}
	return c;
}
