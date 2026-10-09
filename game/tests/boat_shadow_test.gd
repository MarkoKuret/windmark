extends SceneTree
## Drawn boat shadows on the water (water_render.md §4.7, test §9.10), headless: a race of three wm7 on the core in
## the sail scene. On tier M the own boat's drawn shadow lies on the water, points away from the sun and covers the
## projected silhouette of the drawn hull, rig and sails; the others get one within the shadow distance; tier L
## draws the own boat's only, tier H none (the sea takes real shadows there). The native BoatShadowShape against
## the GDScript reference, and the cost per boat. The sun shadow casters on every tier (sail_visuals.md §11.4): no
## shadow proxy is ever drawn in the colour pass, the drawn meshes cast none, a boat casts (proxies shown, sails on)
## only within the tier's cast distance (the own boat always) and while "Boat sun shadows" is on, and turning it off
## and on again puts every caster back.
##   godot --headless --path game -s res://tests/boat_shadow_test.gd

const CELL := 0.1
const IOU_MIN := 0.75

var t := TestLog.new()
var sc: Node


func _init() -> void:
	if not CoreSimSource.available():
		print("boat shadows: the GDExtension is not built (game/native/build.sh); skipped")
		t.finish(self, "boat shadows")
		return
	await process_frame
	sc = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.sim_kind = sc.SimKind.CORE
	sc.race_mode = true
	sc.fleet_size = 3
	sc.sea_quality = SeaQuality.Tier.M
	sc.with_pause_menu = false
	sc.apply_settings = false
	sc.auto_process = false
	root.add_child(sc)
	await process_frame
	sc.scripted_input = RawInput.new()
	await _run(90)
	await check_tier_m()
	await check_native()
	await check_sun_casters("M")
	sc.sea.quality = SeaQuality.Tier.L
	await _run(3)
	check_tier_l()
	await check_sun_casters("L")
	sc.sea.quality = SeaQuality.Tier.H
	await _run(3)
	check_tier_h()
	await check_sun_casters("H")
	sc.queue_free()
	await process_frame
	t.finish(self, "boat shadows")


func _run(frames: int) -> void:
	for i in frames:
		sc.step_frame(1.0 / 60.0)
		await process_frame


func check_tier_m() -> void:
	t.begin("tier M: the own boat's drawn shadow")
	var shadows: BoatShadows = sc.shadows
	var own: int = sc.runner.boat
	var d := shadows.shadow_of(own)
	t.ok(not d.is_empty(), "the own boat has a drawn shadow")
	if d.is_empty():
		return
	var mi := shadows.shadow_node(own)
	t.ok(mi.visible and (mi.material_override as ShaderMaterial).shader == BoatShadows.SHADER
			and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "drawn with the boat shadow shader, casting none")
	t.ok(int(d["n_poly"]) >= 3, "hull, mast and at least one sail: %d polygons" % d["n_poly"])
	# on the water: the plane at the boat's heave, near the sea height there; the grid on that plane
	var o: Vector3 = d["origin"]
	var eta: float = sc.sea.height_at(o.x, -o.z)
	t.near(o.y, eta, 0.3, "the shadow's plane at the heave lies on the sea (height there)")
	var rect: Transform3D = d["rect"]
	t.near(rect.origin.y, o.y, 1e-4, "the grid lies on that plane")
	t.ok(rect.basis.y.is_equal_approx(Vector3.UP), "the grid is level (the drape follows the waves)")
	# away from the sun: the centroid of the coverage against the sun's bearing
	var sun: Vector3 = d["sun"]
	var grid := _cells(d)
	var c := Vector2.ZERO
	var n := 0
	var ours := {}
	for k in grid:
		var p: Vector3 = grid[k]
		if BoatShadows.coverage(d, p) > 0.5:
			ours[k] = true
			c += Vector2(p.x - o.x, p.z - o.z)
			n += 1
	c /= maxf(n, 1)
	var away := -c.dot(Vector2(sun.x, sun.z).normalized())
	t.ok(away > 1.0, "the shadow lies away from the sun: centroid %.2f m from the boat against the sun" % away)
	# the projected silhouette of the drawn boat: hull, rig and sails above the water, along the sun onto the plane,
	# outside the hull's plan
	var tri := _boat_triangles(sc.boat_view)
	var ref := {}
	var plan := {}
	var kx := sun.x / sun.y
	var kz := sun.z / sun.y
	for tr in tri["above"]:
		var q := PackedVector2Array()
		for p: Vector3 in tr:
			q.append(Vector2(p.x - kx * (p.y - o.y), p.z - kz * (p.y - o.y)))
		_raster(q, ref)
	for tr in tri["hull"]:
		_raster(PackedVector2Array([Vector2(tr[0].x, tr[0].z), Vector2(tr[1].x, tr[1].z), Vector2(tr[2].x, tr[2].z)]),
				plan)
	var n_ref := 0
	var n_ours := 0
	var both := 0
	var either := 0
	var seen := {}
	for k in ref.keys() + ours.keys():
		if plan.has(k) or seen.has(k):
			continue
		seen[k] = true
		n_ref += 1 if ref.has(k) else 0
		n_ours += 1 if ours.has(k) else 0
		both += 1 if ref.has(k) and ours.has(k) else 0
		either += 1
	var iou := float(both) / maxf(either, 1.0)
	print("  own boat: %d polygons, plane %.3f m (sea %.3f m), %.2f m from the boat against the sun, IoU %.2f (%.1f m2 drawn, %.1f m2 silhouette)" % [d["n_poly"], o.y, eta, away, iou, n_ours * CELL * CELL, n_ref * CELL * CELL])
	t.ok(iou >= IOU_MIN, "covers the projected hull, rig and sails: intersection over union %.2f (%.1f m2 drawn, %.1f m2 silhouette)"
			% [iou, n_ours * CELL * CELL, n_ref * CELL * CELL])
	# the other boats within the shadow distance get one too
	var cam: Vector3 = sc.rig.camera.global_position
	var near_others := 0
	var drawn_others := 0
	for b in sc.sim.boat_count():
		if b == own:
			continue
		if sc.boat_views[b].global_position.distance_to(cam) < 0.8 * 100.0:
			near_others += 1
			if not shadows.shadow_of(b).is_empty():
				drawn_others += 1
	t.ok(drawn_others == near_others, "the other boats within the shadow distance: %d of %d drawn" % [drawn_others, near_others])


