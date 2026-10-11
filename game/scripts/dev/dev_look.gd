class_name DevLook
extends RefCounted
## The look settings a developer changes to judge the picture (hud.md §18): one function per setting, called by the
## sail scene's startup flags and by the look panel (LookPanel, F9), so the two stay the same. Each setter stores
## the value where the game reads it (Settings' run overrides, LookFx, SkyRig, Sea, BoatShadows, ChaseCamera, the
## scene) and applies it to what the scene already has; a scene that is still being built (its `built` member
## false: the flags) picks the stored value up as it builds. Nothing here is saved. The scene is duck typed: any
## node with the sail scene's `sea`, `sky`, `shadows`, `rig`, `boat_views` members works.

const AA_MODES := ["off", "fxaa", "smaa"]
## the old light preset names (`--sky=`), aliases of a time of day and conditions (Daylight.ALIASES)
const PRESETS := ["clear", "fair", "hazy", "late"]
const CONDITIONS := ["clear", "fair", "hazy", "overcast"]
## the time of day row's steps (h)
const TIME_STEP := 0.5
## the grade and vignette strength rows' range and step
const STRENGTH_MIN := 0.0
const STRENGTH_MAX := 1.5
const STRENGTH_STEP := 0.1
## the render scale choices: 0 keeps the player's setting (Settings.render_scale), the rest are run overrides
const RENDER_SCALES := [0.0, 0.5, 0.67, 0.75, 0.85, 1.0]
## haze factor on the light's haze_max
const HAZE_MIN := 0.0
const HAZE_MAX := 1.5


static func _member(scene: Node, member: String) -> Variant:
	return scene.get(member) if scene != null else null


## The scene has been built (its `built` member, else ready): a setter applies at once; otherwise the scene
## applies the stored value while it builds.
static func _live(scene: Node) -> bool:
	if scene == null or not scene.is_inside_tree():
		return false
	return bool(scene.get("built")) if "built" in scene else scene.is_node_ready()


static func _env(scene: Node) -> Environment:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).environment() if sky is SkyRig else null


# ---- anti-aliasing and render scale (the root viewport) ---------------------------------------------------------

## `--aa=off|fxaa|smaa`: the screen-space anti-aliasing (water_render.md §7), over the project's SMAA.
static func set_aa(scene: Node, mode: String) -> void:
	Settings.aa_override = mode.to_lower()
	if _live(scene):
		Settings.current().apply_render_scale(scene.get_tree().root)


## The anti-aliasing in effect: "off", "fxaa" or "smaa" (the root viewport's when the scene runs).
static func aa(scene: Node) -> String:
	if _live(scene):
		match scene.get_tree().root.screen_space_aa:
			Viewport.SCREEN_SPACE_AA_FXAA:
				return "fxaa"
			Viewport.SCREEN_SPACE_AA_SMAA:
				return "smaa"
		return "off"
	return Settings.aa_override if Settings.aa_override != "" else "smaa"


## `--render-scale=`: this run's render scale (0.5 to 1, or 50 to 100); 0 goes back to the player's setting.
static func set_render_scale(scene: Node, s: float) -> void:
	Settings.render_scale_override = s / 100.0 if s > 1.0 else s
	if _live(scene):
		Settings.current().apply_render_scale(scene.get_tree().root)


## The run's render scale override (0: the setting).
static func render_scale_choice() -> float:
	return Settings.render_scale_override


# ---- the finishing look (LookFx) ----------------------------------------------------------------------------------

## `--look=off`: the colour grade, the vignette, the contact shading and the depth of field together.
static func set_look(scene: Node, on: bool) -> void:
	LookFx.enabled = on
	var sky: Variant = _member(scene, "sky")
	var env := _env(scene)
	if env != null:
		(sky as SkyRig).apply_grade()
		LookFx.apply_quality(env, LookFx.tier)
	_vignette(scene)


static func _vignette(scene: Node) -> void:
	var rig: Variant = _member(scene, "rig")
	if rig is CameraRig:
		(rig as CameraRig).look.strength = LookFx.vignette_for(CameraRig.is_clip((rig as CameraRig).mode))


