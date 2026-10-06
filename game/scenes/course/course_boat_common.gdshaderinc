// Committee and mark boat surfaces shared by the Godot shader (course_boat.gdshader) and the offline preview
// (tests/course_preview.py, compiled there as GLSL 4.1): the flat vertex colours of CourseProps given the wear of a
// working boat. Gelcoat grain, grime streaks down the walls, a stain just above the water line, non-skid and scuffs
// on the decks, glossy glass. Inputs are in the boat's own frame (up +Y, water line at 0), so the texture moves
// with her. Only functions both languages accept.

float wm_cb_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wm_cb_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wm_cb_hash(i);
	float b = wm_cb_hash(i + vec2(1.0, 0.0));
	float c = wm_cb_hash(i + vec2(0.0, 1.0));
	float d = wm_cb_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Albedo and roughness from the vertex colour `base` at the boat-frame point `p` with the boat-frame normal `n`;
// `dist` is the camera distance (fine detail fades out far away, where it would only shimmer).
void wm_cb_surface(vec3 base, vec3 p, vec3 n, float dist, out vec3 albedo, out float rough) {
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float fade = 1.0 - smoothstep(40.0, 260.0, dist);
	float up = clamp(n.y, -1.0, 1.0);
	float wall = 1.0 - smoothstep(0.45, 0.8, abs(up));
	// a horizontal coordinate along the wall, so streaks run straight down whichever way it faces
	vec2 hz = normalize(vec2(-n.z, n.x) + vec2(1e-4, 0.0));
	float along = dot(p.xz, hz);
	vec2 q = vec2(along, p.y);

	// gelcoat grain and a slow, patchy fade of the paint
	float grain = wm_cb_noise(q * 9.0 + p.xz * 3.0) - 0.5;
	float blot = wm_cb_noise(q * 0.7 + 11.0) - 0.5;
	float k = 1.0 + grain * 0.08 * fade + blot * 0.09;

	// grime streaks down the walls, strongest under the deck edges and window frames, on light paint only
	float streak = wm_cb_noise(vec2(along * 7.0, p.y * 0.35)) * wm_cb_noise(vec2(along * 2.3 + 5.0, p.y * 0.2));
	float pale = smoothstep(0.15, 0.5, lum);
	k -= wall * pale * smoothstep(0.12, 0.45, streak) * 0.22;

	// a brownish stain from the water line up some 30 cm on the hull
	float wl = (1.0 - smoothstep(0.0, 0.32 + 0.1 * wm_cb_noise(vec2(along * 1.5, 3.0)), p.y)) * step(-0.05, p.y);
	vec3 col = mix(base, base * vec3(0.68, 0.62, 0.48), wl * wall * 0.9);

	// decks: a fine non-skid dimple, scuffs and footworn patches
	float deck = smoothstep(0.75, 0.95, up);
	float dimple = wm_cb_noise(p.xz * 38.0);
	float scuff = smoothstep(0.55, 0.85, wm_cb_noise(p.xz * 1.3 + 7.0));
	k += deck * ((dimple - 0.5) * 0.18 * fade - scuff * 0.12);

	albedo = col * k;

	// roughness by material: glass is near black and glossy, antifouling and tubes matt, gelcoat satin
	float glass = 1.0 - smoothstep(0.012, 0.03, lum);
	float red = smoothstep(0.25, 0.45, base.r - base.g - base.b);
	rough = 0.42 + grain * 0.1 + streak * 0.12 * wall;
	rough = mix(rough, 0.82 + dimple * 0.1, deck);
	rough = mix(rough, 0.88, red);
	rough = mix(rough, 0.06, glass);
}