## The water cells of the shadow's rectangle (10 cm), on the plane: key Vector2i -> scene point.
func _cells(d: Dictionary) -> Dictionary:
	var rect: Transform3D = d["rect"]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for u in [0.0, 1.0]:
		for v in [0.0, 1.0]:
			var p: Vector3 = rect * Vector3(u, 0.0, v)
			lo = lo.min(p)
			hi = hi.max(p)
	var out := {}
	var y: float = (d["origin"] as Vector3).y
	for i in range(floori(lo.x / CELL), ceili(hi.x / CELL)):
		for j in range(floori(lo.z / CELL), ceili(hi.z / CELL)):
			out[Vector2i(i, j)] = Vector3((i + 0.5) * CELL, y, (j + 0.5) * CELL)
	return out


## Marks the 10 cm cells whose centres lie in a triangle (scene x, z).
func _raster(q: PackedVector2Array, out: Dictionary) -> void:
	var lo := q[0].min(q[1]).min(q[2])
	var hi := q[0].max(q[1]).max(q[2])
	var a := q[0]
	var e1 := q[1] - a
	var e2 := q[2] - a
	var det := e1.x * e2.y - e1.y * e2.x
	if absf(det) < 1e-9:
		return
	for i in range(floori(lo.x / CELL), ceili(hi.x / CELL)):
		for j in range(floori(lo.y / CELL), ceili(hi.y / CELL)):
			var p := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL) - a
			var s := (p.x * e2.y - p.y * e2.x) / det
			var r := (e1.x * p.y - e1.y * p.x) / det
			if s >= 0.0 and r >= 0.0 and s + r <= 1.0:
				out[Vector2i(i, j)] = true


## The drawn boat's triangles in the scene: {above: every triangle with a corner above the plane (hull, rig and the
## sails as their shapes place them), hull: the hull's own (its plan)}.
func _boat_triangles(v: BoatView) -> Dictionary:
	var y0 := v.global_position.y
	var above := []
	var hull := []
	var sail_nodes := {}
	for sp in v.sail_parts:
		sail_nodes[sp.node] = sp
	for n in v.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null \
				or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var xf := mi.global_transform
		var is_sail := sail_nodes.has(mi)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if is_sail and sail_nodes[mi].shape != null:
				pos = sail_nodes[mi].shape.positions()  # headless keeps no in-place mesh updates
			pos = xf * pos
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := idx.size() if idx.size() > 0 else pos.size()
			for k in range(0, count - 2, 3):
				var a := pos[idx[k]] if idx.size() > 0 else pos[k]
				var b := pos[idx[k + 1]] if idx.size() > 0 else pos[k + 1]
				var c := pos[idx[k + 2]] if idx.size() > 0 else pos[k + 2]
				if maxf(a.y, maxf(b.y, c.y)) > y0:
					above.append([a, b, c])
				if not is_sail and minf(a.y, minf(b.y, c.y)) < y0 + 1.0:
					hull.append([a, b, c])
	return {"above": above, "hull": hull}


