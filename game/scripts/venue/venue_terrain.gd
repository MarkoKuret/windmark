class_name VenueTerrain
extends RefCounted
## The drawn terrain of a real venue (presentation only): the meshes venuegen writes from the elevation model and
## the coastline (`data/venues/<venue>.terrain.json` and `.bin`, data_format.md §6.10), their ground colours, and
## the ground height grid the cameras' land avoidance reads. The waterline of the meshes follows the core's land
## polygons inside the land margin (venues.md §4.2), so boats never visibly hit water or pass through rock.
##
##   var t := VenueTerrain.load_venue("garda")   # null when the venue has no terrain file
##   for c in t.chunks: add a MeshInstance3D with c["mesh"] (shared land material), cast shadows if c["shadows"]

const DEPTH_MIN := -7.5
## the land shader's stone on steep faces (land.gdshader `bare_rock`): the colours here carry the rock already
const BARE_ROCK := 0.25

## [{id: String, mesh: ArrayMesh, shadows: bool, triangles: int, vertices: int}] for the terrain chunks, then the
## horizon ridge (id "ridge", no shadows)
var chunks: Array = []
var header := {}
var triangles := 0
var vertices := 0

var _ground := PackedByteArray()
var _g := {}
var _low := FastNoiseLite.new()
var _mid := FastNoiseLite.new()


## The terrain of a venue id (or a .terrain.json path), null when there is none or it does not load.
static func load_venue(venue: String) -> VenueTerrain:
	if venue == "":
		return null
	var path := venue
	if not venue.ends_with(".terrain.json"):
		path = BoatClassData.repo_path("data/venues/%s.terrain.json" % venue)
	if not FileAccess.file_exists(path):
		return null
	var h: Variant = BoatClassData._read_json(path)
	if not h is Dictionary or h.get("schema", "") != "windmark.terrain/1":
		push_warning("terrain: %s is not a windmark.terrain/1 file" % path)
		return null
	var bin := FileAccess.get_file_as_bytes(path.get_base_dir().path_join(String(h["bin"])))
	if bin.is_empty():
		push_warning("terrain: %s has no binary file" % path)
		return null
	var t := VenueTerrain.new()
	t._build(h, bin)
	return t


func _init() -> void:
	for n in [_low, _mid]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
	_low.seed = 11
	_low.frequency = 1.0 / 900.0
	_mid.seed = 12
	_mid.frequency = 1.0 / 140.0


func _build(h: Dictionary, bin: PackedByteArray) -> void:
	header = h
	var parts: Array = (h["chunks"] as Array).duplicate()
	if h.get("ridge") is Dictionary:
		parts.append(h["ridge"])
	for c in parts:
		var mesh := _mesh(_blob(bin, c), int(c["vertices"]), int(c["triangles"]), String(c["id"]) == "ridge")
		chunks.append({"id": String(c["id"]), "mesh": mesh, "shadows": bool(c.get("shadows", false)),
			"triangles": int(c["triangles"]), "vertices": int(c["vertices"])})
		if String(c["id"]) != "ridge":
			triangles += int(c["triangles"])
			vertices += int(c["vertices"])
	var g: Dictionary = h["ground"]
	_g = g["grid"]
	_g["scale"] = float(g.get("scale", 0.1))
	_ground = _blob(bin, g)


static func _blob(bin: PackedByteArray, c: Dictionary) -> PackedByteArray:
	var z := bin.slice(int(c["offset"]), int(c["offset"]) + int(c["bytes"]))
	return z.decompress(int(c["raw_bytes"]), FileAccess.COMPRESSION_GZIP)


## One mesh: positions and normals stay in world ENU (x east, y north, h up) and the node's basis turns them
## into the scene (Frames.enu_to_scene); the colours come from height, slope and the shore distance.
func _mesh(raw: PackedByteArray, n: int, m: int, ridge: bool) -> ArrayMesh:
	var pos := raw.slice(0, 12 * n).to_vector3_array()
	var nrm := raw.slice(12 * n, 24 * n).to_vector3_array()
	var shore := raw.slice(24 * n, 28 * n).to_float32_array()
	var idx := raw.slice(28 * n, 28 * n + 12 * m).to_int32_array()
	idx.reverse()  # counter-clockwise seen from above in the file; Godot's front face is clockwise
	var cols := PackedColorArray()
	cols.resize(n)
	for i in n:
		cols[i] = ground_color(pos[i], nrm[i].z, shore[i], ridge)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The basis that maps world ENU (x east, y north, h up) to the scene (x, h, -y).
