class_name SheetRopesRef
extends RefCounted
## GDScript reference of the native SheetRopes (game/native/src/sheet_ropes.h): the running sheets of
## docs/specs/sail_visuals.md §11.3 for one mesh surface, with the same calls. Tests compare the two; without the
## GDExtension BoatSheets uses this one (and rebuilds its mesh each update instead of writing it in place).

const DRIVE := 6
const NO_DECK := -1.0e9
const WHIP_WAVE := 1.5
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
			if i < ways.size() and not is_nan(ways[i].x):
				p.append(ways[i])
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
