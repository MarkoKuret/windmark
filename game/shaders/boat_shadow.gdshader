// Drawn boat shadow (water_render.md §4.7, tiers L and M): a grid over the boat's shadow, draped on the drawn sea
// like the wake ribbons (wake_common wm_drape), multiplying the colour behind it by the share of the light a real
// shadow on the water keeps. No depth write; the depth test lets the hull, deck and sails in front hide it.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

#define TIER 1
#define WM_DETAIL_LAYERS 1
uniform sampler2D expo_tex : filter_nearest, repeat_disable;
uniform sampler2D land_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D wake_tex : filter_linear, repeat_disable;
#include "res://shaders/sea_common.gdshaderinc"
#include "res://shaders/wake_common.gdshaderinc"
#include "res://shaders/boat_shadow_common.gdshaderinc"

uniform float grid_q = 1.06;
uniform float grid_segments = 256.0;

varying vec3 v_water;

void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p = wm_drape(VERTEX, 0.03, cam, grid_q, grid_segments);
	// the water point before the pull toward the camera: on the same view ray, straight above the input vertex
	vec2 dc = p.xz - cam.xz;
	float s = length(dc) > 1e-4 ? length(VERTEX.xz - cam.xz) / length(dc) : 1.0;
	v_water = cam + (p - cam) * s;
	VERTEX = p;
}

void fragment() {
	vec3 P = v_water;
	float px = length(fwidth(P.xz));
	float s = wm_boat_shadow(P, px);
	vec3 V = normalize(CAMERA_POSITION_WORLD - P);
	ALBEDO = mix(vec3(1.0), wm_shadow_keep(V, normalize(shadow_sun)), s);
}
