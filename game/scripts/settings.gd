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
	"hud.captions",  # the audio has no caption lines yet (audio.md §8)
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
## instrument density (hud.md §16.1): -1 = the device default, else Hud.Density; the density key stores it
var hud_density := -1
var ui_scale := 1.0
## standard, deuteranopia, protanopia, tritanopia
var palette := "standard"
var captions := false

# ---- graphics (water_render.md §7) ----
var quality := SeaQuality.Tier.M
## the 3D view's share of the window's pixels in each direction (menus.md §3): 0 = Auto, else one of RENDER_SCALES
var render_scale := 0.0
var fullscreen := false
var vsync := true
## frames per second, 0 = no limit
var fps_limit := 0
## the capture preset (menus.md §3): "off", or "portrait" (a 1080 x 1920 window, the HUD's portrait layout).
## Session only: not in FIELDS, so never saved or loaded; every run starts with it off.
var capture_preset := "off"

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
	"hud": ["assist", "hud_density", "ui_scale", "palette", "captions"],
	"graphics": ["quality", "render_scale", "fullscreen", "vsync", "fps_limit"],
	"audio": ["master_volume", "effects_volume", "signals_volume", "voice_volume", "ambience_volume",
		"interface_volume"],
	"menu": ["last_setup"],
}

## the render scale choices (menus.md §3); 0 is Auto
const RENDER_SCALES := [0.0, 0.5, 0.67, 0.75, 0.85, 1.0]
## what Auto picks on a large or HiDPI window, and the window sizes that count as large
const AUTO_RENDER_SCALE := 0.67
const AUTO_LARGE := Vector2i(1920, 1200)
const AUTO_LARGE_HIDPI := Vector2i(1280, 800)
## Auto's cap on the 3D view's pixels (menus.md §3): 1930 x 1206, measured at 60 fps on tier M on a MacBook Air M1
const AUTO_PIXEL_BUDGET := 2330000.0
## the capture presets (menus.md §3) and the portrait window, px
const CAPTURE_PRESETS := ["off", "portrait"]
const PORTRAIT_SIZE := Vector2i(1080, 1920)

## Session overrides from the command line (the sail scene's --render-scale and --upscaler), not saved:
## a scale > 0 replaces the setting; "fsr", "bilinear" or "metalfx" replaces the upscaler's choice.
static var render_scale_override := 0.0
static var upscaler_override := ""
## this run only, not saved (sail test `--quality=L|M|H`, `--no-vsync`): -1 keeps the setting
static var quality_override := -1
static var vsync_override := -1
static var _resize_hooked: Window = null
## the window's size before the capture preset resized it (put back when it is turned off); zero when not resized
static var _size_before := Vector2i.ZERO

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
	hud_density = clampi(hud_density, -1, 2)
	quality = clampi(quality, 0, 2) as SeaQuality.Tier
	render_scale = 0.0 if render_scale < 0.25 else clampf(render_scale, 0.5, 1.0)
	fps_limit = maxi(fps_limit, 0)
	if not capture_preset in CAPTURE_PRESETS:
		capture_preset = "off"
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
	if section == "" or section == "graphics":
		capture_preset = fresh.capture_preset  # session only, but Reset section turns it off too


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


## The assist preset and the instrument density; the density key's choice is stored here and saved at once
## (kept per device: the settings file is the device's).
func apply_hud(hud: Hud) -> void:
	hud.assist = assist
	hud.density_auto = hud_density < 0
	if hud_density >= 0:
		hud.density = hud_density as Hud.Density
	if not hud.density_changed.is_connected(_density_chosen):
		hud.density_changed.connect(_density_chosen)


func _density_chosen(level: int) -> void:
	hud_density = level
	save_file()


## The sea's tier, and the environment's part of it (screen-space reflections) when a sky is given.
func apply_sea(sea: Sea, sky: SkyRig = null) -> void:
	var q: SeaQuality.Tier = quality if quality_override < 0 else quality_override as SeaQuality.Tier
	sea.quality = q
	if sky != null and sky.environment() != null:
		SeaQuality.apply_environment(sky.environment(), q)


## Display mode, vsync, frame rate limit, UI scale (the root window's content scale) and render scale.
func apply_display(win: Window) -> void:
	Engine.max_fps = fps_limit
	if win == null:
		return
	win.content_scale_factor = ui_scale
	apply_render_scale(win)
	if DisplayServer.get_name() == "headless":
		return
	var want := Window.MODE_FULLSCREEN if fullscreen and capture_preset == "off" else Window.MODE_WINDOWED
	if win.mode != want:
		win.mode = want
	apply_capture(win)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if (vsync if vsync_override < 0 else vsync_override == 1)
		else DisplayServer.VSYNC_DISABLED)


## The capture preset on the window (menus.md §3): Portrait sizes it to 1080 x 1920 (or the largest 9:16 that
## fits the screen's usable area), centred, and remembers the size it had; Off puts that size back. The window must
## be windowed (apply_display sees to it). Not in headless runs.
func apply_capture(win: Window) -> void:
	if win == null or DisplayServer.get_name() == "headless":
		return
	var scr := DisplayServer.window_get_current_screen()
	var r := capture_window_rect(win.size, DisplayServer.screen_get_usable_rect(scr))
	if r.size != Vector2i.ZERO:
		win.size = r.size
		win.position = r.position


