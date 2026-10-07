shader_type spatial;
// Committee and mark boats (CourseView): CourseProps' vertex colours (linear) worn by course_boat_common.gdshaderinc
// in the boat's own frame.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://scenes/course/course_boat_common.gdshaderinc"

varying vec3 v_opos;
varying vec3 v_onormal;
varying vec3 v_wpos;

void vertex() {
	v_opos = VERTEX;
	v_onormal = NORMAL;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 alb;
	float rough;
	wm_cb_surface(COLOR.rgb, v_opos, normalize(v_onormal), length(cam - v_wpos), alb, rough);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
