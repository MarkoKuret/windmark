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
const CUSHION := Color(0.56, 0.53, 0.46)
const ROPE := Color(0.55, 0.55, 0.50)
const NAV_GREEN := Color(0.02, 0.45, 0.08)

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
	var rng := RandomNumberGenerator.new()
	_hull(m, length, beam, FB, KEEL, x_t)
	# teak toe rail round the deck edge
	var toe := []
	for s in [-1.0, 1.0]:
		var side := []
		for i in 25:
			var x := lerpf(x_t, 0.48 * length, i / 24.0)
			var hb := beam * _half_breadth(x / length)
			side.append(_local(x, s * maxf(hb - 0.04, 0.0), _deck(x, length, FB) + 0.04))
		if s > 0.0:
			side.reverse()
		toe.append_array(side)
	_tube(m, toe, _radii(toe.size(), 0.035), 5, TEAK)
	# ports in the topsides forward, exhausts aft
	for s in [-1.0, 1.0]:
		for f in [0.13, 0.2, 0.27]:
			var x: float = f * length
			var z := _deck(x, length, FB) - 0.42
			_hull_patch(m, length, beam, x, z, s, 0.012, Vector3(0.025, 0.22, 0.52), STEEL)
			_hull_patch(m, length, beam, x, z, s, 0.022, Vector3(0.02, 0.15, 0.44), GLASS)
		_hull_patch(m, length, beam, -0.4 * length, 0.42, s, 0.01, Vector3(0.03, 0.12, 0.3), BLACK)
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
	for ly in [-0.25, 0.25]:
		_tube(m, [_local(-0.495 * length, ly, 0.36), _local(-0.5 * length - 0.02, ly, -0.45)], _radii(2, 0.02), 5, STEEL)
	for k in 3:
		m.box(Transform3D(Basis.IDENTITY, _local(-0.497 * length - 0.01 * k, 0.0, 0.1 - 0.22 * k)),
			Vector3(0.5, 0.025, 0.05), STEEL)
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
	m.box(Transform3D(Basis.IDENTITY, _local(cx, 0.0, roof + 0.45)), Vector3(1.3, 0.9, 0.55), WHITE)
	m.box(Transform3D(Basis(Vector3.RIGHT, 0.5), _local(cx + 0.18, 0.0, roof + 1.05)), Vector3(1.2, 0.35, 0.03),
		GLASS)
	m.box(Transform3D(Basis(Vector3.RIGHT, -0.9), _local(cx - 0.2, 0.0, roof + 0.95)), Vector3(1.2, 0.36, 0.03),
		BLACK)
	_ring(m, _local(cx - 0.36, -0.3, roof + 1.02), Vector3.RIGHT, Vector3(0, 0.62, -0.78), 0.2, 0.018, [BLACK])
	_seat(m, _local(cx - 1.15, 0.0, roof + FLY_FLOOR), 1.6, 0.55)
	# hardtop on four struts forward of the mast, the radar, nav lights and a searchlight on it
	var ht0 := MAST_X * length + 0.55
	var ht1 := f1 - 0.1
	var ht := roof + 2.2
	_loft(m, _footprint(ht0, ht1, fw + 0.05), ht0, ht1, [
		[ht, fw + 0.049, 0.0, WHITE], [ht, 0.0, 0.0, WHITE], [ht + 0.1, 0.0, 0.0, WHITE], [ht + 0.12, 0.04, 0.06, WHITE]],
		WHITE)
	for sy in [-1.0, 1.0]:
		_tube(m, [_local(ht1 - 0.35, sy * (fw - 0.08), roof + 0.6), _local(ht1 - 0.7, sy * (fw - 0.1), ht)],
			_radii(2, 0.035), 6, WHITE)
		_tube(m, [_local(ht0 + 0.15, sy * (fw - 0.1), roof + FLY_FLOOR), _local(ht0 + 0.15, sy * (fw - 0.1), ht)],
			_radii(2, 0.035), 6, WHITE)
		m.box(Transform3D(Basis.IDENTITY, _local(ht1 - 0.5, sy * (fw + 0.06), ht + 0.05)), Vector3(0.04, 0.08, 0.14),
			RED if sy > 0.0 else NAV_GREEN)
	var dome := _local(ht0 + 0.9, 0.0, ht + 0.12)
	m.cylinder(dome, 0.1, 0.1, 0.12, 8, WHITE)
	m.cylinder(dome + Vector3(0, 0.12, 0), 0.3, 0.3, 0.12, 14, WHITE)
	m.blob(dome + Vector3(0, 0.24, 0), Vector3(0.3, 0.07, 0.3), 3, 14, WHITE, WHITE, rng, 0.0)
	m.cylinder(_local(ht1 - 0.4, 0.0, ht + 0.12), 0.05, 0.05, 0.12, 6, STEEL)
	m.cylinder(_local(ht1 - 0.4, 0.0, ht + 0.24), 0.09, 0.08, 0.14, 8, STEEL)
	# the ladder from the cockpit to the flybridge, the saloon door
	var lb := _local(x0 - 0.6, 0.0, base)
	var lt := _local(f0, 0.0, roof + 0.6)
	for ly in [0.5, 0.95]:
		_tube(m, [lb + Vector3(-ly, 0, 0), lt + Vector3(-ly, 0, 0)], _radii(2, 0.025), 5, STEEL)
	for k in range(1, 9):
		var pr := lb.lerp(lt, k / 9.0)
		m.box(Transform3D(Basis.IDENTITY, pr + Vector3(-0.725, 0, 0)), Vector3(0.45, 0.03, 0.08), STEEL)
	m.box(Transform3D(Basis.IDENTITY, _local(x0 - 0.01, -0.35, base + 0.95)), Vector3(0.8, 1.75, 0.03), GLASS)
	var mast := signal_mast(length)
	m.cylinder(mast, 0.07, 0.05, 5.2, 8, WHITE)
	m.box(Transform3D(Basis.IDENTITY, mast + Vector3(0, 4.6, 0)), Vector3(3.0, 0.07, 0.07), WHITE)
	m.box(Transform3D(Basis.IDENTITY, mast + Vector3(0, 4.0, -0.08)), Vector3(0.08, 0.1, 0.08), WHITE)
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
	m.cylinder(_local(0.42 * length, 0.0, _deck(0.42 * length, length, FB)), 0.13, 0.11, 0.2, 10, STEEL)
	# fenders over the side on their lines, cleats at the bow and quarters
	for s in [-1.0, 1.0]:
		for f in [-0.36, -0.12, 0.12]:
			var x: float = f * length
			var hb := beam * _half_breadth(x / length)
			var c := _local(x, s * (hb + 0.14), 0.3)
			m.cylinder(c, 0.12, 0.12, 0.5, 10, WHITE)
			m.blob(c, Vector3(0.12, 0.06, 0.12), 3, 10, WHITE, WHITE, rng, 0.0)
			m.blob(c + Vector3(0, 0.5, 0), Vector3(0.12, 0.06, 0.12), 3, 10, WHITE, WHITE, rng, 0.0)
			_tube(m, [c + Vector3(0, 0.56, 0), _local(x, s * (hb - 0.12), _deck(x, length, FB) + 0.7)], _radii(2, 0.01),
				4, ROPE)
		for f in [-0.44, 0.38]:
			var x: float = f * length
			var hb := beam * _half_breadth(x / length) - 0.22
			m.box(Transform3D(Basis.IDENTITY, _local(x, s * hb, _deck(x, length, FB) + 0.06)), Vector3(0.06, 0.08, 0.3),
				STEEL)
	# a life ring on the aft rail
	var lx := -0.4 * length
	var lhb := beam * _half_breadth(-0.4) - 0.04
	_ring(m, _local(lx, -lhb, _deck(lx, length, FB) + 0.42), Vector3(0, 0, -1), Vector3.UP, 0.27, 0.06,
		[ORANGE, WHITE, ORANGE, WHITE])
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
	# grab lines looped along the top of the tubes
	var rng := RandomNumberGenerator.new()
	for s in [-1.0, 1.0]:
		var line := []
		for i in 57:
			var x := lerpf(-0.38 * length, 0.3 * length, i / 56.0)
			var y := beam * _half_breadth(x / length) - RIB_TUBE
			var sag := sin(PI * fmod(i / 7.0, 1.0))
			line.append(_local(x, s * (y + 0.12 + 0.1 * sag), _deck(x, length, RIB_FB) + 0.36 - 0.12 * sag))
		_tube(m, line, _radii(line.size(), 0.012), 4, ROPE * 0.6)
	var d := _deck(0.0, length, RIB_FB)
	# centre console with a raked screen, the wheel and a grab rail; a jockey seat behind
	var cx := 0.05 * length
	m.box(Transform3D(Basis.IDENTITY, _local(cx, 0.0, d + 0.5)), Vector3(0.8, 1.0, 0.7), WHITE)
	m.box(Transform3D(Basis(Vector3.RIGHT, 0.45), _local(cx + 0.4, 0.0, d + 1.15)), Vector3(0.8, 0.35, 0.03), GLASS)
	m.box(Transform3D(Basis(Vector3.RIGHT, -0.9), _local(cx - 0.3, 0.0, d + 0.98)), Vector3(0.7, 0.3, 0.03), BLACK)
	_ring(m, _local(cx - 0.42, 0.0, d + 1.0), Vector3.RIGHT, Vector3(0, 0.62, -0.78), 0.17, 0.016, [BLACK])
	_tube(m, [_local(cx - 0.35, 0.42, d + 0.55), _local(cx - 0.35, 0.42, d + 0.9), _local(cx + 0.3, 0.42, d + 0.9),
		_local(cx + 0.3, -0.42, d + 0.9), _local(cx - 0.35, -0.42, d + 0.9), _local(cx - 0.35, -0.42, d + 0.55)],
		_radii(6, 0.02), 5, STEEL)
	_seat(m, _local(-0.14 * length, 0.0, d), 0.7, 0.5)
	# T-top over the console on four posts
	for sx in [-0.45, 0.35]:
		for sy in [-0.4, 0.4]:
			_tube(m, [_local(cx + sx, sy, d), _local(cx + sx, sy, d + 2.0)], _radii(2, 0.025), 5, STEEL)
	m.box(Transform3D(Basis.IDENTITY, _local(cx - 0.05, 0.0, d + 2.03)), Vector3(1.0, 0.06, 1.1), NAVY)
	m.cylinder(_local(cx - 0.05, 0.0, d + 2.06), 0.02, 0.01, 1.0, 4, WHITE)
	# outboard on the transom: leg, anti-cavitation plate, propeller, cowl
	var ob := x_t - 0.28
	m.box(Transform3D(Basis.IDENTITY, _local(ob, 0.0, -0.05)), Vector3(0.14, 1.0, 0.24), BLACK)
	m.box(Transform3D(Basis.IDENTITY, _local(ob - 0.05, 0.0, -0.3)), Vector3(0.34, 0.03, 0.42), BLACK)
	m.cylinder(_local(ob - 0.05, 0.0, -0.62), 0.07, 0.07, 0.22, 6, BLACK)
	m.box(Transform3D(Basis.IDENTITY, _local(ob, 0.0, RIB_FB + 0.18)), Vector3(0.3, 0.4, 0.4), BLACK)
	m.blob(_local(ob - 0.03, 0.0, RIB_FB + 0.55), Vector3(0.22, 0.25, 0.33), 5, 10, Color(0.03, 0.03, 0.035), BLACK,
		rng, 0.0)
	# anchor locker lid and the bow light
	m.box(Transform3D(Basis.IDENTITY, _local(0.3 * length, 0.0, _deck(0.3 * length, length, RIB_FB) + 0.04)),
		Vector3(0.5, 0.06, 0.5), WHITE)
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


