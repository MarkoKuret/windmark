// Daytime sky, quality tier L (water_render.md §4.5, §7): the same sky as sky.gdshader, with the cumulus drawn in
// Godot's half-resolution pass (a quarter of the pixels) and blended over the full-resolution ramp, haze and sun
// disc, which stay sharp. No TIME, so Godot only re-renders the radiance map when a parameter changes. Parameters
// are linear colours set by scenes/sea/sky_rig.gd (the same names as sky.gdshader: the rig swaps the shader).
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sky_horizon = vec3(0.60, 0.72, 0.85);
uniform vec3 sky_zenith = vec3(0.12, 0.30, 0.62);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.866);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);
uniform float cloud_cover = 0.35;
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_diffuse = 0.0;   // 1: the overcast deck (water_render.md §4.5)

#include "res://shaders/sky_common.gdshaderinc"

void sky() {
	vec3 sun = normalize(sun_dir);
	if (AT_HALF_RES_PASS) {
		// the clouds, premultiplied so the bilinear read of the full pass blends their edges cleanly
		vec4 cl = wm_sky_clouds(EYEDIR, sun, sky_horizon, sky_zenith, sun_color, cloud_cover, cloud_offset, cloud_diffuse);
		COLOR = cl.rgb * cl.a;
		ALPHA = cl.a;
	} else {
		float disc = AT_CUBEMAP_PASS ? 0.0 : 1.0;
		vec4 cl = HALF_RES_COLOR;
		vec3 col = wm_sky_base(EYEDIR, sun, sky_horizon, sky_zenith, sun_color) * (1.0 - cl.a) + cl.rgb;
		COLOR = col + wm_sky_sun(EYEDIR, sun, sun_color, cl.a, disc, cloud_diffuse);
	}
}
