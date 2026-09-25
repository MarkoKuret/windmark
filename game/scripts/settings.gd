class_name Settings
extends RefCounted
## The player's settings (menus.md §3, controls.md §6): one ConfigFile per player, read by whatever needs them
## through Settings.current(), and applied to the parts of the game that already have the option (apply_*).
## Settings the game does not use yet are stored and listed in NOT_APPLIED.

const VERSION := 1
const DEFAULT_PATH := "user://settings.cfg"

## Stored but not used by the game yet (nothing reads them): kept here so the list stays honest.
const NOT_APPLIED := [
	"controls.rankings_toggle",  # the rankings list comes with the race HUD
	"controls.camera_boost_toggle",  # the free camera boost is hold only
	"controls.vibration",  # no rumble yet
	"hud.palette",  # the HUD has one palette
	"hud.captions",  # no audio yet
	"audio.*",  # applied to a bus only when the bus exists (audio.md §1.1); today only master
]

## where current() loads from and save() writes to (tests point it elsewhere)
static var path := DEFAULT_PATH
static var _current: Settings = null

# ---- controls (controls.md §6) ----
var helm_mode := PlayerControls.HelmMode.SET_AND_HOLD
var stick_dead_zone := 0.10
var stick_curve := 1.6
var sheet_rate := 1.0
var let_fly_toggle := false
var helm_fine_toggle := false
var rankings_toggle := false
var camera_boost_toggle := false
var sheet_turns_auto_trim_off := false
## 0 = off
var vibration := 1.0

# ---- cameras (cameras.md §3, §6; controls.md §4, §6) ----
var camera_speed := 1.0
var invert_orbit_x := false
var invert_orbit_y := false
var invert_look_x := false
var invert_look_y := false
var heel_follow := 0.0
var smooth_switch := false
var reduced_motion := false

# ---- HUD (hud.md §14) ----
var assist := Hud.Assist.STANDARD
var ui_scale := 1.0
## standard, deuteranopia, protanopia, tritanopia
var palette := "standard"
var captions := false

# ---- graphics (water_render.md §7) ----
var quality := SeaQuality.Tier.M
var fullscreen := false
var vsync := true
## frames per second, 0 = no limit
var fps_limit := 0

# ---- audio (audio.md §1.1), linear 0..1 ----
var master_volume := 0.8
var effects_volume := 1.0
var signals_volume := 1.0
var voice_volume := 1.0
var ambience_volume := 1.0
var interface_volume := 1.0

## the last session chosen in the main menu (menus.md §1), GameSetup fields
var last_setup := {}

## key -> [section, field]; the file layout
const FIELDS := {
	"controls": ["helm_mode", "stick_dead_zone", "stick_curve", "sheet_rate", "let_fly_toggle", "helm_fine_toggle",
		"rankings_toggle", "camera_boost_toggle", "sheet_turns_auto_trim_off", "vibration"],
	"cameras": ["camera_speed", "invert_orbit_x", "invert_orbit_y", "invert_look_x", "invert_look_y", "heel_follow",
		"smooth_switch", "reduced_motion"],
	"hud": ["assist", "ui_scale", "palette", "captions"],
	"graphics": ["quality", "fullscreen", "vsync", "fps_limit"],
	"audio": ["master_volume", "effects_volume", "signals_volume", "voice_volume", "ambience_volume",
		"interface_volume"],
	"menu": ["last_setup"],
}

## audio setting -> the buses it drives (audio.md §1.1)
const BUSES := {
	"master_volume": ["Master"],
	"effects_volume": ["own_boat", "fleet", "wind"],
	"signals_volume": ["race"],
	"voice_volume": ["voice"],
	"ambience_volume": ["ambience", "venue"],
	"interface_volume": ["ui"],
}


## The player's settings, loaded from `path` on first use (defaults when there is no file).
static func current() -> Settings:
	if _current == null:
		_current = Settings.new()
		_current.load_file(path)
	return _current


## Forget the loaded settings (tests; a new `path`).
static func reset_current() -> void:
	_current = null


func to_dict() -> Dictionary:
	var d := {}
	for section in FIELDS:
		var s := {}
		for f in FIELDS[section]:
			s[f] = get(f)
		d[section] = s
	return d


## Reads what it knows; unknown keys are ignored and wrong types keep the default.
func from_dict(d: Dictionary) -> void:
	for section in FIELDS:
		var s: Dictionary = d.get(section, {})
		for f in FIELDS[section]:
			if s.has(f):
				_set_checked(f, s[f])


func _set_checked(f: String, v: Variant) -> void:
	var old: Variant = get(f)
	match typeof(old):
		TYPE_FLOAT:
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				set(f, float(v))
		TYPE_INT:
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				set(f, int(v))
		_:
			if typeof(v) == typeof(old):
				set(f, v)
	_clamp()


