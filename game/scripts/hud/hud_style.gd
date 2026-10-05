class_name HudStyle
extends RefCounted
## The HUD's look (hud.md §16, docs/design/hud_direction.md): the colour tokens, the type (Barlow Semi Condensed
## with tabular figures through FontVariation) and the scale from the 1920 x 1080 reference to the screen.

const INK := Color("#06121B")
const PAPER := Color("#F5F8FA")
const MIST := Color(0.961, 0.973, 0.98, 0.66)
const HAIR := Color(0.961, 0.973, 0.98, 0.42)
const MARK := Color("#FFD23F")
const GHOST := Color(0.961, 0.973, 0.98, 0.35)
## the rules colours of each colour-blind palette (hud.md §16.2.1): [stbd, port, owe, have]
const PALETTES := {
	"standard": [Color("#27D17C"), Color("#FF4438"), Color("#FF8A1F"), Color("#2FD8EE")],
	"deuteranopia": [Color("#4D8EFF"), Color("#FF7A66"), Color("#FF4D9F"), Color("#19E0FF")],
	"protanopia": [Color("#33CCFF"), Color("#FF974D"), Color("#FF338D"), Color("#A480FF")],
	"tritanopia": [Color("#80FF81"), Color("#FF667C"), Color("#E64DFF"), Color("#4D94FF")],
}
## the rules colours in use (set_palette)
static var STBD := Color("#27D17C")
static var PORT := Color("#FF4438")
static var OWE := Color("#FF8A1F")
static var HAVE := Color("#2FD8EE")
static var palette := "standard"

## RaceHudValues.Tint -> token (rebuilt by set_palette)
static var TINTS := _tints()

const FONT_FILES := {
	500: "res://fonts/barlow/BarlowSemiCondensed-Medium.ttf",
	600: "res://fonts/barlow/BarlowSemiCondensed-SemiBold.ttf",
	700: "res://fonts/barlow/BarlowSemiCondensed-Bold.ttf",
}
## the smallest text on any screen, px (hud_direction.md §4)
const MIN_TEXT := 11
## hud.md §16.5, portrait design px: the reference width, the side, top and bottom margins (clear of the short-video
## apps' title bar above and their caption and button strip below)
const PORTRAIT_W := 1080.0
const PORTRAIT_SIDE := 48.0
const PORTRAIT_TOP := 140.0
const PORTRAIT_BOTTOM := 200.0

static var _fonts := {}


static func _tints() -> Dictionary:
	return {
		RaceHudValues.Tint.WHITE: PAPER,
		RaceHudValues.Tint.RED: PORT,
		RaceHudValues.Tint.ORANGE: OWE,
		RaceHudValues.Tint.CYAN: HAVE,
		RaceHudValues.Tint.YELLOW: MARK,
		RaceHudValues.Tint.GREEN: STBD,
		RaceHudValues.Tint.GREY: GHOST,
	}


## The rules colours of a colour-blind palette (hud.md §16.2.1); an unknown name is the standard one.
static func set_palette(name: String) -> void:
	palette = name if PALETTES.has(name) else "standard"
	var c: Array = PALETTES[palette]
	STBD = c[0]
	PORT = c[1]
	OWE = c[2]
	HAVE = c[3]
	TINTS = _tints()


## The family at a weight (500, 600, 700) with tabular figures and `tracking` (em) between the letters.
static func font(weight := 600, tracking := 0.0, size_px := 16) -> Font:
	var spacing := int(roundf(tracking * size_px))
	var key := "%d:%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font = load(FONT_FILES.get(weight, FONT_FILES[600]))
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


## A screen taller than wide: the portrait layout of hud.md §16.5 (the 9:16 capture preset).
static func portrait(size: Vector2) -> bool:
	return size.y > size.x and size.x > 0.0


## The scale of the 1920 x 1080 design to a screen of `size` (logical px, after the UI scale): the height on 16:9
## and wider; on narrower screens under 900 px tall (the Steam Deck's 16:10) 0.82 at 1280 x 800, so the Deck is
## not scaled by its height alone (hud_direction.md §5). Portrait: the width over 1080 (hud.md §16.5).
static func ui_k(size: Vector2) -> float:
	if size.y <= 0.0:
		return 1.0
	if portrait(size):
		return size.x / PORTRAIT_W
	if size.x / size.y >= 1.7 or size.y >= 900.0:
		return size.y / 1080.0
	return minf(size.x / 1561.0, size.y / 976.0)


## The margins at `size` (logical px): 56 x 44 of the design on 16:9, 32 x 28 px at 1280 x 800. Portrait has its
## own top and bottom (portrait_margins); this is its left and top.
static func margins(size: Vector2) -> Vector2:
	var k := ui_k(size)
	if portrait(size):
		return Vector2(PORTRAIT_SIDE, PORTRAIT_TOP) * k
	if size.y > 0.0 and size.x / size.y < 1.7:
		return Vector2(39.0, 34.0) * k
	return Vector2(56.0, 44.0) * k


## The bottom margin at `size` (logical px): the portrait one, else the same as the top.
static func bottom_margin(size: Vector2) -> float:
	if portrait(size):
		return PORTRAIT_BOTTOM * ui_k(size)
	return margins(size).y


## Whether the screen gets the small-screen defaults (Glance, hud.md §16.1).
static func small_screen(size: Vector2) -> bool:
	return size.y < 900.0 and size.y > 0.0


## A true minus sign for a leading "-" (hud_direction.md §4).
static func minus(s: String) -> String:
	return "−" + s.substr(1) if s.begins_with("-") else s


## Splits a formatted "197 m" into ["197", "M"] (number and unit); no unit gives [s, ""].
static func split_unit(s: String) -> Array[String]:
	var i := s.rfind(" ")
	if i <= 0:
		return [s, ""]
	return [s.substr(0, i), s.substr(i + 1).to_upper()]
