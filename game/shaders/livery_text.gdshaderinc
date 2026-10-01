// Livery text (data_format.md §8, sail_visuals.md §11.2), shared by hull_livery and sail_livery and by the offline
// preview (tests/livery_preview.py): the per-boat text texture of game/scripts/livery/livery_text.gd, one channel of
// coverage, rows of name, number, nation and insignia. Written in the common subset of Godot's shading language and
// GLSL 4.1 (explicit float literals, no Godot built-ins, no uniform hints).

uniform sampler2D livery_text;

// Coverage of the texture rectangle `rect` (u0, v0, u1, v1) at the box coordinates q (0..1 left to right, 0..1
// top to bottom), 0 outside the box. The glyph edge (coverage 0.5) is sharpened over the pixel footprint, so text
// stays crisp close up and fades to its average when smaller than a pixel.
float wm_text_cov(vec2 q, vec4 rect) {
	vec2 qc = clamp(q, vec2(0.0), vec2(1.0));
	float c = texture(livery_text, mix(rect.xy, rect.zw, qc)).r;
	float w = max(fwidth(c), 1e-3);
	float s = clamp((c - 0.5) / (2.0 * w) + 0.5, 0.0, 1.0);
	float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
	return mix(s, c, clamp(2.0 * w - 0.5, 0.0, 1.0)) * inside;
}

// Share of a pixel (footprint px) inside d < 0.
float wm_lv_inside(float d, float px) {
	return clamp(0.5 - d / max(px, 1e-5), 0.0, 1.0);
}

// Share of a pixel (footprint px) inside the band |d| < hw.
float wm_lv_band(float d, float hw, float px) {
	return wm_lv_inside(abs(d) - hw, px);
}
