// Venue land shading shared by the Godot shader (land.gdshader) and the offline preview (tests/course_preview.py,
// which compiles it as GLSL 4.1): the ground colour baked per vertex by LandTerrain, broken up with fine noise
// so it does not look like smooth paint up close. Only functions both languages accept.

float wm_land_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wm_land_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wm_land_hash(i);
	float b = wm_land_hash(i + vec2(1.0, 0.0));
	float c = wm_land_hash(i + vec2(0.0, 1.0));
	float d = wm_land_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Linear albedo from the vertex colour at a scene position `wpos` with the world normal's up component `ny`.
// `dist` is the camera distance: the fine grain fades out far away, where it would only shimmer.
vec3 wm_land_albedo(vec3 base, vec3 wpos, float ny, float dist) {
	vec2 q = wpos.xz;
	float fine = wm_land_noise(q * 0.9) * 0.6 + wm_land_noise(q * 3.1) * 0.4;
	float coarse = wm_land_noise(q * 0.17);
	float fade = 1.0 - smoothstep(150.0, 900.0, dist);
	float k = 1.0 + ((fine - 0.5) * 0.45 * fade + (coarse - 0.5) * 0.25);
	// steeper faces show bare stone through the vegetation
	float bare = (1.0 - smoothstep(0.55, 0.85, ny)) * 0.35;
	vec3 stone = vec3(0.40, 0.385, 0.35);
	return mix(base, stone, bare * 0.5) * k;
}

// Roughness: wet stone and pebbles at the water line are glossier.
float wm_land_roughness(float wet) {
	return mix(0.92, 0.45, wet);
}
