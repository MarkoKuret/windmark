class_name MenuTheme
extends RefCounted
## The menus' look (menus.md §4): sail-cloth panels over the sea, navy text, the HUD's yellow as the one accent
## (a fill with navy text on it, never yellow text on the cloth), red only for destructive actions and warnings,
## and the HUD's Barlow Semi Condensed type.

const NAVY := Color("1a2a3a")
const INK := Color("24384a")
const MUTED := Color("56646e")
const CLOTH := Color(0.957, 0.945, 0.910, 0.96)
const CLOTH_SOLID := Color("f4f1e8")
const CLOTH_EDGE := Color("d8d1bf")
## the HUD's `mark` yellow (hud.md §16.2): the one accent, used as a fill with navy text on it
const ACCENT := Color("ffd23f")
## warnings, destructive actions (Quit, Reset) and penalties: 5.2:1 on the cloth
const SIGNAL := Color("b8361c")
const FOCUS_FILL := ACCENT
const HOVER_FILL := Color(0.10, 0.16, 0.23, 0.05)
## the navy edge on the left of a focused row or button, px
const FOCUS_EDGE := 5

const SKY_TOP := Color("7fa9c4")
const SKY_HORIZON := Color("e4ece9")
const SEA_HORIZON := Color("5f8fa6")
const SEA_DEEP := Color("16344c")

const TITLE_SIZE := 54
const HEADING_SIZE := 30
const ITEM_SIZE := 28
const ROW_SIZE := 20
const SMALL_SIZE := 16
## the footer actions (Start, Race again, Done, ...): one size on every screen
const ACTION_SIZE := 24

## the hit sizes (menus.md §4): menu items, footer actions and setting rows, px tall at least; the padding inside
const ITEM_H := 58
const ACTION_H := 54
const ROW_H := 46
const ITEM_PAD := Vector2(22, 12)
const ROW_PAD := Vector2(18, 10)

## tracking (em) of the caps styles (menus.md §4)
const ITEM_TRACKING := 0.06
const LABEL_TRACKING := 0.08

## the layout rhythm (menus.md §4), px: the room round every screen, the gap between the rows or items of a list,
## the gap under a heading and above a footer, the gap between footer actions, the help line's least height, and
## the most a wide page or card takes
const MARGIN := 40
const LIST_GAP := 2
const SECTION_GAP := 12
const FOOTER_GAP := 12
const HELP_H := 40
const PAGE_MAX := 980.0

static var _theme: Theme = null


## The gamepad in the menus (menus.md §4): A accepts and B goes back through Godot's `ui_accept` and `ui_cancel`,
## which the engine's defaults do not bind to the pad; added once at the menu's start when missing.
static func ensure_pad_actions() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var action: String = pair[0]
		var button: JoyButton = pair[1]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var found := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
				found = true
		if not found:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			ev.device = -1
			InputMap.action_add_event(action, ev)


## Barlow Semi Condensed at a weight (500, 600, 700), tabular figures, `tracking` em at `size` px.
static func font(weight := 500, tracking := 0.0, size := ROW_SIZE) -> Font:
	return HudStyle.font(weight, tracking, size)


static func box(fill: Color, left := 0, radius := 2, pad := ITEM_PAD, edge := NAVY) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_width_left = left
	s.border_color = edge
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


## The focused look: a yellow bar with the navy edge on its left; `danger`: a red bar (menus.md §4).
static func focus_box(pad := ITEM_PAD, danger := false) -> StyleBoxFlat:
	if danger:
		return box(SIGNAL, 0, 2, pad)
	return box(FOCUS_FILL, FOCUS_EDGE, 2, pad)


