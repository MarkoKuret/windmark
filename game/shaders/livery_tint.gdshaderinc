// Tinted liveries (data_format.md §8.5 "Tinted liveries"): a boat in a livery other than the baked one is drawn on
// the baked textures with their colours substituted per texel. Shared by boat_atlas.gdshader (the hull, transom and
// keel regions of the atlas) and sail_baked.gdshader (the cloth zones of a sail), and compiled by the offline
// preview (tests/livery_preview.py); common subset of Godot's shading language and GLSL 4.1.

// Luminance of a linear colour.
float wm_lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// The baked texel `baked` whose part was baked in `from`, recoloured to `to`: to * (baked / from)^k. k = 1 keeps the
// baked variation, scuffs and dirt as they are (relative to the colour); a smaller k fades them out.
vec3 wm_tint(vec3 baked, vec3 from, vec3 to, float k) {
	vec3 r = max(baked, vec3(1e-4)) / max(from, vec3(1e-4));
	return to * exp(k * log(r));
}

// The exponent of wm_tint for a part going from `from` to `to`: 1 toward a darker colour (a navy hull's light
// scratches stay on a black one), falling toward a lighter one (a white hull shows none of them).
float wm_tint_k(vec3 from, vec3 to) {
	return clamp(wm_lum(from) / max(wm_lum(to), 1e-4), 0.0, 1.0);
}
