class_name SheetRopesRef
extends RefCounted
## GDScript reference of the native SheetRopes (game/native/src/sheet_ropes.h): the running sheets of
## docs/specs/sail_visuals.md §11.3 for one mesh surface, with the same calls. Tests compare the two; without the
## GDExtension BoatSheets uses this one (and rebuilds its mesh each update instead of writing it in place). `route`
## lays a flying sail's line outside the sails, the boom and the rail (§11.3 "Outside route"), `build_deck` builds the
## class's deck height field from its meshes (§11.3 "Deck").

const DRIVE := 6
const NO_DECK := -1.0e9
const WHIP_WAVE := 1.5
## the most waypoints a line's free run takes (`ways` in update: ways.size() / line count slots per line, NaN unused)
const MAX_WAYS := 16
## m, the drape's sample step along a tube (under the field's widening)
const DRAPE_STEP := 0.025
## rad, the angle over which an obstacle point fades in at an end of a route
const ROUTE_FADE := 0.1
## m above the straight line from which an obstacle point lets the line pass under, and over which it fades out
const ROUTE_UNDER := 0.1
const ROUTE_UNDER_FADE := 0.2
## the binormal sign of the tube: cross(normal, along) points against the way round (+v)
const TANGENT_SIGN := -1.0

var _sides := 6
var _tile := 0.05
## per line: {"radius", "free_rings", "lead_rings", "anchor", "fixed": PackedVector3Array, "first_ring", "rings"}
var _lines: Array[Dictionary] = []
var _nr := 0
var _nv := 0
var _ring := PackedVector3Array()
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _tan := PackedFloat32Array()
var _uv := PackedVector2Array()
var _idx := PackedInt32Array()
var _deck := PackedFloat32Array()
var _dx0 := 0.0
var _dz0 := 0.0
var _dcell := 0.05
var _dnx := 0
var _dnz := 0
var _dmax := NO_DECK


func configure(params: Dictionary) -> bool:
	_sides = maxi(3, int(params.get("sides", 6)))
	_tile = float(params.get("tile", 0.05))
	_lines.clear()
	var ring := 0
	for d: Dictionary in params.get("lines", []):
		var l := {"radius": float(d.get("radius", 0.005)), "free_rings": maxi(2, int(d.get("free_rings", 16))),
			"lead_rings": maxi(0, int(d.get("lead_rings", 0))), "anchor": d.get("anchor", Vector3.ZERO),
			"fixed": PackedVector3Array(d.get("fixed", PackedVector3Array()))}
		if l["lead_rings"] > 0 and (l["fixed"] as PackedVector3Array).is_empty():
			return false
		if l["lead_rings"] == 0:
			l["fixed"] = PackedVector3Array()
		l["first_ring"] = ring
		l["rings"] = l["free_rings"] + (l["lead_rings"] + (l["fixed"] as PackedVector3Array).size() - 1 \
				if l["lead_rings"] > 0 else 0)
		ring += l["rings"]
		_lines.append(l)
	_nr = ring
	var per := _sides + 1
	_nv = _nr * per
	_ring.resize(_nr)
	_pos.resize(_nv)
	_nrm.resize(_nv)
	_tan.resize(4 * _nv)
	_uv.resize(_nv)
	_idx.clear()
	for l in _lines:
		for k in int(l["rings"]) - 1:
			var a: int = (int(l["first_ring"]) + k) * per
			var b := a + per
			for j in _sides:
				_idx.append_array([a + j, b + j, b + j + 1, a + j, b + j + 1, a + j + 1])
	_deck = PackedFloat32Array()
	_dnx = 0
	_dnz = 0
	var dk: Dictionary = params.get("deck", {})
	if not dk.is_empty():
		var h: PackedFloat32Array = dk.get("heights", PackedFloat32Array())
		_dnx = int(dk.get("nx", 0))
		_dnz = int(dk.get("nz", 0))
		_dcell = float(dk.get("cell", 0.05))
		var o: Vector2 = dk.get("origin", Vector2.ZERO)
		_dx0 = o.x
		_dz0 = o.y
		if h.size() == _dnx * _dnz and _dnx > 1 and _dnz > 1:
			_deck = h
			_dmax = NO_DECK
			for v in h:
				_dmax = maxf(_dmax, v)
		else:
			_dnx = 0
			_dnz = 0
	return _nr > 0


func get_line_count() -> int:
	return _lines.size()


func get_vertex_count() -> int:
	return _nv


