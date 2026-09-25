extends SceneTree
## Headless checks of the venue land, the course view, the reset key and race mode (WM-016.21, WM-016.10):
##   - the core's land and obstacles equal the venue file; the drawn land is where the polygons are (ground
##     above the water inside the polygon away from its edge, never above the water outside it; quay and rock
##     on their obstacles)
##   - the camera never inside land: the chase camera orbiting a boat by the island, and the free camera
##   - reset_boat re-places the boat at its start point (free sailing) and restarts the race (race mode)
##   - race mode: marks at the core's course positions riding the sea, committee boat heading, start and finish
##     lines from the race state, flags per signal, laylines per hud.md §6, and a run through every start signal
##   godot --headless --path game -s res://tests/course_land_test.gd

var t := TestLog.new()


func _init() -> void:
	if not t.ok(CoreSimSource.available(), "GDExtension loaded (game/native/build.sh)"):
		t.finish(self, "course land test")
		return
	test_shapes()
	await test_land_scene()
	await test_reset_free()
	await test_race()
	t.finish(self, "course land test")


func _scene(race: bool, x := 0.0, y := -300.0, twa := 45.0) -> Node:
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.sim_kind = sc.SimKind.CORE
	sc.race_mode = race
	sc.core_settings = {"free_sailing_s": 5.0}
	sc.start_x = x
	sc.start_y = y
	sc.start_twa_deg = twa
	root.add_child(sc)
	sc.scripted_input = RawInput.new()
	return sc


func test_shapes() -> void:
	t.begin("venue shapes: core against the file")
	var cs := CoreSimSource.new()
	t.ok(cs.create("example_bay"), "world on example_bay")
	var a := VenueShapes.from_core(cs.core)
	var b := VenueShapes.from_file("example_bay")
	t.ok(a.land.size() == 1 and a.obstacles.size() == 2, "one land polygon, two obstacles")
	var same := a.land.size() == b.land.size() and a.obstacles.size() == b.obstacles.size()
	for i in mini(a.land.size(), b.land.size()):
		same = same and a.land[i]["id"] == b.land[i]["id"]
		var pa: PackedVector2Array = a.land[i]["points"]
		var pb: PackedVector2Array = b.land[i]["points"]
		same = same and pa.size() == pb.size()
		for k in mini(pa.size(), pb.size()):
			same = same and pa[k].distance_to(pb[k]) < 1e-3
	for i in mini(a.obstacles.size(), b.obstacles.size()):
		var oa: Dictionary = a.obstacles[i]
		var ob: Dictionary = b.obstacles[i]
		same = same and oa["id"] == ob["id"] and oa["circle"] == ob["circle"]
		same = same and Vector2(oa["c"]).distance_to(ob["c"]) < 1e-3 and absf(oa["r"] - ob["r"]) < 1e-4
	t.ok(same, "the core's land and obstacles are the venue file's")
	var open := CoreSimSource.new()
	t.ok(open.create("") and VenueShapes.from_core(open.core).is_empty(), "open water: no land")