func check_native() -> void:
	t.begin("native geometry against the GDScript reference, cost")
	var shadows: BoatShadows = sc.shadows
	t.ok(shadows.is_native(), "BoatShadows builds natively")
	var st: Dictionary = sc.boat_view.shadow_state(true)
	var sun: Vector3 = (sc.sky as SkyRig).sun_direction()
	var shape: Object = ClassDB.instantiate("BoatShadowShape")
	shape.configure(st["caster"])
	var dn: Dictionary = shape.build(st["xform"], sun, st["sails"], st["sail_counts"])
	var dr := BoatShadows.build(st["caster"], st["xform"], sun, st["sails"], st["sail_counts"])
	t.ok(dn["n_poly"] == dr["n_poly"] and dn["n_excl"] == dr["n_excl"] and dn["corner_end"] == dr["corner_end"],
			"same polygons: %d, footprint %d edges" % [dn["n_poly"], dn["n_excl"]])
	var worst := 0.0
	var pn: PackedVector2Array = dn["corners"]
	var pr: PackedVector2Array = dr["corners"]
	for k in mini(pn.size(), pr.size()):
		worst = maxf(worst, pn[k].distance_to(pr[k]))
	var rn: Transform3D = dn["rect"]
	var rr: Transform3D = dr["rect"]
	for u in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]:
		worst = maxf(worst, (rn * u).distance_to(rr * u))
	t.ok(worst <= 1e-4, "corners and grid rectangle within 1e-4 m (worst %s m)" % String.num_scientific(worst))
	var o: Vector3 = dr["origin"]
	var cov := 0.0
	for k in 2000:
		var p := o + Vector3(randf_range(-20.0, 20.0), randf_range(-0.5, 0.5), randf_range(-20.0, 20.0))
		cov = maxf(cov, absf(BoatShadows.coverage(dn, p) - BoatShadows.coverage(dr, p)))
	t.ok(cov <= 1e-3, "coverage within 1e-3 at 2000 points (worst %s)" % String.num_scientific(cov))
	# cost per boat (the best of five batches, headless timings jitter): the state (BoatView.shadow_state), the
	# polygons, and a whole frame of BoatShadows
	var us_state := _best(func() -> void: sc.boat_view.shadow_state(true), 200)
	var us_native := _best(func() -> void: shape.build_row(st["xform"], sun, st["sails"], st["sail_counts"], 1.0), 200)
	var us_ref := _best(func() -> void: BoatShadows.build(st["caster"], st["xform"], sun, st["sails"], st["sail_counts"]), 20)
	var drawn := 0
	for b in sc.sim.boat_count():
		drawn += 0 if shadows.shadow_of(b).is_empty() else 1
	var us_frame := _best(func() -> void: shadows._frame(), 200)
	var per_boat := us_state + us_frame / maxf(drawn, 1)
	print("  cost per boat: state %.1f us, native polygons %.1f us (GDScript reference %.1f us), frame %.1f us for %d boats"
			% [us_state, us_native, us_ref, us_frame, drawn])
	print("  about %.0f us per boat: %.2f ms for 10 boats" % [per_boat, per_boat * 10.0 / 1000.0])
	t.ok(per_boat * 10.0 < 300.0, "10 boats well under 0.3 ms of CPU: %.2f ms" % (per_boat * 10.0 / 1000.0))


## µs per call, the best of five batches of n.
func _best(f: Callable, n: int) -> float:
	var best := INF
	for batch in 5:
		var t0 := Time.get_ticks_usec()
		for k in n:
			f.call()
		best = minf(best, float(Time.get_ticks_usec() - t0) / n)
	return best