## `--grade=<k>`: the colour grade's strength (0 to 1.5, 0 off; water_render.md §4.5).
static func set_grade_strength(scene: Node, k: float) -> void:
	LookFx.grade_strength = clampf(k, STRENGTH_MIN, STRENGTH_MAX)
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig and (sky as SkyRig).is_inside_tree():
		(sky as SkyRig).apply_grade()


static func grade_strength() -> float:
	return LookFx.grade_strength


## `--vignette=<k>`: the vignette's strength, a factor on every camera's (0 to 1.5, 0 off).
static func set_vignette_strength(scene: Node, k: float) -> void:
	LookFx.vignette_scale = clampf(k, STRENGTH_MIN, STRENGTH_MAX)
	_vignette(scene)


static func vignette_strength() -> float:
	return LookFx.vignette_scale


static func look() -> bool:
	return LookFx.enabled


## `--ssao=on|off|tier`: the contact shading over the tier (-1 the tier's, 0 off, 1 on).
static func set_ssao(scene: Node, mode: int) -> void:
	LookFx.ssao_override = clampi(mode, -1, 1)
	var env := _env(scene)
	if env != null:
		LookFx.apply_quality(env, LookFx.tier)


static func ssao_choice() -> int:
	return LookFx.ssao_override


## Whether the environment draws SSAO now.
static func ssao_on(scene: Node) -> bool:
	var env := _env(scene)
	return env != null and env.ssao_enabled


## `--dof=off`: the depth of field of the long lens and mark clip cameras (cameras.md §9).
static func set_dof(_scene: Node, on: bool) -> void:
	LookFx.dof_enabled = on


static func dof() -> bool:
	return LookFx.dof_enabled


# ---- light ------------------------------------------------------------------------------------------------------

## The scene stores the light flags (its `light_time`, `light_conditions`, `light_alias` members) and applies them
## over the venue's defaults as it builds (the sail scene's _apply_light); a built scene, or one without them, takes
## them on its sky at once.
static func _light_live(scene: Node) -> bool:
	return _live(scene) or not (scene != null and "light_time" in scene)


## `--sky=clear|fair|hazy|late`: an old light preset name, its conditions at the hour of its afternoon sun (SkyRig,
## Daylight.ALIASES). Before the scene is built it replaces any earlier `--time` and `--conditions`. Returns whether
## the name is known.
static func set_preset(scene: Node, name: String) -> bool:
	name = name.to_lower()
	if not Daylight.ALIASES.has(name):
		return false
	if scene != null and "light_alias" in scene:
		scene.set("light_alias", name)
		scene.set("light_time", -1.0)
		scene.set("light_conditions", "")
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig and _light_live(scene):
		(sky as SkyRig).set_preset_name(name)
	return true


## The old preset name the light matches now, else "".
static func preset(scene: Node) -> String:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).preset_name() if sky is SkyRig else ""


## `--time=HH:MM` (or hours): the time of day (SkyRig.hour, clamped to the hours with the sun at 6 deg or more).
static func set_time(scene: Node, h: float) -> void:
	if scene != null and "light_time" in scene:
		scene.set("light_time", h)
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig and _light_live(scene):
		(sky as SkyRig).hour = h


static func time(scene: Node) -> float:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).hour if sky is SkyRig else VenueLook.DEFAULT_TIME


## The time of day row's range on the scene's site: the hours with the sun at 6 deg or more, on TIME_STEP.
static func time_range(scene: Node) -> Vector2:
	var sky: Variant = _member(scene, "sky")
	var r := (sky as SkyRig).hour_range() if sky is SkyRig else Vector2(6.0, 20.0)
	return Vector2(ceilf(r.x / TIME_STEP - 1e-6) * TIME_STEP, floorf(r.y / TIME_STEP + 1e-6) * TIME_STEP)


## The sun's elevation now (deg).
static func sun_elevation(scene: Node) -> float:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).sun_elevation_deg if sky is SkyRig else 0.0