## The window rect the capture preset wants for a window of `size` on a screen whose usable area is `usable`, or a
## zero rect for no change. Turning Portrait on remembers `size` (once, until it is off again); Off gives the
## remembered size back (within the usable area), centred, and forgets it.
func capture_window_rect(size: Vector2i, usable: Rect2i) -> Rect2i:
	if capture_preset == "portrait":
		if _size_before == Vector2i.ZERO:
			_size_before = size
		var sz := capture_window_size(usable.size)
		if size == sz:
			return Rect2i()
		return Rect2i(usable.position + (usable.size - sz) / 2, sz)
	if _size_before == Vector2i.ZERO:
		return Rect2i()
	var back := Vector2i(mini(_size_before.x, usable.size.x), mini(_size_before.y, usable.size.y))
	_size_before = Vector2i.ZERO
	return Rect2i(usable.position + (usable.size - back) / 2, back)


## The portrait capture window for a screen whose usable area is `usable` px: 1080 x 1920, else the largest 9:16
## that fits.
static func capture_window_size(usable: Vector2i) -> Vector2i:
	if usable.x >= PORTRAIT_SIZE.x and usable.y >= PORTRAIT_SIZE.y:
		return PORTRAIT_SIZE
	var h := mini(usable.y, PORTRAIT_SIZE.y)
	var w := int(floorf(h * 9.0 / 16.0))
	if w > usable.x:
		w = usable.x
		h = int(floorf(w * 16.0 / 9.0))
	return Vector2i(maxi(w, 1), maxi(h, 1))


## Auto's render scale for a window of `px` pixels on a screen the system scales by `screen_scale` (menus.md §3):
## 67 % above 1920 x 1200, or above 1280 x 800 on a HiDPI screen; else 100 %; then capped so the 3D view draws at
## most AUTO_PIXEL_BUDGET pixels.
static func auto_render_scale(px: Vector2i, screen_scale: float) -> float:
	var big := px.x > AUTO_LARGE.x or px.y > AUTO_LARGE.y
	var hidpi := screen_scale > 1.0 and (px.x > AUTO_LARGE_HIDPI.x or px.y > AUTO_LARGE_HIDPI.y)
	var s := AUTO_RENDER_SCALE if big or hidpi else 1.0
	var n := float(maxi(px.x, 1)) * float(maxi(px.y, 1))
	return minf(s, sqrt(AUTO_PIXEL_BUDGET / n))


## The render scale in effect for a window: the command-line override, the setting, or Auto resolved.
func effective_render_scale(win: Window) -> float:
	if render_scale_override > 0.0:
		return clampf(render_scale_override, 0.25, 1.0)
	if render_scale > 0.0:
		return render_scale
	if capture_preset != "off":
		return 1.0
	var px := win.size if win != null else Vector2i(1280, 800)
	var screen := DisplayServer.window_get_current_screen() if DisplayServer.get_name() != "headless" else 0
	return auto_render_scale(px, DisplayServer.screen_get_scale(screen))


## The upscaler for a scale below 1 (menus.md §3): FSR 1.0 on the Forward+ and Mobile renderers, bilinear on
## Compatibility; MetalFX spatial only when asked for on the command line (and on Metal).
static func upscaler(scale: float) -> Viewport.Scaling3DMode:
	if scale >= 1.0:
		return Viewport.SCALING_3D_MODE_BILINEAR
	var rd := RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]
	match upscaler_override:
		"bilinear":
			return Viewport.SCALING_3D_MODE_BILINEAR
		"metalfx":
			if rd and RenderingServer.get_current_rendering_driver_name() == "metal":
				return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	return Viewport.SCALING_3D_MODE_FSR if rd else Viewport.SCALING_3D_MODE_BILINEAR


## Anti-aliasing (water_render.md §7): SMAA 1x on every tier, at the 3D render resolution after tone mapping and
## before a spatial upscaler (FSR 1.0, MetalFX spatial), which wants an antialiased input. A temporal upscaler
## (FSR 2, MetalFX temporal) antialiases by itself, so SMAA is off with it.
static func screen_space_aa(mode: Viewport.Scaling3DMode) -> Viewport.ScreenSpaceAA:
	if mode in [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL]:
		return Viewport.SCREEN_SPACE_AA_DISABLED
	return Viewport.SCREEN_SPACE_AA_SMAA


static func upscaler_name(mode: Viewport.Scaling3DMode) -> String:
	match mode:
		Viewport.SCALING_3D_MODE_FSR:
			return "FSR"
		Viewport.SCALING_3D_MODE_FSR2:
			return "FSR2"
		Viewport.SCALING_3D_MODE_METALFX_SPATIAL:
			return "MetalFX"
		Viewport.SCALING_3D_MODE_METALFX_TEMPORAL:
			return "MetalFX temporal"
	return "bilinear"


## The 3D view's resolution (the root viewport's scaling_3d_scale and upscaler); the 2D stays native. Auto is
## resolved again when the window changes size.
func apply_render_scale(win: Window) -> void:
	if win == null:
		return
	var sc := effective_render_scale(win)
	win.scaling_3d_scale = sc
	win.scaling_3d_mode = upscaler(sc)
	win.screen_space_aa = screen_space_aa(win.scaling_3d_mode)
	if _resize_hooked != win:
		if is_instance_valid(_resize_hooked) and _resize_hooked.size_changed.is_connected(_window_resized):
			_resize_hooked.size_changed.disconnect(_window_resized)
		win.size_changed.connect(_window_resized)
		_resize_hooked = win


static func _window_resized() -> void:
	if is_instance_valid(_resize_hooked):
		Settings.current().apply_render_scale(_resize_hooked)


## Volumes on the buses of audio.md §1.1 (made here when missing, AudioBuses).
func apply_audio() -> void:
	AudioBuses.ensure()
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