func check_tier_l() -> void:
	t.begin("tier L: the own boat's only")
	var shadows: BoatShadows = sc.shadows
	var own: int = sc.runner.boat
	var others := 0
	for b in sc.sim.boat_count():
		if b != own and not shadows.shadow_of(b).is_empty():
			others += 1
	t.ok(not shadows.shadow_of(own).is_empty() and others == 0, "own boat drawn, %d others" % others)


func check_tier_h() -> void:
	t.begin("tier H: real shadows, none drawn")
	var shadows: BoatShadows = sc.shadows
	var any := 0
	for b in sc.sim.boat_count():
		if not shadows.shadow_of(b).is_empty() or shadows.shadow_node(b).visible:
			any += 1
	t.ok(any == 0, "no drawn shadows (%d)" % any)
	t.ok(not (sc.sea.material.shader as Shader).code.contains("WM_NO_SHADOWS"), "the sea takes the real shadows")


func check_sun_casters(tier: String) -> void:
	t.begin("tier %s: sun shadow casters" % tier)
	var cd := BoatView.cast_distance
	var cam: Vector3 = sc.rig.camera.global_position
	# as the scene left them: each boat casts by its distance from the camera
	var bad := 0
	for v: BoatView in sc.boat_views:
		var d := v.global_position.distance_to(cam)
		if cd > 0.0 and absf(d - cd) < 2.0:
			continue  # at the threshold the frame's camera may differ from this one
		bad += 0 if _casts_as(v, v.own or cd <= 0.0 or d <= cd) else 1
	t.ok(bad == 0, "every boat casts by its distance (cast distance %.0f m): %d wrong" % [cd, bad])
	t.ok(_colour_pass_proxies() == 0, "no proxy drawn in the colour pass")
	var before := _caster_state()
	# near and far, the own boat and another
	var other: BoatView = null
	for v: BoatView in sc.boat_views:
		if not v.own:
			other = v
	other.update_lod(5.0)
	t.ok(_casts_as(other, true), "another boat 5 m from the camera casts")
	other.update_lod(1000.0)
	t.ok(_casts_as(other, cd <= 0.0), "another boat 1 km from the camera: %s" % ("casts" if cd <= 0.0 else "casts none"))
	sc.boat_view.update_lod(1000.0)
	t.ok(_casts_as(sc.boat_view, true), "the own boat casts at any distance")
	t.ok(_colour_pass_proxies() == 0, "near and far: no proxy drawn in the colour pass")
	# the look panel's Boat sun shadows: off, a near and far switch while off, on
	DevLook.set_boat_shadows(sc, false)
	var off := 0
	for v: BoatView in sc.boat_views:
		off += 1 if _casts_as(v, false) else 0
	other.update_lod(5.0)
	other.update_lod(1000.0)
	other.update_lod(5.0)
	t.ok(off == sc.boat_views.size() and _casts_as(other, false), "sun shadows off: no boat casts, near or far")
	t.ok(_colour_pass_proxies() == 0, "sun shadows off: no proxy drawn in the colour pass")
	DevLook.set_boat_shadows(sc, true)
	await _run(1)
	t.ok(_caster_state() == before, "sun shadows on again: every caster's setting and visibility as before")
	t.ok(_colour_pass_proxies() == 0, "sun shadows on again: no proxy drawn in the colour pass")


## The boat's casters as a casting (`on`) or not-casting boat: proxies shadows-only and shown (hidden), sails ON
## (OFF), every other surface OFF.
func _casts_as(v: BoatView, on: bool) -> bool:
	var sails := {}
	for sp in v.sail_parts:
		sails[sp.node] = true
	var proxies := 0
	for g in v.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if String(gi.name).begins_with("shadow"):
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				return false
			if v.shadow_proxies().has(gi) and v.levels[v.lod]["proxies"].has(gi):
				proxies += 1
				if gi.visible != on:
					return false
			elif gi.visible:
				return false  # a level not shown
		elif sails.has(gi):
			if gi.cast_shadow != (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF):
				return false
		elif gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
	return proxies >= 2  # the static proxy and the boom's at least


func _colour_pass_proxies() -> int:
	var n := 0
	for v: BoatView in sc.boat_views:
		for g in v.find_children("shadow*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if gi.is_visible_in_tree() and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				n += 1
	return n


func _caster_state() -> Dictionary:
	var d := {}
	for v: BoatView in sc.boat_views:
		for g in v.find_children("*", "GeometryInstance3D", true, false):
			d[g.get_instance_id()] = [(g as GeometryInstance3D).cast_shadow, (g as GeometryInstance3D).visible]
	return d
