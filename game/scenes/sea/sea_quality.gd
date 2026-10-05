class_name SeaQuality
extends RefCounted
## Water quality tiers (water_render.md §7). `sea_shadows`: the sea takes the sun's shadows (its shader defines
## WM_NO_SHADOWS otherwise); `shadow_splits`: the sun's cascades (0 off, 1, 2 or 4; §4.6); `tree_shadows`: the
## venue's trees cast (VenueView.apply_quality); `boat_cast_distance`: other boats farther than this from the camera
## cast no sun shadow, 0 = no limit (for the boat view); `drawn_shadow_boats`: boats whose shadow BoatShadows draws
## on the water (§4.7: the own boat and the nearest others within the shadow distance), 0 where the sea takes real
## shadows; `faded_slope`: the per-pixel slope of faded waves (WM_FADED_SLOPE).

enum Tier { L, M, H }

const TIERS := {
	Tier.L: {
		"name": "L", "rings": 120, "segments": 160, "shader": "res://shaders/water_l.gdshader",
		"wake_boats": 1, "wake_radius": 0.0, "spray": "none", "wake_buffer": false, "ssr": false,
		"shadow_splits": 1, "shadow_distance": 45.0, "shadow_split": [0.0, 0.0, 0.0], "shadow_atlas": 2048,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_HARD, "shadow_blend": false, "sea_shadows": false,
		"tree_shadows": false, "boat_cast_distance": 30.0, "drawn_shadow_boats": 1, "faded_slope": false,
	},
	Tier.M: {
		"name": "M", "rings": 180, "segments": 256, "shader": "res://shaders/water_m.gdshader",
		"wake_boats": 7, "wake_radius": 0.0, "spray": "own", "wake_buffer": true, "ssr": false,
		"shadow_splits": 2, "shadow_distance": 90.0, "shadow_split": [0.5, 0.0, 0.0], "shadow_atlas": 2048,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "shadow_blend": false, "sea_shadows": false,
		"tree_shadows": true, "boat_cast_distance": 0.0, "drawn_shadow_boats": 7, "faded_slope": false,
	},
	Tier.H: {
		"name": "H", "rings": 260, "segments": 384, "shader": "res://shaders/water_h.gdshader",
		"wake_boats": 1000, "wake_radius": 400.0, "spray": "all", "wake_buffer": true, "ssr": true,
		"shadow_splits": 4, "shadow_distance": 150.0, "shadow_split": [0.06, 0.26, 0.55], "shadow_atlas": 4096,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "shadow_blend": true, "sea_shadows": true,
		"tree_shadows": true, "boat_cast_distance": 0.0, "drawn_shadow_boats": 0, "faded_slope": true,
	},
}


## Sun shadow bias (water_render.md §4.6): the same on every tier, sized for the split texels above.
const SHADOW_BIAS := 0.1
const SHADOW_NORMAL_BIAS := 2.0
const SHADOW_PANCAKE := 30.0
const SHADOW_BLUR := 1.0


## Development runs only (sail test flags, game/README.md "Measuring performance"): entries merged over every tier.
static var overrides := {}


static func get_tier(tier: Tier) -> Dictionary:
	return TIERS[tier] if overrides.is_empty() else TIERS[tier].merged(overrides, true)


## The DirectionalLight3D mode for a cascade count: 1 one orthogonal map, 2 or 4 parallel splits.
static func shadow_mode(splits: int) -> DirectionalLight3D.ShadowMode:
	match splits:
		1:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## The cascade edges (fractions of the distance) for a tier's cascade count; a count set over the tier (the sail
## test's `--shadow-splits`) without edges of its own takes M's (2) or H's (4).
static func shadow_splits(t: Dictionary) -> Array:
	var sp: Array = t["shadow_split"]
	if t["shadow_splits"] == 2 and sp[0] <= 0.0:
		return TIERS[Tier.M]["shadow_split"]
	if t["shadow_splits"] == 4 and (sp[1] <= 0.0 or sp[2] <= 0.0):
		return TIERS[Tier.H]["shadow_split"]
	return sp


## Screen-space reflections are the environment's (tier H only).
static func apply_environment(env: Environment, tier: Tier) -> void:
	if env:
		env.ssr_enabled = get_tier(tier)["ssr"]


## The sun's shadows for a tier (water_render.md §4.6): cascades sized for a boat seen from the chase and onboard
## cameras, the directional shadow atlas and the soft filter. The atlas and the filter are global rendering
## settings.
static func apply_shadows(sun: DirectionalLight3D, tier: Tier) -> void:
	var t: Dictionary = get_tier(tier)
	if sun:
		sun.shadow_enabled = t["shadow_splits"] > 0
		sun.directional_shadow_mode = shadow_mode(t["shadow_splits"])
		sun.directional_shadow_max_distance = t["shadow_distance"]
		var sp := shadow_splits(t)
		if t["shadow_splits"] >= 2:
			sun.directional_shadow_split_1 = sp[0]
		if t["shadow_splits"] == 4:
			sun.directional_shadow_split_2 = sp[1]
			sun.directional_shadow_split_3 = sp[2]
		sun.directional_shadow_blend_splits = t["shadow_blend"]
		sun.directional_shadow_fade_start = 0.8
		sun.directional_shadow_pancake_size = SHADOW_PANCAKE
		sun.shadow_bias = SHADOW_BIAS
		sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
		sun.shadow_blur = SHADOW_BLUR
		sun.shadow_reverse_cull_face = false
	RenderingServer.directional_shadow_atlas_set_size(t["shadow_atlas"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(t["shadow_soft"])
