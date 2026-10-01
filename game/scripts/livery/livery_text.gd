class_name LiveryText
extends RefCounted
## The per-boat text texture of a livery (data_format.md §8, sail_visuals.md §11.2): one single-channel coverage
## image of 1024 x 512, four rows of 128 px: the boat name, the sail number, the nation letters and the class
## insignia, set in Barlow Semi Condensed Bold (game/fonts/barlow, OFL) on the CPU from the font's glyph cache, so
## it works headless and costs one small texture per boat (about 0.7 MB with mipmaps).

const FONT_PATH := "res://fonts/barlow/BarlowSemiCondensed-Bold.ttf"
const W := 1024
const H := 512
const ROW := 128
## font size in px, and the cap height and baseline it gives in a row
const SIZE := 120
const CAP_TOP := 17
const BASELINE := 102
const PAD := 10
## extra space between characters, of the font size (sail numbers need about 0.2 h between characters, G1.2)
const TRACK := 0.05
## insignia slant (x shift per px of height)
const SLANT := 0.22

enum Row { NAME, NUMBER, NATION, INSIGNIA }

static var _font: FontFile
## glyph cache images converted to RGBA8 (white, coverage in alpha), by texture index
static var _cache_img := {}

var image: Image
var texture: ImageTexture
## per row: {"full": Rect (u0, v0, u1, v1) of the whole row height, "cap": the cap-height band, "w_px": ink width}
var rows := {}


static func build(lv: Livery) -> LiveryText:
	var t := LiveryText.new()
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	t._row(img, Row.NAME, lv.boat_name, false)
	t._row(img, Row.NUMBER, lv.sail_number, false)
	t._row(img, Row.NATION, lv.nation, false)
	t._row(img, Row.INSIGNIA, lv.insignia, true)
	img.convert(Image.FORMAT_R8)
	img.generate_mipmaps()
	t.image = img
	t.texture = ImageTexture.create_from_image(img)
	return t


static func font() -> FontFile:
	if _font == null:
		_font = load(FONT_PATH) as FontFile
	return _font


## Width in px of `text` at the row size (advances plus tracking).
static func measure(text: String) -> float:
	var f := font()
	var w := 0.0
	for i in text.length():
		var g := f.get_glyph_index(SIZE, text.unicode_at(i), 0)
		w += f.get_glyph_advance(0, SIZE, g).x + (TRACK * SIZE if i < text.length() - 1 else 0.0)
	return w


func _row(img: Image, row: int, text: String, insignia: bool) -> void:
	var y0 := row * ROW
	var f := font()
	var sz := Vector2i(SIZE, 0)
	var x := float(PAD)
	var x_max := 0.0
	for i in text.length():
		var g := f.get_glyph_index(SIZE, text.unicode_at(i), 0)
		_glyph_cache(0)
		var ti := f.get_glyph_texture_idx(0, sz, g)
		var gs := f.get_glyph_size(0, sz, g)
		if ti >= 0 and gs.x > 0 and gs.y > 0:
			var src := _glyph_cache(ti)
			var uv := f.get_glyph_uv_rect(0, sz, g)
			var off := f.get_glyph_offset(0, sz, g)
			var dst := Vector2(x + off.x, y0 + BASELINE + off.y)
			var r := Rect2i(Vector2i(uv.position), Vector2i(uv.size))
			if insignia:
				# bold italic: each pixel row shifted by its height above the baseline
				for k in r.size.y:
					var dy := dst.y + k
					var sx := roundi(dst.x + SLANT * (y0 + BASELINE - dy))
					img.blend_rect(src, Rect2i(r.position.x, r.position.y + k, r.size.x, 1), Vector2i(sx, int(dy)))
			else:
				img.blend_rect(src, r, Vector2i(roundi(dst.x), roundi(dst.y)))
			x_max = maxf(x_max, x + off.x + uv.size.x + (SLANT * (BASELINE - CAP_TOP) if insignia else 0.0))
		x += f.get_glyph_advance(0, SIZE, g).x + TRACK * SIZE
	if insignia and text != "":
		# the wave mark under the letters: a thick stroke over the text width
		var x1 := x_max
		for xi in range(PAD, int(x1) + 1):
			var s := float(xi - PAD) / maxf(x1 - PAD, 1.0)
			var yc := y0 + BASELINE + 14.0 - 6.0 * sin(TAU * (s * 1.25 + 0.1))
			var th := 4.0 + 4.0 * sin(PI * s)
			img.fill_rect(Rect2i(xi, int(yc - th * 0.5), 1, maxi(1, int(th))), Color(1, 1, 1, 1))
	var w_px := maxf(x_max - PAD, 1.0)
	var u0 := float(PAD - 2) / W
	var u1 := float(PAD + w_px + 2) / W
	rows[row] = {
		"full": Rect2(u0, float(y0) / H, u1 - u0, float(ROW) / H),
		"cap": Rect2(u0, float(y0 + CAP_TOP) / H, u1 - u0, float(BASELINE - CAP_TOP) / H),
		"w_px": w_px + 4.0,
		"empty": text == "",
	}


## Width over height of a row's box: `cap` the cap band (digits, capitals), else the whole row.
func aspect(row: int, cap: bool) -> float:
	var r: Dictionary = rows[row]
	return float(r["w_px"]) / float(BASELINE - CAP_TOP if cap else ROW)


## The texture rectangle of a row as a Vector4 (u0, v0, u1, v1).
func rect(row: int, cap: bool) -> Vector4:
	var r: Rect2 = rows[row]["cap" if cap else "full"]
	return Vector4(r.position.x, r.position.y, r.end.x, r.end.y)


static func _glyph_cache(ti: int) -> Image:
	# every printable ASCII glyph is rendered once at the row size, then the cache textures (white, coverage in
	# alpha) are converted to RGBA8 for blending
	var f := font()
	var sz := Vector2i(SIZE, 0)
	if _cache_img.is_empty():
		f.render_range(0, sz, 32, 126)
	if not _cache_img.has(ti):
		var img := (f.get_texture_image(0, sz, ti)).duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_cache_img[ti] = img
	return _cache_img[ti]
