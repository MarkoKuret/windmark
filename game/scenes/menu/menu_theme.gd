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
const ITEM_SIZE := 26
const ROW_SIZE := 20
const SMALL_SIZE := 16

## tracking (em) of the caps styles (menus.md §4)
const ITEM_TRACKING := 0.06
const LABEL_TRACKING := 0.08

static var _theme: Theme = null


## Barlow Semi Condensed at a weight (500, 600, 700), tabular figures, `tracking` em at `size` px.
static func font(weight := 500, tracking := 0.0, size := ROW_SIZE) -> Font:
	return HudStyle.font(weight, tracking, size)


static func box(fill: Color, left := 0, radius := 2, pad := Vector2(18, 8), edge := NAVY) -> StyleBoxFlat:
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
static func focus_box(pad := Vector2(18, 8), danger := false) -> StyleBoxFlat:
	if danger:
		return box(SIGNAL, 0, 2, pad)
	return box(FOCUS_FILL, FOCUS_EDGE, 2, pad)


static func panel() -> StyleBoxFlat:
	var s := box(CLOTH, 0, 3, Vector2(28, 24))
	s.border_width_bottom = 3
	s.border_color = CLOTH_EDGE
	s.shadow_color = Color(0.03, 0.08, 0.12, 0.30)
	s.shadow_size = 20
	s.shadow_offset = Vector2(0, 6)
	return s


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


## A menu button: Bold caps. `danger`: a destructive action, red (menus.md §4).
static func button(text: String, size := ITEM_SIZE, danger := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font(700, ITEM_TRACKING, size))
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	if danger:
		set_danger(b)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## Red caps text, a red bar with cloth-coloured text when focused or hovered (menus.md §4).
static func set_danger(b: Button, pad := Vector2(18, 8)) -> void:
	for st in ["focus", "pressed", "hover_pressed", "hover"]:
		b.add_theme_stylebox_override(st, focus_box(pad, true))
	b.add_theme_color_override("font_color", SIGNAL)
	for c in ["font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		b.add_theme_color_override(c, CLOTH_SOLID)


## A heading in Bold caps with the short yellow rule under it.
static func heading(text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(label(text.to_upper(), HEADING_SIZE, NAVY, 700, ITEM_TRACKING))
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(48, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(rule)
	return v


## The primary action (Start): a yellow bar with navy text at all times, the navy edge added when focused.
static func set_primary(b: Button, pad := Vector2(18, 8)) -> void:
	b.add_theme_stylebox_override("normal", box(ACCENT, 0, 2, pad))
	b.add_theme_stylebox_override("hover", box(ACCENT, FOCUS_EDGE, 2, pad))
	b.add_theme_stylebox_override("disabled", box(Color(NAVY, 0.08), 0, 2, pad))
