// Daytime sky (WM-016.03): the two-colour ramp the water shading mirrors, sun glow and disc, a static cloud layer.
// No TIME, so Godot only re-renders the radiance map when a parameter changes. Parameters are linear colours set
// by scenes/sea/sky_rig.gd.
shader_type sky;

uniform vec3 sky_horizon = vec3(0.60, 0.72, 0.85);
uniform vec3 sky_zenith = vec3(0.12, 0.30, 0.62);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.866);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);
uniform float cloud_cover = 0.35;
uniform vec2 cloud_offset = vec2(0.0);

#include "res://shaders/sky_common.gdshaderinc"

void sky() {
	float disc = AT_CUBEMAP_PASS ? 0.0 : 1.0;
	COLOR = wm_sky_color(EYEDIR, normalize(sun_dir), sky_horizon, sky_zenith, sun_color, cloud_cover, cloud_offset, disc);
}
