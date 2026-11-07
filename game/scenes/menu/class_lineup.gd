class_name ClassLineup
extends Control
## The fleet line-up on the Boat step (menus.md §1.1): every class as a small profile silhouette (hull, mast, main
## and headsail from its class file) side by side at one scale, smallest to largest in the picker's order, on a
## faint waterline, the chosen class in navy and the others muted. One glance says how big the chosen boat is
## next to the rest and which of the classes it is. A click on a silhouette picks that class.

signal picked(class_id: String)

## the strip's height (px) and the gap between boats (m of water, scaled with them)
const HEIGHT := 76.0
const GAP_M := 2.4
## the colours: the chosen class, the others, the waterline
const CHOSEN := MenuTheme.NAVY
const OTHER := Color("b9b3a3")
const WATER := Color("d8d1bf")

var classes: Array = []
var chosen := ""
## the silhouettes laid out by _layout(): {id, pts: [PackedVector2Array], box: Rect2} in local px
var _boats: Array = []


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## The classes to line up (ids, picker order) and the chosen one.
func set_classes(ids: Array, chosen_id: String) -> void:
	classes = ids.duplicate()
	chosen = chosen_id
	queue_redraw()


func set_chosen(id: String) -> void:
	if id == chosen:
		return
	chosen = id
	queue_redraw()


## A class's profile in metres, x forward from the mast step's origin (the class file's hull x), y up from the
## waterline: the hull (deck line with the sheer, the topsides to the waterline), the mast, the main and the
## headsail as triangles. Each shape a closed polygon.
static func profile(id: String) -> Array:
	var d := MenuData.class_doc(id)
	if d.is_empty():
		return []
	var hull: Dictionary = d.get("hull", {})
	var rig: Dictionary = d.get("rig", {})
	var fb: Dictionary = hull.get("freeboard", {})
	var loa := float(hull.get("loa", 8.0))
	var stem := float(hull.get("stem_x", loa * 0.5))
	var transom := float(hull.get("transom_x", -loa * 0.5))
	var f_bow := float(fb.get("bow", 0.12 * loa))
	var f_mid := float(fb.get("mid", 0.75 * f_bow))
	var f_stern := float(fb.get("stern", 0.85 * f_bow))
	var mast_x := float(rig.get("mast_x", 0.1 * loa))
	var mast_h := float(rig.get("mast_height", 1.4 * loa))
	var boom := float(rig.get("boom_height", 0.2 * f_mid + 1.0))
	var p := float(rig.get("P", mast_h - boom - 0.3))
	var e := float(rig.get("E", 0.4 * loa))
	var i_h := float(rig.get("I", 0.85 * mast_h))
	var j := float(rig.get("J", 0.3 * loa))
	var sprit := float(rig.get("bowsprit", 0.0))
	# the hull: the stem from the waterline up to the deck, the sheer (a dip at midships), the transom down
	var hull_pts := PackedVector2Array([
		Vector2(stem, 0.0), Vector2(stem, f_bow), Vector2(0.5 * (stem + mast_x), 0.5 * (f_bow + f_mid)),
		Vector2(0.5 * (stem + transom), f_mid), Vector2(0.5 * (transom + mast_x), 0.5 * (f_stern + f_mid)),
		Vector2(transom, f_stern), Vector2(transom, 0.0)])
	var out := [hull_pts]
	# the mast, a thin quad
	var w := maxf(0.012 * mast_h, 0.12)
	out.append(PackedVector2Array([Vector2(mast_x - w, f_mid), Vector2(mast_x + w, f_mid),
		Vector2(mast_x + w, mast_h), Vector2(mast_x - w, mast_h)]))
	# the main: tack at the gooseneck, head up the mast, clew out along the boom; a little roach on the leech
	var tack := Vector2(mast_x, f_mid + boom)
	var head := Vector2(mast_x, f_mid + boom + p)
	var clew := Vector2(mast_x - e, f_mid + boom)
	var roach := 0.5 * (head + clew) + Vector2(-0.08 * e, 0.0)
	out.append(PackedVector2Array([tack, head, roach, clew]))
	# the headsail: head up the mast at I, tack at the stem (the sprit stays bare), clew just aft of the mast
	var j_tack := Vector2(mast_x + j, f_bow)
	var j_head := Vector2(mast_x, f_mid + i_h)
	var j_clew := Vector2(mast_x - 0.25 * j, f_mid + 0.08 * i_h)
	out.append(PackedVector2Array([j_tack, j_head, j_clew]))
	if sprit > 0.0:
		out.append(PackedVector2Array([Vector2(stem, f_bow - 0.1), Vector2(stem + sprit, f_bow - 0.1),
			Vector2(stem + sprit, f_bow + 0.02), Vector2(stem, f_bow + 0.02)]))
	return out


