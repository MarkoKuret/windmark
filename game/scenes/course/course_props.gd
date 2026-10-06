class_name CourseProps
extends RefCounted
## Meshes of the course objects (courses.md §2), vertex-coloured, in the local frame of their node: up +Y, and
## for boats the bow along -Z and port along -X (body (x fwd, y port, z up) -> local (-y, z, -x)).
##   buoys: `inflatable` (a race cylinder of the mark's radius), `large` (a taller one), `tetra` (a pyramid)
##   committee and mark boats: a flybridge cruiser and a RIB inside the 17-point outline of courses.md §2
##   (`outline()`)
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
const TEAK := Color(0.30, 0.15, 0.06)
const STEEL := Color(0.55, 0.56, 0.58)
const TUBE_GREY := Color(0.06, 0.065, 0.07)

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

## Committee boat layout (body x / L): the deckhouse from HOUSE_X0 to HOUSE_X1, the signal mast at MAST_X on the
## flybridge floor; heights in m above the deck edge at the house (the sheer is flat aft of -0.1 L).
const HOUSE_X0 := -0.30
const HOUSE_X1 := 0.12
const HOUSE_H := 2.05
const FLY_FLOOR := 0.02
const MAST_X := -0.24
const STAFF_X := -0.465
const RIB_STAFF_X := -0.40
## freeboard at the deck edge and the keel depth: committee boat, mark boat (a RIB's hard hull)
const FB := 1.35
const KEEL := -0.8
const RIB_FB := 0.45
const RIB_KEEL := -0.35
const RIB_TUBE := 0.27


## A committee boat (a flybridge motor cruiser of length x beam) or a small mark boat (`small`, a RIB), inside
## the outline: shaped hull with antifouling, boot stripe and rubbing strake, deck, rails and fittings.
static func committee_boat(length: float, beam: float, small := false) -> ArrayMesh:
	var m := ColorMesh.new()
	if small:
		_rib(m, length, beam)
	else:
		_cruiser(m, length, beam)
	return m.mesh()


