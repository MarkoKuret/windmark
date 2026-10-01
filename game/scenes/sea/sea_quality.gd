class_name SeaQuality
extends RefCounted
## Water quality tiers (water_render.md §7). `sea_shadows`: the sea takes the sun's shadows (its shader defines
## WM_NO_SHADOWS otherwise); `drawn_shadow_boats`: boats whose shadow BoatShadows draws on the water (§4.7: the own
## boat and the nearest others within the shadow distance), 0 where the sea takes real shadows.

enum Tier { L, M, H }

const TIERS := {
	Tier.L: {
		"name": "L", "rings": 120, "segments": 160, "shader": "res://shaders/water_l.gdshader",
		"wake_boats": 1, "wake_radius": 0.0, "spray": "none", "wake_buffer": false, "ssr": false,
		"shadow_splits": 2, "shadow_distance": 60.0, "shadow_split": [0.6, 0.0, 0.0], "shadow_atlas": 2048,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "shadow_blend": false, "sea_shadows": false,
		"drawn_shadow_boats": 1,
	},
	Tier.M: {
		"name": "M", "rings": 180, "segments": 256, "shader": "res://shaders/water_m.gdshader",
		"wake_boats": 7, "wake_radius": 0.0, "spray": "own", "wake_buffer": true, "ssr": false,
		"shadow_splits": 4, "shadow_distance": 100.0, "shadow_split": [0.08, 0.36, 0.65], "shadow_atlas": 4096,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "shadow_blend": false, "sea_shadows": false,
		"drawn_shadow_boats": 7,
	},
	Tier.H: {
		"name": "H", "rings": 260, "segments": 384, "shader": "res://shaders/water_h.gdshader",
		"wake_boats": 1000, "wake_radius": 400.0, "spray": "all", "wake_buffer": true, "ssr": true,
		"shadow_splits": 4, "shadow_distance": 150.0, "shadow_split": [0.06, 0.26, 0.55], "shadow_atlas": 4096,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "shadow_blend": true, "sea_shadows": true,
		"drawn_shadow_boats": 0,
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
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if t["shadow_splits"] == 4 \
				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = t["shadow_distance"]
		sun.directional_shadow_split_1 = t["shadow_split"][0]
		if t["shadow_splits"] == 4:
			sun.directional_shadow_split_2 = t["shadow_split"][1]
			sun.directional_shadow_split_3 = t["shadow_split"][2]
		sun.directional_shadow_blend_splits = t["shadow_blend"]
		sun.directional_shadow_fade_start = 0.8
		sun.directional_shadow_pancake_size = SHADOW_PANCAKE
		sun.shadow_bias = SHADOW_BIAS
		sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
		sun.shadow_blur = SHADOW_BLUR
		sun.shadow_reverse_cull_face = false
	RenderingServer.directional_shadow_atlas_set_size(t["shadow_atlas"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(t["shadow_soft"])
