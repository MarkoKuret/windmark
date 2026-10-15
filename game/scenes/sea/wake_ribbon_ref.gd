class_name WakeRibbonRef
extends RefCounted
## One wake ribbon (water_render.md §5): rows laid down behind the bow (or the transom) every 50 ms of render
## time, left where they were laid, opening at the Kelvin angle for 4 s and fading over 9 s. Rows optionally launch two
## spray particles that fly under gravity, stick where they reach the surface and become the ribbon's outer
## vertices. World coordinates are ENU metres (x east, y north, z up); heights come from a callable.
##
## The GDScript reference of the native WakeRibbon (game/native/src/sea_wakes.h): SeaWakes uses it when the
## extension is missing, and tests/wakes_native_test.gd compares the two. Keep them in step.

const N_ROWS := 180
const LIFE_S := 9.0
## the edges stop opening after SPREAD_S (the diverging waves have broken)
const SPREAD_S := 4.0
const KELVIN := 0.354      # tan 19.47 deg
const GRAVITY := 9.81
const U_OUTER := 0.0
const U_EDGE := 0.2
## Vertices across a row: the two outer (feathered) vertices and thirteen from edge to edge (at most about
## 0.8 m apart on a 4 s ribbon), so the ribbon follows the waves between its edges.
const ACROSS := 15

## 0: the bow ribbon (the diverging waves' foam lines, opening at the wake angle); 1: the transom ribbon (the
## turbulent wake, widening slowly). water_render.md §5.
var kind := 0
## the transom ribbon's widening: w = w0·(1 + TURB_SPREAD·t)
const TURB_SPREAD := 0.15
## the bow ribbon's foam lines: LINE_M wide just inside each edge
const LINE_M := 0.3


func set_kind(k: int) -> void:
	kind = k


## Rows, oldest first. Each: {t, p: Vector2, fwd: Vector2, v, w0, ratio, visible, dist, spray: Array}
var rows: Array = []


func emit(t_s: float, p: Vector2, heading: float, v: float, w0: float, ratio: float, visible: bool,
		dist: float) -> Dictionary:
	var row := {
		"t": t_s, "p": p, "fwd": Vector2(sin(heading), cos(heading)), "v": v, "w0": w0, "ratio": ratio,
		"visible": visible, "dist": dist, "spray": [],
	}
	rows.append(row)
	while rows.size() > N_ROWS:
		rows.pop_front()
	return row


## Port unit vector of a row's frozen heading (sea.md §5.2: lx = -fy, ly = fx).
static func port(row: Dictionary) -> Vector2:
	var f: Vector2 = row["fwd"]
	return Vector2(-f.y, f.x)


static func age(row: Dictionary, t_s: float) -> float:
	return t_s - float(row["t"])


## The tangent of the wake's half angle at a speed ratio: Kelvin's 19.47° at low Froude number, falling as 1/Fr
## above (Rabaud and Moisy 2013: α ≈ 0.1995 rad / Fr), with Fr = 0.399·ratio (the hull Froude number).
static func wake_tan(ratio: float) -> float:
	var fr := 0.399 * ratio
	if fr <= 0.1995 / 0.33983:
		return KELVIN
	return tan(0.1995 / fr)


static func half_width(row: Dictionary, t_s: float, k := 0) -> float:
	if k == 1:
		return float(row["w0"]) * (1.0 + TURB_SPREAD * minf(age(row, t_s), LIFE_S))
	return float(row["w0"]) + wake_tan(float(row["ratio"])) * float(row["v"]) * minf(age(row, t_s), SPREAD_S)


static func alpha(row: Dictionary, t_s: float) -> float:
	if not row["visible"]:
		return 0.0
	return clampf(1.0 - age(row, t_s) / LIFE_S, 0.0, 1.0) * minf(1.0, float(row["ratio"]) * 2.0)


## Port and starboard edge points of a row (world x, y).
static func edges(row: Dictionary, t_s: float) -> Array:
	var w := half_width(row, t_s)
	var l := port(row) * w
	return [row["p"] + l, row["p"] - l]


## Launches the two spray particles of a row from its edges: speed k_s * ratio^2 * pulse, direction 0.6 outward
## and 0.8 up, the up part tilted with the heel but kept within 10 deg of the vertical.
func launch_spray(row: Dictionary, speed: float, heel: float, base_z: Array) -> void:
	var e := edges(row, float(row["t"]))
	var lp := port(row)
	var tilt := clampf(heel, deg_to_rad(-10.0), deg_to_rad(10.0))
	for side in 2:
		var out := lp if side == 0 else -lp
		var up := Vector3(lp.x * sin(tilt), lp.y * sin(tilt), cos(tilt))
		var d := Vector3(out.x, out.y, 0.0) * 0.6 + up * 0.8
		var p0: Vector2 = e[side]
		row["spray"].append({"pos": Vector3(p0.x, p0.y, base_z[side]), "vel": d.normalized() * speed, "landed": false})


## Number of rows (the native WakeRibbon's call).
func row_count() -> int:
	return rows.size()


## Edges of the newest row at t_s (the native WakeRibbon's call).
func last_edges(t_s: float) -> Array:
	return edges(rows[-1], t_s) if not rows.is_empty() else []


## launch_spray on the newest row (the native WakeRibbon's call).
func launch_last_spray(speed: float, heel: float, z_port: float, z_stbd: float) -> void:
	if not rows.is_empty():
		launch_spray(rows[-1], speed, heel, [z_port, z_stbd])


