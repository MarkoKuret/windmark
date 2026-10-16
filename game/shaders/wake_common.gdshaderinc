// Wake ribbon functions shared by wake.gdshader and the offline preview (tests/water_preview.py). Include after
// sea_common.gdshaderinc.

// Drapes a vertex (scene position, y ignored) on the drawn sea plus `lift` (the ribbon: 0.1 m), with the grid
// fade of the sea's tier at that distance from the camera origin, then pulls it toward the camera (cam, scene position) so the
// sea's facets never cover it. Between its vertices (at most about 0.8 m apart across) the ribbon is flat while
// the sea keeps the short waves its own grid carries, so the ribbon must clear the sea by the height of those
// waves: 0.15 m plus twice the amplitude of the components shorter than 2 to 4 m that the sea grid carries. The
// pull is along the view ray, which leaves the vertex on its pixel (only the depth changes), and a grazing view
// needs a longer pull for the same height; it is capped at 30 % of the distance. A vertex lifted above 0.1 m
// needs that much less.
vec3 wm_drape(vec3 v, float lift, vec3 cam, float grid_q, float grid_segments) {
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
	vec3 p = vec3(v.x, eta * expo + lift, v.z);
	float clear_h = max(0.15 + 2.0 * short_a * expo - max(lift - 0.1, 0.0), 0.0);
	vec3 to_cam = cam - p;
	float d = max(length(to_cam), 1e-3);
	float elev = max(to_cam.y / d, 0.02);
	return p + to_cam * (min(clear_h / elev, 0.3 * d) / d);
}

vec3 wm_wake_drape(vec3 v, vec3 cam, float grid_q, float grid_segments) {
	return wm_drape(v, 0.1, cam, grid_q, grid_segments);
}

// Mist sprite coverage (water_render.md §5): a soft round cloud broken up by the foam noise, or (kind 1, a burst's
// sheet of droplets) only the noise's high values, a speckle thinning toward the edge. uv: the quad's 0..1; n: a
// foam noise sample for the sprite.
float wm_mist_alpha(vec2 uv, float n, float kind) {
	vec2 q = uv * 2.0 - 1.0;
	float r2 = clamp(dot(q, q), 0.0, 1.0);
	float soft = (1.0 - r2) * (1.0 - r2);
	float cloud = mix(0.35, 1.0, smoothstep(0.2, 0.8, n));
	float drops = smoothstep(0.5 + 0.2 * r2, 0.62 + 0.2 * r2, n) * 1.8;
	return soft * mix(cloud, drops, kind);
}

// Wake foam coverage (shared with the offline preview, water_render.md §5). uv: (across 0..1, distance sailed /
// 10 m); centre: the turbulent band's half width over the ribbon's (transom ribbon; 0 on the bow ribbon); b: on the
// bow ribbon 0.25 m over the half width, on the transom ribbon the hollow behind a planing transom; a: row alpha;
// age: the row's age over the ribbon's 9 s; n1: fine foam noise in world metres; n2, p: noise along the ribbon. The
// edge vertices sit at across 0.2 and 0.8 (|2u - 1| = 0.6), the outer vertices at 0 and 1 are a feathered margin
// where nothing is drawn.
float wm_wake_alpha(vec2 uv, float centre, float b, float a, float age, float n1, float n2, float p) {
	float s = abs(uv.x * 2.0 - 1.0) / 0.6;
	float t = 9.0 * age;
	float bands = 0.0;
	float hollow = 0.0;
	if (centre <= 0.0 && b > 0.0 && s <= 1.0) {
		// the diverging waves' foam: bands inside the edges, narrow at the bow, widening and softening as they spread
		float bw = (0.5 + 0.55 * t) * b / 0.25;
		float band = smoothstep(1.0 - bw, 1.0 - 0.35 * bw, s) * (1.0 - smoothstep(0.9, 1.0, s));
		float tl = 0.5 + 0.25 * age;
		float lace = smoothstep(tl, tl + 0.35, 0.6 * (n1 * 0.7 + n2 * 0.5) + 0.4 * p);
		bands = band * lace * (1.0 - smoothstep(0.05, 0.38, age)) * 0.65 / (1.0 + 0.25 * t);
	} else if (centre > 0.0) {
		hollow = b;
	}
	// the turbulent wake, hollow right behind a planing transom
	float mid = (1.0 - smoothstep(0.6 * centre, centre, s)) * (1.0 - 0.85 * hollow * (1.0 - smoothstep(0.25, 0.75, s)));
	// the bubbles break up into clumps and streaks, and with age into separate patches that thin out
	float th = 0.45 + 0.35 * age;
	float breakup = smoothstep(th, th + 0.4 - 0.25 * age, 0.6 * (n1 * 0.7 + n2 * 0.5) + 0.4 * p);
	return clamp(a * a * (bands + 0.9 * mid * breakup), 0.0, 1.0);
}