func deck_height(x: float, z: float) -> float:
	if _deck.is_empty():
		return NO_DECK
	var fx := (x - _dx0) / _dcell
	var fz := (z - _dz0) / _dcell
	if fx < 0.0 or fz < 0.0 or fx > _dnx - 1 or fz > _dnz - 1:
		return NO_DECK
	var ix := mini(int(fx), _dnx - 2)
	var iz := mini(int(fz), _dnz - 2)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _deck[iz * _dnx + ix]
	var h10 := _deck[iz * _dnx + ix + 1]
	var h01 := _deck[(iz + 1) * _dnx + ix]
	var h11 := _deck[(iz + 1) * _dnx + ix + 1]
	if h00 <= NO_DECK or h10 <= NO_DECK or h01 <= NO_DECK or h11 <= NO_DECK:
		return maxf(maxf(h00, h10), maxf(h01, h11))
	return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz


static func _side_of(a: Vector3, g: Vector3) -> Vector3:
	var s := a.cross(g)
	if s.length_squared() < 1e-12:
		s = Vector3(1, 0, 0).cross(g)
	if s.length_squared() < 1e-12:
		s = Vector3(0, 0, 1).cross(g)
	return s.normalized()


func update(starts: PackedVector3Array, ways: PackedVector3Array, drive: PackedFloat32Array, gravity: Vector3) -> void:
	var g := gravity.normalized() if gravity.length_squared() > 1e-12 else Vector3.DOWN
	var per := _sides + 1
	var slots := mini(ways.size() / _lines.size(), MAX_WAYS) if not _lines.is_empty() else 0
	for i in _lines.size():
		var l: Dictionary = _lines[i]
		var first: int = l["first_ring"]
		var rings: int = l["rings"]
		var anchor: Vector3 = l["anchor"]
		var radius: float = l["radius"]
		var s0: Vector3 = starts[i] if i < starts.size() else anchor
		var shown := drive.size() >= (i + 1) * DRIVE and drive[i * DRIVE] > 0.5
		if not shown:
			for k in rings:
				_ring[first + k] = s0
		else:
			var o := i * DRIVE
			var sag_f := drive[o + 1]
			var sag_l := drive[o + 2]
			var psi := drive[o + 3]
			var whip := drive[o + 4]
			var phi := drive[o + 5]
			var p := PackedVector3Array([s0])
			for j in slots:
				var w := ways[i * slots + j]
				if not is_nan(w.x):
					p.append(w)
			p.append(anchor)
			var c := PackedFloat32Array([0.0])
			for k in range(1, p.size()):
				c.append(c[k - 1] + (p[k] - p[k - 1]).length())
			var length := c[p.size() - 1]
			var side := _side_of(anchor - s0, g)
			var sag := (g * cos(psi) + side * sin(psi)) * (length * sag_f)
			var nf: int = l["free_rings"]
			for k in nf:
				var t := float(k) / float(nf - 1)
				var s := t * length
				var b := 4.0 * t * (1.0 - t)
				var q := _along(p, c, s) + sag * b + side * (b * whip * length * sin(phi - TAU * s / WHIP_WAVE))
				if k > 0 and k < nf - 1:
					q.y = maxf(q.y, deck_height(q.x, q.z) + radius)
				_ring[first + k] = q
			_drape(first, nf, radius)
			var nl: int = l["lead_rings"]
			if nl > 0:
				var fixed: PackedVector3Array = l["fixed"]
				var e := fixed[0]
				var sag2 := g * ((e - anchor).length() * sag_l)
				for k in range(1, nl + 1):
					var t := float(k) / float(nl)
					var q := anchor + (e - anchor) * t + sag2 * (4.0 * t * (1.0 - t))
					if k < nl:
						q.y = maxf(q.y, deck_height(q.x, q.z) + radius)
					_ring[first + nf - 1 + k] = q
				_drape(first + nf - 1, nl + 1, radius)
				for k in range(1, fixed.size()):
					_ring[first + nf - 1 + nl + k] = fixed[k]
		var acc := 0.0
		var nprev := Vector3.ZERO
		for k in rings:
			var a := maxi(k - 1, 0)
			var bk := mini(k + 1, rings - 1)
			var t := _ring[first + bk] - _ring[first + a]
			if k > 0:
				acc += (_ring[first + k] - _ring[first + k - 1]).length()
			t = t.normalized() if t.length_squared() > 1e-14 else Vector3(0, 0, 1)
			var nn: Vector3
			if k == 0:
				nn = t.cross(Vector3(0, 1, 0) if absf(t.y) < 0.9 else Vector3(1, 0, 0))
			else:
				nn = nprev - t * nprev.dot(t)
				if nn.length_squared() < 1e-10:
					nn = t.cross(Vector3(0, 1, 0) if absf(t.y) < 0.9 else Vector3(1, 0, 0))
			nn = nn.normalized()
			nprev = nn
			var bb := t.cross(nn)
			var base := (first + k) * per
			for j in _sides + 1:
				var th := TAU * float(j) / float(_sides)
				var d := nn * cos(th) + bb * sin(th)
				_pos[base + j] = _ring[first + k] + d * radius
				_nrm[base + j] = d
				_tan[4 * (base + j)] = t.x
				_tan[4 * (base + j) + 1] = t.y
				_tan[4 * (base + j) + 2] = t.z
				_tan[4 * (base + j) + 3] = TANGENT_SIGN
				_uv[base + j] = Vector2(acc, _tile * float(j) / float(_sides))


