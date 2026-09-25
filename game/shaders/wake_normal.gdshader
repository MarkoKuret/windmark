// Wake normal buffer pass (water_render.md §5, tiers M and H): the ribbons seen from above in a camera-centred
// orthographic view, written as a normal disturbance (R, G = world east, north; 0.5 = none) that the sea shader
// adds to its detail normal. The buffer viewport has a linear tonemap, so the output is the sRGB-decoded value.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	// a ridge across the ribbon and ripples along it
	float ridge = sin(3.14159265 * x);
	float ripple = 0.6 + 0.4 * sin(6.28318530718 * UV.y * 4.0);
	vec2 d = UV2 * ridge * ripple;
	ALBEDO = srgb_to_linear(vec3(0.5 + 0.5 * d, 0.5));
	ALPHA = COLOR.a;
}
