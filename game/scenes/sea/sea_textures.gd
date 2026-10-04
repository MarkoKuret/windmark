class_name SeaTextures
extends RefCounted
## Tiling textures of the sea shader, generated at load from Godot's seamless noise (no texture files):
## the detail normal map (water_render.md §4.1), the foam noise of the wakes and bow waves (§5: R = streaks, G = coarse
## breakup) and the whitecap foam levels (§4.4).
## Built once and shared by every Sea node.

const SIZE := 256
## whitecap foam texture side (texels); the shader maps it to CAPS_TILE metres (sea.gd)
const CAPS_SIZE := 256

static var _detail_image: Image
static var _foam_image: Image
static var _detail: ImageTexture
static var _foam: ImageTexture
static var _caps_image: Image
static var _caps: ImageTexture


static func _noise(seed: int, freq: float, octaves: int, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = kind
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	return n


## RGBA8 normal map (x in R, y in G, 0.5 = flat), with mipmaps.
static func detail_image() -> Image:
	if _detail_image == null:
		var n := _noise(1301, 1.0 / 24.0, 4)
		var img := n.get_seamless_image(SIZE, SIZE, false, false, 0.15, true)
		img.convert(Image.FORMAT_RF)
		img.bump_map_to_normal_map(6.0)
		img.generate_mipmaps()
		_detail_image = img
	return _detail_image


## RG8: R streak noise (stretched along the wind by the shader's uv), G coarse breakup, with mipmaps.
static func foam_image() -> Image:
	if _foam_image == null:
		var a := _noise(2203, 1.0 / 20.0, 3).get_seamless_image(SIZE, SIZE, false, false, 0.15, true)
		var b := _noise(4409, 1.0 / 48.0, 2).get_seamless_image(SIZE, SIZE, false, false, 0.15, true)
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)
		for y in SIZE:
			for x in SIZE:
				img.set_pixel(x, y, Color(a.get_pixel(x, y).r, b.get_pixel(x, y).r, 0.0))
		img.generate_mipmaps()
		_foam_image = img
	return _foam_image


## Whitecap foam (water_render.md §4.4): RGBA8, CAPS_SIZE², tiling, with mipmaps. Each channel is the foam
## coverage (0..1) of one density level, nested (every level holds the foam of the ones before it): R sparse fizz
## (broken fine lace and a few longer filaments), G the lace net, B dense foam (thick lace, the cells filling with bubbles), A
## near-solid white with a few dark holes. The shader blends between the levels by foam intensity, so the mips
## (which average coverage) fade a distant cap to its true mean whiteness instead of shimmering.
## Built from periodic cellular (Worley) noise, which tiles exactly, and seamless FastNoiseLite for the breakup.
static func caps_image() -> Image:
	if _caps_image == null:
		var n := CAPS_SIZE
		# a smooth periodic warp bends the straight cell borders into the curved lines of real foam
		var wx := _noise(3301, 1.0 / 40.0, 2).get_seamless_image(n, n, false, false, 0.2, true)
		var wy := _noise(3307, 1.0 / 40.0, 2).get_seamless_image(n, n, false, false, 0.2, true)
		var coarse := _worley(n, 12, 5101, wx, wy, 0.45)
		var fine := _worley(n, 28, 7207, wx, wy, 0.8)
		var brk := _noise(9311, 1.0 / 46.0, 3).get_seamless_image(n, n, false, false, 0.2, true)
		var blobs := _noise(6113, 1.0 / 20.0, 2).get_seamless_image(n, n, false, false, 0.2, true)
		var ec: PackedFloat32Array = coarse[0]   # F2 - F1 of the coarse cells (0 on a cell border)
		var ef: PackedFloat32Array = fine[0]
		var cf: PackedFloat32Array = fine[1]     # F1 of the fine cells (0 at a bubble centre)
		var data := PackedByteArray()
		data.resize(n * n * 4)
		for y in n:
			for x in n:
				var k := y * n + x
				var b: float = brk.get_pixel(x, y).r
				var bl: float = blobs.get_pixel(x, y).r
				var lace_c := 1.0 - smoothstep(0.02, 0.12, ec[k])
				var lace_cw := 1.0 - smoothstep(0.05, 0.24, ec[k])
				var lace_f := 1.0 - smoothstep(0.03, 0.14, ef[k])
				var film := smoothstep(0.35, 0.75, bl)   # a thin milky film between the filaments
				var l0 := maxf(lace_f * smoothstep(0.55, 0.70, b), lace_c * smoothstep(0.62, 0.76, b)) * 0.75
				var l1 := maxf(l0, maxf(lace_c * smoothstep(0.38, 0.54, b), lace_f * smoothstep(0.40, 0.55, b)) * 0.9)
				l1 = maxf(l1, 0.3 * film * smoothstep(0.3, 0.5, b))
				var l2 := maxf(l1, maxf(lace_cw * smoothstep(0.30, 0.46, b), lace_f * smoothstep(0.30, 0.46, b)))
				l2 = maxf(l2, maxf(smoothstep(0.50, 0.70, bl) * smoothstep(0.35, 0.55, b), 0.45 * film))
				var l3 := maxf(l2, smoothstep(0.06 + 0.10 * bl, 0.20 + 0.10 * bl, cf[k]) * (0.8 + 0.2 * smoothstep(0.3, 0.5, b)))
				data[4 * k] = int(clampf(l0, 0.0, 1.0) * 255.0 + 0.5)
				data[4 * k + 1] = int(clampf(l1, 0.0, 1.0) * 255.0 + 0.5)
				data[4 * k + 2] = int(clampf(l2, 0.0, 1.0) * 255.0 + 0.5)
				data[4 * k + 3] = int(clampf(l3, 0.0, 1.0) * 255.0 + 0.5)
		var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
		img.generate_mipmaps()
		_caps_image = img
	return _caps_image