## Advances the ribbon to render time t_s: drops rows older than LIFE_S, drifts rows with the current and moves
## the spray. height: Callable(x, y) -> sea height (m); current: Callable(x, y) -> Vector2 (m/s) or null.
func step(t_s: float, dt: float, height: Callable, current = null) -> void:
	while not rows.is_empty() and age(rows[0], t_s) > LIFE_S:
		rows.pop_front()
	for row in rows:
		if current is Callable:
			var c: Vector2 = current.call(row["p"].x, row["p"].y)
			row["p"] += c * dt
			for s in row["spray"]:
				if s["landed"]:
					s["pos"] += Vector3(c.x, c.y, 0.0) * dt
		for s in row["spray"]:
			if s["landed"]:
				continue
			s["vel"].z -= GRAVITY * dt
			s["pos"] += s["vel"] * dt
			var h: float = height.call(s["pos"].x, s["pos"].y)
			if s["pos"].z <= h and s["vel"].z < 0.0:
				s["pos"].z = h
				s["landed"] = true


## Flying spray particle positions (world ENU), for drawing.
func flying_spray() -> PackedVector3Array:
	var out := PackedVector3Array()
	for row in rows:
		for s in row["spray"]:
			if not s["landed"]:
				out.append(s["pos"])
	return out


## Rows smoothed over for the spray reach (either side), so the ribbon's outer edge has no steps.
const REACH_SMOOTH := 4


## How far the spray of a row reaches beyond its feathered edge on each side (m, >= 0): the horizontal distance
## of the row's particles from the row point, flying or landed, so the reach grows smoothly as the spray flies.
static func spray_excess(row: Dictionary, t_s: float) -> Vector2:
	var hw := half_width(row, t_s)
	var base := hw + 0.3 + 0.25 * hw
	var lp := port(row)
	var out := Vector2.ZERO
	var sp: Array = row["spray"]
	for side in mini(sp.size(), 2):
		var q := Vector2(sp[side]["pos"].x, sp[side]["pos"].y)
		var d: float = (q - row["p"]).dot(lp if side == 0 else -lp)
		out[side] = maxf(0.0, d - base)
	return out


## Mesh arrays of the ribbon at t_s, newest row first, ACROSS vertices per row from the outer port vertex to the
## outer starboard one in scene axes with y = 0 (the wake shader drapes it on the sea). UV: (across,
## distance sailed / 10 m); UV2: the row's port direction (world x, y);
## COLOR.r: 1 on the transom ribbon (all of it is the turbulent wake), 0 on the bow ribbon; COLOR.g: the row's age over
## LIFE_S; COLOR.b: the foam line's width over the half width (bow ribbon), 0 on the transom's; COLOR.a: the row alpha. The outer vertices sit a feathered margin
## outside the edges, pushed out by the spray reach smoothed over neighbouring rows (never inside the edge, so
## the strip does not fold, and without steps from row to row).
func build_arrays(t_s: float) -> Array:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := rows.size()
	var excess: Array[Vector2] = []
	excess.resize(n)
	for k in n:
		excess[k] = spray_excess(rows[k], t_s)
	var prev := -1
	for k in range(n - 1, -1, -1):
		var row: Dictionary = rows[k]
		var a := alpha(row, t_s)
		if a <= 0.0:
			prev = -1
			continue
		var hw := half_width(row, t_s, kind)
		var lp := port(row)
		var feather := 0.3 + 0.25 * hw
		# triangular smoothing of the spray reach over the neighbouring rows
		var ex := Vector2.ZERO
		var wsum := 0.0
		for o in range(-REACH_SMOOTH, REACH_SMOOTH + 1):
			var kk := k + o
			if kk < 0 or kk >= n:
				continue
			var w := float(REACH_SMOOTH + 1 - absi(o))
			ex += excess[kk] * w
			wsum += w
		ex /= wsum
		var reach := [hw + feather + ex.x, hw + feather + ex.y]
		var base := verts.size()
		var centre := 1.0 if kind == 1 else 0.0
		var line := 0.0 if kind == 1 else clampf(LINE_M / maxf(hw, 1e-3), 0.0, 1.0)
		var p: Vector2 = row["p"]
		for i in ACROSS:
			var u: float = U_OUTER if i == 0 else (1.0 - U_OUTER if i == ACROSS - 1 else
					U_EDGE + (1.0 - 2.0 * U_EDGE) * float(i - 1) / float(ACROSS - 3))
			var off: float
			if i == 0:
				off = reach[0]
			elif i == ACROSS - 1:
				off = -reach[1]
			else:
				off = hw * (1.0 - 2.0 * float(i - 1) / float(ACROSS - 3))
			var q := p + lp * off
			verts.append(Vector3(q.x, 0.0, -q.y))
			uvs.append(Vector2(u, float(row["dist"]) / 10.0))
			uv2s.append(lp)
			cols.append(Color(centre, clampf(age(row, t_s) / LIFE_S, 0.0, 1.0), line, 0.0 if i == 0 or i == ACROSS - 1 else a))
		if prev >= 0:
			for i in ACROSS - 1:
				idx.append_array([prev + i, base + i, base + i + 1, prev + i, base + i + 1, prev + i + 1])
		prev = base
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays
