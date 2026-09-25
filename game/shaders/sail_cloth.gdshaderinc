// Sail cloth (sail_visuals.md §11.1), shared by shaders/sail.gdshader and the offline preview
// (tests/sail_preview.py): the panel layout, seams and stitching, edge tapes, corner patches, batten pockets,
// tell-tales and the fine structure of the cloth, all procedural in the sail's cloth coordinates. Written in the
// common subset of Godot's shading language and GLSL 4.1: explicit float literals, no Godot built-ins, no
// uniform hints.
//
// Cloth coordinates are the generator's uv0 (metres: along the row aft from the luff, and up the sail as the
// summed mean row spacing) and the
// row fraction uv1.y (1 at the foot, 0 at the head). They are the same on both cloth layers, so both sides show
// the same panels. The flat plan puts them back in the sail's plane: the rows leave the luff at the angle
// `cloth_shear` = (cos, sin) of the angle between the luff and the rows.
//
// Every line is box-filtered over the pixel footprint `px` (m), so seams, stitching and fibres fade to their
// average instead of shimmering when they are smaller than a pixel.

uniform int cloth_style = 0;                    // 0 woven polyester, cross-cut; 1 laminate, tri-radial; 2 nylon, tri-radial
uniform int cloth_kind = 0;                     // 0 main, 1 headsail, 2 spinnaker
uniform vec2 cloth_shear = vec2(0.0, 1.0);
uniform vec2 cloth_tack = vec2(0.0, 0.0);       // flat-plan corners, m
uniform vec2 cloth_clew = vec2(3.0, 0.0);
uniform vec2 cloth_head = vec2(0.0, 9.0);
uniform vec2 cloth_head_aft = vec2(0.0, 9.0);   // top of the leech (= head on a pointed head)
uniform float cloth_rows = 2.0;
uniform float cloth_chord[48];                  // row chords along the row, m, foot first
uniform float cloth_panel = 0.9;                // panel width, m
uniform float cloth_patch = 0.5;                // corner patch radius, m
uniform int cloth_battens = 0;
uniform int cloth_telltales = 0;

const float WM_SC_PI = 3.14159265359;

vec2 wm_cloth_plan(vec2 uv0) {
	return vec2(uv0.x * cloth_shear.y, uv0.y + uv0.x * cloth_shear.x);
}

float wm_cloth_chord(float v1) {
	float r = clamp((1.0 - v1) * (cloth_rows - 1.0), 0.0, cloth_rows - 1.0);
	int i = int(floor(r));
	int j = min(i + 1, int(cloth_rows) - 1);
	return mix(cloth_chord[i], cloth_chord[j], r - float(i));
}

// Share of a pixel (footprint px, centred at signed distance d) covered by the band |d| < hw.
float wm_band(float d, float hw, float px) {
	float lo = max(d - 0.5 * px, -hw);
	float hi = min(d + 0.5 * px, hw);
	return clamp((hi - lo) / px, 0.0, 1.0);
}

// Share of a pixel inside d < 0 (a filled edge).
float wm_inside(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

// Signed distance to the nearest of the lines s = k * w.
float wm_period(float s, float w) {
	return (fract(s / w + 0.5) - 0.5) * w;
}

float wm_hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// Angle of q about a corner, measured from the direction toward the middle of the sail (so it never wraps
// inside the sail).
float wm_corner_angle(vec2 q, vec2 into) {
	vec2 b = normalize(into);
	return atan(dot(q, vec2(-b.y, b.x)), dot(q, b));
}

// A seam: one extra ply of width 2 hw with two rows of stitching.
void wm_seam(float d, float hw, float px, inout float layers, inout float stitch) {
	layers += wm_band(d, hw, px);
	stitch += 0.8 * (wm_band(abs(d) - 0.65 * hw, 0.0006, px));
}

// Reinforcement patch at a corner: radial fingers of staggered length over two full plies.
void wm_patch(vec2 p, vec2 a, vec2 into, float r0, float seed, float px, inout float layers, inout float stitch) {
	if (r0 <= 0.0) {
		return;
	}
	vec2 q = p - a;
	float r = length(q);
	if (r > r0 * 1.2 + px) {
		return;
	}
	float ang = wm_corner_angle(q, into);
	float f = floor(ang / 0.26);
	float rf = r0 * (0.75 + 0.25 * wm_hash(f + seed));
	float k1 = wm_inside(r - 0.42 * r0, px);
	float k2 = wm_inside(r - 0.68 * r0, px);
	float k3 = wm_inside(r - rf, px);
	layers += 0.9 * (k1 + k2) + 0.7 * k3;
	stitch += 0.7 * (wm_band(r - 0.42 * r0, 0.0006, px) + wm_band(r - 0.68 * r0, 0.0006, px));
	// the fingers' side seams
	float side = (fract(ang / 0.26 + 0.5) - 0.5) * 0.26 * r;
	stitch += 0.5 * wm_band(side, 0.0006, px) * k3 * (1.0 - k2);
}

// The cloth at a point. uv0: cloth coordinates (m); v1: uv1.y; px: pixel footprint (m).
// layers: plies over the single cloth (seams, tapes, patches, batten pockets, battens);
// stitch: thread lines 0..1; panel: 0..1 per panel (0.5 where panels are too small to tell apart);
// fibre: scrim fibres (laminate) or ripstop threads (nylon) 0..1; mark: tell-tale coverage 0..1.
void wm_cloth(vec2 uv0, float v1, float px, out float layers, out float stitch, out float panel, out float fibre,
		out float mark) {
	layers = 0.0;
	stitch = 0.0;
	panel = 0.5;
	fibre = 0.0;
	mark = 0.0;
	px = max(px, 1e-4);
	vec2 p = wm_cloth_plan(uv0);
	float sn = cloth_shear.y;
	vec2 hd = 0.5 * (cloth_head + cloth_head_aft);
	vec2 mid = (cloth_tack + cloth_clew + hd) / 3.0;
	vec2 dl = normalize(cloth_head_aft - cloth_clew);   // up the leech
	float w = cloth_panel;
	float hw = cloth_style == 2 ? 0.005 : (cloth_style == 1 ? 0.009 : 0.008);

	// panels and seams
	float pid = 0.0;
	vec2 grain = dl;           // the panel's fibre direction
	float radial = 0.0;        // angle * reach in a radial panel group, for the load-path fibres
	if (cloth_style == 0) {
		// cross-cut: seams square to the leech
		float s = dot(p - cloth_clew, dl);
		pid = floor(s / w);
		wm_seam(wm_period(s, w), hw, px, layers, stitch);
		grain = vec2(-dl.y, dl.x);
	} else {
		// tri-radial: panel groups fanning from the head, the tack and the clew, cross-cut across the middle
		vec2 fm = 0.5 * (cloth_tack + cloth_clew);
		float foot = length(cloth_clew - cloth_tack);
		vec2 ca[3];
		ca[0] = hd;
		ca[1] = cloth_tack;
		ca[2] = cloth_clew;
		float cr[3];
		cr[0] = 0.56 * length(hd - fm);
		cr[1] = 0.40 * foot;
		cr[2] = 0.52 * foot;
		float dmin = 1.0;
		float dsec = 1e6;
		int zmin = 3;
		int zsec = 3;
		for (int k = 0; k < 3; k++) {
			float d = length(p - ca[k]) / cr[k];
			if (d < dmin) {
				dsec = dmin;
				zsec = zmin;
				dmin = d;
				zmin = k;
			} else if (d < dsec) {
				dsec = d;
				zsec = k;
			}
		}
		// the seam between two groups: the metric distance to the line where their scaled distances meet
		vec2 g1 = zmin < 3 ? (p - ca[min(zmin, 2)]) / max(length(p - ca[min(zmin, 2)]), 1e-4) / cr[min(zmin, 2)] : vec2(0.0);
		vec2 g2 = zsec < 3 ? (p - ca[min(zsec, 2)]) / max(length(p - ca[min(zsec, 2)]), 1e-4) / cr[min(zsec, 2)] : vec2(0.0);
		float bd = (min(dsec, 4.0) - dmin) / max(length(g2 - g1), 1e-3);
		wm_seam(bd, 1.25 * hw, px, layers, stitch);
		if (zmin < 3) {
			vec2 a = ca[zmin];
			vec2 q = p - a;
			float ang = wm_corner_angle(q, mid - a);
			float dphi = w / cr[zmin];
			pid = float(zmin) * 64.0 + floor(ang / dphi);
			if (bd > 0.0) {
				wm_seam(wm_period(ang, dphi) * length(q), hw, px, layers, stitch);
			}
			grain = q / max(length(q), 1e-4);
			radial = ang * cr[zmin];
		} else {
			float s = dot(p - cloth_clew, dl);
			pid = 200.0 + floor(s / w);
			wm_seam(wm_period(s, w), hw, px, layers, stitch);
			grain = vec2(-dl.y, dl.x);
			radial = dot(p, dl);
		}
	}
	panel = mix(wm_hash(pid + 7.0 * float(cloth_kind)), 0.5, clamp((px - 0.05 * w) / (0.2 * w), 0.0, 1.0));

	// edge tapes
	float d_luff = uv0.x * sn;
	float d_leech = (wm_cloth_chord(v1) - uv0.x) * sn;
	float d_foot = uv0.y * sn;
	float t_luff = cloth_kind == 2 ? 0.02 : (cloth_kind == 1 ? 0.045 : 0.035);
	float t_leech = cloth_kind == 2 ? 0.02 : 0.025;
	float t_foot = cloth_kind == 2 ? 0.02 : 0.03;
	float tape = max(wm_inside(d_luff - t_luff, px), max(wm_inside(d_leech - t_leech, px), wm_inside(d_foot - t_foot, px)));
	if (cloth_kind == 0 && length(cloth_head_aft - cloth_head) > 0.05) {
		tape = max(tape, wm_inside((cloth_head.y - uv0.y) * sn - 0.03, px));
	}
	layers += 1.2 * tape;
	stitch += 0.7 * (wm_band(d_luff - t_luff, 0.0006, px) + wm_band(d_leech - t_leech, 0.0006, px)
			+ wm_band(d_foot - t_foot, 0.0006, px));

	// corner patches
	float rp = cloth_patch;
	wm_patch(p, cloth_tack, mid - cloth_tack, 0.8 * rp, 11.0, px, layers, stitch);
	wm_patch(p, cloth_clew, mid - cloth_clew, rp, 23.0, px, layers, stitch);
	wm_patch(p, cloth_head, mid - cloth_head, rp, 37.0, px, layers, stitch);
	if (length(cloth_head_aft - cloth_head) > 0.05) {
		wm_patch(p, cloth_head_aft, mid - cloth_head_aft, 0.6 * rp, 41.0, px, layers, stitch);
	}

	// batten pockets on the main: square to the leech, the top one full length
	if (cloth_battens > 0) {
		float ll = length(cloth_head_aft - cloth_clew);
		vec2 nf = vec2(-dl.y, dl.x);
		if (nf.x > 0.0) {
			nf = -nf;
		}
		for (int k = 1; k <= 6; k++) {
			if (k > cloth_battens) {
				break;
			}
			float f = float(k) / float(cloth_battens + 1);
			vec2 b = cloth_clew + dl * ll * f;
			float full = b.x / max(-nf.x, 0.2);
			float lb = k == cloth_battens ? full - 0.06 : (0.22 + 0.10 * f) * full;
			float t = dot(p - b, nf);
			float across = dot(p - b, dl);
			float along = wm_inside(t - lb, px) * wm_inside(-0.8 - t, px);
			float pocket = wm_band(across, 0.028, px) * along;
			layers += 1.5 * pocket;
			layers += 5.0 * wm_band(across, 0.011, px) * wm_inside(t - (lb - 0.04), px) * wm_inside(-0.8 - t, px);
			layers += wm_band(across, 0.06, px) * wm_inside(t - 0.2, px) * wm_inside(-0.8 - t, px);
			stitch += 0.7 * (wm_band(abs(across) - 0.028, 0.0006, px)) * along;
		}
	}

	// fine structure
	vec2 gp = vec2(-grain.y, grain.x);
	if (cloth_style == 1) {
		// laminate scrim: load-path fibres along the panel's grain and a light diagonal grid
		float s1 = dot(p, grain * 0.866 + gp * 0.5);
		float s2 = dot(p, grain * 0.866 - gp * 0.5);
		fibre = max(wm_band(wm_period(radial, 0.022), 0.0005, px),
				0.7 * max(wm_band(wm_period(s1, 0.045), 0.0004, px), wm_band(wm_period(s2, 0.045), 0.0004, px)));
	} else if (cloth_style == 2) {
		// ripstop: a thicker thread every 6 mm both ways
		fibre = max(wm_band(wm_period(dot(p, grain), 0.006), 0.0004, px), wm_band(wm_period(dot(p, gp), 0.006), 0.0004, px));
	}

	// tell-tales on a headsail: three short strips just aft of the luff
	if (cloth_telltales > 0) {
		float ly = cloth_head.y;
		for (int k = 1; k <= 3; k++) {
			float lk = ly * float(k) / 4.0;
			float along = wm_inside(0.27 - uv0.x, px) * wm_inside(uv0.x - 0.44, px);
			mark = max(mark, wm_band(uv0.y - lk + 0.12 * (uv0.x - 0.27), 0.007, px) * along);
		}
	}
	stitch = clamp(stitch, 0.0, 1.0);
}
