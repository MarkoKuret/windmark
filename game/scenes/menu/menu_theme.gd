class_name MenuTheme
extends RefCounted
## The menus' look (menus.md §4): sea and sky behind, sail-cloth panels, navy text, one signal-flag accent.

const NAVY := Color("1a2a3a")
const INK := Color("24384a")
const MUTED := Color("5f6f7a")
const CLOTH := Color(0.957, 0.945, 0.910, 0.96)
const CLOTH_EDGE := Color("d8d1bf")
const ACCENT := Color("d4492a")
const FOCUS_FILL := Color(0.83, 0.29, 0.16, 0.10)
const HOVER_FILL := Color(0.10, 0.16, 0.23, 0.05)

const SKY_TOP := Color("7fa9c4")
const SKY_HORIZON := Color("e4ece9")
const SEA_HORIZON := Color("5f8fa6")
const SEA_DEEP := Color("16344c")

const TITLE_SIZE := 50
const HEADING_SIZE := 30
const ITEM_SIZE := 26
const ROW_SIZE := 20
const SMALL_SIZE := 16

static var _theme: Theme = null


static func box(fill: Color, left := 0, radius := 3, pad := Vector2(18, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_width_left = left
	s.border_color = ACCENT
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


static func panel() -> StyleBoxFlat:
	var s := box(CLOTH, 0, 4, Vector2(28, 24))
	s.border_width_bottom = 3
	s.border_color = CLOTH_EDGE
	s.shadow_color = Color(0.05, 0.12, 0.18, 0.25)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = ROW_SIZE
	# buttons: flat text on the cloth, a flag-coloured bar on the left when focused
	t.set_stylebox("normal", "Button", box(Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "Button", box(HOVER_FILL, 0))
	t.set_stylebox("pressed", "Button", box(FOCUS_FILL, 5))
	t.set_stylebox("focus", "Button", box(FOCUS_FILL, 5))
	t.set_stylebox("disabled", "Button", box(Color(0, 0, 0, 0), 0))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", NAVY)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_constant("h_separation", "Button", 10)
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", panel())
	# scroll bars: thin, navy
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


static func label(text: String, size := ROW_SIZE, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size := ITEM_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## A heading with the thin rule under it.
static func heading(text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(label(text, HEADING_SIZE, NAVY))
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(48, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(rule)
	return v
