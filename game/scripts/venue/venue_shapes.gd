class_name VenueShapes
extends RefCounted
## The venue's land polygons and obstacles (data_format.md §6.5) as the core uses them for collisions: from the
## core world (CoreSim.venue_land, venue_obstacles) or, on FakeSim, from the venue file itself. World ENU metres.
## Plain 2-D geometry for the land view, the cameras and the tests.

## [{id: String, points: PackedVector2Array}], counter-clockwise, interior = land
var land: Array = []
## [{id: String, circle: bool, points: PackedVector2Array (polygon), c: Vector2, r: float (circle)}]
var obstacles: Array = []

var _land_boxes: Array[Rect2] = []


## From the core world: the shapes the collisions use.
static func from_core(core: Object) -> VenueShapes:
	var v := VenueShapes.new()
	if core == null:
		return v
	for l in core.venue_land():
		v.land.append({"id": String(l["id"]), "points": PackedVector2Array(l["points"])})
	for o in core.venue_obstacles():
		v.obstacles.append({"id": String(o["id"]), "circle": bool(o["circle"]),
			"points": PackedVector2Array(o["points"]), "c": Vector2(o["c"]), "r": float(o["r"])})
	v._boxes()
	return v


## From a venue file (data/venues/<venue>.venue.json when a bare name). Empty on a missing or bad file.
static func from_file(venue: String) -> VenueShapes:
	var v := VenueShapes.new()
	var path := venue
	if venue != "" and not venue.contains("/"):
		path = BoatClassData.repo_path("data/venues/%s.venue.json" % venue)
	var d: Variant = BoatClassData._read_json(path)
	if not d is Dictionary:
		return v
	for l in d.get("land", []):
		v.land.append({"id": String(l["id"]), "points": _pts(l["points"])})
	for o in d.get("obstacles", []):
		if o.has("circle"):
			var c: Array = o["circle"]["c"]
			v.obstacles.append({"id": String(o["id"]), "circle": true, "points": PackedVector2Array(),
				"c": Vector2(c[0], c[1]), "r": float(o["circle"]["r"])})
		else:
			v.obstacles.append({"id": String(o["id"]), "circle": false, "points": _pts(o["polygon"]),
				"c": Vector2.ZERO, "r": 0.0})
	v._boxes()
	return v


static func _pts(a: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for q in a:
		p.append(Vector2(q[0], q[1]))
	return p


func _boxes() -> void:
	_land_boxes.clear()
	for l in land:
		var pts: PackedVector2Array = l["points"]
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		_land_boxes.append(r)


func is_empty() -> bool:
	return land.is_empty() and obstacles.is_empty()


## Bounding box of land polygon i.
func land_box(i: int) -> Rect2:
	return _land_boxes[i]


## Signed distance to land polygon i: positive inside (land), negative in the water.
func land_distance(i: int, p: Vector2) -> float:
	var pts: PackedVector2Array = land[i]["points"]
	return signed_distance(pts, p)


## Index of the land polygon containing p, -1 in the water.
func land_at(p: Vector2) -> int:
	for i in land.size():
		if _land_boxes[i].has_point(p) and Geometry2D.is_point_in_polygon(p, land[i]["points"]):
			return i
	return -1


## Index of the obstacle containing p, -1 outside every obstacle.
func obstacle_at(p: Vector2) -> int:
	for i in obstacles.size():
		var o: Dictionary = obstacles[i]
		if o["circle"]:
			if p.distance_to(o["c"]) <= o["r"]:
				return i
		elif Geometry2D.is_point_in_polygon(p, o["points"]):
			return i
	return -1


## Signed distance to a simple polygon: positive inside.
static func signed_distance(pts: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	var n := pts.size()
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return d if Geometry2D.is_point_in_polygon(p, pts) else -d