func test_land_scene() -> void:
	t.begin("land drawn where the core has it")
	var sc := _scene(false, 100.0, 1990.0, -90.0)
	await process_frame
	var v: VenueView = sc.venue_view
	var s: VenueShapes = v.shapes
	t.ok(s.land.size() == 1 and v.parts.has("land_island_n") and v.parts.has("quay_pier")
		and v.parts.has("rock_rock_e"), "land, pier and rock meshes (%s)" % str(v.parts.keys()))
	var inside_ok := 0
	var inside_n := 0
	var outside_bad := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var box := s.land_box(0).grow(60.0)
	for i in 4000:
		var p := box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
		var d := s.land_distance(0, p)
		var g := v.terrain.height(p.x, p.y)
		if d > LandTerrain.SHORE_WOBBLE + 1.0:
			inside_n += 1
			if g > 0.05:
				inside_ok += 1
		elif d < 0.0 and s.obstacle_at(p) < 0 and g > 0.0:
			outside_bad += 1
	t.ok(inside_ok == inside_n and inside_n > 500, "ground above the water inside the polygon (%d/%d)" % [inside_ok, inside_n])
	t.ok(outside_bad == 0, "no ground above the water outside it (%d points)" % outside_bad)
	# the mesh itself: every vertex above the water lies inside the polygon
	var mesh: Mesh = v.parts["land_island_n"].mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bad := 0
	var peak := -INF
	for q in verts:
		var e := Frames.scene_to_enu(q)
		peak = maxf(peak, e.z)
		if e.z > 0.0 and s.land_distance(0, Vector2(e.x, e.y)) < 0.0:
			bad += 1
	t.ok(bad == 0, "land mesh above the water only inside the polygon (%d of %d)" % [bad, verts.size()])
	t.ok(peak > 20.0 and peak < 80.0, "low hills (top %.1f m)" % peak)
	t.ok(v.ground_height(0.0, 2000.0) >= VenueView.QUAY_TOP - 1e-3, "quay deck on the pier polygon")
	t.ok(v.ground_height(420.0, 1950.0) > 2.0 and v.ground_height(420.0 + 6.5, 1950.0) == -INF,
		"rock on its circle, water outside it")
	t.ok(v.ground_height(0.0, -300.0) == -INF, "open water at the start")
	# the camera never inside land: orbit a boat close to the island at every azimuth, low and far
	var rig: CameraRig = sc.rig
	var worst := INF
	var pulled := false
	var dt := 1.0 / 30.0
	for i in 900:
		rig.chase.az = Frames.wrap_pi(i * 0.02)
		rig.chase.R = 400.0
		rig.chase.el = deg_to_rad(2.0)
		sc.step_frame(dt)
		var eye := rig.camera.global_position
		var g := v.ground_height(eye.x, -eye.z)
		if g > -INF:
			worst = minf(worst, eye.y - g)
		pulled = pulled or rig.chase.land.pull > 1.0
		if i % 30 == 0:
			await process_frame
	t.ok(worst > 0.0, "chase eye never below the ground (clearance %.2f m)" % worst)
	t.ok(pulled, "the chase camera was pulled in front of the land")
	# a boat behind the island, a segment through the hill: pulled in to 2 m short of it
	var tg := CamTypes.Target.new()
	tg.ground = v.ground_height
	var from := Frames.enu_to_scene(0.0, 1900.0, 2.0)
	var to := Frames.enu_to_scene(0.0, 2600.0, 10.0)
	var hit := tg.land_hit(from, to)
	var la := CamTypes.LandAvoid.new()
	var eye2 := la.apply(to, from, tg, dt)
	t.ok(hit < INF and absf(from.distance_to(eye2) - (hit - 2.0)) < 0.05, "eye 2 m short of the crossing")
	for i in 120:
		la.apply(Frames.enu_to_scene(0.0, 1800.0, 10.0), from, tg, dt)
	t.ok(la.pull < 0.05, "eased back out when clear (pull %.3f m)" % la.pull)
	# free camera: flown down into the hill it stays above ground
	rig.select_mode(CameraRig.Mode.FREE, sc.target)
	rig.free.pos = Frames.enu_to_scene(30.0, 2400.0, 5.0)
	sc.step_frame(dt)
	var fe := rig.camera.global_position
	t.ok(fe.y >= v.ground_height(fe.x, -fe.z) + 0.99, "free camera above the ground")
	sc.queue_free()
	await process_frame


