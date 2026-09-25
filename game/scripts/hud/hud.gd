class_name Hud
extends Control
## The minimal in-race HUD (hud.md §2, §3.1, §5 and the §14 assist presets for these elements): boat speed,
## heading, heel, true and apparent wind, the helm and sheet indicators, the sail status and the trim gauges.
## Numbers refresh at 4 Hz from HudValues; bars and needles every frame. Player-facing text has no em dashes.

enum Assist { FULL, STANDARD, MINIMAL }

const REFRESH := 0.25
const FLASH_TIME := 1.2
const MESSAGE_TIME := 3.0
const COLOURS := {
	HudValues.Colour.NONE: Color(0.85, 0.85, 0.85),
	HudValues.Colour.GREEN: Color(0.3, 0.85, 0.35),
	HudValues.Colour.YELLOW: Color(0.95, 0.8, 0.2),
	HudValues.Colour.RED: Color(0.95, 0.3, 0.25),
}

var assist := Assist.STANDARD
var values := HudValues.new()
## the viewed boat is the player's own: frame() shows its commands from the local controls
var local_commands := true:
	set(on):
		local_commands = on
		if not on:
			values.commands_local = false
## label nodes by key: bsp, sog, hdg, cog, heel, polar, tws, twa, twd, aws, awa, sail, sheet, rudder, message
var labels := {}
var rudder_bar: HudBar
var sheet_bar: HudBar
var gauge_box: HBoxContainer
var gauge_views: Array[TrimGaugeView] = []

var _refresh_t := INF
var _flash_t := 0.0
var _message_t := 0.0


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := _panel("Instruments", Control.PRESET_TOP_LEFT)
	for k in ["bsp", "sog", "hdg", "cog", "heel", "polar"]:
		_label(left, k)
	var right := _panel("Wind", Control.PRESET_TOP_RIGHT)
	for k in ["tws", "twa", "twd", "aws", "awa"]:
		_label(right, k)
	var bottom := _panel("Boat", Control.PRESET_CENTER_BOTTOM)
	_label(bottom, "sail")
	_label(bottom, "rudder")
	rudder_bar = HudBar.new()
	rudder_bar.name = "RudderBar"
	rudder_bar.centred = true
	bottom.add_child(rudder_bar)
	_label(bottom, "sheet")
	sheet_bar = HudBar.new()
	sheet_bar.name = "SheetBar"
	bottom.add_child(sheet_bar)
	gauge_box = HBoxContainer.new()
	gauge_box.name = "TrimGauges"
	gauge_box.add_theme_constant_override("separation", 16)
	bottom.add_child(gauge_box)
	_label(bottom, "message")


func _panel(n: String, preset: int) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.name = n
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	pc.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	match preset:
		Control.PRESET_TOP_RIGHT:
			pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_BOTTOM:
			pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
			pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(190, 0)
	pc.add_child(v)
	return v


func _label(parent: Node, key: String) -> Label:
	var l := Label.new()
	l.name = key.capitalize().replace(" ", "")
	l.add_theme_font_size_override("font_size", 18)
	parent.add_child(l)
	labels[key] = l
	return l


func text_of(key: String) -> String:
	return (labels[key] as Label).text


## Once per simulation tick.
func tick(sim: SimSource, boat: int) -> void:
	values.tick(sim, boat)


## Once per rendered frame. `controls` (optional) supplies the HUD feedback of the controls and, while
## `local_commands` is on (the viewed boat is the player's own), the helm and sheet commands: the local command
## of this frame, not the one the sim applied, so the helm mark, the sheet bar and the sheet text answer at once
## (the core shows a queued command only after its next step).
func frame(dt: float, controls: PlayerControls = null) -> void:
	if controls != null:
		if local_commands and values.set_commands(controls):
			refresh_text()
		if controls.busy_flash:
			controls.busy_flash = false
			_flash_t = FLASH_TIME
		if not controls.messages.is_empty():
			labels["message"].text = controls.messages.back()
			controls.messages.clear()
			_message_t = MESSAGE_TIME
	_flash_t = maxf(_flash_t - dt, 0.0)
	_message_t = maxf(_message_t - dt, 0.0)
	if _message_t <= 0.0:
		labels["message"].text = ""
	var sail_label: Label = labels["sail"]
	sail_label.modulate.a = 1.0 if _flash_t <= 0.0 or fmod(_flash_t, 0.3) > 0.15 else 0.35
	_refresh_t += dt
	if _refresh_t >= REFRESH:
		_refresh_t = 0.0
		refresh_text()
	_bars()


