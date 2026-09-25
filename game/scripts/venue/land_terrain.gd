class_name LandTerrain
extends RefCounted
## The drawn terrain of the venue land (presentation only): a height and a ground colour at every world point,
## built on the land polygons of VenueShapes so that the drawn waterline never lies outside the polygon the
## core collides with. Used by VenueView for the mesh and by the cameras (cameras.md §7) for land avoidance.
##
## Profile across the shore, with e = (signed distance into the polygon) - w, where w is 0 to SHORE_WOBBLE m of
## noise, so the waterline wanders inland of the polygon edge, never out of it:
##   e <= 0   under water, sloping down at 1 in 6 to DEPTH_MIN;
##   e > 0    a pebble beach rising 1 in 8 (or, where the rock mask is on, a low rocky shore of up to
##            CLIFF_HEIGHT m), then low hills up to about `hill_height` m in the middle of the island.

const DEPTH_MIN := -6.0
const UNDER_SLOPE := 0.17
const BEACH_SLOPE := 0.125
const BEACH_WIDTH := 14.0
const CLIFF_HEIGHT := 6.5
const SHORE_WOBBLE := 2.5
## outside this distance from a land polygon the terrain is not evaluated (height -INF)
const MARGIN := 40.0
## beaches around obstacle polygons (a harbour beach by the pier)
const HARBOUR_RADIUS := 110.0

var shapes: VenueShapes
var hill_height := 44.0
var noise_seed := 7

var _low := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _boxes: Array[Rect2] = []


func _init(s: VenueShapes, seed_value := 7) -> void:
	shapes = s
	self.noise_seed = seed_value
	for n in [_low, _mid, _fine, _shore]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_low.seed = seed_value
	_low.frequency = 1.0 / 260.0
	_low.fractal_octaves = 2
	_mid.seed = seed_value + 1
	_mid.frequency = 1.0 / 70.0
	_mid.fractal_octaves = 3
	_fine.seed = seed_value + 2
	_fine.frequency = 1.0 / 14.0
	_fine.fractal_octaves = 2
	_shore.seed = seed_value + 3
	_shore.frequency = 1.0 / 30.0
	_shore.fractal_octaves = 2
	for i in shapes.land.size():
		_boxes.append(shapes.land_box(i).grow(MARGIN))


## Terrain height at a world point (m above the still water line), -INF away from every land polygon.
func height(x: float, y: float) -> float:
	var p := Vector2(x, y)
	var best := -INF
	for i in _boxes.size():
		if _boxes[i].has_point(p):
			best = maxf(best, sample(i, p)["h"])
	return best


## Height and the shore quantities the colours use, for land polygon i.
## {h, e (m inland of the drawn waterline), rock (0..1 rocky shore mask)}
func sample(i: int, p: Vector2) -> Dictionary:
	var d := shapes.land_distance(i, p)
	var w := SHORE_WOBBLE * (0.5 + 0.5 * _shore.get_noise_2dv(p))
	var e := d - w
	var rock := _rock_mask(p)
	var h: float
	if e <= 0.0:
		h = maxf(e * UNDER_SLOPE * (1.0 + 1.5 * rock), DEPTH_MIN)
	else:
		var beach := minf(e, BEACH_WIDTH) * BEACH_SLOPE
		var cliff := CLIFF_HEIGHT * (0.6 + 0.4 * _fine.get_noise_2dv(p)) * _smooth(0.0, 9.0, e)
		h = lerpf(beach, cliff, rock)
		var lo := _low.get_noise_2dv(p)
		h += hill_height * pow(_smooth(8.0, 320.0, e), 0.85) * (0.72 + 0.28 * lo)
		h += 3.0 * _mid.get_noise_2dv(p) * _smooth(10.0, 50.0, e)
	return {"h": h, "e": e, "rock": rock}


## 0 on beaches, 1 on rocky shore: large patches, always a beach within HARBOUR_RADIUS of a quay.
func _rock_mask(p: Vector2) -> float:
	var m := _smooth(-0.15, 0.2, _low.get_noise_2d(p.x + 913.0, p.y - 377.0))
	for o in shapes.obstacles:
		if not o["circle"]:
			var c := _centroid(o["points"])
			m *= _smooth(0.6 * HARBOUR_RADIUS, HARBOUR_RADIUS, p.distance_to(c))
	return m


## Linear ground colour (rgb) and wetness (a) at a point with height h, slope normal_y, and the sample fields.
func color(p: Vector2, s: Dictionary, normal_y: float) -> Color:
	var h: float = s["h"]
	var e: float = s["e"]
	var rock: float = s["rock"]
	var f := _fine.get_noise_2dv(p)
	var m := _mid.get_noise_2dv(p)
	# palette (linear): pale karst limestone, pebbles, dry grass, maquis, dark wet stone
	var limestone := Color(0.42, 0.40, 0.36).lerp(Color(0.52, 0.50, 0.46), 0.5 + 0.5 * f)
	var pebbles := Color(0.40, 0.37, 0.31).lerp(Color(0.50, 0.47, 0.40), 0.5 + 0.5 * f)
	var grass := Color(0.20, 0.18, 0.08).lerp(Color(0.28, 0.24, 0.11), 0.5 + 0.5 * m)
	var maquis := Color(0.045, 0.07, 0.025).lerp(Color(0.075, 0.10, 0.04), 0.5 + 0.5 * f)
	var wet := Color(0.07, 0.065, 0.055)
	var steep := 1.0 - _smooth(0.72, 0.9, normal_y)
	var ground := pebbles.lerp(limestone, rock)
	# vegetation starts a little inland, earlier on the beaches' backs, and not on steep ground
	var veg := _smooth(BEACH_WIDTH * 0.7, BEACH_WIDTH + 12.0, e + 6.0 * m) * (1.0 - steep)
	var green := grass.lerp(maquis, _smooth(-0.25, 0.35, m + 0.4 * f + 0.25 * (h / maxf(hill_height, 1.0))))
	var c := ground.lerp(green, veg)
	c = c.lerp(limestone * 0.9, steep * 0.85)
	# wet band just above the water and under it
	var wetness := 1.0 - _smooth(0.05, 0.55, h)
	c = c.lerp(wet, wetness * 0.85)
	if h < -0.3:
		c = Color(0.05, 0.07, 0.06)  # under water (hidden by the opaque sea)
	c.a = wetness
	return c


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	return c / maxf(pts.size(), 1)


## Noise at a point in [-1, 1] (tree placement in VenueView).
func mid_noise(p: Vector2) -> float:
	return _mid.get_noise_2dv(p)