func _clamp() -> void:
	stick_dead_zone = clampf(stick_dead_zone, 0.0, 0.30)
	stick_curve = clampf(stick_curve, 1.0, 3.0)
	sheet_rate = clampf(sheet_rate, 0.5, 2.0)
	vibration = clampf(vibration, 0.0, 1.0)
	camera_speed = clampf(camera_speed, 0.25, 3.0)
	heel_follow = clampf(heel_follow, 0.0, 1.0)
	ui_scale = clampf(ui_scale, 0.8, 1.3)
	helm_mode = clampi(helm_mode, 0, 1) as PlayerControls.HelmMode
	assist = clampi(assist, 0, 2) as Hud.Assist
	quality = clampi(quality, 0, 2) as SeaQuality.Tier
	fps_limit = maxi(fps_limit, 0)
	for f in BUSES:
		set(f, clampf(get(f), 0.0, 1.0))


func save_file(p := "") -> Error:
	if p == "":
		p = path
	var cf := ConfigFile.new()
	cf.set_value("settings", "version", VERSION)
	var d := to_dict()
	for section in d:
		for f in d[section]:
			cf.set_value(section, f, d[section][f])
	return cf.save(p)


func load_file(p := "") -> Error:
	if p == "":
		p = path
	var cf := ConfigFile.new()
	var err := cf.load(p)
	if err != OK:
		return err
	var d := {}
	for section in FIELDS:
		var s := {}
		for f in FIELDS[section]:
			if cf.has_section_key(section, f):
				s[f] = cf.get_value(section, f)
		d[section] = s
	from_dict(d)
	return OK


## Back to the defaults of one section (the settings screen's reset), or of everything with "".
func reset(section := "") -> void:
	var fresh := Settings.new()
	for s in FIELDS:
		if section == "" or s == section:
			for f in FIELDS[s]:
				set(f, fresh.get(f))


# ---- apply ----

func apply_controls(pc: PlayerControls) -> void:
	pc.helm_mode = helm_mode
	pc.stick_dead_zone = stick_dead_zone
	pc.stick_gamma = stick_curve
	pc.sheet_rate_scale = sheet_rate
	pc.let_fly_toggle = let_fly_toggle
	pc.helm_fine_toggle = helm_fine_toggle
	pc.sheet_turns_auto_trim_off = sheet_turns_auto_trim_off


func apply_cameras(rig: CameraRig) -> void:
	var o := rig.options
	o.speed = camera_speed
	o.invert_orbit_x = invert_orbit_x
	o.invert_orbit_y = invert_orbit_y
	o.invert_look_x = invert_look_x
	o.invert_look_y = invert_look_y
	o.smooth_switch = smooth_switch
	o.reduced_motion = reduced_motion
	rig.onboard.heel_follow = heel_follow


func apply_hud(hud: Hud) -> void:
	hud.assist = assist


## The sea's tier, and the environment's part of it (screen-space reflections) when a sky is given.
func apply_sea(sea: Sea, sky: SkyRig = null) -> void:
	sea.quality = quality
	if sky != null and sky.environment() != null:
		SeaQuality.apply_environment(sky.environment(), quality)


## Display mode, vsync, frame rate limit and UI scale (the root window's content scale).
func apply_display(win: Window) -> void:
	Engine.max_fps = fps_limit
	if win == null:
		return
	win.content_scale_factor = ui_scale
	if DisplayServer.get_name() == "headless":
		return
	var want := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if win.mode != want:
		win.mode = want
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Volumes on the buses that exist (audio.md §1.1).
func apply_audio() -> void:
	for f in BUSES:
		for bus in BUSES[f]:
			var i := AudioServer.get_bus_index(bus)
			if i >= 0:
				var v: float = get(f)
				AudioServer.set_bus_volume_db(i, linear_to_db(v) if v > 0.0 else -80.0)
				AudioServer.set_bus_mute(i, v <= 0.0)


## Everything a running sail scene has: its controls, camera rig, HUD, sea and sky, found by name (duck typed,
## so any scene with these members works); the display and audio settings too.
func apply_to_scene(scene: Node) -> void:
	if scene == null:
		return
	var pc: Variant = scene.get("controls")
	if pc is PlayerControls:
		apply_controls(pc)
	var rig: Variant = scene.get("rig")
	if rig is CameraRig:
		apply_cameras(rig)
	var hud: Variant = scene.get("hud")
	if hud is Hud:
		apply_hud(hud)
		var cv: Variant = scene.get("course_view")
		if cv is Object and cv != null and "show_laylines" in cv:
			cv.show_laylines = assist != Hud.Assist.MINIMAL
			cv.show_zone = assist != Hud.Assist.MINIMAL
	var sea: Variant = scene.get("sea")
	if sea is Sea:
		var sky: Variant = scene.get("sky")
		apply_sea(sea, sky if sky is SkyRig else null)
	if scene.is_inside_tree():
		apply_display(scene.get_tree().root)
	apply_audio()