func test_reset_free() -> void:
	t.begin("reset key, free sailing")
	var sc := _scene(false)
	await process_frame
	var sim: CoreSimSource = sc.sim
	var r: RawInput = sc.scripted_input
	for i in 200:
		sc.step_frame(0.1)
	var s0 := sim.state(0)
	t.ok(Vector2(s0.pos_x, s0.pos_y).distance_to(Vector2(0, -300)) > 20.0, "boat sailed away (%.0f m)"
		% Vector2(s0.pos_x, s0.pos_y).distance_to(Vector2(0, -300)))
	r.pressed.clear()
	r.pressed.append(&"reset_boat")
	sc.step_frame(0.0)
	r.pressed.clear()
	var s1 := sim.state(0)
	t.ok(Vector2(s1.pos_x, s1.pos_y).distance_to(Vector2(0, -300)) < 1e-3, "re-placed at the start point")
	t.ok(absf(Frames.angle_diff(s1.psi, sc._start_psi())) < 1e-4 and s1.v > 1.0, "on the start heading, sailing")
	t.ok(sc.controls.h_cmd == 0.0, "helm centred")
	var eye: Vector3 = sc.rig.camera.global_position
	t.ok(eye.distance_to(Frames.enu_to_scene(0, -300, 0)) < 80.0, "camera cut to the boat")
	sc.step_frame(0.1)
	t.ok(sim.state(0).v > 1.0, "sails on after the reset")
	sc.queue_free()
	await process_frame
	# FakeSim too
	var fs := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	fs.auto_process = false
	fs.sim_kind = fs.SimKind.FAKE
	root.add_child(fs)
	fs.scripted_input = RawInput.new()
	await process_frame
	for i in 100:
		fs.step_frame(0.1)
	fs.scripted_input.pressed.append(&"reset_boat")
	fs.step_frame(0.0)
	var fst: SimSource.BoatState = fs.sim.state(0) as SimSource.BoatState
	t.ok(Vector2(fst.pos_x, fst.pos_y).length() < 1e-3, "FakeSim: re-placed at the start point")
	t.ok(fs.venue_view.parts.has("land_island_n"), "FakeSim: land drawn from the venue file")
	fs.queue_free()
	await process_frame