static func _cruiser(m: ColorMesh, length: float, beam: float) -> void:
	var x_t := -0.47 * length
	_hull(m, length, beam, FB, KEEL, x_t)
	# rubbing strake along the sheer, round the stem
	var strake := []
	for s in [-1.0, 1.0]:
		var side := []
		for i in 25:
			var x := lerpf(x_t, 0.49 * length, i / 24.0)
			var hb := beam * _half_breadth(x / length)
			side.append(_local(x, s * (hb + 0.03), _deck(x, length, FB) - 0.1))
		if s > 0.0:
			side.reverse()
		strake.append_array(side)
	_tube(m, strake, _radii(strake.size(), 0.06), 6, NAVY)
	# swim platform
	m.box(Transform3D(Basis.IDENTITY, _local(-0.485 * length, 0.0, 0.32)), Vector3(0.8 * beam, 0.08, 0.03 * length),
		TEAK)
	# deckhouse: windows all round, the windscreen raked, an overhanging roof
	var x0 := HOUSE_X0 * length
	var x1 := HOUSE_X1 * length
	var w := beam * _half_breadth(HOUSE_X1) - 0.6
	var base := FB
	_loft(m, _footprint(x0, x1, w), x0, x1, [
		[base - 0.2, 0.0, 0.0, HULL_WHITE], [base + 1.0, 0.05, 0.2, GLASS], [base + 1.75, 0.1, 0.95, HULL_WHITE],
		[base + 1.95, 0.12, 1.05, HULL_WHITE], [base + 1.95, -0.06, 0.92, WHITE], [base + HOUSE_H, -0.06, 0.92, WHITE]],
		WHITE)
	# window mullions on the sides
	for s in [-1.0, 1.0]:
		for f in [0.3, 0.62]:
			var x: float = lerpf(x0, x1, f)
			m.box(Transform3D(Basis.IDENTITY, _local(x, s * (w - 0.06), base + 1.38)), Vector3(0.03, 0.78, 0.08),
				HULL_WHITE)
	# flybridge: a coaming round the aft part of the roof, the helm console, a bench, the radar on the mast
	var roof := base + HOUSE_H
	var f0 := x0 + 0.15
	var f1 := lerpf(x0, x1, 0.72)
	var fw := w - 0.1
	_loft(m, _footprint(f0, f1, fw), f0, f1, [
		[roof - 0.02, 0.0, 0.0, HULL_WHITE], [roof + 0.6, 0.0, 0.0, WHITE], [roof + 0.6, 0.08, 0.08, HULL_WHITE],
		[roof + FLY_FLOOR, 0.08, 0.08, DECK]], DECK)
	var cx := f1 - 0.75
	m.box(Transform3D(Basis.IDENTITY, _local(cx, 0.0, roof + 0.5)), Vector3(1.3, 1.0, 0.55), WHITE)
	m.box(Transform3D(Basis(Vector3.RIGHT, 0.5), _local(cx + 0.18, 0.0, roof + 1.12)), Vector3(1.2, 0.35, 0.03),
		GLASS)
	m.box(Transform3D(Basis.IDENTITY, _local(cx - 1.1, 0.0, roof + 0.25)), Vector3(1.6, 0.5, 0.55), NAVY)
	var mast := signal_mast(length)
	m.cylinder(mast, 0.07, 0.05, 5.2, 8, WHITE)
	m.box(Transform3D(Basis.IDENTITY, mast + Vector3(0, 4.6, 0)), Vector3(3.0, 0.07, 0.07), WHITE)
	m.box(Transform3D(Basis.IDENTITY, mast + Vector3(0, 3.0, -0.3)), Vector3(0.12, 0.06, 0.6), WHITE)
	m.cylinder(mast + Vector3(0, 3.03, -0.55), 0.3, 0.28, 0.22, 12, WHITE)
	for s in [-1.0, 1.0]:
		m.cylinder(_local(f0 + 0.2, s * (fw - 0.15), roof + 0.6), 0.025, 0.012, 2.6, 5, WHITE)
	# rails on stanchions from the cockpit to a bow pulpit
	var rail := []
	for s in [-1.0, 1.0]:
		var side := []
		for i in 14:
			var x := lerpf(-0.45 * length, 0.43 * length, i / 13.0)
			var hb := beam * _half_breadth(x / length) - 0.12
			var foot := _local(x, s * hb, _deck(x, length, FB))
			m.cylinder(foot, 0.022, 0.02, 0.7, 5, STEEL)
			side.append(foot + Vector3(0, 0.7, 0))
		if s > 0.0:
			side.reverse()
		rail.append_array(side)
		if s < 0.0:
			rail.append(_local(0.47 * length, 0.0, _deck(0.47 * length, length, FB) + 0.75))
	_tube(m, rail, _radii(rail.size(), 0.025), 5, STEEL)
	# anchor on the bow roller, a foredeck hatch
	var bow := _local(0.46 * length, 0.0, _deck(0.46 * length, length, FB) + 0.08)
	m.box(Transform3D(Basis.IDENTITY, bow), Vector3(0.22, 0.14, 0.7), STEEL)
	m.box(Transform3D(Basis.IDENTITY, _local(0.28 * length, 0.0, _deck(0.28 * length, length, FB) + 0.1)),
		Vector3(0.8, 0.12, 0.8), HULL_WHITE)
	# fenders over the side
	for s in [-1.0, 1.0]:
		for f in [-0.36, -0.12, 0.12]:
			var x: float = f * length
			var hb := beam * _half_breadth(x / length) + 0.14
			m.cylinder(_local(x, s * hb, 0.3), 0.13, 0.13, 0.65, 8, NAVY)
	# the stern staff for the orange flag
	m.cylinder(_local(STAFF_X * length, 0.0, _deck(STAFF_X * length, length, FB)), 0.03, 0.025, 2.4, 6, WHITE)