## A cloth panel: flat, no edge, no shadow (menus.md §4).
static func panel() -> StyleBoxFlat:
	return box(CLOTH, 0, 3, Vector2(28, 26))


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = ROW_SIZE
	# buttons: flat caps text on the cloth, a yellow bar when focused
	t.set_stylebox("normal", "Button", box(Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "Button", box(HOVER_FILL, 0))
	t.set_stylebox("pressed", "Button", focus_box())
	t.set_stylebox("focus", "Button", focus_box())
	t.set_stylebox("hover_pressed", "Button", focus_box())
	t.set_stylebox("disabled", "Button", box(Color(0, 0, 0, 0), 0))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		t.set_color(c, "Button", NAVY)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_constant("h_separation", "Button", 10)
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", panel())
	# scroll bars: thin, navy, a yellow grabber while dragged
	var grab := box(Color(NAVY, 0.35), 0, 3, Vector2(3, 3))
	var track := box(Color(NAVY, 0.06), 0, 3, Vector2(3, 3))
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(NAVY, 0.55), 0, 3, Vector2(3, 3)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 0, 3, Vector2(3, 3)))
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_color("separator", "HSeparator", CLOTH_EDGE)
	_theme = t
	return t


## Sentence text (Medium), or with `weight` and `tracking` a caps style.
static func label(text: String, size := ROW_SIZE, color := INK, weight := 500, tracking := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, tracking, size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A caps label (setting names, small headings): SemiBold, tracking +8 %.
static func caps(text: String, size := ROW_SIZE, color := INK) -> Label:
	return label(text.to_upper(), size, color, 600, LABEL_TRACKING)


## A menu button: Bold caps, at least `min_h` px tall (ITEM_H for menu items, ACTION_H at ACTION_SIZE, the row
## height below). `danger`: a destructive action, red (menus.md §4).
static func button(text: String, size := ITEM_SIZE, danger := false, min_h := -1) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font(700, ITEM_TRACKING, size))
	b.add_theme_font_size_override("font_size", size)
	if min_h < 0:
		min_h = ITEM_H if size >= ITEM_SIZE else (ACTION_H if size >= ACTION_SIZE else ROW_H)
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_ALL
	if danger:
		set_danger(b)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## Red caps text, a red bar with cloth-coloured text when focused or hovered (menus.md §4).
static func set_danger(b: Button, pad := ITEM_PAD) -> void:
	for st in ["focus", "pressed", "hover_pressed", "hover"]:
		b.add_theme_stylebox_override(st, focus_box(pad, true))
	b.add_theme_color_override("font_color", SIGNAL)
	for c in ["font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		b.add_theme_color_override(c, CLOTH_SOLID)


## A heading in Bold caps (no rule under it, menus.md §4); the label is the box's first child.
static func heading(text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_child(label(text.to_upper(), HEADING_SIZE, NAVY, 700, ITEM_TRACKING))
	return v


## A sub-heading inside a page (Bindings, Your race): small navy caps, the setting-name style (menus.md §4),
## `pad` px from the left so it lines up with what it heads.
static func subheading(text: String, pad := 0.0) -> Label:
	var l := caps(text, SMALL_SIZE, NAVY)
	l.custom_minimum_size = Vector2(0, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if pad > 0.0:
		l.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), 0, 0, Vector2(pad, 0)))
	return l


## A list of rows or items (menus.md §4): a column with the list gap.
static func list() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", LIST_GAP)
	return v


## A vertical gap of `h` px (under a heading, above a footer).
static func gap(h := SECTION_GAP) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The help line (menus.md §3, §4): sentence text, small and muted, wrapping, at least HELP_H tall so the screen
## does not jump when it empties.
static func help_label(text := "") -> Label:
	var l := label(text, SMALL_SIZE, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, HELP_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A footer (menus.md §4): the way back or the lesser actions on the left, the primary action on the right, the
## footer gap between them.
static func footer(left: Array, right: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Footer"
	h.add_theme_constant_override("separation", FOOTER_GAP)
	for b in left:
		h.add_child(b)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(push)
	for b in right:
		h.add_child(b)
	return h


## The primary action (Start): a yellow bar with navy text at all times, the navy edge added when focused.
static func set_primary(b: Button, pad := ITEM_PAD) -> void:
	b.add_theme_stylebox_override("normal", box(ACCENT, 0, 2, pad))
	b.add_theme_stylebox_override("hover", box(ACCENT, FOCUS_EDGE, 2, pad))
	b.add_theme_stylebox_override("disabled", box(Color(NAVY, 0.08), 0, 2, pad))
