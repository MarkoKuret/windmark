// Sails (docs/specs/sail_visuals.md §11; game/scripts/boat_view.gd): the boatgen sailcloth slot, opaque, back faces
// culled (each of the two cloth layers faces its own side), roughness about 0.55, and a back-light of about 0.3 of
// the albedo so the sun shows through the cloth. The two layers lie 2 mm apart, so a sunlit sail shadows its own
// far layer in the shadow map: the back-light is therefore taken from the light without its shadow attenuation
// (the sun through the cloth), while the front keeps the shadowed light.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
// share of the albedo lit from behind (the sun through the cloth)
uniform float backlight : hint_range(0.0, 1.0) = 0.3;
// the same cap on the linear albedo as the boat shader
uniform float albedo_max = 0.8;

void vertex() {
	UV = UV * uv_scale;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = min(a.rgb, vec3(albedo_max));
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += max(-ndl, 0.0) * backlight * LIGHT_COLOR / PI;
	// a soft sheen (Blinn-Phong from the roughness), shadowed
	vec3 h = normalize(VIEW + LIGHT);
	float shin = 2.0 / max(roughness * roughness * roughness * roughness, 1e-3) - 2.0;
	float spec = pow(max(dot(NORMAL, h), 0.0), shin) * (shin + 8.0) / (8.0 * PI);
	SPECULAR_LIGHT += 0.04 * spec * max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR;
}