## The silhouettes placed in the strip: one scale for all, the row centred, the hulls on the waterline near the
## bottom. Returns the px per metre.
func _layout() -> float:
	_boats.clear()
	if classes.is_empty():
		return 0.0
	var profiles := {}
	var total := 0.0
	var tallest := 0.0
	for id in classes:
		var pr := profile(id)
		if pr.is_empty():
			continue
		profiles[id] = pr
		var box := _bounds(pr)
		total += box.size.x
		tallest = maxf(tallest, box.end.y)
	if profiles.is_empty():
		return 0.0
	var pad := 6.0
	var w := size.x - 2.0 * pad
	var h := size.y - 2.0 * pad
	var gaps := GAP_M * (profiles.size() - 1)
	var k := minf(h / maxf(tallest, 1.0), w / maxf(total + gaps, 1.0))
	var x := 0.5 * size.x - 0.5 * k * (total + gaps)
	var water := size.y - pad - 1.0
	for id in classes:
		if not profiles.has(id):
			continue
		var pr: Array = profiles[id]
		var box := _bounds(pr)
		var shapes := []
		for poly in pr:
			var pts := PackedVector2Array()
			for q in poly:
				pts.append(Vector2(x + k * (q.x - box.position.x), water - k * q.y))
			shapes.append(pts)
		_boats.append({"id": id, "pts": shapes,
			"box": Rect2(x, water - k * box.end.y, k * box.size.x, k * box.end.y)})
		x += k * (box.size.x + GAP_M)
	return k


static func _bounds(polys: Array) -> Rect2:
	var r := Rect2(polys[0][0], Vector2.ZERO)
	for poly in polys:
		for q in poly:
			r = r.expand(q)
	return r


func _draw() -> void:
	_layout()
	var pad := 6.0
	draw_line(Vector2(pad, size.y - pad), Vector2(size.x - pad, size.y - pad), WATER, 1.0, true)
	for b in _boats:
		var col: Color = CHOSEN if b["id"] == chosen else OTHER
		for pts in b["pts"]:
			draw_colored_polygon(pts, col)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for b in _boats:
			var box: Rect2 = b["box"]
			if box.grow(4.0).has_point(ev.position):
				accept_event()
				picked.emit(b["id"])
				return


## The offline previews (tests/menu_preview_dump.gd): the silhouettes in global px.
func preview_polys() -> Array:
	_layout()
	var out := []
	var at := get_global_rect().position
	var pad := 6.0
	var y := at.y + size.y - pad
	out.append({"k": "poly", "pts": [[at.x + pad, y], [at.x + size.x - pad, y], [at.x + size.x - pad, y + 1],
		[at.x + pad, y + 1]], "col": [WATER.r, WATER.g, WATER.b, 1.0]})
	for b in _boats:
		var c: Color = CHOSEN if b["id"] == chosen else OTHER
		for pts in b["pts"]:
			var l := []
			for q in pts:
				l.append([at.x + q.x, at.y + q.y])
			out.append({"k": "poly", "pts": l, "col": [c.r, c.g, c.b, c.a]})
	return out
