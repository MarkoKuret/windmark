class_name Wordmark
extends Control
## The game's logo (menus.md §1.2): WINDMARK in Barlow Semi Condensed Black Italic, cream with a navy outline and
## two hard shadows (navy, then yellow, each the outlined letters in one colour), and the tagline bar under it:
## REGATTA SAILING SIMULATOR in ExtraBold Italic, navy on a yellow parallelogram with a hard navy shadow. One scene
## (wordmark.tscn), so a later logo replaces it without touching the menu. Every size and offset is a whole pixel
## of the WINDMARK font size, so it stays crisp at every UI scale; fit_width scales it down by font size. The results
## screen (menus.md §5) uses the same lockup with its own words (`text`, `tagline_text`, set_words).

const TEXT := "WINDMARK"
const TAGLINE := "REGATTA SAILING SIMULATOR"
## the WINDMARK font size on the main menu at 100 % UI scale, px
const SIZE := 76
## the smallest WINDMARK size fit_width goes down to, px
const MIN_SIZE := 28
const BLACK_ITALIC := "res://fonts/barlow/BarlowSemiCondensed-BlackItalic.ttf"
const EXTRABOLD_ITALIC := "res://fonts/barlow/BarlowSemiCondensed-ExtraBoldItalic.ttf"

const CREAM := Color("f4f1e8")
const NAVY := Color("1a2a3a")
const YELLOW := Color("ffd23f")

## fractions of the WINDMARK font size
const TRACKING := 0.03
const OUTLINE := 0.03
const SHADOW_NAVY := 0.038
const SHADOW_YELLOW := 0.076
const TAG_SIZE := 0.22
const TAG_SHADOW := 4.0 / 76.0
## the gap between the title's shadow and the bar
const TAG_GAP := 0.04
## fractions of the tagline font size
const TAG_TRACKING := 0.30
const TAG_PAD := 0.6
const TAG_HEIGHT := 1.45
const TAG_SLANT_DEG := 14.0
## Barlow's vertical metrics (font units over the em: ascent 1000, cap height 700) and italic angle
const ASCENT := 1.0
const CAP := 0.7
const ITALIC_DEG := 7.0

## the words: the title and the tagline bar's (the logo's by default)
var text := TEXT
var tagline_text := TAGLINE
## the WINDMARK font size now, px
var title_px := SIZE
var title: Label
var shadow_navy: Label
var shadow_yellow: Label
var tagline: Label
## the bar and its shadow, local px
var bar := PackedVector2Array()
var bar_shadow := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow_yellow = _label("ShadowYellow", text)
	shadow_navy = _label("ShadowNavy", text)
	title = _label("Title", text)
	tagline = _label("Tagline", tagline_text)
	_layout()


## Other words in the lockup (the results screen's place and result); keeps the size.
func set_words(t: String, tag: String) -> void:
	text = t
	tagline_text = tag
	if not is_node_ready():
		return
	for l in [shadow_yellow, shadow_navy, title]:
		l.text = t
	tagline.text = tag
	_layout()


## Scales the lockup down (by font size) until it is at most `w` px wide; never above SIZE.
func fit_width(w: float) -> void:
	var px := SIZE
	while px > MIN_SIZE and natural_size(px).x > w:
		px -= 1
	if px != title_px:
		title_px = px
		if is_node_ready():
			_layout()


## The lockup's size at a WINDMARK size of `px`.
func natural_size(px: int) -> Vector2:
	return _geometry(px)["size"]