## §11.3 "Deck": lifts the rings first .. first + n - 1 of a run (its ends fixed) so the straight tube between each
## pair clears the field at every DRAPE_STEP, by the least lift of the pair; one pass (a lift only raises).
func _drape(first: int, n: int, radius: float) -> void:
	if _deck.is_empty() or n < 3:
		return
	for _pass in 1:  # one pass: a lift only raises the tubes either side of a ring
		for k in n - 1:
			var p0 := _ring[first + k]
			var p1 := _ring[first + k + 1]
			if minf(p0.y, p1.y) > _dmax + radius:
				continue
			var dx := p1.x - p0.x
			var dz := p1.z - p0.z
			var m := clampi(int(ceil(sqrt(dx * dx + dz * dz) / DRAPE_STEP)), 1, 64)
			var w0f := 0.0 if k == 0 else 1.0
			var w1f := 0.0 if k + 1 == n - 1 else 1.0
			# a fixed end inside the field (a block on the deck) lets its tube in by its own depth, fading along it
			var e0 := maxf(deck_height(p0.x, p0.z) + radius - p0.y, 0.0) if k == 0 else 0.0
			var e1 := maxf(deck_height(p1.x, p1.z) + radius - p1.y, 0.0) if k + 1 == n - 1 else 0.0
			for j in range(1, m):
				var f := float(j) / float(m)
				var h := deck_height(p0.x + dx * f, p0.z + dz * f)
				if h <= NO_DECK:
					continue
				var d := h + radius - (p0.y + (p1.y - p0.y) * f) - e0 * (1.0 - f) - e1 * f
				if d <= 0.0:
					continue
				var w0 := w0f * (1.0 - f)
				var w1 := w1f * f
				var den := w0 * w0 + w1 * w1
				if den < 1e-9:
					continue
				p0.y += d * w0 / den
				p1.y += d * w1 / den
			_ring[first + k] = p0
			_ring[first + k + 1] = p1


