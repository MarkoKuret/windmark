class_name SeaQuality
extends RefCounted
## Water quality tiers (water_render.md §7).

enum Tier { L, M, H }

const TIERS := {
	Tier.L: {
		"name": "L", "rings": 120, "segments": 160, "shader": "res://shaders/water_l.gdshader",
		"wake_boats": 1, "wake_radius": 0.0, "spray": "none", "wake_buffer": false, "ssr": false,
	},
	Tier.M: {
		"name": "M", "rings": 180, "segments": 256, "shader": "res://shaders/water_m.gdshader",
		"wake_boats": 7, "wake_radius": 0.0, "spray": "own", "wake_buffer": true, "ssr": false,
	},
	Tier.H: {
		"name": "H", "rings": 260, "segments": 384, "shader": "res://shaders/water_h.gdshader",
		"wake_boats": 1000, "wake_radius": 400.0, "spray": "all", "wake_buffer": true, "ssr": true,
	},
}


static func get_tier(tier: Tier) -> Dictionary:
	return TIERS[tier]


## Screen-space reflections are the environment's (tier H only).
static func apply_environment(env: Environment, tier: Tier) -> void:
	if env:
		env.ssr_enabled = TIERS[tier]["ssr"]
