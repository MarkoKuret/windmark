// Wake ribbon functions shared by wake.gdshader and the offline preview (tests/water_preview.py). Include after
// sea_common.gdshaderinc.

// Drapes a ribbon vertex (scene position, y ignored) on the drawn sea plus 0.1 m, with the grid fade of the sea's
// tier at that distance from the camera origin, then pulls it toward the camera (cam, scene position) so the
// sea's facets never cover it. Between its vertices (at most about 0.8 m apart across) the ribbon is flat while
// the sea keeps the short waves its own grid carries, so the ribbon must clear the sea by the height of those
// waves: 0.15 m plus twice the amplitude of the components shorter than 2 to 4 m that the sea grid carries. The
// pull is along the view ray, which leaves the vertex on its pixel (only the depth changes), and a grazing view
// needs a longer pull for the same height; it is capped at 30 % of the distance.
vec3 wm_wake_drape(vec3 v, vec3 cam, float grid_q, float grid_segments) {
	vec2 xl = vec2(v.x, -v.z) - sea_origin;
	float r = length(xl);
	float s = r < 0.6 ? 0.6 : max(r * (grid_q - 1.0), 6.28318530718 * r / grid_segments);
	float eta = 0.0;
	float short_a = 0.0;
	for (int i = 0; i < n_comp; i++) {
		vec4 c = comp[i];
		float w = wm_fade(c.y, c.z, s);
		float f = fract(c.y * xl.x + c.z * xl.y + c.w);
		eta += w * c.x * cos(WM_TWO_PI * f);
		short_a += w * c.x * (1.0 - wm_fade(c.y, c.z, 1.0));
	}
	float expo = wm_exposure(sea_origin + xl);
	vec3 p = vec3(v.x, eta * expo + 0.1, v.z);
	float clear_h = 0.15 + 2.0 * short_a * expo;
	vec3 to_cam = cam - p;
	float d = max(length(to_cam), 1e-3);
	float elev = max(to_cam.y / d, 0.02);
	return p + to_cam * (min(clear_h / elev, 0.3 * d) / d);
}

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
