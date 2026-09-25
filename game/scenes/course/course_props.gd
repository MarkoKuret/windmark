class_name CourseProps
extends RefCounted
## Meshes of the course objects (courses.md §2), vertex-coloured, in the local frame of their node: up +Y, and
## for boats the bow along -Z and port along -X (body (x fwd, y port, z up) -> local (-y, z, -x)).
##   buoys: `inflatable` (a race cylinder of the mark's radius), `large` (a taller one), `tetra` (a pyramid)
##   committee and mark boats: the hull on the 17-point outline of courses.md §2 (`outline()`)
##   flags (race.md §3.2, hud.md §9.1): the class flag, P, I, Z, U, black, X, orange and blue

const YELLOW := Color(0.80, 0.52, 0.02)
const ORANGE := Color(0.85, 0.22, 0.02)
const WHITE := Color(0.78, 0.78, 0.76)
const HULL_WHITE := Color(0.70, 0.71, 0.70)
const NAVY := Color(0.01, 0.025, 0.08)
const DECK := Color(0.42, 0.42, 0.40)
const GLASS := Color(0.01, 0.012, 0.018)
const RED := Color(0.55, 0.02, 0.02)
const BLACK := Color(0.012, 0.012, 0.012)
const FLAG_YELLOW := Color(0.85, 0.62, 0.02)
const FLAG_BLUE := Color(0.01, 0.07, 0.40)
const FLAG_RED := Color(0.62, 0.02, 0.02)
const FLAG_WHITE := Color(0.80, 0.80, 0.78)
const FLAG_GREEN := Color(0.02, 0.30, 0.08)

## courses.md §2 default outline stations: body x / L and half-breadth / B
const OUT_X := [-0.5, -0.35, -0.2, 0.0, 0.1, 0.25, 0.37, 0.45]
const OUT_F := [0.4, 0.451, 0.484, 0.5, 0.4724054, 0.3564127, 0.2092049, 0.0863752]

## flag size (m) and the kinds
const FLAG_W := 1.1
const FLAG_H := 0.75
enum Flag { CLASS, P, I, Z, U, BLACK, X, ORANGE, BLUE }


