class_name SeaModel
extends RefCounted
## CPU side of the sea renderer (water_render.md §2) and a double-precision mirror of the core's sea
## (sea.md §4, §6, §7.2) and puff factor (wind.md §6.4). Inputs are the data the core exports: the wave
## components (a, kx, ky, c, T), the exposure grid, and the live puff patches. Until the core binding exists the
## scene feeds it from a placeholder source (sea_env_source.gd); later the binding feeds the same fields.

const MAX_COMPONENTS := 22
const MAX_PUFFS := 10

## Each component: [a (m), kx, ky (cycles per metre), c (cycles), T (ms)], sorted by wavelength, longest first
## (water_render.md §3.2).
var components: Array = []
## The wavelength of each component (m, same order), the shader's comp_lam.
var wavelengths := PackedFloat32Array()
## Exposure grid (data_format.md §6.4): {x0, y0, dx, dy, nx, ny, default, e: PackedFloat32Array}; empty = none.
var exposure: Dictionary = {}
var sum_a := 0.0
var hs_eff := 0.0
## Venue wind field (data_format.md §6.2): {x0, y0, dx, dy, nx, ny, f: Array of 8 PackedFloat32Array (from N,
## NE, ... NW)}; empty = none. Only the speed factor f is drawn (the direction offset d does not show on water).
var wind_field: Dictionary = {}


func set_components(list: Array) -> void:
	components = []
	for c in list:
		if components.size() >= MAX_COMPONENTS:
			push_warning("SeaModel: more than %d sea components, the rest are not drawn" % MAX_COMPONENTS)
			break
		components.append([float(c[0]), float(c[1]), float(c[2]), float(c[3]), int(c[4])])
	# water_render.md §3.2: longest wavelength first, so the pixel shader's band loop can skip and stop early.
	# Every sum over the components is order-independent. Ties keep their input order.
	var order := range(components.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		var li := wavelength(components[i][1], components[i][2])
		var lj := wavelength(components[j][1], components[j][2])
		return li > lj or (li == lj and i < j))
	var sorted := []
	wavelengths = PackedFloat32Array()
	for i in order:
		sorted.append(components[i])
		wavelengths.append(wavelength(components[i][1], components[i][2]))
	components = sorted
	sum_a = 0.0
	var var_sum := 0.0
	for c in components:
		sum_a += c[0]
		var_sum += c[0] * c[0] * 0.5
	hs_eff = 4.0 * sqrt(var_sum)


func set_exposure(grid) -> void:
	exposure = {}
	if grid == null or not (grid is Dictionary) or grid.is_empty():
		return
	var e := PackedFloat32Array(grid["e"])
	exposure = {
		"x0": float(grid["x0"]), "y0": float(grid["y0"]), "dx": float(grid["dx"]), "dy": float(grid["dy"]),
		"nx": int(grid["nx"]), "ny": int(grid["ny"]), "default": float(grid.get("default", 1.0)), "e": e,
	}


## sea.md §6: E(x, y), the grid sampler of wind.md §8.1.
func exposure_at(x: float, y: float) -> float:
	if exposure.is_empty():
		return 1.0
	var g := exposure
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	if x < g["x0"] or y < g["y0"] or x > g["x0"] + (nx - 1) * g["dx"] or y > g["y0"] + (ny - 1) * g["dy"]:
		return g["default"]
	var u: float = (x - g["x0"]) / g["dx"]
	var v: float = (y - g["y0"]) / g["dy"]
	var i := mini(int(u), nx - 2)
	var j := mini(int(v), ny - 2)
	var tx := u - i
	var ty := v - j
	var e: PackedFloat32Array = g["e"]
	var r0 := lerpf(e[j * nx + i], e[j * nx + i + 1], tx)
	var r1 := lerpf(e[(j + 1) * nx + i], e[(j + 1) * nx + i + 1], tx)
	return lerpf(r0, r1, ty)


func set_wind_field(field) -> void:
	wind_field = {}
	if field == null or not (field is Dictionary) or field.is_empty() or not field.has("grid"):
		return
	var g: Dictionary = field["grid"]
	var sectors: Array = field.get("sectors", [])
	if sectors.size() != 8:
		push_warning("SeaModel: a venue wind field needs 8 sectors, got %d" % sectors.size())
		return
	var f := []
	for s in sectors:
		f.append(PackedFloat32Array(s["f"]))
	wind_field = {
		"x0": float(g["x0"]), "y0": float(g["y0"]), "dx": float(g["dx"]), "dy": float(g["dy"]),
		"nx": int(g["nx"]), "ny": int(g["ny"]), "f": f,
	}


## wind.md §8: the two sectors around the direction the wind blows from and the blend weight, [k0, k1, tw].
static func land_sectors(global_from: float) -> Array:
	var w := fposmod(global_from, TAU) / (PI * 0.25)
	var k0 := int(floor(w)) & 7
	return [k0, (k0 + 1) & 7, w - floor(w)]