static func _font(path: String, spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.spacing_glyph = spacing
	return fv


func _label(n: String, text: String) -> Label:
	var l := Label.new()
	l.name = n
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Every position and size of the lockup at a WINDMARK size of `px` (menus.md §1.2).
func _geometry(px: int) -> Dictionary:
	var g := {}
	var t := float(px)
	# the title: the engine strokes outline_size / 4 px each side
	var outline := maxi(roundi(4.0 * OUTLINE * t), 4)
	var r := ceili(outline / 4.0)
	var spacing := roundi(TRACKING * t)
	var tf := _font(BLACK_ITALIC, spacing)
	var tw := tf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x - spacing
	var ds1 := roundi(SHADOW_NAVY * t)
	var ds2 := roundi(SHADOW_YELLOW * t)
	# the italic's top-right lean past the last advance
	var lean := ceili(CAP * t * tan(deg_to_rad(ITALIC_DEG)) * 0.5)
	var x0 := r
	var y0 := r - roundi((ASCENT - CAP) * t)
	var title_w := x0 + ceili(tw) + lean + r + ds2
	var title_h := r + roundi(CAP * t) + r + ds2
	# the tagline bar
	var s := maxi(roundi(TAG_SIZE * t), 8)
	var ts := roundi(TAG_TRACKING * s)
	var gf := _font(EXTRABOLD_ITALIC, ts)
	var gw := gf.get_string_size(tagline_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x - ts
	var bh := roundi(TAG_HEIGHT * s)
	var skew := bh * tan(deg_to_rad(TAG_SLANT_DEG))
	var pad := roundi(TAG_PAD * s)
	var bw := ceili(gw) + 2 * pad + roundi(skew * 0.5)
	var by := float(title_h + roundi(TAG_GAP * t))
	var dt := roundi(TAG_SHADOW * t)
	var pts := PackedVector2Array([Vector2(skew, by), Vector2(skew + bw, by), Vector2(bw, by + bh), Vector2(0, by + bh)])
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(dt, dt))
	g["bar"] = pts
	g["bar_shadow"] = sh
	g["title_font"] = tf
	g["outline"] = outline
	g["title_pos"] = Vector2(x0, y0)
	g["ds1"] = ds1
	g["ds2"] = ds2
	g["tag_font"] = gf
	g["tag_px"] = s
	# the text from the bar's slant at mid-height, its caps centred in the bar
	g["tag_pos"] = Vector2(roundi(pad + skew * 0.5), roundi(by + (bh - CAP * s) * 0.5 - (ASCENT - CAP) * s))
	g["size"] = Vector2(maxi(title_w, ceili(skew) + bw + dt), int(by) + bh + dt)
	return g


func _style(l: Label, font: Font, px: int, fill: Color, edge: Color, outline: int) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", fill)
	l.add_theme_color_override("font_outline_color", edge)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_constant_override("line_spacing", 0)
	l.size = l.get_minimum_size()


func _layout() -> void:
	var g := _geometry(title_px)
	var tf: Font = g["title_font"]
	var o: int = g["outline"]
	var p: Vector2 = g["title_pos"]
	_style(shadow_yellow, tf, title_px, YELLOW, YELLOW, o)
	_style(shadow_navy, tf, title_px, NAVY, NAVY, o)
	_style(title, tf, title_px, CREAM, NAVY, o)
	shadow_yellow.position = p + Vector2(g["ds2"], g["ds2"])
	shadow_navy.position = p + Vector2(g["ds1"], g["ds1"])
	title.position = p
	_style(tagline, g["tag_font"], g["tag_px"], NAVY, NAVY, 0)
	tagline.position = g["tag_pos"]
	bar = g["bar"]
	bar_shadow = g["bar_shadow"]
	custom_minimum_size = g["size"]
	queue_redraw()


func _draw() -> void:
	for e in [[bar_shadow, NAVY], [bar, YELLOW]]:
		var pts: PackedVector2Array = e[0]
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, e[1])
		# antialiased edges on the slant
		var ring := pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, e[1], 1.0, true)


## The offline previews (tests/menu_preview_dump.gd): the bar and its shadow in global px.
func preview_polys() -> Array:
	var out := []
	var at := get_global_rect().position
	for e in [[bar_shadow, NAVY], [bar, YELLOW]]:
		var pts := []
		for q in e[0]:
			pts.append([at.x + q.x, at.y + q.y])
		var c: Color = e[1]
		out.append({"k": "poly", "pts": pts, "col": [c.r, c.g, c.b, c.a]})
	return out