## courses.md §2: the 17 body-frame vertices (x forward, y port), counter-clockwise.
static func outline(length: float, beam: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 8:
		p.append(Vector2(OUT_X[i] * length, -(OUT_F[i] * beam)))
	p.append(Vector2(0.5 * length, 0.0))
	for i in range(7, -1, -1):
		p.append(Vector2(OUT_X[i] * length, OUT_F[i] * beam))
	return p


static func _local(x: float, y: float, z: float) -> Vector3:
	return Vector3(-y, z, -x)


# ---- buoys ----------------------------------------------------------------------------------------------------

## An inflatable race cylinder: radius r, `h` above the water line, 0.4 m below, rounded shoulders, with a
## darker band where the tether ring sits.
static func buoy(r: float, h: float, col: Color) -> ArrayMesh:
	var m := ColorMesh.new()
	var sides := 20
	var shoulder := minf(0.18 * r, 0.25)
	# profile (radius, height) from the bottom up
	var prof := [[r * 0.8, -0.45], [r, -0.25], [r, h - shoulder], [r - shoulder * 0.45, h - shoulder * 0.25],
		[r - shoulder, h], [0.0, h]]
	var base := m.verts.size()
	for j in prof.size():
		for k in sides + 1:
			var a := TAU * k / sides
			var d := Vector3(cos(a), 0.0, sin(a))
			var pr: Array = prof[j]
			var n := d if j < 3 else (d + Vector3.UP * (1.5 if j > 3 else 0.7)).normalized()
			if j == prof.size() - 1:
				n = Vector3.UP
			var c := col
			if pr[1] < 0.05:
				c = col * 0.45
			m.vertex(d * pr[0] + Vector3(0, pr[1], 0), n, c)
	for j in prof.size() - 1:
		for k in sides:
			var a := base + j * (sides + 1) + k
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			var out := m.verts[a] + m.verts[d] - Vector3(0, m.verts[a].y + m.verts[d].y, 0) + Vector3(0, 0.001, 0)
			if j == prof.size() - 2:
				out = Vector3.UP
			m.tri(a, b, d, out)
			m.tri(a, d, c, out)
	# lifting handle on top
	m.box(Transform3D(Basis.IDENTITY, Vector3(0, h + 0.06, 0)), Vector3(0.5 * r, 0.1, 0.06), col * 0.6)
	return m.mesh()


## The small pin-end pyramid (`tetra`): a triangular inflatable pyramid on the circle of radius r.
static func tetra(r: float, col: Color) -> ArrayMesh:
	var m := ColorMesh.new()
	var h := 1.45 * r + 0.3
	var apex := Vector3(0, h, 0)
	var base_pts := []
	for k in 3:
		var a := TAU * k / 3.0 + PI / 6.0
		base_pts.append(Vector3(cos(a) * r, -0.3, sin(a) * r))
	for k in 3:
		var a: Vector3 = base_pts[k]
		var b: Vector3 = base_pts[(k + 1) % 3]
		var mid := (a + b) * 0.5
		var low_a := a.lerp(apex, 0.0)
		m.flat_tri(low_a, b, apex, col, Vector3(mid.x, 0.3, mid.z))
	m.flat_tri(base_pts[0], base_pts[1], base_pts[2], col * 0.4, Vector3.DOWN)
	return m.mesh()


# ---- boats ----------------------------------------------------------------------------------------------------

## A committee boat (a motor cruiser of length x beam) or a small mark boat (`small`), on the outline.
static func committee_boat(length: float, beam: float, small := false) -> ArrayMesh:
	var m := ColorMesh.new()
	var ol := outline(length, beam)
	var fb := 0.85 if small else 1.35  # freeboard at the deck edge
	# rings (height, scale, colour) from the keel up; the sheer rises toward the bow
	var rings := [[-0.55 if small else -0.8, 0.5, RED], [-0.05, 0.9, RED], [0.02, 0.92, NAVY], [0.28, 0.95, NAVY],
		[0.3, 0.955, HULL_WHITE], [fb, 1.0, HULL_WHITE]]
	var n := ol.size()
	for j in rings.size() - 1:
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		for k in n:
			var a := ol[k]
			var b := ol[(k + 1) % n]
			var pa0 := _local(a.x * r0[1], a.y * r0[1], r0[0])
			var pb0 := _local(b.x * r0[1], b.y * r0[1], r0[0])
			var ya1: float = r1[0] + (_sheer(a.x, length, fb) if j + 1 == rings.size() - 1 else 0.0)
			var yb1: float = r1[0] + (_sheer(b.x, length, fb) if j + 1 == rings.size() - 1 else 0.0)
			var pa1 := _local(a.x * r1[1], a.y * r1[1], ya1)
			var pb1 := _local(b.x * r1[1], b.y * r1[1], yb1)
			var mid := (a + b) * 0.5
			var out := _local(mid.x, mid.y, 0.0)
			m.quad(pa0, pb0, pb1, pa1, r1[2] if j >= 3 else r0[2], out)
	# keel bottom and the deck (fans from the middle; the outline is convex)
	var keel: Array = rings[0]
	var ck := m.vertex(_local(0, 0, keel[0] - 0.1), Vector3.DOWN, RED)
	var ring := []
	for k in n:
		ring.append(m.vertex(_local(ol[k].x * keel[1], ol[k].y * keel[1], keel[0]), Vector3.DOWN, RED))
	for k in n:
		m.tri(ck, ring[k], ring[(k + 1) % n], Vector3.DOWN)
	var cd := m.vertex(_local(0, 0, fb + _sheer(0.0, length, fb)), Vector3.UP, DECK)
	ring = []
	for k in n:
		ring.append(m.vertex(_local(ol[k].x, ol[k].y, fb + _sheer(ol[k].x, length, fb)), Vector3.UP, DECK))
	for k in n:
		m.tri(cd, ring[k], ring[(k + 1) % n], Vector3.UP)
	# a rubbing strake along the sheer
	for k in n:
		var a := ol[k]
		var b := ol[(k + 1) % n]
		var ya := fb + _sheer(a.x, length, fb)
		var yb := fb + _sheer(b.x, length, fb)
		var out := _local((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
		m.quad(_local(a.x * 1.01, a.y * 1.01, ya - 0.12), _local(b.x * 1.01, b.y * 1.01, yb - 0.12),
			_local(b.x * 1.01, b.y * 1.01, yb + 0.02), _local(a.x * 1.01, a.y * 1.01, ya + 0.02), NAVY, out)
	var deck_y := fb + _sheer(0.0, length, fb)
	if small:
		# centre console with a windscreen, and the flag staff at the stern
		m.box(Transform3D(Basis.IDENTITY, _local(0.0, 0.0, deck_y + 0.5)), Vector3(0.8, 1.0, 0.7), HULL_WHITE)
		m.box(Transform3D(Basis.IDENTITY, _local(0.3, 0.0, deck_y + 1.15)), Vector3(0.85, 0.3, 0.06), GLASS)
		m.cylinder(_local(-0.42 * length, 0.0, deck_y), 0.03, 0.025, 3.2, 6, WHITE)
	else:
		# deckhouse with windows, a flybridge rail, the signal mast with its yard
		var hx := -0.08 * length
		var hl := 0.34 * length
		var hw := 0.72 * beam
		m.box(Transform3D(Basis.IDENTITY, _local(hx, 0.0, deck_y + 1.0)), Vector3(hw, 2.0, hl), HULL_WHITE)
		m.box(Transform3D(Basis.IDENTITY, _local(hx, 0.0, deck_y + 1.3)), Vector3(hw + 0.02, 0.6, hl + 0.02), GLASS)
		m.box(Transform3D(Basis.IDENTITY, _local(hx + 0.5 * hl - 0.05, 0.0, deck_y + 1.4)),
			Vector3(hw * 0.9, 0.7, 0.12), GLASS)
		m.box(Transform3D(Basis.IDENTITY, _local(hx, 0.0, deck_y + 2.03)), Vector3(hw + 0.1, 0.06, hl + 0.1), WHITE)
		for s in [-1.0, 1.0]:
			m.box(Transform3D(Basis.IDENTITY, _local(hx - 0.1 * hl, s * 0.5 * hw, deck_y + 2.5)),
				Vector3(0.04, 0.9, 0.5 * hl), WHITE)
		var mast := signal_mast(length)
		m.cylinder(mast, 0.07, 0.05, 5.2, 8, WHITE)
		m.box(Transform3D(Basis.IDENTITY, mast + Vector3(0, 4.6, 0)), Vector3(3.0, 0.07, 0.07), WHITE)
		# stern staff for the orange flag
		m.cylinder(_local(-0.47 * length, 0.0, deck_y), 0.03, 0.025, 2.4, 6, WHITE)
	return m.mesh()


## The sheer: the deck edge rises toward the bow.
static func _sheer(x: float, length: float, fb: float) -> float:
	return 0.35 * fb * clampf((x / length) + 0.1, 0.0, 0.6) / 0.6


## The foot of the committee boat's signal mast on the deckhouse roof (local); its yard is 4.6 m above.
static func signal_mast(length: float) -> Vector3:
	return _local(-0.13 * length, 0.0, 1.35 + _sheer(0.0, length, 1.35) + 2.06)


## Top of the mark boat's flag staff (local).
static func staff_top(length: float, small: bool) -> Vector3:
	var fb := 0.85 if small else 1.35
	return _local(-(0.42 if small else 0.47) * length, 0.0, fb + _sheer(0.0, length, fb) + (3.2 if small else 2.4))


# ---- flags ----------------------------------------------------------------------------------------------------

## A flag in its own frame: the hoist along +Y from 0 to FLAG_H at x = 0, the fly toward +X.
static func flag(kind: int) -> ArrayMesh:
	var m := ColorMesh.new()
	var w := FLAG_W
	var h := FLAG_H
	var q := func(x0: float, y0: float, x1: float, y1: float, c: Color, lift := 0.0) -> void:
		m.card(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0), c, lift)
	match kind:
		Flag.P:
			q.call(0, 0, w, h, FLAG_BLUE)
			q.call(w / 3.0, h / 3.0, 2.0 * w / 3.0, 2.0 * h / 3.0, FLAG_WHITE, 0.004)
		Flag.I:
			q.call(0, 0, w, h, FLAG_YELLOW)
			var c := Vector3(w * 0.5, h * 0.5, 0)
			var r := 0.3 * h
			for k in 20:
				var a0 := TAU * k / 20.0
				var a1 := TAU * (k + 1) / 20.0
				m.card_tri(c, c + Vector3(cos(a0), sin(a0), 0) * r, c + Vector3(cos(a1), sin(a1), 0) * r, BLACK, 0.004)
		Flag.Z:
			var c := Vector3(w * 0.5, h * 0.5, 0)
			m.card_tri(Vector3(0, h, 0), Vector3(w, h, 0), c, FLAG_YELLOW)
			m.card_tri(Vector3(w, h, 0), Vector3(w, 0, 0), c, FLAG_BLUE)
			m.card_tri(Vector3(w, 0, 0), Vector3(0, 0, 0), c, FLAG_RED)
			m.card_tri(Vector3(0, 0, 0), Vector3(0, h, 0), c, BLACK)
		Flag.U:
			q.call(0, h * 0.5, w * 0.5, h, FLAG_RED)
			q.call(w * 0.5, h * 0.5, w, h, FLAG_WHITE)
			q.call(0, 0, w * 0.5, h * 0.5, FLAG_WHITE)
			q.call(w * 0.5, 0, w, h * 0.5, FLAG_RED)
		Flag.BLACK:
			q.call(0, 0, w, h, BLACK)
		Flag.X:
			q.call(0, 0, w, h, FLAG_WHITE)
			q.call(w * 0.5 - 0.1 * h, 0, w * 0.5 + 0.1 * h, h, FLAG_BLUE, 0.004)
			q.call(0, h * 0.4, w, h * 0.6, FLAG_BLUE, 0.004)
		Flag.ORANGE:
			q.call(0, 0, w, h, ORANGE)
		Flag.BLUE:
			q.call(0, 0, w, h, FLAG_BLUE)
		_:
			# the class flag: green with a white band
			q.call(0, 0, w, h, FLAG_GREEN)
			q.call(0, h * 0.38, w, h * 0.62, FLAG_WHITE, 0.004)
	return m.mesh()


# ---- guidance (hud.md §7) -------------------------------------------------------------------------------------

## The rounding arrow: a flat arc of radius r around the mark, 200 degrees, anticlockwise seen from above
## (leave to port) with its head at the end; mirror it (scale x -1) for starboard. Starts at local -Z.
static func rounding_arrow(r: float, col: Color) -> ArrayMesh:
	var m := ColorMesh.new()
	var w := 0.55
	var span := deg_to_rad(200.0)
	var steps := 24
	# scene from above: angle a measured from -Z toward -X is anticlockwise (east +X, north -Z)
	var pt := func(a: float, rr: float) -> Vector3: return Vector3(-sin(a) * rr, 0.0, -cos(a) * rr)
	for k in steps:
		var a0 := span * k / steps
		var a1 := span * (k + 1) / steps
		m.quad(pt.call(a0, r - w * 0.5), pt.call(a1, r - w * 0.5), pt.call(a1, r + w * 0.5), pt.call(a0, r + w * 0.5),
			col, Vector3.UP)
	var tip: Vector3 = pt.call(span + 0.28, r)
	m.flat_tri(pt.call(span, r - w * 1.6), pt.call(span, r + w * 1.6), tip, col, Vector3.UP)
	return m.mesh()


## The next-mark marker (hud.md §7, far away): a downward chevron, 1 m tall, tip at the origin.
static func marker(col: Color) -> ArrayMesh:
	var m := ColorMesh.new()
	var a := Vector3(-0.5, 1.0, 0)
	var b := Vector3(0.5, 1.0, 0)
	var c := Vector3(0, 0, 0)
	m.card_tri(a, b, c, col)
	var a2 := Vector3(0, 1.0, -0.5)
	var b2 := Vector3(0, 1.0, 0.5)
	m.card_tri(a2, b2, c, col * 0.8)
	return m.mesh()