func test_race() -> void:
	t.begin("race mode")
	var sc := _scene(true)
	await process_frame
	var sim: CoreSimSource = sc.sim
	var cv: CourseView = sc.course_view
	if not t.ok(sim.core.has_race() and cv != null, "a race on example_wl with the course drawn"):
		return
	t.ok(sim.boat_count() == 1 and sim.class_info(0).id == "wm7", "the player's wm7 alone")
	var course: Dictionary = sim.core.course()
	var pos_ok := true
	var n_drawn := 0
	for m in course["marks"]:
		var node := cv.mark_node(m["id"])
		if int(m["type"]) == CourseView.MARK_VIRTUAL:
			pos_ok = pos_ok and node == null
			continue
		n_drawn += 1
		var p := Frames.scene_to_enu(node.global_position)
		pos_ok = pos_ok and Vector2(p.x, p.y).distance_to(Vector2(m["x"], m["y"])) < 1e-3
	t.ok(pos_ok and n_drawn == 8, "8 marks drawn at the core's positions, virtual ones not (%d)" % n_drawn)
	var rc := cv.mark_node("rc")
	var hd: float = course["marks"][0]["heading"]
	var bow := -rc.global_basis.z
	t.ok(absf(Frames.angle_diff(Frames.compass(bow.x, -bow.z), hd)) < 0.1, "committee boat on its resolved heading")
	var ol := CourseProps.outline(14.0, 4.5)
	t.ok(ol.size() == 17 and absf(ol[8].x - 7.0) < 1e-4 and absf(ol[0].y + 1.8) < 1e-4, "17-point outline")
	# run through the sequence with the pilot
	var r: RawInput = sc.scripted_input
	var dt := 0.1
	var seen := {}
	var bob_min := INF
	var bob_max := -INF
	var line_ok := true
	var flags_ok := true
	var layline_ok := true
	var laylines_seen := false
	var started_seen := false
	var green_seen := false
	var white_seen := false
	var w_node := cv.mark_node("w")
	sc.runner.ticked.connect(func(_n: int) -> void:
		for e in sc.sim.core.race_events():
			if int(e["kind"]) == 0:
				seen[int(e["signal"])] = true)
	var w_pos: Vector2 = cv.marks[2]["pos"]
	for i in 3300:
		CoursePilot.steer(sc)
		sc.step_frame(dt)
		var h := w_node.global_position.y
		bob_min = minf(bob_min, h)
		bob_max = maxf(bob_max, h)
		var sea_h: float = sc.sea.height_at(w_pos.x, w_pos.y)
		line_ok = line_ok and absf(h - cv.marks[2]["heave"]) < 1e-5 and absf(h - sea_h) < 0.3
		var race: Dictionary = sim.core.race()
		var rb: Dictionary = sim.core.race_boat(0)
		var st: int = race["state"]
		var tr: float = race["race_time"]
		var want := "hidden"
		if st == CourseView.RACE_SEQUENCE:
			want = "red" if tr >= -60.0 and cv.is_over(sc.target.pose) else "white"
		elif st >= CourseView.RACE_RACING and not rb["started"]:
			want = "green"
		line_ok = line_ok and cv.start_line_state == want
		white_seen = white_seen or cv.start_line_state == "white"
		green_seen = green_seen or cv.start_line_state == "green"
		var start_drawn := false
		for l in cv.lines:
			if l["kind"] == "start":
				start_drawn = true
				var ends := cv.step_points(0)
				line_ok = line_ok and ((l["a"] == ends[0] and l["b"] == ends[1]) or (l["a"] == ends[1] and l["b"] == ends[0]))
		line_ok = line_ok and start_drawn == (want != "hidden")
		var tw := cv.warning_time()
		var class_up: bool = st == CourseView.RACE_SEQUENCE and tr >= -tw and tr < 0.0
		flags_ok = flags_ok and cv.flags_up.get(CourseProps.Flag.CLASS, false) == class_up
		flags_ok = flags_ok and cv.flags_up.get(CourseProps.Flag.I, false) == (st == CourseView.RACE_SEQUENCE and tr >= -(tw - 60.0) and tr < -60.0)
		if rb["started"]:
			started_seen = true
		if not cv.laylines.is_empty():
			laylines_seen = true
			var vmg: Dictionary = sim.core.polar_vmg(0, cv._tws)
			for l in cv.laylines:
				var d: Vector2 = l["a"] - l["b"]
				var cog := Frames.compass(d.x, d.y)
				var th: float = vmg["up_twa"] if cv.leg == "beat" else vmg["down_twa"]
				var psi := Frames.wrap_2pi(cv.twd() - l["tack"] * th)
				layline_ok = layline_ok and absf(Frames.angle_diff(cog, psi)) < deg_to_rad(8.0)
				layline_ok = layline_ok and d.length() >= 1.2 * 500.0 - 1.0
			var cnt := 0
			for l in cv.lines:
				if l["kind"] == "layline":
					cnt += 1
					layline_ok = layline_ok and l["color"] == (CourseView.COL_GREEN if l["tack"] > 0 else CourseView.COL_RED)
			layline_ok = layline_ok and cnt == cv.laylines.size() and cv.lines.size() <= 8
		if i % 100 == 0:
			await process_frame
		if started_seen and laylines_seen and cv.race_time() > 60.0:
			break
	t.ok(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "warning, prep up, one minute and start signals (%s)" % str(seen.keys()))
	t.ok(white_seen and green_seen and line_ok, "start line drawn per the race state (white %s, green %s)" % [white_seen, green_seen])
	t.ok(flags_ok, "class and I flags up in their windows")
	t.ok(bob_max - bob_min > 0.02, "the windward mark rides the sea (%.2f m)" % (bob_max - bob_min))
	t.ok(started_seen, "the boat started")
	t.ok(laylines_seen and layline_ok, "laylines at the polar VMG angles of the smoothed wind, red port, green starboard")
	var txt: String = sc._race_label.text
	t.ok(txt.contains("Next: Windward"), "race status names the next mark (%s)" % txt.replace("\n", " | "))
	# reset restarts the race
	r.pressed.clear()
	r.pressed.append(&"reset_boat")
	sc.step_frame(0.0)
	r.pressed.clear()
	var race2: Dictionary = sc.sim.core.race()
	t.ok(sc.sim != sim and int(race2["state"]) <= CourseView.RACE_FREE and sc.course_view != cv,
		"reset restarts the race (state %d)" % race2["state"])
	sc.step_frame(0.1)
	sc.queue_free()
	await process_frame
