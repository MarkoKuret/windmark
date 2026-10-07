// Sails from the class's baked sail textures (sail_visuals.md §11.2, data_format.md §8.5): the simple path, no
// procedural cloth. Per pixel: the layer's albedo (the port image, or the starboard image mirrored), the ORM map
// (occlusion, roughness, light through the cloth), the normal map with the cloth's tiling detail, the tangent frame
// from screen-space derivatives (livery_baked.gdshaderinc), and the boat's nation letters and sail number from its
// text texture, one sample per side. Light, layers and shadows as shaders/sail.gdshader (keep light() in step).
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

#include "res://shaders/livery_text.gdshaderinc"
#include "res://shaders/livery_baked.gdshaderinc"

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
	vec3 a = v_side > 0.5 ? texture(sk_albedo_stbd, vec2(1.0 - t.x, t.y)).rgb : texture(sk_albedo_port, t).rgb;
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
