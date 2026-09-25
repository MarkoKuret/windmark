class_name SeaTextures
extends RefCounted
## Tiling textures of the sea shader, generated at load from Godot's seamless noise (no texture files):
## the detail normal map (water_render.md §4.1) and the foam noise (§4.4: R = streaks, G = coarse breakup).
## Built once and shared by every Sea node.

const SIZE := 256

static var _detail_image: Image
static var _foam_image: Image
static var _detail: ImageTexture
static var _foam: ImageTexture


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
