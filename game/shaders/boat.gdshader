// Boat surfaces (game/scripts/boat_materials.gd): the boatgen PBR slot of the imported StandardMaterial3D (tiling
// texture set on uv0, glTF factors) with the baked ambient occlusion of COLOR_0 applied to the ambient and
// reflected light only (AO, AO_LIGHT_AFFECT 0), not to the albedo, so sunlit parts keep their colour.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// glTF metallicRoughness: roughness in G, metallic in B
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec2 uv_scale = vec2(1.0);
// share of the baked AO applied (1 = as baked); COLOR.r is 1 where a mesh has no baked AO
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
// cap on the linear albedo: bright paints and gelcoats reflect at most about 80 % (the sun then does not clip
// white hulls to a flat white)
uniform float albedo_max = 0.8;

void vertex() {
	UV = UV * uv_scale;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = min(a.rgb, vec3(albedo_max));
	vec4 mr = texture(mr_tex, UV);
	ROUGHNESS = clamp(mr.g * roughness, 0.0, 1.0);
	METALLIC = clamp(mr.b * metallic, 0.0, 1.0);
	SPECULAR = specular;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	AO = mix(1.0, COLOR.r, ao_strength);
	AO_LIGHT_AFFECT = 0.0;
}