## §11.3 "Outside route": the waypoints of the taut string from `a` to `b` round the obstacles on side `side` (sgn x),
## about `pivot`; `obstacles` = [PackedVector3Array points, float margin, ...]; `spacing` the ring spacing of the run;
## at most `max_ways` waypoints.
func route(a: Vector3, b: Vector3, pivot: Vector3, side: float, obstacles: Array, spacing: float,
		max_ways: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sg := 1.0 if side >= 0.0 else -1.0
	var ta := atan2(sg * (a.x - pivot.x), a.z - pivot.z)
	var tb := atan2(sg * (b.x - pivot.x), b.z - pivot.z)
	if absf(tb - ta) >= PI - 0.05 or absf(tb - ta) < 1e-9:
		return out
	var tlo := minf(ta, tb)
	var thi := maxf(ta, tb)
	var cx := b.x - a.x
	var cz := b.z - a.z
	var so := 1.0 if cx * (pivot.z - a.z) - cz * (pivot.x - a.x) >= 0.0 else -1.0
	var k: Array = []  # [theta, x, z, margin]
	for gi in range(0, obstacles.size() - 1, 2):
		var pts: PackedVector3Array = obstacles[gi]
		var m: float = obstacles[gi + 1]
		for p in pts:
			if (cx * (p.z - a.z) - cz * (p.x - a.x)) * so >= 0.0:
				continue
			var th := atan2(sg * (p.x - pivot.x), p.z - pivot.z)
			if th <= tlo or th >= thi:
				continue
			# a point well above the straight line there (the boom over the cockpit, the main above it) lets the
			# line pass under: it moves onto the chord as it rises from ROUTE_UNDER to ROUTE_UNDER + ROUTE_UNDER_FADE
			var f := clampf(((p.x - a.x) * cx + (p.z - a.z) * cz) / maxf(cx * cx + cz * cz, 1e-12), 0.0, 1.0)
			var gap := p.y - (a.y + (b.y - a.y) * f)
			var v := clampf((gap - ROUTE_UNDER) / ROUTE_UNDER_FADE, 0.0, 1.0)
			var hv := 1.0 - v * v * (3.0 - 2.0 * v)
			if hv <= 0.0:
				continue
			var fx := a.x + cx * f
			var fz := a.z + cz * f
			var qx := fx + (p.x - fx) * hv
			var qz := fz + (p.z - fz) * hv
			# a point coming into the wedge past an end starts at that end and moves out to its place over
			# ROUTE_FADE of angle, so the line bends away from it smoothly instead of jumping round it
			var near_a := absf(th - ta) <= absf(th - tb)
			var u := minf(absf(th - (ta if near_a else tb)) / ROUTE_FADE, 1.0)
			var sf := u * u * (3.0 - 2.0 * u)
			var e := a if near_a else b
			qx = e.x + (qx - e.x) * sf
			qz = e.z + (qz - e.z) * sf
			if sf * hv >= 1.0:
				k.append([th, p.x, p.z, m])
			else:
				k.append([atan2(sg * (qx - pivot.x), qz - pivot.z), qx, qz, m * sf * hv])
	if k.is_empty():
		return out
	var up := tb > ta
	k.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0] if up else p[0] > q[0])
	var ch: Array = [[ta, a.x, a.z, 0.0]]
	k.append([tb, b.x, b.z, 0.0])
	for p: Array in k:
		while ch.size() >= 2:
			var c0: Array = ch[ch.size() - 2]
			var c1: Array = ch[ch.size() - 1]
			if ((c1[1] - c0[1]) * (p[2] - c1[2]) - (c1[2] - c0[2]) * (p[1] - c1[1])) * so > 0.0:
				break
			ch.pop_back()
		ch.append(p)
	while ch.size() - 2 > maxi(max_ways, 0):
		var best := 1
		var bt := 1e9
		for i in range(1, ch.size() - 1):
			var t := _turn(ch, i)
			if t < bt:
				bt = t
				best = i
		# its depth outside the new edge goes to the margins of its neighbours, so the edge still clears it
		var p: Array = ch[best - 1]
		var v: Array = ch[best]
		var q: Array = ch[best + 1]
		var ex: float = q[1] - p[1]
		var ez: float = q[2] - p[2]
		var el := maxf(Vector2(ex, ez).length(), 1e-9)
		var extra: float = float(v[3]) + maxf(-so * (ex * (v[2] - p[2]) - ez * (v[1] - p[1])) / el, 0.0)
		if best - 1 > 0:
			p[3] = maxf(p[3], extra)
		if best + 2 < ch.size():
			q[3] = maxf(q[3], extra)
		ch.remove_at(best)
	if ch.size() < 3:
		return out
	var wx := PackedFloat64Array()
	var wz := PackedFloat64Array()
	for c: Array in ch:
		wx.append(c[1])
		wz.append(c[2])
	# each corner's allowance takes the turns within a ring spacing of it, weighted down linearly over the spacing
	var tn := PackedFloat64Array()
	var c0 := PackedFloat64Array([0.0])
	tn.resize(ch.size())
	for i in range(1, ch.size()):
		c0.append(c0[i - 1] + Vector2(ch[i][1] - ch[i - 1][1], ch[i][2] - ch[i - 1][2]).length())
	for i in range(1, ch.size() - 1):
		tn[i] = _turn(ch, i)
	var hs := maxf(spacing, 1e-6)
	for i in range(1, ch.size() - 1):
		var ae := 0.0
		for j in range(1, ch.size() - 1):
			ae += tn[j] * maxf(0.0, 1.0 - absf(c0[j] - c0[i]) / hs)
		ae = minf(ae, 2.5)
		var ax: float = ch[i][1] - ch[i - 1][1]
		var az: float = ch[i][2] - ch[i - 1][2]
		var bx: float = ch[i + 1][1] - ch[i][1]
		var bz: float = ch[i + 1][2] - ch[i][2]
		var la := maxf(sqrt(ax * ax + az * az), 1e-9)
		var lb := maxf(sqrt(bx * bx + bz * bz), 1e-9)
		ax /= la
		az /= la
		bx /= lb
		bz /= lb
		var nx := so * (az + bz)
		var nz := -so * (ax + bx)
		var nl := sqrt(nx * nx + nz * nz)
		if nl < 1e-9:
			nx = so * az
			nz = -so * ax
			nl = 1.0
		nx /= nl
		nz /= nl
		var al := acos(clampf(ax * bx + az * bz, -1.0, 1.0))
		# a chord cuts a corner by at most half a ring spacing times sin(turn / 2), and no chord starts before the
		# route's first ring or ends after its last (the ends are rings)
		var reach := minf(0.5 * spacing, minf(c0[i], c0[ch.size() - 1] - c0[i]))
		var push: float = (float(ch[i][3]) + reach * sin(0.5 * ae)) / maxf(cos(0.5 * al), 0.3)
		wx[i] += nx * push
		wz[i] += nz * push
	var cl := PackedFloat64Array([0.0])
	for i in range(1, ch.size()):
		cl.append(cl[i - 1] + Vector2(wx[i] - wx[i - 1], wz[i] - wz[i - 1]).length())
	var tot := maxf(cl[ch.size() - 1], 1e-9)
	for i in range(1, ch.size() - 1):
		out.append(Vector3(wx[i], a.y + (b.y - a.y) * cl[i] / tot, wz[i]))
	return out


