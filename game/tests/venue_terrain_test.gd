extends SceneTree
## Headless checks of a real venue's drawn terrain (WM-106, venues.md §4.2, data_format.md §6.10) on Lake Garda:
##   - the terrain file loads: at most 4 chunks and the ridge, the triangle caps, the load time
##   - in the scene on the core (race mode on garda/garda_wl): the terrain parts on one shared land material,
##     the draw estimate, the shadow casters per tier (2 on M, none on L), no per-polygon land, no props
##   - the ground the cameras read: open water at the course, land above the water inland of the core's polygons
##     and not above it offshore, the chase camera above the ground
##   - cost against practice_waters: scene build, frame (headless, no GPU) and core tick with 10 boats
##   godot --headless --path game -s res://tests/venue_terrain_test.gd

var t := TestLog.new()


func _init() -> void:
	if not t.ok(CoreSimSource.available(), "GDExtension loaded (game/native/build.sh)"):
		t.finish(self, "venue terrain test")
		return
	test_file()
	await test_scene()
	await test_cost()
	t.finish(self, "venue terrain test")


func _scene(venue: String, course: String, fleet := 1, wind_from := 0.0) -> Node:
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.sim_kind = sc.SimKind.CORE
	sc.venue = venue
	sc.course = course
	sc.race_mode = true
	sc.fleet_size = fleet
	sc.wind_from_deg = wind_from
	sc.core_settings = {"free_sailing_s": 5.0}
	root.add_child(sc)
	sc.scripted_input = RawInput.new()
	return sc


func test_file() -> void:
	t.begin("terrain file")
	t.ok(VenueTerrain.load_venue("practice_waters") == null, "practice_waters: no terrain file (drawn from its polygons)")
	var t0 := Time.get_ticks_usec()
	var tr := VenueTerrain.load_venue("garda")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not t.ok(tr != null, "garda terrain loads"):
		return
	var ridge := 0
	var n := 0
	for c in tr.chunks:
		if c["id"] == "ridge":
			ridge = c["triangles"]
		else:
			n += 1
	print("  garda terrain: %d chunks, %d triangles, %d vertices, ridge %d triangles, loaded in %.0f ms"
		% [n, tr.triangles, tr.vertices, ridge, ms])
	t.ok(n <= 4, "at most 4 terrain chunks (%d)" % n)
	t.ok(tr.triangles + ridge <= 120000, "at most 120k triangles with the ridge (%d)" % (tr.triangles + ridge))
	t.ok(ridge > 0 and ridge <= 10000, "horizon ridge at most 10k triangles (%d)" % ridge)
	t.ok(ms < 1000.0, "loads in under a second (%.0f ms)" % ms)


