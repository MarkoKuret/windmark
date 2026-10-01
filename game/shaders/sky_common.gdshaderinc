// Daytime sky radiance, shared by sky.gdshader and the offline preview renderer (tests/water_preview.py).
// Common subset of Godot's shading language and GLSL 3.30; everything comes in as parameters. Scene axes: y up.
// The colours come from SkyRig (scenes/sea/sky_rig.gd), which also hands them to the sea shader.
// water_render.md §4.5.

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

// The two coarse octaves of the cloud noise (the cloud masses).
float wm_fbm_lo(vec2 p) {
	return 0.5 * wm_vnoise(p) + 0.25 * wm_vnoise(vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y));
}

// The three fine octaves (the billows on their edges).
float wm_fbm_hi(vec2 p) {
	float s = 0.0;
	float a = 0.125;
	p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
	p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
	for (int i = 0; i < 3; i++) {
		s += a * wm_vnoise(p);
		p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
		a *= 0.5;
	}
	return s;
}

// d: unit view direction; sun: unit direction toward the sun; horizon, zenith: the ramp colours (linear);
// sun_col: sun colour times energy; cover: cloud cover 0..1; cloud_off: cloud layer offset (static per preset);
// disc: 1 to draw the sun disc and its halo (0 for the radiance pass, where the light's own specular already gives
// the glint).
vec3 wm_sky_color(vec3 d, vec3 sun, vec3 horizon, vec3 zenith, vec3 sun_col, float cover, vec2 cloud_off, float disc) {
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.45));
	// below the horizon: a darker sea haze, so reflections of low directions are not brighter than the horizon
	col = mix(col, horizon * vec3(0.55, 0.62, 0.70), smoothstep(0.0, -0.25, h));
	float mu = max(dot(d, sun), 0.0);
	// forward scattering around the sun, stronger near the horizon
	float haze = 1.0 - clamp(abs(h) * 2.5, 0.0, 1.0);
	col += sun_col * (0.03 * pow(mu, 8.0) * (0.5 + haze) + 0.12 * pow(mu, 64.0));
	// fair-weather cumulus: a layer projected on a plane above the camera. The coarse octaves give the cloud masses,
	// the fine ones their billowed edges; one more look-up of the coarse octaves a little toward the sun lights the
	// side facing the sun and leaves the far side and the base grey.
	if (h > 0.0 && cover > 0.0) {
		vec2 uv = d.xz / (h + 0.06) * 0.55 + cloud_off;
		vec2 p = uv * 1.7;
		float lo = wm_fbm_lo(p);
		float n = lo + wm_fbm_hi(p);
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.16, n) * smoothstep(0.0, 0.10, h);
		if (c > 0.0) {
			vec2 to_sun = normalize(sun.xz + vec2(1e-4, 0.0));
			float lo_s = wm_fbm_lo(p + to_sun * 0.35);
			float lit = clamp(0.62 + 5.0 * (lo - lo_s) - 1.2 * max(n - (1.0 - cover) - 0.25, 0.0), 0.0, 1.0);
			vec3 base = mix(horizon, zenith, 0.35) * 0.85 + sun_col * 0.07;
			vec3 top = sun_col * 0.40 + horizon * 0.25;
			vec3 cc = mix(base, top, lit);
			// thin edges toward the sun glow (silver lining)
			cc += sun_col * pow(mu, 10.0) * (1.0 - c) * 0.8;
			// distant clouds fade into the horizon haze
			cc = mix(horizon * 1.08, cc, smoothstep(0.0, 0.3, h));
			col = mix(col, cc, c * 0.95);
		}
	}
	// sun disc (0.53 deg across) with a soft rim, and a tight bright halo of a few degrees
	float disc_mu = smoothstep(0.999955, 0.999985, mu);
	col += disc * sun_col * (20.0 * disc_mu + 0.35 * pow(mu, 2048.0) + 0.06 * pow(mu, 256.0));
	return col;
}
