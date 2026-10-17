// Wake ribbons (water_render.md §5): foam laid on the drawn sea. The vertex shader drapes the ribbon on the same
// height the sea shader draws (sea_common, same uniforms, the grid fade of the sea's tier) plus 0.1 m
// (wake_common wm_wake_drape).
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

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;   // where the row lies on the water, before the drape
	VERTEX = wm_wake_drape(VERTEX, CAMERA_POSITION_WORLD, grid_q, grid_segments);
}

void fragment() {
	float a = wm_wake_alpha(UV, COLOR.r, COLOR.b, COLOR.a, COLOR.g, texture(foam_tex, v_world / 3.0).r,
			texture(foam_tex, UV * vec2(0.6, 0.7) + 0.37).g, texture(foam_tex, UV * vec2(0.15, 0.17) + 0.71).g);
	ALBEDO = col_foam;
	ALPHA = a;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}