func test_scene() -> void:
	t.begin("garda in the scene")
	var t0 := Time.get_ticks_usec()
	var sc := _scene("garda", "garda/garda_wl", 1, 195.0)
	await process_frame
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sim: CoreSimSource = sc.sim
	if not t.ok(sim.core.has_race(), "a race on garda_wl"):
		return
	var v: VenueView = sc.venue_view
	t.ok(v.venue_terrain != null, "the venue's terrain drawn")
	var meshes := 0
	var mats := {}
	var casters := 0
	var others := []
	for n in v.parts:
		var mi: MeshInstance3D = v.parts[n]
		if String(n).begins_with("terrain_"):
			meshes += mi.mesh.get_surface_count()
			mats[mi.material_override] = true
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
		else:
			others.append(n)
	print("  garda scene: built in %.0f ms; venue draws %d (main pass), shadow casters %d, materials %d"
		% [build_ms, meshes, casters, mats.size()])
	t.ok(meshes <= 8 and meshes >= 2, "venue draws within 8 (%d)" % meshes)
	t.ok(mats.size() == 1, "one shared land material")
	t.ok(others.is_empty(), "no per-polygon land, trees or props (%s)" % [others])
	t.ok(casters == 2, "2 shadow casters on M (%d)" % casters)
	v.apply_quality(SeaQuality.Tier.L)
	var cl := 0
	for n in v.parts:
		if (v.parts[n] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			cl += 1
	t.ok(cl == 0, "no shadow casters on L (%d)" % cl)
	v.apply_quality(SeaQuality.Tier.M)
	# the ground the cameras read against the core's polygons
	var course: Dictionary = sim.core.course()
	var water_ok := true
	for m in course["marks"]:
		water_ok = water_ok and v.ground_height(m["x"], m["y"]) == -INF
	t.ok(water_ok, "open water at every mark")
	var shapes := VenueShapes.from_core(sim.core)
	var bounds := Rect2(-1800, -2400, 3700, 5000)
	var inland_ok := 0
	var off_ok := 0
	var tried := 0
	for i in shapes.land.size():
		var pts: PackedVector2Array = shapes.land[i]["points"]
		for k in pts.size():
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			var mid := (a + b) * 0.5
			if not bounds.has_point(mid) or a.distance_to(b) < 30.0:
				continue
			var out := Vector2((b - a).y, -(b - a).x).normalized()  # land on the left: outward to the right
			var p_in := mid - out * 15.0
			var p_out := mid + out * 15.0
			# away from narrow spits and inlets: the probes are clearly on their side (the ground grid is 10 m)
			if shapes.land_distance(i, p_in) < 10.0 or _land_distance(shapes, p_out) > -10.0:
				continue
			tried += 1
			if v.ground_height(p_in.x, p_in.y) > 0.0:
				inland_ok += 1
			if v.ground_height(p_out.x, p_out.y) <= 0.0:
				off_ok += 1
	t.ok(tried > 20 and inland_ok == tried and off_ok == tried,
		"ground above the water 15 m inland of the core's shore, not 15 m off it (%d, %d of %d)"
		% [inland_ok, off_ok, tried])
	for i in 120:
		CoursePilot.steer(sc)
		sc.step_frame(0.1)
	var eye: Vector3 = sc.rig.camera.global_position
	t.ok(eye.y >= v.ground_height(eye.x, -eye.z), "chase camera above the ground")
	sc.queue_free()
	await process_frame


func _land_distance(s: VenueShapes, p: Vector2) -> float:
	var best := -INF
	for i in s.land.size():
		best = maxf(best, s.land_distance(i, p))
	return best


func _cost(venue: String, course: String, wind_from: float) -> Array:
	var t0 := Time.get_ticks_usec()
	var sc := _scene(venue, course, 10, wind_from)
	await process_frame
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var dt := 1.0 / 60.0
	for i in 60:
		sc.step_frame(dt)
	var n := 600
	var t1 := Time.get_ticks_usec()
	for i in n:
		CoursePilot.steer(sc)
		sc.step_frame(dt)
	var frame_us := float(Time.get_ticks_usec() - t1) / n
	var sim: CoreSimSource = sc.sim
	var t2 := Time.get_ticks_usec()
	for i in 400:
		sim.core.step()
	var step_us := float(Time.get_ticks_usec() - t2) / 400.0
	sc.queue_free()
	await process_frame
	return [build_ms, frame_us, step_us]


func test_cost() -> void:
	t.begin("cost against practice_waters, 10 boats")
	var a: Array = await _cost("practice_waters", "practice_waters/example_wl", 0.0)
	var b: Array = await _cost("garda", "garda/garda_wl", 195.0)
	print("  practice_waters: scene %.0f ms, frame %.2f ms (headless), core tick %.3f ms" % [a[0], a[1] / 1000.0, a[2] / 1000.0])
	print("  garda:       scene %.0f ms, frame %.2f ms (headless), core tick %.3f ms" % [b[0], b[1] / 1000.0, b[2] / 1000.0])
	t.ok(b[1] < 16000.0, "garda frame under 16 ms headless (%.2f ms)" % (b[1] / 1000.0))
	t.ok(b[2] < a[2] * 1.25 + 50.0, "core tick within the example's (%.3f against %.3f ms)" % [b[2] / 1000.0, a[2] / 1000.0])
