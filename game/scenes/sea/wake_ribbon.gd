class_name WakeRibbon
extends RefCounted
## One wake ribbon (water_render.md §5): rows laid down behind the bow (or the transom) every 50 ms of render
## time, left where they were laid, opening at the Kelvin angle and fading over 4 s. Rows optionally launch two
## spray particles that fly under gravity, stick where they reach the surface and become the ribbon's outer
## vertices. World coordinates are ENU metres (x east, y north, z up); heights come from a callable.

const N_ROWS := 80
const LIFE_S := 4.0
const KELVIN := 0.354      # tan 19.47 deg
const GRAVITY := 9.81
const U_OUTER := 0.0
const U_EDGE := 0.2
## Vertices across a row: the two outer (feathered) vertices and seven from edge to edge, so the ribbon follows
## the waves between its edges.
const ACROSS := 9

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


static func half_width(row: Dictionary, t_s: float) -> float:
	return float(row["w0"]) + KELVIN * float(row["v"]) * age(row, t_s)


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


## Advances the ribbon to render time t_s: drops rows older than 4 s, drifts rows with the current and moves
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


## Mesh arrays of the ribbon at t_s, newest row first, ACROSS vertices per row from the outer port vertex to the
## outer starboard one in scene axes with y = 0 (the wake shader drapes it on the sea). UV: (across,
## distance sailed / 10 m); UV2: the row's port direction (world x, y); COLOR.r: the bow half width as a
## fraction of the ribbon's (the centre wake); COLOR.a: the row alpha.
func build_arrays(t_s: float) -> Array:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var prev := -1
	for k in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[k]
		var a := alpha(row, t_s)
		if a <= 0.0:
			prev = -1
			continue
		var hw := half_width(row, t_s)
		var lp := port(row)
		# outer vertices: a feathered margin outside the edges, pushed out to where the row's spray landed
		# when that is further (never inside the edge, so the strip does not fold)
		var feather := 0.3 + 0.25 * hw
		var reach := [hw + feather, hw + feather]
		var sp: Array = row["spray"]
		for side in sp.size():
			if sp[side]["landed"]:
				var q := Vector2(sp[side]["pos"].x, sp[side]["pos"].y)
				var d: float = (q - row["p"]).dot(lp if side == 0 else -lp)
				reach[side] = maxf(reach[side], d)
		var base := verts.size()
		var centre := clampf(float(row["w0"]) / maxf(hw + feather, 1e-3), 0.0, 1.0)
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
			cols.append(Color(centre, 1, 1, 0.0 if i == 0 or i == ACROSS - 1 else a))
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
