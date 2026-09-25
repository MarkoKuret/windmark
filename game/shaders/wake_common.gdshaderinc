// Wake foam coverage (shared with the offline preview). uv: (across 0..1, distance sailed / 10 m); centre: the
// bow half width as a fraction of the ribbon's; a: row alpha; n1, n2: foam noise samples. The edge vertices sit
// at across 0.2 and 0.8 (|2u - 1| = 0.6), the outer vertices at 0 and 1 are a feathered margin.
float wm_wake_alpha(vec2 uv, float centre, float a, float n1, float n2) {
	float across = abs(uv.x * 2.0 - 1.0);
	// the diverging waves: a band just inside the edges
	float edge = smoothstep(0.38, 0.58, across) * (1.0 - smoothstep(0.62, 0.9, across));
	// the turbulent centre wake, about the hull's width
	float c = 0.6 * centre;
	float mid = 0.8 * (1.0 - smoothstep(0.4 * c, c, across));
	float breakup = smoothstep(0.3, 0.8, n1 * 0.7 + n2 * 0.5);
	return clamp(a * a * (0.7 * edge + mid) * breakup, 0.0, 1.0);
}
