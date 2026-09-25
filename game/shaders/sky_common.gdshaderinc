// Daytime sky radiance, shared by sky.gdshader and the offline preview renderer (tests/water_preview.py).
// Common subset of Godot's shading language and GLSL 3.30; everything comes in as parameters. Scene axes: y up.
// The base gradient is the same two-colour ramp the water uses for its slope contrast (sea_common wm_sky_ramp).

float wm_hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wm_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wm_hash21(i);
	float b = wm_hash21(i + vec2(1.0, 0.0));
	float c = wm_hash21(i + vec2(0.0, 1.0));
	float d = wm_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float wm_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * wm_vnoise(p);
		p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
		a *= 0.5;
	}
	return s;
}

// d: unit view direction; sun: unit direction toward the sun; horizon, zenith: the ramp colours (linear);
// sun_col: sun colour times energy; cover: cloud cover 0..1; cloud_off: cloud layer offset (static per preset);
// disc: 1 to draw the sun disc (0 for the radiance pass, where the light's own specular already gives the glint).
vec3 wm_sky_color(vec3 d, vec3 sun, vec3 horizon, vec3 zenith, vec3 sun_col, float cover, vec2 cloud_off, float disc) {
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.45));
	// below the horizon: a darker sea haze, so reflections of low directions are not brighter than the horizon
	col = mix(col, horizon * vec3(0.55, 0.62, 0.70), smoothstep(0.0, -0.25, h));
	float mu = max(dot(d, sun), 0.0);
	// forward scattering around the sun, stronger near the horizon
	float haze = 1.0 - clamp(abs(h) * 2.5, 0.0, 1.0);
	col += sun_col * (0.03 * pow(mu, 8.0) * (0.5 + haze) + 0.15 * pow(mu, 64.0));
	// clouds: a thin layer projected on a plane above the camera
	if (h > 0.0 && cover > 0.0) {
		vec2 uv = d.xz / (h + 0.06) * 0.55 + cloud_off;
		float n = wm_fbm(uv * 1.7);
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.35, n) * smoothstep(0.0, 0.12, h);
		vec3 lit = mix(vec3(0.80, 0.83, 0.88), vec3(1.10, 1.06, 1.00), 0.5 + 0.5 * mu) * (0.85 + 0.3 * n);
		col = mix(col, lit * (0.55 + 0.45 * horizon.g / max(zenith.g, 1e-3) * 0.5), c * 0.85);
	}
	// sun disc (0.53 deg across) with a soft rim
	float disc_mu = smoothstep(0.999955, 0.999985, mu);
	col += disc * disc_mu * sun_col * 20.0;
	return col;
}