## A torus of ring radius `rr` and tube radius `r` about `c` in the plane of the unit vectors u and v, in
## equal arcs of the given colours (a life ring's bands, a wheel).
static func _ring(m: ColorMesh, c: Vector3, u: Vector3, v: Vector3, rr: float, r: float, cols: Array,
		segs := 24, sides := 6) -> void:
	v = v.normalized()
	var axis := u.cross(v).normalized()
	var per := segs / cols.size()
	for q in cols.size():
		var base := m.verts.size()
		for i in per + 1:
			var a := TAU * float(q * per + i) / segs
			var d := u * cos(a) + v * sin(a)
			for k in sides + 1:
				var b := TAU * k / sides
				var nrm := d * cos(b) + axis * sin(b)
				m.vertex(c + d * rr + nrm * r, nrm, cols[q])
		for i in per:
			for k in sides:
				var a0 := base + i * (sides + 1) + k
				var a1 := a0 + sides + 1
				var out := m.normals[a0] + m.normals[a1 + 1]
				m.tri(a0, a0 + 1, a1 + 1, out)
				m.tri(a0, a1 + 1, a1, out)


## A thin box lying on the topsides at body (x, z) on side s (+1 port), `off` m proud of the hull, its long side
## along the hull's waterline direction (ports, exhausts).
static func _hull_patch(m: ColorMesh, length: float, beam: float, x: float, z: float, s: float, off: float,
		size: Vector3, col: Color) -> void:
	var y := _hull_y(x, z, length, beam)
	var dy := _hull_y(x + 0.1, z, length, beam) - _hull_y(x - 0.1, z, length, beam)
	var basis := Basis(Vector3.UP, atan2(s * dy, 0.2))
	m.box(Transform3D(basis, _local(x, s * (y + off), z)), size, col)


## The half-breadth of the committee hull at body x and height z (on the topsides).
static func _hull_y(x: float, z: float, length: float, beam: float) -> float:
	var sec := _section(x, length, beam, FB, KEEL)
	for j in sec.size() - 1:
		var z0: float = sec[j][1]
		var z1: float = sec[j + 1][1]
		if z >= minf(z0, z1) and z <= maxf(z0, z1) and absf(z1 - z0) > 1e-5:
			return lerpf(sec[j][0], sec[j + 1][0], (z - z0) / (z1 - z0))
	return float(sec[-1][0])


## A cushioned bench (width x depth) at a local foot point, with a backrest on its aft side.
static func _seat(m: ColorMesh, foot: Vector3, width: float, depth: float) -> void:
	m.box(Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.2, 0)), Vector3(width, 0.4, depth), WHITE)
	m.box(Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.46, 0)), Vector3(width - 0.04, 0.12, depth - 0.04), CUSHION)
	m.box(Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.72, 0.5 * depth - 0.06)), Vector3(width - 0.04, 0.42, 0.1),
		CUSHION)


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
