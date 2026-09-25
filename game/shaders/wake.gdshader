// Wake ribbons (water_render.md §5): foam laid on the drawn sea. The vertex shader drapes the ribbon on the same
// height the sea shader draws (sea_common, same uniforms, the grid fade of the sea's tier) plus 0.1 m.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

#define TIER 1
#define WM_DETAIL_LAYERS 1
uniform sampler2D expo_tex : filter_nearest, repeat_disable;
uniform sampler2D land_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D wake_tex : filter_linear, repeat_disable;
#include "res://shaders/sea_common.gdshaderinc"
#include "res://shaders/wake_common.gdshaderinc"

uniform float grid_q = 1.06;
uniform float grid_segments = 256.0;

void vertex() {
	vec2 xl = vec2(VERTEX.x, -VERTEX.z) - sea_origin;
	float r = length(xl);
	float s = r < 0.6 ? 0.6 : max(r * (grid_q - 1.0), 6.28318530718 * r / grid_segments);
	float eta;
	vec2 grad;
	wm_sea_height(xl, s, eta, grad);
	VERTEX.y = eta * wm_exposure(sea_origin + xl) + 0.1;
	// pulled toward the camera so the sea's linear facets between its vertices never cover the ribbon
	vec3 to_cam = CAMERA_POSITION_WORLD - VERTEX;
	VERTEX += to_cam * min(0.3 / max(length(to_cam), 1e-3), 0.05);
}

void fragment() {
	float a = wm_wake_alpha(UV, COLOR.r, COLOR.a, texture(foam_tex, UV * vec2(1.5, 2.0)).r, texture(foam_tex, UV * vec2(0.6, 0.7) + 0.37).g);
	ALBEDO = col_foam;
	ALPHA = a;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}