## wind.md §8.1 grid sampler on one sector's speed factor, 1 outside the grid.
func land_sector_at(k: int, x: float, y: float) -> float:
	var g := wind_field
	if g.is_empty():
		return 1.0
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	if x < g["x0"] or y < g["y0"] or x > g["x0"] + (nx - 1) * g["dx"] or y > g["y0"] + (ny - 1) * g["dy"]:
		return 1.0
	var u: float = (x - g["x0"]) / g["dx"]
	var v: float = (y - g["y0"]) / g["dy"]
	var i := mini(int(u), nx - 2)
	var j := mini(int(v), ny - 2)
	var tx := u - i
	var ty := v - j
	var f: PackedFloat32Array = g["f"][k]
	var r0 := lerpf(f[j * nx + i], f[j * nx + i + 1], tx)
	var r1 := lerpf(f[(j + 1) * nx + i], f[(j + 1) * nx + i + 1], tx)
	return lerpf(r0, r1, ty)


## wind.md §8: the venue's land-effect speed factor at a point for the wind from global_from (rad).
func land_factor_at(x: float, y: float, global_from: float) -> float:
	if wind_field.is_empty():
		return 1.0
	var s := land_sectors(global_from)
	return lerpf(land_sector_at(s[0], x, y), land_sector_at(s[1], x, y), s[2])


## water_render.md §2: the per-frame phases d_i' = frac(c_i - fmod(t_r, T_i)/T_i + kx_i*ox + ky_i*oy), in double.
func phases(t_ms: float, ox: float, oy: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(components.size())
	for i in components.size():
		var c: Array = components[i]
		var T := float(c[4])
		var d: float = c[3] - fmod(t_ms, T) / T + c[1] * ox + c[2] * oy
		out[i] = d - floor(d)
	return out


## The shader's height at a camera-relative point (xl, yl) for the phases of an origin, every component (w_i = 1),
## before the exposure. Double precision.
func height_local(xl: float, yl: float, ph: PackedFloat64Array) -> float:
	var eta := 0.0
	for i in components.size():
		var c: Array = components[i]
		var f: float = c[1] * xl + c[2] * yl + ph[i]
		eta += c[0] * cos(TAU * (f - floor(f)))
	return eta


## sea_height(x, y) at render time t_ms (sea.md §7.2), with the exposure. Double precision.
func height(x: float, y: float, t_ms: float) -> float:
	var eta := 0.0
	for c in components:
		var T := float(c[4])
		var f: float = c[1] * x + c[2] * y + c[3] - fmod(t_ms, T) / T
		eta += c[0] * cos(TAU * (f - floor(f)))
	return exposure_at(x, y) * eta


## Slope (d eta/dx, d eta/dy) at render time t_ms, the gradient of E ignored (sea.md §4).
func slope(x: float, y: float, t_ms: float) -> Vector2:
	var gx := 0.0
	var gy := 0.0
	for c in components:
		var T := float(c[4])
		var f: float = c[1] * x + c[2] * y + c[3] - fmod(t_ms, T) / T
		var s := sin(TAU * (f - floor(f)))
		gx -= c[0] * TAU * c[1] * s
		gy -= c[0] * TAU * c[2] * s
	var e := exposure_at(x, y)
	return Vector2(e * gx, e * gy)


## water_render.md §3.2: the standard deviation of the height the grid fade removes where the grid spacing is
## s (m): sqrt(sum(((1 - w_i) a_i)^2 / 2)).
func faded_sigma(s: float) -> float:
	var v := 0.0
	for c in components:
		var r: float = (1.0 - fade(c[1], c[2], s)) * c[0]
		v += r * r * 0.5
	return sqrt(v)


static func fade(kx: float, ky: float, s: float) -> float:
	if s <= 0.0:
		return 1.0
	return smoothstep(2.0, 4.0, wavelength(kx, ky) / s)


## Wavelength (m) of a component with wave numbers kx, ky (cycles per metre), as the shader's wm_fade.
static func wavelength(kx: float, ky: float) -> float:
	return 1.0 / maxf(Vector2(kx, ky).length(), 1e-6)


static func wrap_tile(d: float, tile: float) -> float:
	return d - tile * floor(d * (1.0 / tile) + 0.5)


## §2 puff uniforms: (px - ox, py - oy, R, e*s) per live patch, centres wrapped to the nearest image of the
## camera (the shader wraps again, which changes nothing). `patches`: [px, py, R, s, e] each.
static func pack_puffs(patches: Array, ox: float, oy: float, tile: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	for p in patches:
		if float(p[4]) < 1e-4:
			continue
		if out.size() >= MAX_PUFFS:
			push_warning("SeaModel: more than %d live puff patches, the rest are not drawn" % MAX_PUFFS)
			break
		out.append(Vector4(wrap_tile(float(p[0]) - ox, tile), wrap_tile(float(p[1]) - oy, tile), float(p[2]),
				float(p[4]) * float(p[3])))
	return out


## §4.3 the shader's puff factor at a camera-relative point from packed patches (double-precision mirror).
static func puff_factor_local(xl: float, yl: float, puffs: PackedVector4Array, tile: float, lo: float,
		hi: float) -> float:
	var m := 1.0
	for p in puffs:
		var dx := wrap_tile(xl - p.x, tile)
		var dy := wrap_tile(yl - p.y, tile)
		var r2 := dx * dx + dy * dy
		var R2 := p.z * p.z
		if r2 <= R2:
			m *= 1.0 + p.w * (1.0 - r2 / R2)
	return clampf(m, lo, hi)
