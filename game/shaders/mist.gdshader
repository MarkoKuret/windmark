// Bow mist (water_render.md §5): soft camera-facing spray clouds, unshaded (sky horizon colour plus a share of the
// sun that grows toward it), faded where they meet the water or the hull and near the camera. MultiMesh instances:
// the transform carries position and size; INSTANCE_CUSTOM = (alpha, seed, 0, 0).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#define TIER 1
#define WM_DETAIL_LAYERS 1
uniform sampler2D expo_tex : filter_nearest, repeat_disable;
uniform sampler2D land_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D wake_tex : filter_linear, repeat_disable;
#include "res://shaders/sea_common.gdshaderinc"
#include "res://shaders/wake_common.gdshaderinc"
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying float v_alpha;
varying float v_seed;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_alpha = INSTANCE_CUSTOM.x;
	v_seed = INSTANCE_CUSTOM.y;
}

void fragment() {
	float c = cos(v_seed * 6.2831);
	float sn = sin(v_seed * 6.2831);
	vec2 ruv = mat2(vec2(c, sn), vec2(-sn, c)) * (UV - 0.5);
	float n = texture(foam_tex, ruv * 0.7 + v_seed * 3.7).r;
	float a = wm_mist_alpha(UV, n) * v_alpha;
	// depth fade against the water and the hull, and near the camera
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -vp.z / vp.w;
	a *= clamp((scene_z + VERTEX.z) / 0.6, 0.0, 1.0) * smoothstep(1.0, 3.0, -VERTEX.z);
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float fwd = pow(max(dot(view_dir, normalize(sun_dir)), 0.0), 3.0);
	ALBEDO = 0.35 * sky_horizon + 0.12 * sun_color * (1.0 + 2.0 * fwd);
	ALPHA = clamp(a, 0.0, 1.0);
}