static func _turn(ch: Array, i: int) -> float:
	var ax: float = ch[i][1] - ch[i - 1][1]
	var az: float = ch[i][2] - ch[i - 1][2]
	var bx: float = ch[i + 1][1] - ch[i][1]
	var bz: float = ch[i + 1][2] - ch[i][2]
	var la := sqrt(ax * ax + az * az)
	var lb := sqrt(bx * bx + bz * bz)
	if la < 1e-9 or lb < 1e-9:
		return 0.0
	return acos(clampf((ax * bx + az * bz) / (la * lb), -1.0, 1.0))


## §11.3 "Deck": the deck height field from `surfaces` = [{positions, indices, cap}] in model axes (cap < 0: deck,
## else a fitting counted where it stands at most `cap` above the deck), on a grid of `cell`, the skirt `skirt` cells
## out over the hull side, widened by `dilate` cells. {heights, origin, cell, nx, nz, max, edge_lo, edge_hi}
func build_deck(surfaces: Array, cell: float, skirt: int, dilate: int) -> Dictionary:
	cell = maxf(cell, 1e-3)
	var xmin := INF
	var xmax := -INF
	var zmin := INF
	var zmax := -INF
	for d: Dictionary in surfaces:
		if float(d.get("cap", -1.0)) >= 0.0:
			continue
		for p: Vector3 in d.get("positions", PackedVector3Array()):
			xmin = minf(xmin, p.x)
			xmax = maxf(xmax, p.x)
			zmin = minf(zmin, p.z)
			zmax = maxf(zmax, p.z)
	if xmax < xmin:
		return {}
	var pad := maxi(skirt, 0) + maxi(dilate, 0) + 2
	var x0 := xmin - pad * cell
	var z0 := zmin - pad * cell
	var nx := int(ceil((xmax - xmin) / cell)) + 2 * pad + 1
	var nz := int(ceil((zmax - zmin) / cell)) + 2 * pad + 1
	var h := PackedFloat64Array()
	h.resize(nx * nz)
	h.fill(NO_DECK)
	for d: Dictionary in surfaces:
		if float(d.get("cap", -1.0)) < 0.0:
			_raster(d, x0, z0, cell, nx, nz, h, PackedFloat64Array(), -1.0)
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(nz)
	hi.resize(nz)
	for k in nz:
		var l := NAN
		var r := NAN
		for i in nx:
			if h[k * nx + i] <= NO_DECK:
				continue
			var x := x0 + i * cell
			if is_nan(l):
				l = x
			r = x
		lo[k] = l
		hi[k] = r
	var deck := h.duplicate()
	for d: Dictionary in surfaces:
		if float(d.get("cap", -1.0)) >= 0.0:
			_raster(d, x0, z0, cell, nx, nz, h, deck, float(d["cap"]))
	for _step in skirt:
		var src := h.duplicate()
		for k in nz:
			for i in nx:
				if src[k * nx + i] > NO_DECK:
					continue
				var best := NO_DECK
				for dk in range(maxi(k - 1, 0), mini(k + 1, nz - 1) + 1):
					for di in range(maxi(i - 1, 0), mini(i + 1, nx - 1) + 1):
						best = maxf(best, src[dk * nx + di])
				h[k * nx + i] = best
	if dilate > 0:
		var tmp := h.duplicate()
		for k in nz:
			for i in nx:
				var best := NO_DECK
				for di in range(maxi(0, i - dilate), mini(nx - 1, i + dilate) + 1):
					best = maxf(best, h[k * nx + di])
				tmp[k * nx + i] = best
		for k in nz:
			for i in nx:
				var best := NO_DECK
				for dk in range(maxi(0, k - dilate), mini(nz - 1, k + dilate) + 1):
					best = maxf(best, tmp[dk * nx + i])
				h[k * nx + i] = best
	var hf := PackedFloat32Array(Array(h))
	var mx := NO_DECK
	for v in hf:
		mx = maxf(mx, v)
	return {"heights": hf, "origin": Vector2(x0, z0), "cell": cell, "nx": nx, "nz": nz, "max": mx,
		"edge_lo": lo, "edge_hi": hi}