## `--conditions=clear|fair|hazy|overcast`. Returns whether the name is known.
static func set_conditions(scene: Node, c: String) -> bool:
	c = c.to_lower()
	if not Daylight.is_condition(c):
		return false
	if scene != null and "light_conditions" in scene:
		scene.set("light_conditions", c)
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig and _light_live(scene):
		(sky as SkyRig).conditions = c
	return true


static func conditions(scene: Node) -> String:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).conditions if sky is SkyRig else "fair"


## `--light-advance=<rate>`: the clock runs at rate game hours per real hour (0 fixed, 1 real time).
static func set_light_advance(scene: Node, rate: float) -> void:
	if scene != null and "light_advance" in scene:
		scene.set("light_advance", maxf(rate, 0.0))
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig:
		(sky as SkyRig).light_advance = rate


## `--haze=<factor>`: the distance haze as a factor of the light's haze_max (0 to 1.5); 1 is the light's.
static func set_haze(scene: Node, k: float) -> void:
	var sky: Variant = _member(scene, "sky")
	if sky is SkyRig:
		(sky as SkyRig).haze_scale = clampf(k, HAZE_MIN, HAZE_MAX)


static func haze(scene: Node) -> float:
	var sky: Variant = _member(scene, "sky")
	return (sky as SkyRig).haze_scale if sky is SkyRig else 1.0


# ---- quality tier -----------------------------------------------------------------------------------------------

## `--quality=L|M|H`: this run's tier over the setting (SeaQuality.Tier, -1 the setting). Live: the sea's grid
## and water shader, the wakes, the drawn shadows, the sun's shadows, the glow, the SSAO, the reflections and the
## depth of field quality, everything SkyRig.apply_quality and Settings.apply_sea touch.
static func set_quality(scene: Node, tier: int) -> void:
	Settings.quality_override = clampi(tier, -1, 2)
	var sea: Variant = _member(scene, "sea")
	if _live(scene) and sea is Sea:
		var sky: Variant = _member(scene, "sky")
		Settings.current().apply_sea(sea, sky if sky is SkyRig else null)


## The tier the sea draws now (or the stored override before it is built).
static func quality(scene: Node) -> int:
	var sea: Variant = _member(scene, "sea")
	if _live(scene) and sea is Sea:
		return (sea as Sea).quality
	return Settings.quality_override


# ---- the sea ----------------------------------------------------------------------------------------------------

## `--caps=on` / `--caps=off`: the whitecaps (water_render.md §4.4; off by default).
static func set_whitecaps(scene: Node, on: bool) -> void:
	var sea: Variant = _member(scene, "sea")
	if sea is Sea:
		(sea as Sea).whitecaps = on


static func whitecaps(scene: Node) -> bool:
	var sea: Variant = _member(scene, "sea")
	return (sea as Sea).whitecaps if sea is Sea else false


## `--drawn-wind=<kn>`: the wind the water draws (whitecaps, puffs) instead of the simulation's, 0 the simulation's.
## The waves and the boats keep the world's wind (the restart with a wind changes those).
static func set_drawn_wind(scene: Node, kn: float) -> void:
	var sea: Variant = _member(scene, "sea")
	if sea is Sea:
		(sea as Sea).drawn_wind_kn = maxf(kn, 0.0)


static func drawn_wind(scene: Node) -> float:
	var sea: Variant = _member(scene, "sea")
	return (sea as Sea).drawn_wind_kn if sea is Sea else 0.0


# ---- shadows ----------------------------------------------------------------------------------------------------

## `--no-drawn-shadows`: the boats' shadows drawn on the water (tiers L and M, water_render.md §4.7).
static func set_drawn_shadows(scene: Node, on: bool) -> void:
	if scene != null and "no_drawn_shadows" in scene:
		scene.set("no_drawn_shadows", not on)
	var sh: Variant = _member(scene, "shadows")
	if sh is BoatShadows:
		(sh as BoatShadows).enabled = on