static func enu_basis() -> Basis:
	return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))


## Linear ground colour (rgb) and wetness (a) at an ENU point p (p.z the height above the water) with the
## normal's up component ny and the signed shore distance s (m, positive inland): a plain lake-and-mountain
## palette: wet stone and pale pebbles at the waterline, grey-green scrub and meadows low down, dark mixed forest
## on the slopes, bare limestone on steep faces and high up.
func ground_color(p: Vector3, ny: float, s: float, ridge := false) -> Color:
	var h := p.z
	var lo := _low.get_noise_2d(p.x, p.y)
	var mi := 0.0 if ridge else _mid.get_noise_2d(p.x, p.y)
	var limestone := Color(0.15, 0.145, 0.13).lerp(Color(0.22, 0.21, 0.185), 0.5 + 0.5 * mi)
	var pebbles := Color(0.40, 0.38, 0.33)
	var meadow := Color(0.16, 0.17, 0.07).lerp(Color(0.22, 0.21, 0.10), 0.5 + 0.5 * mi)
	var scrub := Color(0.085, 0.10, 0.05)
	var forest := Color(0.032, 0.05, 0.022).lerp(Color(0.05, 0.068, 0.03), 0.5 + 0.5 * lo)
	var alpine := Color(0.21, 0.20, 0.14)
	var wet := Color(0.07, 0.065, 0.055)
	# the 30 m elevation model rounds the cliffs: only the steepest faces show bare rock through the trees
	var steep := (1.0 - LandTerrain._smooth(0.36, 0.6, ny + 0.12 * mi)) * 0.65
	# low land: meadows and scrub; slopes from about 150 m: forest; above about 1500 m: alpine grass, then rock
	var green := meadow.lerp(scrub, LandTerrain._smooth(-0.3, 0.4, mi + 0.5 * lo))
	green = green.lerp(forest, LandTerrain._smooth(40.0, 200.0, h + 120.0 * lo))
	green = green.lerp(alpine, LandTerrain._smooth(1350.0, 1750.0, h + 200.0 * lo))
	green = green.lerp(limestone, LandTerrain._smooth(1900.0, 2300.0, h + 150.0 * lo))
	var c := green.lerp(limestone, steep)
	# the shore: a band of pebbles and stone a few metres wide, darker and wet at the water
	var beach := 1.0 - LandTerrain._smooth(2.0, 9.0 + 4.0 * mi, s)
	c = c.lerp(pebbles.lerp(limestone, steep), beach)
	var wetness := 1.0 - LandTerrain._smooth(0.05, 0.6, h)
	c = c.lerp(wet, wetness * 0.85)
	if h < -0.3:
		c = Color(0.05, 0.07, 0.06)  # under water (hidden by the opaque water)
	c.a = wetness
	return c


## Ground height (m above the still water) at a world point from the ground grid around the racing area, -INF on
## open water and outside the grid (cameras.md §7).
func height(x: float, y: float) -> float:
	if _ground.is_empty():
		return -INF
	var u := (x - float(_g["x0"])) / float(_g["dx"])
	var v := (y - float(_g["y0"])) / float(_g["dy"])
	var nx := int(_g["nx"])
	var ny := int(_g["ny"])
	if u < 0.0 or v < 0.0 or u > nx - 1 or v > ny - 1:
		return -INF
	var i := mini(int(u), nx - 2)
	var j := mini(int(v), ny - 2)
	var tu := u - i
	var tv := v - j
	var k := 2 * (j * nx + i)
	var a := _ground.decode_s16(k)
	var b := _ground.decode_s16(k + 2)
	var c := _ground.decode_s16(k + 2 * nx)
	var d := _ground.decode_s16(k + 2 * nx + 2)
	var hh := (lerpf(lerpf(a, b, tu), lerpf(c, d, tu), tv)) * float(_g["scale"])
	return -INF if hh <= DEPTH_MIN else hh
