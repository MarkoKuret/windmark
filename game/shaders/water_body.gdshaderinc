// Godot stage functions of the sea shader (water_render.md §3, §4). Included by water_l/m/h.gdshader after they
// set TIER and WM_DETAIL_LAYERS; the maths lives in sea_common.gdshaderinc, shared with the offline preview.
// WM_FADED_SLOPE (tier H): the per-pixel slope of the waves the grid faded (water_render.md §3.2, §7).
// WM_NO_SHADOWS (tiers L and M): the sea takes no shadows (water_render.md §4.6); BoatShadows draws the boats'
// shadows on the water instead (§4.7)
#ifdef WM_NO_SHADOWS
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;
#else
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#endif

uniform sampler2D expo_tex : filter_nearest, repeat_disable;
uniform sampler2D land_tex : filter_nearest, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D wake_tex : filter_linear, repeat_disable;
uniform sampler2D caps_tex : filter_linear_mipmap_anisotropic, repeat_enable;
#define WM_WHITECAPS

#include "res://shaders/sea_common.gdshaderinc"

varying vec2 v_local;     // camera-relative world metres
varying float v_spacing;  // grid spacing at the vertex, m
varying float v_eta;
varying float v_expo;
varying float v_land;     // venue speed factor (wind.md §8)
varying vec3 v_normal;    // geometric normal, scene axes

void vertex() {
	vec2 xl = vec2(VERTEX.x, -VERTEX.z);
	float s = UV.x;
	float eta;
	vec2 grad;
	wm_sea_height(xl, s, eta, grad);
	float expo = wm_exposure(sea_origin + xl);
	eta *= expo;
	grad *= expo;
	VERTEX.y = eta;
	NORMAL = normalize(vec3(-grad.x, 1.0, grad.y));
	v_local = xl;
	v_spacing = s;
	v_eta = eta;
	v_expo = expo;
	v_land = wm_land(sea_origin + xl);
	v_normal = NORMAL;
}

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 view = normalize(cam - wpos);
	float dist = length(cam.xz - wpos.xz);
	vec3 n_geo = normalize(v_normal);
	float px = max(length(fwidth(v_local)), 1e-3);
#ifdef WM_FADED_SLOPE
	vec2 g = wm_faded_slope(v_local, v_spacing, px) * v_expo;
	n_geo = normalize(n_geo + vec3(-g.x, 0.0, g.y));
#endif
#if TIER >= 2
	vec2 wuv = v_local / wake_extent + 0.5;
	vec2 wake = texture(wake_tex, vec2(wuv.x, 1.0 - wuv.y)).rg * 2.0 - 1.0;
	wake *= step(0.0, wuv.x) * step(wuv.x, 1.0) * step(0.0, wuv.y) * step(wuv.y, 1.0);
#else
	vec2 wake = vec2(0.0);
#endif
	WmSurface S = wm_surface(v_local, v_eta, n_geo, view, dist, px, wake, v_land);
	wm_apply_caps(S, v_local, px, v_expo, dist, n_geo);
	vec4 ov = wm_overlays(v_local, dist, view.y, v_eta, cam.y - (wpos.y - v_eta));
	ALBEDO = mix(S.albedo, ov.rgb * 0.8, ov.a);
	EMISSION = mix(S.emission, ov.rgb * 0.35, ov.a);
	ROUGHNESS = mix(S.roughness, 0.5, ov.a);
	SPECULAR = S.specular;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(S.normal, 0.0)).xyz);
}
