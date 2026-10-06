shader_type spatial;
// Venue land (VenueView): LandTerrain's per-vertex ground colour (rgb, linear) and wetness (a), with the fine
// grain of land_common.gdshaderinc.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://scenes/venue/land_common.gdshaderinc"

// the stone shown on steep faces (wm_land_albedo): 1 for polygon land, VenueTerrain sets less
uniform float bare_rock = 1.0;

varying vec3 v_wpos;
varying vec3 v_wnormal;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	ALBEDO = wm_land_albedo(COLOR.rgb, v_wpos, normalize(v_wnormal).y, length(cam - v_wpos), bare_rock);
	ROUGHNESS = wm_land_roughness(COLOR.a);
	SPECULAR = 0.35;
}
