// Sails (docs/specs/sail_visuals.md §11; game/scripts/boat_view.gd, BoatMaterials.sail_cloth): the boatgen
// sailcloth slot, opaque, back faces culled (each of the two cloth layers faces its own side), with the cloth of
// sail_cloth.gdshaderinc: panels, seams, tapes, corner patches, batten pockets and tell-tales, which show as
// denser cloth in front light and as darker shapes against the sun.
//
// Shadows (water_render.md §4.6): the two layers lie 2 mm apart, closer than any shadow bias, so in the shadow
// pass the sail is drawn pushed 5 cm away from the light along its normal (only the layer facing the light is
// drawn there, back faces culled). Neither layer then shadows itself or its twin, while the shadows of the mast,
// the boom and the other sails still fall on it, and on the far side show through the cloth.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
// how much of the generator's weave texture shows
uniform float weave : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
// share of the albedo lit from behind through one ply (the sun through the cloth)
uniform float backlight : hint_range(0.0, 1.0) = 0.3;
// fibre colour and strength (laminate scrim, ripstop)
uniform vec3 fibre_color : source_color = vec3(0.12, 0.12, 0.13);
uniform float fibre_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 telltale_color : source_color = vec3(0.55, 0.05, 0.04);
// the same cap on the linear albedo as the boat shader (on the plain cloth, before the seams and patches)
uniform float albedo_max = 0.8;
// shadow pass offset along the normal, away from the light (m)
uniform float shadow_push = 0.05;

#include "res://shaders/sail_cloth.gdshaderinc"

varying float v_trans;

void vertex() {
	if (IN_SHADOW_PASS) {
		VERTEX -= NORMAL * shadow_push;
	}
}

void fragment() {
	float px = max(fwidth(UV.x), fwidth(UV.y));
	float layers;
	float stitch;
	float panel;
	float fibre;
	float mark;
	wm_cloth(UV, UV2.y, px, layers, stitch, panel, fibre, mark);
	vec3 tex = texture(albedo_tex, UV * uv_scale).rgb;
	vec3 a = min(albedo_color.rgb * mix(vec3(1.0), tex, weave), vec3(albedo_max));
	// seams, tapes and patches read as slightly greyer cloth, the stitching as thread lines
	a *= (1.0 - 0.045 * min(layers, 4.0)) * (1.0 - 0.45 * stitch) * (1.0 + 0.06 * (panel - 0.5));
	a = mix(a, fibre_color, fibre * fibre_amount);
	a = mix(a, telltale_color, mark);
	ALBEDO = a;
	ROUGHNESS = clamp(roughness + 0.1 * (panel - 0.5), 0.05, 1.0);
	SPECULAR = 0.5;
	v_trans = backlight * exp(-0.8 * layers) * (1.0 - 0.6 * fibre * fibre_amount) * (1.0 - 0.6 * mark);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	// through the cloth: brighter looking toward the sun, with the shadows of the rig and the other sails
	float fwd = pow(max(dot(-VIEW, LIGHT), 0.0), 4.0);
	DIFFUSE_LIGHT += max(-ndl, 0.0) * v_trans * (0.75 + 0.75 * fwd) * mix(1.0, ATTENUATION, 0.8) * LIGHT_COLOR / PI;
	// a soft sheen (Blinn-Phong from the roughness), shadowed
	vec3 h = normalize(VIEW + LIGHT);
	float shin = 2.0 / max(ROUGHNESS * ROUGHNESS * ROUGHNESS * ROUGHNESS, 1e-3) - 2.0;
	float spec = pow(max(dot(NORMAL, h), 0.0), shin) * (shin + 8.0) / (8.0 * PI);
	SPECULAR_LIGHT += 0.04 * spec * max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR;
}
