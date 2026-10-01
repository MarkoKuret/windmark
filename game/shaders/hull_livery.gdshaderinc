// Hull livery (data_format.md §8) on the topsides gelcoat: colour, graphic, boat name and sail number, in the
// generator's uv1 hull atlas (Godot's UV2: starboard in v 0..0.5, port in 0.5..1, sheer at the top of each band, u
// along the length so text reads left to right on both sides). Included by shaders/boat.gdshader and the offline
// preview (tests/livery_preview.py); common subset of Godot's shading language and GLSL 4.1.
//
// Topsides coordinates: x = fraction of the hull length from the stern, d = metres below the sheer, t = d over the
// topsides height at x (0 at the sheer, 1 at the top of the boot stripe). The sheer and the boot stripe top are
// given per class as the band's v at 17 stations (BoatLivery.hull_geometry, from the imported hull).

#include "res://shaders/livery_text.gdshaderinc"

uniform int hl_on = 0;
uniform float hl_sheer[17];
uniform float hl_boot[17];
uniform float hl_vm = 3.0;                      // metres of girth per unit of band v
uniform float hl_len = 7.0;                     // hull length, m
uniform vec3 hl_top = vec3(0.7, 0.7, 0.7);      // topsides colour, linear
uniform int hl_graphic = 0;                     // 0 none, 1 stripes, 2 two_tone, 3 swoosh, 4 gradient, 5 bow
uniform vec3 hl_c0 = vec3(0.0, 0.0, 0.0);
uniform vec3 hl_c1 = vec3(0.0, 0.0, 0.0);
uniform vec4 hl_p = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 hl_q = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec3 hl_text_color = vec3(0.0, 0.0, 0.0);
uniform vec4 hl_name_panel = vec4(0.0, 0.0, 0.0, 0.0);   // x0, d0, x1, d1 (x fractions, m below the sheer)
uniform vec4 hl_name_box = vec4(0.0, 0.0, 1.0, 1.0);     // the text box in the panel (s0, t0, s1, t1)
uniform vec4 hl_name_tex = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 hl_num_panel = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 hl_num_box = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 hl_num_tex = vec4(0.0, 0.0, 0.0, 0.0);

float wm_hl_sheer(float x) {
	float r = clamp(x, 0.0, 1.0) * 16.0;
	int i = int(min(floor(r), 15.0));
	return mix(hl_sheer[i], hl_sheer[i + 1], r - float(i));
}

float wm_hl_boot(float x) {
	float r = clamp(x, 0.0, 1.0) * 16.0;
	int i = int(min(floor(r), 15.0));
	return mix(hl_boot[i], hl_boot[i + 1], r - float(i));
}

// Text in a panel (x0, d0, x1, d1): s runs left to right as seen from the side (aft to fwd on starboard).
float wm_hl_text(float x, float d, float port, vec4 panel, vec4 box, vec4 rect) {
	float s = mix((x - panel.x) / (panel.z - panel.x), (panel.z - x) / (panel.z - panel.x), port);
	float t = (d - panel.y) / (panel.w - panel.y);
	vec2 q = (vec2(s, t) - box.xy) / (box.zw - box.xy);
	return wm_text_cov(q, rect);
}

// The topsides colour (linear, before the gelcoat's texture detail) at the hull uv1 `uv2`; port: 1 on the port
// side (model +X), 0 on starboard (the side, not uv2.y, decides: the port sheer meets v = 0.5 amidships).
vec3 wm_hull_livery(vec2 uv2, float port) {
	float x = mix(uv2.x, 1.0 - uv2.x, port);
	float vv = uv2.y - 0.5 * port;
	float sh = wm_hl_sheer(x);
	float d = (vv - sh) * hl_vm;
	float th = max((wm_hl_boot(x) - sh) * hl_vm, 0.05);
	float t = d / th;
	float pd = max(fwidth(d), 1e-4);
	float pxm = max(fwidth(x) * hl_len, 1e-4);
	vec3 c = hl_top;
	if (hl_graphic == 1) {
		// stripes along the sheer, ends cut leaning aft
		float lean = d / hl_len;
		float span = wm_lv_inside(hl_q.x - lean - x, pxm / hl_len) * wm_lv_inside(x - (hl_q.y - lean), pxm / hl_len);
		c = mix(c, hl_c0, wm_lv_band(d - hl_p.x, 0.5 * hl_p.y, pd) * span);
		c = mix(c, hl_c1, wm_lv_band(d - hl_p.z, 0.5 * hl_p.w, pd) * span * step(1e-4, hl_p.w));
	} else if (hl_graphic == 2) {
		// two-tone: below the split line, with a pinstripe on it
		float ds = (hl_p.x + hl_p.y * (x - 0.5)) * th;
		c = mix(c, hl_c0, wm_lv_inside(ds - d, pd));
		c = mix(c, hl_c1, wm_lv_band(d - ds, 0.5 * hl_p.z, pd));
	} else if (hl_graphic == 3) {
		// swoosh: a band low aft that rises ever steeper toward the bow, tapering, an edge line above it
		float s = (x - hl_p.x) / max(hl_p.z - hl_p.x, 1e-3);
		float sc = clamp(s, 0.0, 1.0);
		float e = pow(sc, 2.2);
		float dc = mix(hl_p.y, hl_p.w, e) * th;
		float w = mix(hl_q.x, hl_q.y, sc) * smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.97, 1.0, s));
		float inx = step(0.0, s) * step(s, 1.0);
		c = mix(c, hl_c0, wm_lv_band(d - dc, 0.5 * w, pd) * inx);
		c = mix(c, hl_c1, wm_lv_band(d - (dc - 0.5 * w - 0.03), 0.012 * min(1.0, w / 0.04), pd) * inx * step(0.004, w));
	} else if (hl_graphic == 4) {
		// gradient toward the bow, the blend line leaning aft toward the sheer
		float xs = x + hl_p.z * (1.0 - clamp(t, 0.0, 1.0));
		c = mix(c, hl_c0, smoothstep(hl_p.x, hl_p.y, xs));
	} else if (hl_graphic == 5) {
		// bow: forward of a slanted line, with a line along its edge
		float xe = hl_p.x - hl_p.y * clamp(t, 0.0, 1.0);
		float dx = (x - xe) * hl_len;
		c = mix(c, hl_c0, wm_lv_inside(-dx, pxm));
		c = mix(c, hl_c1, wm_lv_band(dx + 0.5 * hl_p.z + 0.02, 0.5 * hl_p.z, pxm));
	}
	float cov = max(wm_hl_text(x, d, port, hl_name_panel, hl_name_box, hl_name_tex),
			wm_hl_text(x, d, port, hl_num_panel, hl_num_box, hl_num_tex));
	return mix(c, hl_text_color, cov);
}