## The top of one surface's triangles at the grid nodes into `h` (a deck surface: the highest; a fitting, cap >= 0:
## where it stands at most `cap` above `deck`).
static func _raster(d: Dictionary, x0: float, z0: float, cell: float, nx: int, nz: int, h: PackedFloat64Array,
		deck: PackedFloat64Array, cap: float) -> void:
	var p: PackedVector3Array = d.get("positions", PackedVector3Array())
	var idx: PackedInt32Array = d.get("indices", PackedInt32Array())
	for t in range(0, idx.size() - 2, 3):
		if idx[t] < 0 or idx[t + 1] < 0 or idx[t + 2] < 0 or idx[t] >= p.size() or idx[t + 1] >= p.size() \
				or idx[t + 2] >= p.size():
			continue
		var a := p[idx[t]]
		var b := p[idx[t + 1]]
		var c := p[idx[t + 2]]
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		var i0 := maxi(0, int(ceil((minf(a.x, minf(b.x, c.x)) - x0) / cell)))
		var i1 := mini(nx - 1, int(floor((maxf(a.x, maxf(b.x, c.x)) - x0) / cell)))
		var k0 := maxi(0, int(ceil((minf(a.z, minf(b.z, c.z)) - z0) / cell)))
		var k1 := mini(nz - 1, int(floor((maxf(a.z, maxf(b.z, c.z)) - z0) / cell)))
		for k in range(k0, k1 + 1):
			var pz := z0 + k * cell
			for i in range(i0, i1 + 1):
				var px := x0 + i * cell
				var w0 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
				var w1 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
				var w2 := 1.0 - w0 - w1
				if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
					continue
				var y := w0 * a.y + w1 * b.y + w2 * c.y
				var n := k * nx + i
				if cap < 0.0:
					h[n] = maxf(h[n], y)
				elif deck[n] > NO_DECK and y > h[n] and y <= deck[n] + cap:
					h[n] = y


static func _along(p: PackedVector3Array, c: PackedFloat32Array, s: float) -> Vector3:
	for k in range(1, p.size()):
		if s <= c[k] or k == p.size() - 1:
			var seg := c[k] - c[k - 1]
			var t := clampf((s - c[k - 1]) / seg, 0.0, 1.0) if seg > 1e-9 else 0.0
			return p[k - 1] + (p[k] - p[k - 1]) * t
	return p[0]


func indices() -> PackedInt32Array:
	return _idx


func positions() -> PackedVector3Array:
	return _pos


func normals() -> PackedVector3Array:
	return _nrm


func tangents() -> PackedFloat32Array:
	return _tan


func uvs() -> PackedVector2Array:
	return _uv


func centre(line: int) -> PackedVector3Array:
	if line < 0 or line >= _lines.size():
		return PackedVector3Array()
	var l: Dictionary = _lines[line]
	return _ring.slice(int(l["first_ring"]), int(l["first_ring"]) + int(l["rings"]))


## The reference cannot write a mesh in place: BoatSheets rebuilds the mesh from positions(), normals() and uvs().
func attach_mesh(_mesh: RID, _surface: int) -> bool:
	return false


func write_mesh() -> void:
	pass