## A mark boat: a RIB, tubes round a hard hull, a centre console, an outboard and the flag staff.
static func _rib(m: ColorMesh, length: float, beam: float) -> void:
	var x_t := -0.47 * length
	var hull_beam := beam - 2.0 * RIB_TUBE * 0.6
	_hull(m, length, hull_beam, RIB_FB, RIB_KEEL, x_t)
	var tube := []
	var radii := PackedFloat32Array()
	for s in [-1.0, 1.0]:
		var side := []
		var rr := []
		side.append(_local(-0.53 * length, s * (0.5 * hull_beam * OUT_F[0] * 2.0 - 0.05), RIB_FB + 0.12))
		rr.append(RIB_TUBE * 0.55)
		for i in 15:
			var x := lerpf(x_t, 0.4 * length, i / 14.0)
			var y := beam * _half_breadth(x / length) - RIB_TUBE
			side.append(_local(x, s * maxf(y, 0.12), _deck(x, length, RIB_FB) + 0.1))
			rr.append(RIB_TUBE * lerpf(1.0, 0.8, clampf((x / length - 0.2) / 0.2, 0.0, 1.0)))
		if s > 0.0:
			side.reverse()
			rr.reverse()
		tube.append_array(side)
		for r in rr:
			radii.append(r)
		if s < 0.0:
			tube.append(_local(0.47 * length, 0.0, _deck(0.47 * length, length, RIB_FB) + 0.18))
			radii.append(RIB_TUBE * 0.75)
	_tube(m, tube, radii, 10, TUBE_GREY)
	var d := _deck(0.0, length, RIB_FB)
	# centre console with a raked screen, a seat behind it
	m.box(Transform3D(Basis.IDENTITY, _local(0.05 * length, 0.0, d + 0.5)), Vector3(0.8, 1.0, 0.7), WHITE)
	m.box(Transform3D(Basis(Vector3.RIGHT, 0.45), _local(0.05 * length + 0.4, 0.0, d + 1.15)),
		Vector3(0.8, 0.35, 0.03), GLASS)
	m.box(Transform3D(Basis.IDENTITY, _local(-0.14 * length, 0.0, d + 0.3)), Vector3(0.7, 0.6, 0.5), NAVY)
	# outboard on the transom
	m.box(Transform3D(Basis.IDENTITY, _local(x_t - 0.25, 0.0, 0.0)), Vector3(0.22, 1.0, 0.18), BLACK)
	m.box(Transform3D(Basis.IDENTITY, _local(x_t - 0.28, 0.0, RIB_FB + 0.4)), Vector3(0.42, 0.55, 0.5), BLACK)
	m.cylinder(_local(RIB_STAFF_X * length, 0.0, d), 0.03, 0.025, 3.2, 6, WHITE)


## The deck edge height at body x (freeboard plus sheer).
static func _deck(x: float, length: float, fb: float) -> float:
	return fb + _sheer(x, length, fb)


## The sheer: the deck edge rises toward the bow.
static func _sheer(x: float, length: float, fb: float) -> float:
	return 0.35 * fb * clampf((x / length) + 0.1, 0.0, 0.6) / 0.6


## Half-breadth / B of the default outline at body x / L (linear between its stations, 0 at the stem).
static func _half_breadth(xr: float) -> float:
	if xr <= OUT_X[0]:
		return OUT_F[0]
	for i in 7:
		if xr <= OUT_X[i + 1]:
			return lerpf(OUT_F[i], OUT_F[i + 1], (xr - OUT_X[i]) / (OUT_X[i + 1] - OUT_X[i]))
	return lerpf(OUT_F[7], 0.0, clampf((xr - OUT_X[7]) / (0.5 - OUT_X[7]), 0.0, 1.0))


## A hull section at body x: the port points [y, z] from the keel to the deck edge (starboard mirrors y). A deep V
## aft that fines into a raked stem with the forefoot rising; the chine, then flared topsides; the extra points at
## z = 0 and 0.2 bound the boot stripe.
static func _section(x: float, length: float, beam: float, fb: float, keel: float) -> Array:
	var xr := x / length
	var hb := beam * _half_breadth(xr)
	var d := _deck(x, length, fb)
	var fwd := clampf((xr - 0.1) / 0.4, 0.0, 1.0)
	var k := lerpf(keel, -0.04, fwd * fwd) if xr > 0.1 else lerpf(0.75 * keel, keel, clampf((xr + 0.5) / 0.4, 0.0, 1.0))
	var zc := lerpf(0.4 * keel, -0.03, fwd)
	var yc := hb * lerpf(0.9, 0.5, fwd)
	var pts := [[0.0, k], [0.55 * yc, lerpf(k, zc, 0.7)], [yc, zc]]
	for z in [0.0, 0.2]:
		var u := clampf((z - zc) / (d - zc), 0.0, 1.0)
		pts.append([yc + (hb - yc) * (1.0 - (1.0 - u) * (1.0 - u)), z])
	pts.append([hb, d])
	return pts


## The hull from the transom at body x_t to the stem: smooth along its length, creased at the chine and the colour
## bands (antifouling, boot stripe, topsides); the flat transom and a cambered deck close it.
static func _hull(m: ColorMesh, length: float, beam: float, fb: float, keel: float, x_t: float) -> void:
	var ns := 28
	var secs := []
	for i in ns + 1:
		var x := lerpf(x_t, 0.5 * length, float(i) / ns)
		var sec := _section(x, length, beam, fb, keel)
		# the raked stem: toward the bow the lower points draw aft, the deck edge stays
		var f := clampf((x / length - 0.25) / 0.25, 0.0, 1.0)
		var k: float = sec[0][1]
		var d: float = sec[-1][1]
		var pts := []
		for p in sec:
			pts.append(Vector3(x - 0.09 * length * f * f * (d - float(p[1])) / (d - k), p[0], p[1]))
		secs.append(pts)
	var cols := [RED, RED, RED, NAVY, HULL_WHITE]
	for s in [-1.0, 1.0]:
		var flip := Vector3(1.0, s, 1.0)
		for j in cols.size():
			var base := m.verts.size()
			for i in ns + 1:
				for e in [j, j + 1]:
					var p: Vector3 = secs[i][e] * flip
					var t_long: Vector3 = (secs[mini(i + 1, ns)][e] - secs[maxi(i - 1, 0)][e]) * flip
					var t_sec: Vector3 = (secs[i][j + 1] - secs[i][j]) * flip
					var n := t_long.cross(t_sec).normalized()
					if n.dot(p - Vector3(p.x, 0.0, 0.3)) < 0.0:
						n = -n
					m.vertex(_local(p.x, p.y, p.z), _local(n.x, n.y, n.z), cols[j])
			for i in ns:
				var a := base + 2 * i
				var out := m.normals[a] + m.normals[a + 3]
				m.tri(a, a + 2, a + 3, out)
				m.tri(a, a + 3, a + 1, out)
	# transom
	var aft := _local(-1.0, 0.0, 0.0)
	var sec: Array = secs[0]
	for j in cols.size():
		var p0: Vector3 = sec[j]
		var p1: Vector3 = sec[j + 1]
		m.quad(_local(p0.x, p0.y, p0.z), _local(p0.x, -p0.y, p0.z), _local(p1.x, -p1.y, p1.z), _local(p1.x, p1.y, p1.z),
			HULL_WHITE if j == 4 else cols[j], aft)
	# cambered deck
	var cam := 0.06
	for i in ns:
		var a: Vector3 = secs[i][5]
		var b: Vector3 = secs[i + 1][5]
		for k in 6:
			var v0 := -1.0 + k / 3.0
			var v1 := -1.0 + (k + 1) / 3.0
			var q := [Vector3(a.x, a.y * v0, a.z + cam * (1.0 - v0 * v0)), Vector3(b.x, b.y * v0, b.z + cam * (1.0 - v0 * v0)),
				Vector3(b.x, b.y * v1, b.z + cam * (1.0 - v1 * v1)), Vector3(a.x, a.y * v1, a.z + cam * (1.0 - v1 * v1))]
			m.quad(_local(q[0].x, q[0].y, q[0].z), _local(q[1].x, q[1].y, q[1].z), _local(q[2].x, q[2].y, q[2].z),
				_local(q[3].x, q[3].y, q[3].z), DECK, Vector3.UP)


## A deckhouse footprint (body x, y), convex and counter-clockwise: square aft, the front rounded.
static func _footprint(x0: float, x1: float, w: float) -> PackedVector2Array:
	var rf := 0.8 * w
	var p := PackedVector2Array([Vector2(x0, -w)])
	for k in 9:
		var a := -PI * 0.5 + PI * k / 8.0
		p.append(Vector2(x1 - rf + rf * cos(a), w * sin(a)))
	p.append(Vector2(x0, w))
	return p


## A loft through rings over a footprint: each ring [z, side inset, front inset, colour of the band to the next
## ring]; the front inset grows toward the nose (the rake). Walls going down face inward (a coaming's inside),
## flat steps face up or down; the last ring is capped in `top`.
static func _loft(m: ColorMesh, fp: PackedVector2Array, x0: float, x1: float, rings: Array, top: Color) -> void:
	var xm := 0.5 * (x0 + x1)
	var w := 0.0
	for p in fp:
		w = maxf(w, absf(p.y))
	var ring_pts := func(r: Array) -> Array:
		var out := []
		for p in fp:
			var x: float = p.x
			if x > xm:
				x -= float(r[2]) * (x - xm) / (x1 - xm)
			out.append(_local(x, p.y * (w - float(r[1])) / w, r[0]))
		return out
	var centre := _local(xm, 0.0, 0.0)
	var prev: Array = ring_pts.call(rings[0])
	for j in rings.size() - 1:
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var cur: Array = ring_pts.call(r1)
		var dz: float = r1[0] - r0[0]
		for k in fp.size():
			var k1 := (k + 1) % fp.size()
			var mid: Vector3 = (prev[k] + prev[k1]) * 0.5
			var out := Vector3(mid.x - centre.x, 0.0, mid.z - centre.z)
			if absf(dz) < 1e-4:
				out = Vector3.UP if float(r1[1]) > float(r0[1]) else Vector3.DOWN
			elif dz < 0.0:
				out = -out
			m.quad(prev[k], prev[k1], cur[k1], cur[k], r0[3], out)
		prev = cur
	var c := Vector3.ZERO
	for p in prev:
		c += p
	c /= prev.size()
	for k in prev.size():
		m.flat_tri(c, prev[k], prev[(k + 1) % prev.size()], top, Vector3.UP)


## A tube along a polyline of local points with a radius per point (rails, the strake, a RIB's tubes).
static func _tube(m: ColorMesh, pts: Array, radii: PackedFloat32Array, sides: int, col: Color) -> void:
	var n := pts.size()
	var base := m.verts.size()
	for i in n:
		var t: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var u := t.cross(Vector3.UP)
		if u.length() < 0.1:
			u = t.cross(Vector3.RIGHT)
		u = u.normalized()
		var v := t.cross(u)
		for k in sides + 1:
			var a := TAU * k / sides
			var d := u * cos(a) + v * sin(a)
			m.vertex(pts[i] + d * radii[i], d, col)
	for i in n - 1:
		for k in sides:
			var a := base + i * (sides + 1) + k
			var out := m.normals[a] + m.normals[a + sides + 2]
			m.tri(a, a + 1, a + sides + 2, out)
			m.tri(a, a + sides + 2, a + sides + 1, out)


static func _radii(n: int, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(r)
	return out


## The foot of the committee boat's signal mast on the flybridge floor (local); its yard is 4.6 m above.
static func signal_mast(length: float) -> Vector3:
	return _local(MAST_X * length, 0.0, FB + HOUSE_H + FLY_FLOOR)


## Top of the mark boat's flag staff (local).
static func staff_top(length: float, small: bool) -> Vector3:
	var x: float = (RIB_STAFF_X if small else STAFF_X) * length
	return _local(x, 0.0, _deck(x, length, RIB_FB if small else FB) + (3.2 if small else 2.4))


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