## Rewrites every number from the filtered values (hud.md §1 formats).
func refresh_text() -> void:
	var v := values
	labels["bsp"].text = "BSP  %s kn" % HudFormat.speed_kn(v.bsp)
	labels["sog"].text = "SOG  %s kn" % HudFormat.speed_kn(v.sog)
	labels["hdg"].text = "HDG  %s" % HudFormat.compass_deg(v.hdg)
	labels["cog"].text = "COG  %s" % HudFormat.compass_deg(v.cog) if v.sog / HudFormat.KNOT > 0.3 else "COG  ---"
	labels["heel"].text = "Heel  %s" % HudFormat.side_angle(v.heel, "S", "P")
	labels["polar"].text = "Polar  %s %%" % HudFormat.percent(v.polar_pct)
	labels["tws"].text = "TWS  %s kn" % HudFormat.speed_kn(v.tws)
	labels["twa"].text = "TWA  %s" % HudFormat.side_angle(v.twa, "S", "P")
	labels["twd"].text = "TWD  %s" % HudFormat.compass_deg(v.twd)
	labels["aws"].text = "AWS  %s kn" % HudFormat.speed_kn(v.aws)
	labels["awa"].text = "AWA  %s" % HudFormat.side_angle(v.awa, "S", "P")
	var sail := _sail_name(v.sail_up) if v.sail_up != "" else "Main only"
	if v.sail_hoisting != "":
		sail += ", hoisting %s %s %%" % [_sail_name(v.sail_hoisting), HudFormat.percent(100.0 * v.hoist_progress)]
	labels["sail"].text = "Sail  %s" % sail
	labels["rudder"].text = "Helm  %s" % _signed_pct(v.h)
	var sheet := "AUTO" if v.auto_trim else "%s %%" % HudFormat.percent(100.0 * v.sheet_cmd)
	labels["sheet"].text = "Sheet  %s%s" % [sheet, "   LET FLY" if v.let_fly else ""]


static func _sail_name(n: String) -> String:
	return n.capitalize()


static func _signed_pct(h: float) -> String:
	var p := int(HudFormat.round_half_away(100.0 * absf(h)))
	if p == 0:
		return "0"
	return "%d %s" % [p, "S" if h > 0.0 else "P"]


func _bars() -> void:
	var v := values
	rudder_bar.value = v.h
	rudder_bar.mark = v.h_cmd
	rudder_bar.queue_redraw()
	sheet_bar.visible = not v.auto_trim
	sheet_bar.value = v.sheet_cmd
	sheet_bar.mark = NAN
	sheet_bar.queue_redraw()
	while gauge_views.size() < v.gauges.size():
		var gv := TrimGaugeView.new()
		gauge_box.add_child(gv)
		gauge_views.append(gv)
	for i in gauge_views.size():
		var gv := gauge_views[i]
		gv.visible = i < v.gauges.size()
		if not gv.visible:
			continue
		var g: HudValues.Gauge = v.gauges[i]
		gv.name = "Gauge" + g.name.capitalize().replace(" ", "")
		gv.title = g.name.capitalize()
		gv.auto = g.auto
		gv.greyed = g.greyed
		gv.needle = g.needle
		gv.show_needle = assist != Assist.MINIMAL
		gv.colour = COLOURS[HudValues.Colour.NONE] if (g.auto or assist == Assist.MINIMAL) else COLOURS[g.colour]
		gv.telltale = g.telltale
		gv.queue_redraw()


func toggle_hidden() -> void:
	visible = not visible