## Periodic Worley noise on an n x n image of g x g jittered cells (one feature point each, wrapped, so it tiles):
## [F2 - F1, F1] per pixel in cell units (row major). The lookup point is displaced by (wx, wy) (seamless images,
## 0.5 = none) times `warp` cells.
static func _worley(n: int, g: int, seed: int, wx: Image, wy: Image, warp: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	pts.resize(g * g)
	for j in g:
		for i in g:
			pts[j * g + i] = Vector2(i + rng.randf_range(0.1, 0.9), j + rng.randf_range(0.1, 0.9))
	var edge := PackedFloat32Array()
	var f1s := PackedFloat32Array()
	edge.resize(n * n)
	f1s.resize(n * n)
	var s := float(g) / float(n)
	for y in n:
		for x in n:
			var px := (x + 0.5) * s + (wx.get_pixel(x, y).r - 0.5) * 2.0 * warp
			var py := (y + 0.5) * s + (wy.get_pixel(x, y).r - 0.5) * 2.0 * warp
			var ci := floori(px)
			var cj := floori(py)
			var f1 := 9.0
			var f2 := 9.0
			for dj in 3:
				var jj := cj + dj - 1
				var oy := g * floori(float(jj) / g)
				var row := (jj - oy) * g
				for di in 3:
					var ii := ci + di - 1
					var ox := g * floori(float(ii) / g)
					var p := pts[row + ii - ox]
					var dx := p.x + ox - px
					var dy := p.y + oy - py
					var d := sqrt(dx * dx + dy * dy)
					if d < f1:
						f2 = f1
						f1 = d
					elif d < f2:
						f2 = d
			edge[y * n + x] = f2 - f1
			f1s[y * n + x] = f1
	return [edge, f1s]


static func caps() -> ImageTexture:
	if _caps == null:
		_caps = ImageTexture.create_from_image(caps_image())
	return _caps


static func detail() -> ImageTexture:
	if _detail == null:
		_detail = ImageTexture.create_from_image(detail_image())
	return _detail


static func foam() -> ImageTexture:
	if _foam == null:
		_foam = ImageTexture.create_from_image(foam_image())
	return _foam


## The exposure grid as an nx x ny R32F texture, texel (i, j) = node (i, j) (sampled with texelFetch).
static func exposure_texture(grid: Dictionary) -> ImageTexture:
	if grid.is_empty():
		var one := Image.create(2, 2, false, Image.FORMAT_RF)
		one.fill(Color(1, 0, 0))
		return ImageTexture.create_from_image(one)
	var e: PackedFloat32Array = grid["e"]
	var img := Image.create_from_data(grid["nx"], grid["ny"], false, Image.FORMAT_RF, e.to_byte_array())
	return ImageTexture.create_from_image(img)
