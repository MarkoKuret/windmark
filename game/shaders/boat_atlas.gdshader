// The boat material (sail_visuals.md §11.4, data_format.md §8.5, game/scripts/boat_materials.gd): every opaque
// surface of a boat but the sails in one material, so a node is one draw. Each vertex carries its slot in COLOR.g
// (slot id / 255; COLOR.r is the baked ambient occlusion). The slot table gives the slot's mean colour (linear),
// roughness, metallic, its tile in the shared tiling atlas (a 4 x 2 grid of 512 tiles: tile_color, tile_mr,
// tile_normal) with the tile size in metres of uv0, and its livery region:
//   0 none (the slot colour), 1 hull, 2 deck (and the coachroof's aft face on its own rectangle of the deck image),
//   3 transom (the boat's livery atlas on uv1), 4 keel (the atlas in side
//   view of the model frame), 5 keel colour (the slot colour, which the livery sets).
// With the livery atlas (bk_on) the regions read its albedo, normal and ORM maps (the deck's ORM blue is the
// non-slip mask, which picks the non-slip tile's detail over the gelcoat's; on the hull and transom the ORM's red
// and blue are the colour masks of a tinted livery, tn_on: the colour zone and the paint coverage, data_format.md
// §8.5 "Tinted liveries", livery_tint.gdshaderinc); without it the regions take the slot colours the livery set,
// and the topsides the procedural hull livery (hull_livery.gdshaderinc). The boat's name and number (hull) and
// name (transom) come from its text texture. Tangent frames come from screen-space derivatives
// (wm_perturb): the meshes carry no tangents. The baked AO and the atlas occlusion darken the ambient and reflected
// light only.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int SLOTS = 32;
const int HULL_GELCOAT = 0;

// the slot table: colour (linear rgb, a: normal strength), pbr (roughness, metallic, tile index, 1 / tile size m),
// map (region, ao strength, specular, steep: 1 when a steep face reads its own map (the coachroof's aft face, on its
// own rectangle of the deck image), 0 when a steep deck face takes the slot's plain colour)
uniform vec4 slot_color[SLOTS];
uniform vec4 slot_pbr[SLOTS];
uniform vec4 slot_map[SLOTS];

// the shared tiling atlas (generated/boats/_tex) and its layout
uniform sampler2D tile_color : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_mr : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile_grid = vec2(4.0, 2.0);
uniform float tile_inset = 0.002;
// the detail textures' means (linear grey of the colour, roughness channel), so the detail varies around 1
uniform float detail_mean = 0.92;
uniform float rough_mean = 0.8;
// the deck's tiles: gelcoat tile, 1 / its size, non-slip tile, 1 / its size
uniform vec4 deck_tiles = vec4(0.0, 2.0, 1.0, 10.0);
uniform float ns_normal_scale = 1.0;
uniform float albedo_max = 0.8;

// the boat's livery atlas (data_format.md §8.5 "Staged boat atlas"): rectangle per region (index 1 hull, 2 deck,
// 3 transom, 4 keel), the keel image's rectangle in the model frame (forward min, top, length, height)
uniform bool bk_on = false;
uniform sampler2D bk_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bk_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 bk_rect[5];
uniform vec4 bk_keel = vec4(0.0, 0.0, 1.0, 1.0);

// the boat's name on the transom: box on the transom uv1 and its rectangle in the text texture
uniform int tr_on = 0;
uniform vec4 tr_box = vec4(0.0);
uniform vec4 tr_tex = vec4(0.0);

// a tinted livery (data_format.md §8.5): per part the colour the atlas was baked in, the boat's colour and the
// exponent of wm_tint: 0 antifouling, 1 boot stripe, 2 graphic colour 0, 3 graphic colour 1, 4 topsides paint,
// 5 keel (linear)
uniform int tn_on = 0;
uniform vec3 tn_from[6];
uniform vec3 tn_to[6];
uniform float tn_k[6];

#include "res://shaders/hull_livery.gdshaderinc"
#include "res://shaders/livery_baked.gdshaderinc"
#include "res://shaders/livery_tint.gdshaderinc"

// A hull or transom texel of the atlas recoloured to the boat's livery: its zone's colours (ORM red) blended
// with the paint's by the paint coverage (ORM blue).
vec3 wm_tint_hull(vec3 baked, float zone, float paint) {
	int z = clamp(int(zone * 3.0 + 0.5), 0, 3);
	vec3 f = mix(tn_from[z], tn_from[4], paint);
	vec3 t = mix(tn_to[z], tn_to[4], paint);
	float k = mix(tn_k[z], tn_k[4], paint);
	return wm_tint(baked, f, t, k);
}

varying flat int v_slot;
varying vec2 v_keel;
varying float v_up;
varying float v_port;

void vertex() {
	v_slot = clamp(int(COLOR.g * 255.0 + 0.5), 0, SLOTS - 1);
	v_keel = vec2((VERTEX.z - bk_keel.x) / bk_keel.z, (bk_keel.y - VERTEX.y) / bk_keel.w);
	v_up = abs(NORMAL.y);
	v_port = VERTEX.x > 0.0 ? 1.0 : 0.0;
}

