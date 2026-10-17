// Sails from the class's baked sail textures (sail_visuals.md §11.2, data_format.md §8.5): the simple path, no
// procedural cloth. Per pixel: the layer's albedo (the port image, or the starboard image mirrored), the ORM map
// (occlusion, roughness, light through the cloth), the normal map with the cloth's tiling detail, the tangent frame
// from screen-space derivatives (livery_baked.gdshaderinc), and the boat's nation letters and sail number from its
// text texture, one sample per side. A tinted livery (st_on, §8.5 "Tinted liveries") recolours the cloth zones of
// the albedo's alpha to the boat's design (sail_design.gdshaderinc) and number colour (livery_tint.gdshaderinc).
// Light, layers and shadows as shaders/sail.gdshader (keep light() in step).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D sk_albedo_port : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D sk_albedo_stbd : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D sk_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D sk_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
// tiling cloth detail: relief (red, green) and brightness / 2 (blue), sk_detail_tile metres across
uniform sampler2D sk_detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sk_detail_tile = 0.125;
uniform float sk_detail_amount = 1.0;
// the flat plan (cos, sin of the luff-to-row angle) and the images' rectangle in it (x min, y max, width, height)
uniform vec2 sk_shear = vec2(0.0, 1.0);
uniform vec4 sk_rect = vec4(0.0, 10.0, 4.0, 10.0);
uniform float albedo_max = 0.8;
// shadow pass offset along the normal, away from the light (m)
uniform float shadow_push = 0.05;
// rows * cols: vertex indices from here are the starboard layer
uniform int sl_layer_n = 0;

// a tinted livery (data_format.md §8.5): the class set's colours the sail was baked in, by zone of the albedo's
// alpha (0 fixed parts, 1 the number colour, 2 design colour 1, 3 design colour 0, 4 the cloth; linear), and the
// boat's design in the plan frame of sn_axis, sn_up, sn_tack (sail_design.gdshaderinc)
uniform int st_on = 0;
uniform vec3 st_from[5];
uniform int sd_design = 0;
uniform vec3 sd_cloth = vec3(0.8);
uniform vec3 sd_c0 = vec3(0.8);
uniform vec3 sd_c1 = vec3(0.8);
uniform vec4 sd_dp = vec4(0.0);
uniform vec2 sd_clew = vec2(4.0, 0.0);
uniform vec2 sd_head = vec2(0.0, 10.0);
uniform vec2 sd_head_aft = vec2(0.5, 10.0);
uniform float sd_height = 10.0;

#include "res://shaders/livery_text.gdshaderinc"
#include "res://shaders/livery_baked.gdshaderinc"
#include "res://shaders/livery_tint.gdshaderinc"
#include "res://shaders/sail_design.gdshaderinc"

varying vec2 v_plan;
varying float v_trans;
varying flat float v_side;

void vertex() {
	v_side = VERTEX_ID >= sl_layer_n ? 1.0 : 0.0;
	v_plan = vec2(UV.x * sk_shear.y, UV.y + UV.x * sk_shear.x);
	if (IN_SHADOW_PASS) {
		VERTEX -= NORMAL * shadow_push;
	}
}

void fragment() {
	vec2 t = vec2((v_plan.x - sk_rect.x) / sk_rect.z, (sk_rect.y - v_plan.y) / sk_rect.w);
	vec4 ab = v_side > 0.5 ? texture(sk_albedo_stbd, vec2(1.0 - t.x, t.y)) : texture(sk_albedo_port, t);
	vec3 a = ab.rgb;
	if (st_on != 0) {
		int z = clamp(int(ab.a * 4.0 + 0.5), 0, 4);
		if (z >= 2) {
			float px = max(fwidth(v_plan.x), fwidth(v_plan.y));
			vec3 to = wm_design(sd_cloth, v_plan, 0.0, px, sn_tack, sd_clew, sd_head, sd_head_aft, sn_axis, sn_up,
					sd_height, sd_design, sd_c0, sd_c1, sd_dp);
			a = wm_tint(a, st_from[z], to, wm_tint_k(st_from[z], to));
		} else if (z == 1) {
			a = wm_tint(a, st_from[1], sn_color, wm_tint_k(st_from[1], sn_color));
		}
	}
	vec3 orm = texture(sk_orm, t).rgb;
	vec3 nm = wm_normal_texel(texture(sk_normal, t).rgb);
	vec3 dt = texture(sk_detail, vec2(v_plan.x, -v_plan.y) / sk_detail_tile).rgb;
	nm = normalize(vec3(nm.xy + (dt.xy * 2.0 - 1.0) * sk_detail_amount, nm.z));
	a *= mix(1.0, dt.b * 2.0, sk_detail_amount);
	vec2 near = wm_sn_cov(v_plan, v_side);
	vec2 far = wm_sn_cov(v_plan, 1.0 - v_side);
	a = mix(a, sn_color, near.x) * (1.0 - 0.12 * near.y);
	ALBEDO = min(a, vec3(albedo_max));
	ROUGHNESS = clamp(mix(orm.g, 0.4, near.x), 0.05, 1.0);
	SPECULAR = 0.5;
	AO = orm.r;
	NORMAL = wm_perturb(NORMAL, VERTEX, v_plan, nm, 1.0);
	v_trans = orm.b * (1.0 - 0.85 * near.x) * (1.0 - 0.85 * far.x);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	// through the cloth: brighter looking toward the sun, with the shadows of the rig and the other sails
	float fwd = pow(max(dot(-VIEW, LIGHT), 0.0), 4.0);
	DIFFUSE_LIGHT += max(-ndl, 0.0) * v_trans * (0.75 + 0.75 * fwd) * mix(1.0, ATTENUATION, 0.8) * LIGHT_COLOR / PI;
	// the cloth's sheen (sail_visuals.md §11.5: the Charlie sheen, no plastic highlight), shadowed
	vec3 h = normalize(VIEW + LIGHT);
	float nh = dot(NORMAL, h);
	float nl = max(ndl, 0.0);
	float nv = max(dot(NORMAL, VIEW), 1e-4);
	float ia = 1.0 / max(ROUGHNESS, 0.05);
	float d = (2.0 + ia) * pow(max(1.0 - nh * nh, 0.0), 0.5 * ia) / (2.0 * PI);
	float vs = 1.0 / (4.0 * max(nl + nv - nl * nv, 1e-3));
	SPECULAR_LIGHT += (0.03 + 0.35 * ALBEDO) * d * vs * nl * ATTENUATION * LIGHT_COLOR;
}