static func drawn_shadows(scene: Node) -> bool:
	var sh: Variant = _member(scene, "shadows")
	return (sh as BoatShadows).enabled if sh is BoatShadows else true


## `--no-boat-shadows`: the boats cast the sun's shadows (BoatView.sun_shadows: the proxies hidden, the sails OFF;
## sail_visuals.md §11.4).
static func set_boat_shadows(scene: Node, on: bool) -> void:
	if scene != null and "no_boat_shadows" in scene:
		scene.set("no_boat_shadows", not on)
	var views: Variant = _member(scene, "boat_views")
	if not views is Array:
		return
	for v in views:
		if v is BoatView:
			(v as BoatView).sun_shadows = on


static func boat_shadows(scene: Node) -> bool:
	return not bool(_member(scene, "no_boat_shadows"))


# ---- cameras ----------------------------------------------------------------------------------------------------

## `--breathing=off`: the chase camera's breathing (cameras.md §2.1) or the plain follow.
static func set_breathing(scene: Node, on: bool) -> void:
	if scene != null and "chase_breathing" in scene:
		scene.set("chase_breathing", on)
	var rig: Variant = _member(scene, "rig")
	if rig is CameraRig:
		(rig as CameraRig).chase.breathing = on


static func breathing(scene: Node) -> bool:
	var rig: Variant = _member(scene, "rig")
	if rig is CameraRig:
		return (rig as CameraRig).chase.breathing
	return bool(_member(scene, "chase_breathing")) if scene != null and "chase_breathing" in scene else true


# ---- everything a built scene takes from the stored values ------------------------------------------------------

## The stored look on a scene that has just been built (the end of the sail scene's _ready): grade, SSAO,
## vignette, shadows and the camera breathing. The render scale, anti-aliasing and tier follow the settings' own
## apply calls.
static func apply_built(scene: Node) -> void:
	set_look(scene, LookFx.enabled)
	set_drawn_shadows(scene, not bool(_member(scene, "no_drawn_shadows")))
	if bool(_member(scene, "no_boat_shadows")):
		set_boat_shadows(scene, false)
	set_breathing(scene, bool(_member(scene, "chase_breathing")) if "chase_breathing" in scene else true)


## A startup flag after `--` that sets a look setting; returns false for any other argument (the scene reads
## those itself).
static func apply_flag(scene: Node, a: String) -> bool:
	var i := a.find("=")
	var key := a.substr(0, i) if i >= 0 else a
	var val := a.substr(i + 1).to_lower() if i >= 0 else ""
	var off := val in ["off", "0", "no", "false"]
	match key:
		"--aa":
			set_aa(scene, val)
		"--look":
			set_look(scene, not off)
		"--ssao":
			set_ssao(scene, 1 if val == "on" else (0 if off else -1))
		"--dof":
			set_dof(scene, not off)
		"--sky":
			if not set_preset(scene, val):
				push_warning("--sky: clear, fair, hazy or late")
		"--time":
			var h := Daylight.parse_hour(val) if val.contains(":") else (val.to_float() if val.is_valid_float() else -1.0)
			if h >= 0.0:
				set_time(scene, h)
			else:
				push_warning("--time: HH:MM")
		"--conditions":
			if not set_conditions(scene, val):
				push_warning("--conditions: clear, fair, hazy or overcast")
		"--light-advance":
			set_light_advance(scene, val.to_float())
		"--grade":
			set_grade_strength(scene, val.to_float())
		"--vignette":
			set_vignette_strength(scene, val.to_float())
		"--haze":
			set_haze(scene, val.to_float())
		"--quality":
			set_quality(scene, "LMH".find(val.to_upper()))
		"--caps":
			set_whitecaps(scene, not off)
		"--drawn-wind":
			set_drawn_wind(scene, val.to_float())
		"--no-drawn-shadows":
			set_drawn_shadows(scene, false)
		"--no-boat-shadows":
			set_boat_shadows(scene, false)
		"--breathing":
			set_breathing(scene, not off)
		"--render-scale":
			set_render_scale(scene, val.to_float())
		_:
			return false
	return true
