// Boat surfaces painted from a baked livery (data_format.md §8.5, game/scripts/livery/boat_livery.gd): the simple
// path, no procedural livery. The hull's topsides, boot stripe and antifouling read the livery's albedo, normal and
// ORM maps on the uv1 atlas, the transom and the deck theirs on their own uv1; the keel reads its albedo in side
// view. The slot's tiling detail on uv0 (boat.gdshader) stays on top around its mean; on the deck the ORM's blue is
// the non-slip mask, which picks between the gelcoat's detail and the non-slip's (bk_mask), and steep faces (the
// coaming and cabin sides, whose plan uv1 is a line) keep plain gelcoat relief. The baked AO of COLOR_0 darkens the
// ambient and reflected light only, and on the hull and the transom each boat's name (and number) come from its
// text texture (livery_baked.gdshaderinc), one sample.
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
// the baked maps; bk_proj: 0 the uv1 of the surface (hull atlas, transom, deck), 1 side view (keel)
uniform sampler2D bk_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int bk_proj = 0;
// normal and ORM maps present (the hull, transom and deck)
uniform bool bk_maps = true;
// side view: the image's rectangle in the model frame (forward min, top edge, length, height)
uniform vec4 bk_rect = vec4(0.0, 0.0, 1.0, 1.0);
// the deck: ORM blue is the non-slip mask between the slot's (gelcoat) detail and the non-slip detail below
uniform bool bk_mask = false;
uniform sampler2D ns_albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ns_mr_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ns_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool ns_use_normal = false;
uniform float ns_normal_scale = 1.0;
uniform vec2 ns_uv_scale = vec2(1.0);
uniform float ns_detail_mean = 1.0;
uniform float ns_rough_mean = 1.0;

#include "res://shaders/livery_text.gdshaderinc"
#include "res://shaders/livery_baked.gdshaderinc"

varying vec2 v_bk;
varying vec2 v_uv0;
varying float v_up;

void vertex() {
	v_uv0 = UV;
	v_up = abs(NORMAL.y);
	UV = UV * uv_scale;
	if (bk_proj == 1) {
		v_bk = vec2((VERTEX.z - bk_rect.x) / bk_rect.z, (bk_rect.y - VERTEX.y) / bk_rect.w);
	} else {
		v_bk = UV2;
	}
}

void fragment() {
	vec3 det = texture(albedo_tex, UV).rgb / bk_detail_mean;
	vec4 mr = texture(mr_tex, UV);
	float rough = clamp(mr.g * roughness, 0.0, 1.0);
	float rdet = mr.g / bk_rough_mean;
	float occ = 1.0;
	float ns = 0.0;
	float flat_k = 1.0;
	vec3 orm = vec3(1.0);
	if (bk_maps) {
		orm = texture(bk_orm, v_bk).rgb;
	}
	if (bk_mask) {
		// the deck: the non-slip's moulded pattern where the mask says, smooth gelcoat elsewhere and on steep faces
		flat_k = smoothstep(0.35, 0.7, v_up);
		ns = orm.b * flat_k;
		vec2 uvn = v_uv0 * ns_uv_scale;
		det = mix(det, texture(ns_albedo_tex, uvn).rgb / ns_detail_mean, ns);
		rdet = mix(rdet, texture(ns_mr_tex, uvn).g / ns_rough_mean, ns);
	}
	vec3 a = texture(bk_albedo, v_bk).rgb * det;
	if (bk_maps) {
		rough = orm.g * rdet;
		occ = orm.r;
		// the livery's relief (vinyl and tape edges, fairing, non-slip edges, sealant, scratches); image top is -v
		vec3 nb = texture(bk_normal, v_bk).rgb * 2.0 - 1.0;
		nb = mix(vec3(0.0, 0.0, 1.0), nb, flat_k);
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
	if (use_normal_tex || (bk_mask && ns_use_normal)) {
		vec3 nm = use_normal_tex ? texture(normal_tex, UV).rgb : vec3(0.5, 0.5, 1.0);
		if (bk_mask && ns_use_normal) {
			nm = mix(nm, texture(ns_normal_tex, v_uv0 * ns_uv_scale).rgb, ns);
		}
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = mix(normal_scale, ns_normal_scale, ns);
	}
	AO = mix(1.0, COLOR.r, ao_strength) * occ;
	AO_LIGHT_AFFECT = 0.0;
}