// A tile of the tiling atlas at the metric coordinates uv (already scaled to tiles): wrapped inside its cell, with
// the gradients of the unwrapped coordinates so the wrap shows no mip seam.
vec4 tile_tex(sampler2D s, vec2 uv, float tile) {
	vec2 cell = vec2(mod(tile, tile_grid.x), floor(tile / tile_grid.x));
	vec2 inner = vec2(1.0 - 2.0 * tile_inset);
	vec2 a = (cell + tile_inset + fract(uv) * inner) / tile_grid;
	vec2 g = inner / tile_grid;
	return textureGrad(s, a, dFdx(uv) * g, dFdy(uv) * g);
}

void fragment() {
	int s = v_slot;
	vec4 sc = slot_color[s];
	vec4 sp = slot_pbr[s];
	vec4 sm = slot_map[s];
	int region = int(sm.x + 0.5);
	vec2 tuv = UV * sp.w;
	float tile = sp.z;
	if (region == 2) {
		// the deck: the gelcoat's detail, the non-slip's where the mask says (below)
		tuv = UV * deck_tiles.y;
		tile = deck_tiles.x;
	}
	vec3 det = tile_tex(tile_color, tuv, tile).rgb / detail_mean;
	vec4 mr = tile_tex(tile_mr, tuv, tile);
	vec3 tn = tile_tex(tile_normal, tuv, tile).rgb;
	float nscale = sc.a;
	float rdet = mr.g / rough_mean;
	vec3 a = sc.rgb * det;
	float rough = sp.x * rdet;
	float metal = sp.y * mr.b;
	float occ = 1.0;
	vec3 n = NORMAL;
	if (bk_on && region >= 1 && region <= 4) {
		vec2 t = clamp(region == 4 ? v_keel : UV2, vec2(0.0), vec2(1.0));
		vec4 r = bk_rect[region];
		vec2 at = r.xy + t * r.zw;
		vec3 base = texture(bk_albedo, at).rgb;
		if (region == 4) {
			// the keel: its colour in side view, the slot's roughness and detail
			if (tn_on != 0) {
				base = wm_tint(base, tn_from[5], tn_to[5], tn_k[5]);
			}
			a = base * det;
		} else {
			vec3 orm = texture(bk_orm, at).rgb;
			float flat_k = 1.0;
			float occ_map = 1.0;
			if (region == 2) {
				occ_map = orm.r;
			} else if (tn_on != 0) {
				base = wm_tint_hull(base, orm.r, orm.b);
			}
			if (region == 2) {
				// the deck's non-slip by the mask; steep faces (coamings, cabin sides) keep plain gelcoat
				flat_k = max(smoothstep(0.35, 0.7, v_up), sm.w);
				float ns = orm.b * flat_k;
				vec2 nuv = UV * deck_tiles.w;
				det = mix(det, tile_tex(tile_color, nuv, deck_tiles.z).rgb / detail_mean, ns);
				rdet = mix(rdet, tile_tex(tile_mr, nuv, deck_tiles.z).g / rough_mean, ns);
				tn = mix(tn, tile_tex(tile_normal, nuv, deck_tiles.z).rgb, ns);
				nscale = mix(nscale, ns_normal_scale, ns);
			}
			// steep deck faces (coamings, the coachroof's sides and aft face) take the texels of their footprint, a line
			// in the plan: plain gelcoat in the livery's deck colour there, so nothing painted on the top smears down
			a = mix(sc.rgb, base, flat_k) * det;
			rough = mix(sp.x * rdet, orm.g * rdet, flat_k);
			occ = mix(1.0, occ_map, flat_k);
			// the livery's relief (vinyl and tape edges, fairing, non-slip edges, sealant, painted fittings)
			vec3 nb = wm_normal_texel(texture(bk_normal, at).rgb);
			nb = mix(vec3(0.0, 0.0, 1.0), nb, flat_k);
			n = wm_perturb(n, VERTEX, t, nb, -1.0);
			if (region == 1 && ov_on != 0) {
				// the boat's name and number: cut vinyl over the paint, a faint line of dirt along its edge
				vec2 c = wm_ov_hull(UV2);
				a = mix(a, ov_color * det, c.x);
				a *= 1.0 - 0.12 * c.y;
				rough = mix(rough, 0.24, c.x);
			} else if (region == 3 && tr_on != 0) {
				vec2 q = (UV2 - tr_box.xy) / max(tr_box.zw - tr_box.xy, vec2(1e-6));
				vec2 c = wm_text_cov2(q, tr_tex);
				a = mix(a, ov_color * det, c.x);
				a *= 1.0 - 0.12 * c.y * (1.0 - c.y) * 4.0;
				rough = mix(rough, 0.24, c.x);
			}
		}
	} else if (s == HULL_GELCOAT && hl_on != 0) {
		// the procedural livery on the topsides (hull_livery.gdshaderinc, data_format.md §8)
		a = det * wm_hull_livery(UV2, v_port);
	}
	// the tile's relief (orange peel, non-slip diamonds, weave, braid, brushed grain)
	vec3 m = wm_normal_texel(tn);
	m.xy *= nscale;
	n = wm_perturb(n, VERTEX, tuv, m, -1.0);
	NORMAL = n;
	ALBEDO = min(a, vec3(albedo_max));
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = sm.z;
	AO = mix(1.0, COLOR.r, sm.y) * occ;
	AO_LIGHT_AFFECT = 0.0;
}
