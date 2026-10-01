// Boat surfaces painted from a baked livery (data_format.md §8.5, game/scripts/livery/boat_livery.gd): the simple
// path, no procedural livery. The hull's topsides, boot stripe and antifouling read the livery's albedo, normal and
// ORM maps on the uv1 atlas; the keel reads its albedo in side view and the deck an optional colour override from
// above. The slot's tiling detail on uv0 (boat.gdshader) stays on top around its mean, the baked AO of COLOR_0
// darkens the ambient and reflected light only, and on the hull each boat's name and number come from its text
// texture (livery_baked.gdshaderinc), one sample.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// the slot's tiling detail and factors, as in boat.gdshader
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec2 uv_scale = vec2(1.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float albedo_max = 0.8;
// means of the detail textures (linear grey of the albedo, roughness channel), so the detail varies around 1
uniform float bk_detail_mean = 1.0;
uniform float bk_rough_mean = 1.0;
// the baked maps; bk_proj: 0 the hull atlas (uv1), 1 side view (keel), 2 top view (deck)
uniform sampler2D bk_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int bk_proj = 0;
// normal and ORM maps present (the hull)
uniform bool bk_maps = true;
// side and top views: the image's rectangle in the model frame (forward min, top edge, length, height)
uniform vec4 bk_rect = vec4(0.0, 0.0, 1.0, 1.0);

#include "res://shaders/livery_text.gdshaderinc"
#include "res://shaders/livery_baked.gdshaderinc"

varying vec2 v_bk;

void vertex() {
	UV = UV * uv_scale;
	if (bk_proj == 1) {
		v_bk = vec2((VERTEX.z - bk_rect.x) / bk_rect.z, (bk_rect.y - VERTEX.y) / bk_rect.w);
	} else if (bk_proj == 2) {
		v_bk = vec2((VERTEX.z - bk_rect.x) / bk_rect.z, (bk_rect.y - VERTEX.x) / bk_rect.w);
	} else {
		v_bk = UV2;
	}
}

void fragment() {
	vec3 det = texture(albedo_tex, UV).rgb / bk_detail_mean;
	vec3 a = texture(bk_albedo, v_bk).rgb * det;
	vec4 mr = texture(mr_tex, UV);
	float rough = clamp(mr.g * roughness, 0.0, 1.0);
	float occ = 1.0;
	if (bk_maps) {
		vec3 orm = texture(bk_orm, v_bk).rgb;
		rough = orm.g * mr.g / bk_rough_mean;
		occ = orm.r;
		// the livery's relief (vinyl and tape edges, fairing, roller marks, scratches); the atlas' image top is -v
		vec3 nb = texture(bk_normal, v_bk).rgb * 2.0 - 1.0;
		NORMAL = wm_perturb(NORMAL, VERTEX, v_bk, nb, -1.0);
	}
	if (ov_on != 0) {
		// the boat's name and number: cut vinyl over the paint, a faint line of dirt along its edge
		vec2 c = wm_ov_hull(UV2);
		a = mix(a, ov_color * det, c.x);
		a *= 1.0 - 0.12 * c.y;
		rough = mix(rough, 0.24, c.x);
	}
	ALBEDO = min(a, vec3(albedo_max));
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = clamp(mr.b * metallic, 0.0, 1.0);
	SPECULAR = specular;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	AO = mix(1.0, COLOR.r, ao_strength) * occ;
	AO_LIGHT_AFFECT = 0.0;
}
