// Bow wave sheets (water_render.md §5): water peeling off the stem into a foam crest, draped on the drawn sea like
// the wake ribbons (wake_common wm_drape) with the lift of each vertex (UV2.x). UV: (across, along); COLOR.a: the
// vertex alpha; the instance's `flow`: the distance sailed mod 20 m (the foam texture flows aft).
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
// the lighter water of the sheet
uniform vec3 col_sheet : source_color = vec3(0.10, 0.22, 0.24);

instance uniform float flow = 0.0;

varying vec2 v_flow;

void vertex() {
	v_flow = vec2(UV.x * 2.0, UV2.y - flow);
	VERTEX = wm_drape(VERTEX, UV2.x, CAMERA_POSITION_WORLD, grid_q, grid_segments);
}

void fragment() {
	vec2 f = wm_bow_alpha(UV, COLOR.a, texture(foam_tex, v_flow * vec2(1.6, 0.9)).g,
			texture(foam_tex, v_flow * vec2(0.45, 0.2) + 0.61).g);
	ALBEDO = mix(col_sheet, col_foam, f.x);
	ALPHA = f.y;
	ROUGHNESS = mix(0.12, 0.6, f.x);
	SPECULAR = 0.4;
}
