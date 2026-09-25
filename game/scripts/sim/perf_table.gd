class_name PerfTable
extends RefCounted
## A 1-3 axis rectilinear table from a performance file (data_format.md §5), looked up as in conventions.md §8:
## clamped at the ends, right-continuous at steps, values row-major with the last axis fastest.

var axes: Array[PackedFloat64Array] = []
var values := PackedFloat64Array()


static func from_json(d: Variant) -> PerfTable:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var t := PerfTable.new()
	for a in d["axes"]:
		t.axes.append(PackedFloat64Array(a["points"]))
	t.values = PackedFloat64Array(d["values"])
	return t


## A value that is either a number or a table (sails.md §4.4 durations) as a table of one point.
static func constant_or_table(d: Variant) -> PerfTable:
	if typeof(d) == TYPE_DICTIONARY:
		return from_json(d)
	var t := PerfTable.new()
	t.axes.append(PackedFloat64Array([0.0]))
	t.values = PackedFloat64Array([float(d)])
	return t


static func _bracket(a: PackedFloat64Array, x: float) -> Vector3:
	var n := a.size()
	if n == 1 or not (x >= a[0]):
		return Vector3(0, 0, 0)
	if x >= a[n - 1]:
		return Vector3(n - 1, n - 1, 0)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if a[mid] <= x:
			lo = mid
		else:
			hi = mid
	return Vector3(lo, lo + 1, (x - a[lo]) / (a[lo + 1] - a[lo]))


## Lookup with one argument per axis (extra axes of a 1-point table are ignored).
func at(x: float, y: float = 0.0, w: float = 0.0) -> float:
	match axes.size():
		1:
			var b := _bracket(axes[0], x)
			return lerpf(values[int(b.x)], values[int(b.y)], b.z)
		2:
			var bx := _bracket(axes[0], x)
			var by := _bracket(axes[1], y)
			var n1 := axes[1].size()
			var r0 := lerpf(values[int(bx.x) * n1 + int(by.x)], values[int(bx.x) * n1 + int(by.y)], by.z)
			var r1 := lerpf(values[int(bx.y) * n1 + int(by.x)], values[int(bx.y) * n1 + int(by.y)], by.z)
			return lerpf(r0, r1, bx.z)
		3:
			var bx := _bracket(axes[0], x)
			var by := _bracket(axes[1], y)
			var bw := _bracket(axes[2], w)
			var n1 := axes[1].size()
			var n2 := axes[2].size()
			var c := func(i: int, j: int) -> float:
				var base := (i * n1 + j) * n2
				return lerpf(values[base + int(bw.x)], values[base + int(bw.y)], bw.z)
			var r0 := lerpf(c.call(int(bx.x), int(by.x)), c.call(int(bx.x), int(by.y)), by.z)
			var r1 := lerpf(c.call(int(bx.y), int(by.x)), c.call(int(bx.y), int(by.y)), by.z)
			return lerpf(r0, r1, bx.z)
	return 0.0
