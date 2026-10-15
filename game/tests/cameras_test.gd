extends SceneTree
## cameras.md §10 tests (headless), plus the free camera, near planes and the smooth switch.
##   godot --headless --path game -s res://tests/cameras_test.gd

var t := TestLog.new()


func _init() -> void:
	test_chase_geometry()
	test_heading_follow()
	test_frame_rate()
	test_water_clearance()
	test_onboard_side()
	if CoreSimSource.available():
		test_onboard_classes()
	else:
		t.ok(false, "the GDExtension is not loaded: the onboard eye on the generated classes skipped")
	test_aerial_up()
	test_presets()
	test_shake()
	test_free()
	test_switching()
	test_clip_start_line()
	test_clip_mark()
	test_clip_long_lens_helicopter()
	test_clip_choosing()
	test_breathing()
	test_lens()
	t.finish(self, "cameras_test")


func _target(psi := 0.0) -> CamTypes.Target:
	var tg := CamTypes.Target.new()
	tg.loa = 7.2
	tg.beam_max = 2.5
	tg.pose.psi = psi
	var g := BoatGeometry.new()
	g.xh = -3.04
	g.yh_abs = 0.98
	g.zh = 1.58
	g.deck_half_beam = 1.15
	tg.geometry = g
	return tg


func _rig() -> CameraRig:
	var r := CameraRig.new()
	root.add_child(r)
	return r


func test_chase_geometry() -> void:
	t.begin("1 chase geometry")
	var rig := _rig()
	var tg := _target()
	t.near(tg.r0(), 24.5, 1e-6, "wm7 R0")
	var v := rig.frame(tg, CameraInput.new(), 1.0 / 60.0)
	var el := deg_to_rad(13.5)
	t.near_v(v.xform.origin, Vector3(0, 24.5 * sin(el) + 1.0, 24.5 * cos(el)), 0.001, "eye astern (+Z)")
	t.near(v.fov, 40.0, 1e-6, "fov")
	t.ok(rig.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "vertical fov (keep height)")
	# looks at the lifted target: forward is -Z, level aim through (0, 1, 0)
	var fwd := -v.xform.basis.z
	var want := (Vector3(0, 1, 0) - v.xform.origin).normalized()
	t.near_v(fwd, want, 1e-4, "view direction toward target + lift")
	rig.queue_free()


func test_heading_follow() -> void:
	t.begin("2 heading follow")
	var dt := 1.0 / 60.0
	var cam := ChaseCamera.new()
	var tg := _target(0.0)
	var o := CamTypes.Options.new()
	cam.update(tg, o, dt)
	tg.pose.psi = PI * 0.5
	for i in 63:  # 1.05 s = 3 tau_yaw
		cam.update(tg, o, dt)
	var err := absf(Frames.angle_diff(cam.psi_c, PI * 0.5))
	t.ok(err <= 0.05 * PI * 0.5, "within 5 %% of the new heading after 1.05 s (%.2f deg off)" % rad_to_deg(err))
	cam = ChaseCamera.new()
	cam.tau_yaw = 0.0
	tg.pose.psi = 0.0
	cam.update(tg, o, dt)
	tg.pose.psi = PI * 0.5
	cam.update(tg, o, dt)
	t.near(Frames.angle_diff(cam.psi_c, PI * 0.5), 0.0, 1e-6, "tau_yaw = 0: at once")
	# reduced motion keeps tau_yaw >= 0.5 s
	cam = ChaseCamera.new()
	cam.tau_yaw = 0.0
	o.reduced_motion = true
	tg.pose.psi = 0.0
	cam.update(tg, o, dt)
	tg.pose.psi = PI * 0.5
	cam.update(tg, o, dt)
	t.ok(absf(Frames.angle_diff(cam.psi_c, PI * 0.5)) > 1.0, "reduced motion slows the follow")


func test_frame_rate() -> void:
	t.begin("3 frame-rate independence")
	for fps in [30.0, 60.0, 144.0]:
		var rig := _rig()
		var tg := _target()
		var c := CameraInput.new()
		rig.frame(tg, c, 1.0 / fps)
		var az0 := rig.chase.az
		c.orbit = Vector2(1, 0)
		for i in int(fps):
			rig.frame(tg, c, 1.0 / fps)
		var d := rad_to_deg(Frames.angle_diff(rig.chase.az, az0))
		t.near(d, 120.0, 0.5, "%d fps: 1 s of orbit" % fps)
		rig.queue_free()


func test_water_clearance() -> void:
	t.begin("4 water clearance")
	var sim := FakeSim.new()
	sim.wind_from = 0.0
	sim.set_swell(1.5)
	sim.add_boat("wm7", 0, 0, deg_to_rad(320), 3.0)
	var tg := _target()
	tg.sea_height = sim.sea_height
	var cam := ChaseCamera.new()
	cam.recentre(tg)
	cam.el = deg_to_rad(2.0)
	var o := CamTypes.Options.new()
	var dt := 1.0 / 60.0
	var acc := 0.0
	var worst := INF
	var raised := 0
	var hs_check := 0.0
	for i in 36000:  # 10 minutes
		acc += dt
		while acc >= SimSource.DT:
			sim.step()
			acc -= SimSource.DT
		tg.pose = sim.render_pose(0, acc / SimSource.DT)
		var v := cam.update(tg, o, dt)
		var e := v.xform.origin
		worst = minf(worst, e.y - (sim.sea_height(e.x, -e.z) + 0.99))
		if cam.clearance.corr > 0.0:
			raised += 1
		var hh := sim.sea_height(0, 0)
		hs_check += hh * hh
	var hs := 4.0 * sqrt(hs_check / 36000.0)
	t.near(hs, 1.5, 0.25, "the test sea has Hs about 1.5 m")
	t.ok(worst >= 0.0, "eye never below sea_height + 0.99 (margin %.3f m)" % worst)
	t.ok(raised > 0, "the clearance was active (%d frames)" % raised)


## the eye's body-frame position from the view and the pose
static func _eye_body(v: CamTypes.View, p: SimSource.RenderPose) -> Vector3:
	var boat := Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
	var m := boat.affine_inverse() * v.xform.origin
	return Vector3(m.z, m.x, m.y)


func test_onboard_side() -> void:
	t.begin("5 onboard side")
	for fps in [60.0, 144.0]:
		var dt: float = 1.0 / fps
		var cam := OnboardCamera.new()
		var o := CamTypes.Options.new()
		var tg := _target()
		tg.pose.twa = deg_to_rad(40.0)  # starboard tack: eye to starboard (y < 0)
		tg.pose.phi = deg_to_rad(-15.0)
		var v := cam.update(tg, o, dt)
		var yh := tg.geometry.yh_abs
		t.near(_eye_body(v, tg.pose).y, -yh, 1e-4, "%d fps: starboard tack, eye on the starboard side" % fps)
		t.near(_eye_body(v, tg.pose).z, tg.geometry.zh, 1e-4, "%d fps: eye height" % fps)
		tg.pose.twa = deg_to_rad(-40.0)  # the tack at t = 0
		tg.pose.phi = deg_to_rad(15.0)
		var due := 0.6 + 2.0 * yh / 1.5
		var arrived := -1.0
		var outside := false
		var n := int(ceil((due + 1.0) * fps))
		for i in n:
			v = cam.update(tg, o, dt)
			var y := _eye_body(v, tg.pose).y
			outside = outside or absf(y) > tg.geometry.deck_half_beam + 1e-6
			if arrived < 0.0 and y >= yh - 1e-6:
				arrived = (i + 1) * dt
		t.ok(absf(arrived - due) <= dt + 1e-6, "%d fps: on the new side at %.3f s, due %.3f s" % [fps, arrived, due])
		t.ok(not outside, "%d fps: never outside the deck edge" % fps)
		# a tack back during the crossing reverses it from where it is: no jump, back to the port side
		tg.pose.twa = deg_to_rad(40.0)
		var prev := _eye_body(cam.update(tg, o, dt), tg.pose).y
		var max_step := 0.0
		var mid := 0.0
		for i in int(3.0 * fps):
			if i == int(1.0 * fps):
				mid = prev
				tg.pose.twa = deg_to_rad(-40.0)
			var y := _eye_body(cam.update(tg, o, dt), tg.pose).y
			max_step = maxf(max_step, absf(y - prev))
			prev = y
		t.ok(mid < yh - 0.05 and mid > -yh + 0.05, "%d fps: mid-crossing when the tack back comes (%.2f)" % [fps, mid])
		t.ok(max_step <= 1.5 * 1.5 * dt + 1e-6, "%d fps: no jump (largest step %.4f m)" % [fps, max_step])
		t.near(prev, yh, 1e-4, "%d fps: back on the port side" % fps)
	# heel follow and near plane
	var cam := OnboardCamera.new()
	var tg := _target()
	tg.pose.phi = deg_to_rad(20.0)
	var v := cam.update(tg, CamTypes.Options.new(), 0.016)
	t.near(v.xform.basis.x.y, 0.0, 1e-5, "horizon level by default")
	t.near(v.near, 0.1, 1e-9, "near plane 0.1 m")
	cam.heel_follow = 1.0
	v = cam.update(tg, CamTypes.Options.new(), 0.016)
	t.ok(v.xform.basis.x.y < -0.3, "heel follow 1: starboard down rolls the frame")


## cameras.md §3 and §10.5: the eye on the generated wm7 (tiller) and wm12 (wheel), clear of the boat
func test_onboard_classes() -> void:
	t.begin("5b onboard eye on the generated classes")
	t.near(OnboardCamera.new().fov, 75.0, 1e-9, "default fov 75")
	var saved := OnboardCamera.new()
	saved.set_params({"fov": 65.0})
	t.near(saved.fov, 75.0, 1e-9, "a profile with the old default 65 loads the new default")
	saved.set_params({"fov": 58.0})
	t.near(saved.fov, 58.0, 1e-9, "a zoomed profile keeps its fov")
	for cls in ["wm7", "wm12"]:
		var sim := CoreSimSource.new()
		sim.settings = {"wind_speed": 6.0, "wind_from": 0.0, "shift_preset": 0, "puffs": false, "seed": 11}
		if not t.ok(sim.create(), "%s: core created" % cls):
			continue
		var info := sim.class_info(sim.add_boat(cls, 0.0, 0.0, 0.0))
		var bv := BoatView.create(info, info.rudder_max)
		var g := BoatGeometry.onboard(info, bv.model)
		var rig: Dictionary = info.physics.get("rig", {})
		var deck := BoatGeometry._deck_triangles(bv.model)
		if cls == "wm12":
			var r := BoatGeometry._rim_radius(bv.model)
			t.ok(r > 0.8 and r < 0.95, "wm12: rim radius from the wheel mesh (%.3f m)" % r)
			t.near(g.xh, float(rig["wheel_hub"][0]) - 0.7 * r, 1e-4, "wm12: 0.7 R behind the wheel hub")
			t.near(g.yh_abs, 0.55 * r, 1e-4, "wm12: behind the windward half of the rim")
			t.near(g.zh - BoatGeometry._deck_height(deck, g.xh, g.yh_abs), 1.60, 1e-4, "wm12: standing eye height")
			t.ok(BoatGeometry._deck_height(deck, g.xh, g.yh_abs) < 0.7, "wm12: standing on the cockpit floor")
			# the wheel's top and windward rim in the lower half of the default frame, starboard tack
			var cam := OnboardCamera.new()
			var tg := _target()
			tg.geometry = g
			tg.pose.twa = deg_to_rad(40.0)
			var v := cam.update(tg, CamTypes.Options.new(), 0.016)
			var hub := Vector3(float(rig["wheel_hub"][0]), float(rig["wheel_hub"][1]), float(rig["wheel_hub"][2]))
			var boat := Frames.boat_transform(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
			for e in [["top", hub + Vector3(0, 0, r)], ["windward rim", hub + Vector3(0, -0.55 * r, sqrt(r * r * (1.0 - 0.3025)))]]:
				var w: Vector3 = boat * Frames.body_to_model(e[1])
				var c := v.xform.affine_inverse() * w
				var half := tan(deg_to_rad(0.5 * v.fov))
				var sy := (c.y / -c.z) / half  # -1 bottom, +1 top
				var sx := (c.x / -c.z) / (half * 16.0 / 9.0)
				t.ok(c.z < 0.0 and sy < 0.0 and sy > -1.0 and absf(sx) < 1.0,
						"wm12: the wheel's %s in the lower half of the frame (x %.2f, y %.2f)" % [e[0], sx, sy])
		else:
			var tip := BoatGeometry._part_box(bv.model, "rudder").end.x
			t.ok(tip > float(rig["rudder_stock"][0]) + 0.5, "wm7: the tiller's tip from the rudder part (%.2f)" % tip)
			t.near(g.xh, tip + 0.15, 1e-4, "wm7: just forward of the tiller's end")
			t.near(g.yh_abs, 0.9 * g.deck_half_beam, 1e-4, "wm7: on the windward side deck")
			t.near(g.zh - BoatGeometry._deck_height(deck, g.xh, g.yh_abs), 0.80, 1e-4, "wm7: seated eye height")
		# the steering is drawn: its meshes visible at the onboard camera's distance (no LOD swap, no hidden part)
		bv.update_lod(Vector3(g.xh, g.yh_abs, g.zh).length())
		var part := bv.model.find_child("wheel" if cls == "wm12" else "rudder", true, false) as Node3D
		var shown := part != null and bv.lod == 0
		var up: Node = part
		while shown and up != null and up != bv:
			shown = not (up is Node3D) or (up as Node3D).visible
			up = up.get_parent()
		t.ok(shown, "%s: the %s drawn for the onboard camera" % [cls, "wheel" if cls == "wm12" else "tiller"])
		t.ok(g.xh > BoatGeometry._aft_end(deck) + 0.2, "%s: over the deck, forward of the transom (x %.2f)" % [cls, g.xh])
		var tris := _model_triangles(bv.model, g)
		var side := INF
		var path := INF
		for i in 21:
			var q := -1.0 + 2.0 * i / 20.0
			var p := Vector3(g.xh, q * g.yh_abs, g.zh - OnboardCamera.DIP * (1.0 - q * q))
			var d := _clearance(p, tris)
			path = minf(path, d)
			if i == 0 or i == 20:
				side = minf(side, d)
		t.ok(side >= 0.3, "%s: the eye clear of the boat where it sits (%.2f m)" % [cls, side])
		t.ok(path >= 0.3, "%s: clear along the crossing (%.2f m)" % [cls, path])
		bv.free()


## the model's triangles (sails, sheets and shadow proxies left out) within 1.5 m of the eye's crossing, body frame
static func _model_triangles(model: Node3D, g: BoatGeometry) -> Array:
	var out := []
	var lo := Vector3(g.xh - 1.5, -g.yh_abs - 1.5, g.zh - 2.0)
	var hi := Vector3(g.xh + 1.5, g.yh_abs + 1.5, g.zh + 1.5)
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nm := String(mi.name)
		if nm.begins_with("sail") or nm.begins_with("shadow") or nm == "sheets":
			continue
		var xf := BoatGeometry._relative(model, mi)
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var k := 0
			while k + 2 < idx.size():
				var tri := []
				var a_lo := Vector3(INF, INF, INF)
				var a_hi := -a_lo
				for j in 3:
					var m := xf * v[idx[k + j]]
					var b := Vector3(m.z, m.x, m.y)  # model (port, up, bow) -> body (x, y, z)
					tri.append(b)
					a_lo = a_lo.min(b)
					a_hi = a_hi.max(b)
				k += 3
				if a_hi.x >= lo.x and a_lo.x <= hi.x and a_hi.y >= lo.y and a_lo.y <= hi.y and a_hi.z >= lo.z and a_lo.z <= hi.z:
					out.append(tri)
	return out


## shortest distance from p to the triangles
static func _clearance(p: Vector3, tris: Array) -> float:
	var best := INF
	for tri in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (b - a).cross(c - a)
		var l := n.length()
		if l > 1e-12:
			n /= l
			var d := (p - a).dot(n)
			var q := p - d * n
			if (b - a).cross(q - a).dot(n) >= 0.0 and (c - b).cross(q - b).dot(n) >= 0.0 \
					and (a - c).cross(q - c).dot(n) >= 0.0:
				best = minf(best, absf(d))
				continue
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)))
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
		best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))
	return best


func test_aerial_up() -> void:
	t.begin("6 aerial up modes")
	var cam := AerialCamera.new()
	var tg := _target(deg_to_rad(30))
	tg.pose.twd_from = deg_to_rad(70.0)
	var o := CamTypes.Options.new()
	var v := cam.update(tg, o, 0.016)
	t.near_v(v.xform.basis.y, Vector3(0, 0, -1), 1e-4, "up = north: scene -Z to the top of the screen")
	t.near_v(-v.xform.basis.z, Vector3(0, -1, 0), 1e-4, "looking straight down")
	t.near(v.xform.origin.y, 250.0, 1e-3, "H = 250 m")
	cam.up = AerialCamera.Up.WIND
	cam.snap(tg)
	for i in 60:
		v = cam.update(tg, o, 0.016)
	var up := v.xform.basis.y
	var c := Frames.compass(up.x, -up.z)
	t.ok(absf(rad_to_deg(Frames.angle_diff(c, tg.pose.twd_from))) <= 1.0,
		"up = wind: the true wind comes from the top (%.2f deg)" % rad_to_deg(c))
	cam.up = AerialCamera.Up.BOAT
	cam.snap(tg)
	v = cam.update(tg, o, 0.016)
	up = v.xform.basis.y
	t.near(rad_to_deg(Frames.angle_diff(Frames.compass(up.x, -up.z), tg.pose.psi)), 0.0, 0.5, "up = boat")
	cam.tilt = deg_to_rad(60.0)
	cam.up = AerialCamera.Up.NORTH
	v = cam.update(tg, o, 0.016)
	t.ok(v.xform.origin.z > 0.0, "tilt < 90: raked from astern of up (south of the boat for north up)")
	var c2 := CameraInput.new()
	c2.orbit = Vector2(1, 0)
	cam.handle_input(c2, o, 0.5)
	t.ok(cam.up == AerialCamera.Up.FIXED and absf(rad_to_deg(cam.up_angle) - 60.0) < 0.5, "orbit keys turn up by hand")
	cam.recentre(tg)
	t.ok(cam.up == AerialCamera.Up.NORTH and cam.H == 250.0 and cam.tilt == PI * 0.5, "recentre")


func test_presets() -> void:
	t.begin("7 presets")
	var rig := _rig()
	var tg := _target()
	rig.frame(tg, CameraInput.new(), 0.016)
	rig.chase.set_params({"R": 40.0, "el": 0.5, "az": 1.0, "fov": 55.0, "tau_yaw": 0.8, "tau_heave": 0.1,
		"lift": 2.0})
	var stored := rig.chase.params().duplicate()
	var c := CameraInput.new()
	c.preset_store = 2
	rig.frame(tg, c, 0.016)
	rig.chase.set_params({"R": 10.0, "el": 0.2, "az": -2.0, "fov": 30.0, "tau_yaw": 0.1, "tau_heave": 0.9,
		"lift": 0.5})
	rig.select_mode(CameraRig.Mode.AERIAL, tg)
	rig.aerial.set_params({"H": 900.0, "tilt": 1.0, "up": AerialCamera.Up.WIND, "fov": 50.0})
	c = CameraInput.new()
	c.preset_recall = 2
	rig.frame(tg, c, 0.016)
	t.ok(rig.mode == CameraRig.Mode.CHASE, "mode restored")
	t.ok(rig.chase.params() == stored, "every chase parameter restored exactly")
	# an aerial preset
	rig.select_mode(CameraRig.Mode.AERIAL, tg)
	var ast := rig.aerial.params().duplicate()
	rig.store_preset(5)
	rig.aerial.set_params({"H": 100.0, "tilt": 1.2, "up": AerialCamera.Up.BOAT, "up_angle": 1.0, "fov": 30.0,
		"framing": AerialCamera.Framing.BOAT_AND_MARK})
	rig.select_mode(CameraRig.Mode.CHASE, tg)
	rig.recall_preset(5, tg)
	t.ok(rig.mode == CameraRig.Mode.AERIAL and rig.aerial.params() == ast, "aerial preset restored exactly")
	rig.factory_presets(tg.r0())
	var fine := rig.presets.size() == 8
	for i in 8:
		var p: Dictionary = rig.presets[i]
		fine = fine and p["mode"] == CameraRig.Mode.CHASE and absf(p["params"]["R"] - 1.6 * 24.5) < 1e-9 \
			and absf(Frames.angle_diff(p["params"]["az"], deg_to_rad(45.0 * i))) < 1e-9 \
			and absf(p["params"]["el"] - deg_to_rad(13.5)) < 1e-9
	t.ok(fine, "factory reset: eight chase presets at 1.6 R0, az every 45 deg")
	# profile round trip
	var path := OS.get_cache_dir().path_join("windmark_cameras_test.cfg")
	rig.chase.R = 33.0
	t.ok(rig.save_profile(path) == OK, "profile saved")
	var rig2 := _rig()
	t.ok(rig2.load_profile(path) == OK and rig2.chase.R == 33.0 and rig2.presets.size() == 8, "profile loaded")
	DirAccess.remove_absolute(path)
	rig.queue_free()
	rig2.queue_free()


func test_shake() -> void:
	t.begin("8 shake")
	var dt := 1.0 / 60.0
	var s := CameraShake.new(7)
	s.contact(2.0)
	var peak := 0.0
	var off := []
	var n := int(0.9 * 60.0)
	for i in n + 1:
		off = s.advance(dt)
		peak = maxf(peak, (off[0] as Vector3).length())
	t.near(peak, 0.08, 1e-6, "a 2 m/s contact peaks at 0.08 m")
	t.ok((off[0] as Vector3).length() < 0.05 * 0.08, "under 5 %% after 0.9 s (%.5f m)" % (off[0] as Vector3).length())
	var s2 := CameraShake.new()
	s2.contact(0.2)
	t.ok(not s2.active(), "below 0.3 m/s: no shake")
	s2.contact(1.0)
	s2.contact(0.5)
	t.near(s2.amp_pos, 0.04, 1e-9, "overlapping events take the larger amplitude")
	# through the rig: chase only, off with reduced motion
	var rig := _rig()
	var tg := _target()
	var base := rig.frame(tg, CameraInput.new(), dt).xform.origin
	rig.contact(2.0)
	var shaken := rig.frame(tg, CameraInput.new(), dt).xform.origin
	t.near(shaken.distance_to(base), 0.08, 0.01, "rig applies the shake to the chase camera")
	rig.options.reduced_motion = true
	rig.contact(3.0)
	for i in 120:
		rig.frame(tg, CameraInput.new(), dt)
	var calm := rig.frame(tg, CameraInput.new(), dt).xform.origin
	t.near(calm.distance_to(base), 0.0, 0.002, "reduced motion: no shake")
	rig.queue_free()


func test_free() -> void:
	t.begin("free camera")
	var rig := _rig()
	var tg := _target(deg_to_rad(90))
	tg.pose.pos_x = 100.0
	rig.frame(tg, CameraInput.new(), 0.016)
	rig.select_mode(CameraRig.Mode.FREE, tg)
	var v := rig.frame(tg, CameraInput.new(), 0.016)
	t.near_v(v.xform.origin, Vector3(40, 40, 0), 1e-3, "first selection: 60 m astern, 40 m up")
	t.near_v(-v.xform.basis.z, (Vector3(100, 0, 0) - Vector3(40, 40, 0)).normalized(), 1e-4, "looking at the boat")
	var c := CameraInput.new()
	c.move = Vector3(0, -1, 0)
	for i in 600:
		v = rig.frame(tg, c, 0.016)
	t.ok(v.xform.origin.y >= 1.0 - 1e-6, "kept 1 m above the sea (y %.3f)" % v.xform.origin.y)
	c = CameraInput.new()
	c.move = Vector3(0, 0, 1)
	var p0 := rig.free.pos
	for i in 60:
		rig.frame(tg, c, 1.0 / 60.0)
	var sp := (rig.free.pos - p0).length()
	t.ok(sp > 7.0 and sp < 11.0, "about 10 m/s near the water (%.2f m in 1 s with 0.15 s smoothing)" % sp)
	var kept := rig.free.pos
	rig.select_mode(CameraRig.Mode.CHASE, tg)
	rig.select_mode(CameraRig.Mode.FREE, tg)
	t.near_v(rig.free.pos, kept, 1e-6, "the free camera keeps its pose across switches")
	c = CameraInput.new()
	c.recentre = true
	v = rig.frame(tg, c, 0.016)
	t.near_v(rig.free.pos, Vector3(40, 40, 0), 0.5, "recentre goes back to the start pose")
	t.near(CamTypes.near_for(50.0), 0.5, 1e-9, "near plane low")
	t.near(CamTypes.near_for(2080.0), 120.0, 1e-9, "near plane high")
	t.near(v.far, 30000.0, 1e-9, "far plane 30 km")
	rig.queue_free()


func test_switching() -> void:
	t.begin("switching")
	var rig := _rig()
	var tg := _target()
	rig.frame(tg, CameraInput.new(), 0.016)
	var order := []
	for i in 4:
		var c := CameraInput.new()
		c.next = true
		rig.frame(tg, c, 0.016)
		order.append(rig.mode)
	t.ok(order == [CameraRig.Mode.ONBOARD, CameraRig.Mode.AERIAL, CameraRig.Mode.FREE, CameraRig.Mode.CHASE],
		"cycle chase, onboard, aerial, free, chase: %s" % [order])
	var c := CameraInput.new()
	c.select = CameraRig.Mode.AERIAL
	var v := rig.frame(tg, c, 0.016)
	t.near(v.xform.origin.y, 250.0, 0.01, "direct select cuts by default")
	rig.options.smooth_switch = true
	c = CameraInput.new()
	c.select = CameraRig.Mode.CHASE
	v = rig.frame(tg, c, 0.1)
	t.ok(v.xform.origin.y > 10.0 and v.xform.origin.y < 250.0, "smooth switch blends chase and aerial")
	for i in 5:
		v = rig.frame(tg, CameraInput.new(), 0.1)
	t.ok(v.xform.origin.y < 10.0, "blend done after 0.4 s")
	c = CameraInput.new()
	c.select = CameraRig.Mode.ONBOARD
	v = rig.frame(tg, c, 0.016)
	t.near(v.near, 0.1, 1e-9, "other pairs always cut")
	# chase recentre
	rig.select_mode(CameraRig.Mode.CHASE, tg)
	rig.chase.R = 99.0
	rig.chase.az = 1.0
	c = CameraInput.new()
	c.recentre = true
	rig.frame(tg, c, 0.016)
	t.ok(rig.chase.R == tg.r0() and rig.chase.az == 0.0, "recentre resets the current mode")
	rig.queue_free()


## a course for the clip cameras: start line P (0, 0) - C (100, 0), next mark (0, 500) from (0, 0) (east, north)
func _course(side := 1) -> ClipCourse:
	var c := ClipCourse.new()
	c.has_line = true
	c.pin = Frames.enu_to_scene(0.0, 0.0, 0.0)
	c.committee = Frames.enu_to_scene(100.0, 0.0, 0.0)
	c.has_mark = true
	c.mark = Frames.enu_to_scene(0.0, 500.0, 0.0)
	c.approach = Frames.enu_to_scene(0.0, 0.0, 0.0)
	c.side = side
	c.zone_r = 21.6
	return c


func _select_clip(rig: CameraRig, tg: CamTypes.Target, m: int) -> CamTypes.View:
	var v: CamTypes.View = null
	for i in 5:
		if rig.mode == m:
			break
		var c := CameraInput.new()
		c.clip = true
		v = rig.frame(tg, c, 1.0 / 60.0)
	return v


func test_clip_start_line() -> void:
	t.begin("9 start line shot")
	var rig := _rig()
	rig.course = _course()
	var tg := _target()
	var v := _select_clip(rig, tg, CameraRig.Mode.START_LINE)
	t.ok(rig.mode == CameraRig.Mode.START_LINE, "camera_clip selects the start line first")
	t.near_v(v.xform.origin, Frames.enu_to_scene(120.0, 0.0, 6.0), 0.001, "eye 20 m outside the committee end, 6 m up")
	var want := (rig.course.pin - v.xform.origin).normalized()
	var ang := rad_to_deg((-v.xform.basis.z).angle_to(want))
	t.ok(ang < 0.1, "looks at the pin end (%.4f deg off)" % ang)
	t.near(v.fov, 30.0, 1e-6, "fov 30")
	rig.queue_free()


func test_clip_mark() -> void:
	t.begin("10 mark shot")
	for side in [1, -1]:
		var rig := _rig()
		rig.course = _course(side)
		var tg := _target()
		tg.pose.pos_x = 0.0
		tg.pose.pos_y = 300.0
		var v := _select_clip(rig, tg, CameraRig.Mode.MARK)
		t.ok(rig.mode == CameraRig.Mode.MARK, "side %+d: mark shot selected" % side)
		var b := deg_to_rad(225.0 if side > 0 else 135.0)
		var want := Frames.enu_to_scene(40.0 * sin(b), 500.0 + 40.0 * cos(b), 6.0)
		t.near_v(v.xform.origin, want, 0.001, "side %+d: eye at bearing %d from the mark" % [side, 225 if side > 0 else 135])
		if side > 0:
			t.near_v(v.xform.origin, Frames.enu_to_scene(-28.28, 471.72, 6.0), 0.01, "left to port: (-28.28, 471.72, 6)")
		# zone empty: the viewed boat, 2 m up
		t.near_v(rig.mark.aim, tg.point(0.0) + Vector3(0, 2, 0), 1e-4, "side %+d: zone empty, aims at the viewed boat" % side)
		# two boats in the zone: the one ahead in race order
		rig.course.boats = [Frames.enu_to_scene(30.0, 300.0, 0.0), Frames.enu_to_scene(5.0, 490.0, 0.0),
			Frames.enu_to_scene(-5.0, 485.0, 0.0)]
		for i in 300:
			v = rig.frame(tg, CameraInput.new(), 1.0 / 60.0)
		var lead := Frames.enu_to_scene(5.0, 490.0, 0.0) + Vector3(0, 2, 0)
		t.near_v(rig.mark.aim, lead, 0.05, "side %+d: aims at the zone leader after 5 s (tau 0.5 s)" % side)
		t.near_v(v.xform.origin, want, 0.001, "side %+d: the eye stays fixed" % side)
		rig.queue_free()


func test_clip_long_lens_helicopter() -> void:
	t.begin("11 long lens and helicopter")
	var rig := _rig()
	rig.course = null
	var tg := _target()
	var v := _select_clip(rig, tg, CameraRig.Mode.LONG_LENS)
	t.ok(rig.mode == CameraRig.Mode.LONG_LENS, "without a course camera_clip starts at the long lens")
	var el := deg_to_rad(5.0)
	t.near_v(v.xform.origin, Vector3(0, 150.0 * sin(el) + 1.0, 150.0 * cos(el)), 0.001, "long lens eye")
	t.near(v.fov, 12.0, 1e-6, "long lens fov 12")
	var c := CameraInput.new()
	c.zoom_notches = 3
	v = rig.frame(tg, c, 1.0 / 60.0)
	t.ok(v.fov < 12.0 and rig.long_lens.R == 150.0, "long lens zoom changes fov (%.2f), not the distance" % v.fov)
	c = CameraInput.new()
	c.zoom_notches = 50
	v = rig.frame(tg, c, 1.0 / 60.0)
	t.near(v.fov, 6.0, 1e-6, "long lens fov floor 6")
	c = CameraInput.new()
	c.recentre = true
	v = rig.frame(tg, c, 1.0 / 60.0)
	t.near(v.fov, 12.0, 1e-6, "recentre restores the long lens")
	v = _select_clip(rig, tg, CameraRig.Mode.HELICOPTER)
	t.near_v(v.xform.origin, Vector3(0, 60, 120), 0.01, "helicopter starts 120 m astern, 60 m up")
	for i in 1080:
		v = rig.frame(tg, CameraInput.new(), 1.0 / 60.0)
	t.near_v(v.xform.origin, Vector3(-120, 60, 0), 0.01, "after 18 s 90 deg clockwise: 120 m west")
	var fwd := -v.xform.basis.z
	t.near_v(fwd, (Vector3.ZERO - v.xform.origin).normalized(), 1e-4, "looks at the boat")
	t.near(v.fov, 35.0, 1e-6, "helicopter fov 35")
	# frame-rate independent turn
	for fps in [30.0, 144.0]:
		var r2 := _rig()
		_select_clip(r2, tg, CameraRig.Mode.HELICOPTER)
		for i in int(18.0 * fps):
			r2.frame(tg, CameraInput.new(), 1.0 / fps)
		t.near_v(r2.view.xform.origin, Vector3(-120, 60, 0), 0.01, "%d fps: 120 m west after 18 s" % fps)
		r2.queue_free()
	rig.queue_free()


func test_clip_choosing() -> void:
	t.begin("12 choosing the clip cameras")
	var tg := _target()
	var rig := _rig()
	rig.frame(tg, CameraInput.new(), 0.016)
	var order := []
	for i in 3:
		var c := CameraInput.new()
		c.clip = true
		rig.frame(tg, c, 0.016)
		order.append(rig.mode)
	t.ok(order == [CameraRig.Mode.LONG_LENS, CameraRig.Mode.HELICOPTER, CameraRig.Mode.LONG_LENS],
		"no course: long lens, helicopter, long lens: %s" % [order])
	rig.course = _course()
	order = []
	for i in 5:
		var c := CameraInput.new()
		c.clip = true
		rig.frame(tg, c, 0.016)
		order.append(rig.mode)
	t.ok(order == [CameraRig.Mode.HELICOPTER, CameraRig.Mode.START_LINE, CameraRig.Mode.MARK,
		CameraRig.Mode.LONG_LENS, CameraRig.Mode.HELICOPTER], "with a course all four in turn: %s" % [order])
	var before := rig.presets.duplicate(true)
	var c := CameraInput.new()
	c.preset_store = 2
	rig.frame(tg, c, 0.016)
	t.ok(rig.presets == before, "store does nothing while a clip camera is shown")
	t.ok(rig.to_dict()["mode"] == CameraRig.Mode.CHASE, "a clip camera is not saved as the mode")
	c = CameraInput.new()
	c.next = true
	rig.frame(tg, c, 0.016)
	t.ok(rig.mode == CameraRig.Mode.CHASE, "camera_next from a clip camera selects chase")
	c = CameraInput.new()
	c.clip = true
	rig.frame(tg, c, 0.016)
	t.ok(rig.mode == CameraRig.Mode.HELICOPTER, "from a regular camera camera_clip returns to the last clip camera")
	rig.from_dict({"mode": CameraRig.Mode.MARK})
	t.ok(rig.mode == CameraRig.Mode.CHASE, "a saved clip mode loads as chase")
	rig.queue_free()
	var off := _rig()
	off.clip_allowed = false
	off.frame(tg, CameraInput.new(), 0.016)
	c = CameraInput.new()
	c.clip = true
	off.frame(tg, c, 0.016)
	t.ok(off.mode == CameraRig.Mode.CHASE, "online (clip cameras not allowed) the key changes nothing")
	off.queue_free()


func test_breathing() -> void:
	t.begin("13 chase breathing")
	var dt := 1.0 / 60.0
	var o := CamTypes.Options.new()
	t.near(ChaseCamera.BANK_MAX, deg_to_rad(1.5), 1e-9, "bank at most 1.5 deg")
	t.near(ChaseCamera.SURGE_MAX, 0.8, 1e-9, "surge trail at most 0.8 m")
	t.near(ChaseCamera.LEAN_K, 0.2, 1e-9, "lean 0.2 loa sin(heel)")
	# eased heading: no overshoot, a gentler start than a first-order follow, settled by 3 tau_yaw
	var cam := ChaseCamera.new()
	var tg := _target(0.0)
	cam.update(tg, o, dt)
	tg.pose.psi = PI * 0.5
	var prev := 0.0
	var mono := true
	var at_01 := 0.0
	for i in 63:
		cam.update(tg, o, dt)
		var a := Frames.angle_diff(cam.psi_c, 0.0)
		mono = mono and a >= prev - 1e-9 and a <= PI * 0.5 + 1e-6
		prev = a
		if i == 5:
			at_01 = a
	t.ok(mono, "the swing never overshoots")
	t.ok(at_01 < PI * 0.5 * (1.0 - exp(-0.1 / 0.35)), "eases in: %.1f deg after 0.1 s" % rad_to_deg(at_01))
	# bank into a right turn (heading increasing): the right side of the frame goes down
	cam = ChaseCamera.new()
	tg = _target(0.0)
	var v := cam.update(tg, o, dt)
	var max_bank := 0.0
	var right_down := false
	for i in 120:
		tg.pose.psi = deg_to_rad(25.0) * (i + 1) * dt
		v = cam.update(tg, o, dt)
		max_bank = maxf(max_bank, absf(cam.bank))
		right_down = right_down or v.xform.basis.x.y < -1e-4
	t.ok(right_down and cam.bank > 0.0, "banks into a turn to starboard (%.2f deg)" % rad_to_deg(cam.bank))
	t.ok(max_bank <= deg_to_rad(1.5) + 1e-6, "bank within 1.5 deg (%.2f)" % rad_to_deg(max_bank))
	# surge: speeding up north the target trails (south, +Z), then settles back at a steady speed
	cam = ChaseCamera.new()
	tg = _target(0.0)
	cam.update(tg, o, dt)
	var speed := 0.0
	var max_trail := 0.0
	for i in 120:  # 2 s at 1 m/s²
		speed += 1.0 * dt
		tg.pose.pos_y += speed * dt
		cam.update(tg, o, dt)
		max_trail = maxf(max_trail, cam.surge.z)
	t.ok(max_trail > 0.1 and max_trail <= 0.8 + 1e-6, "trails a speed-up by %.2f m (at most 0.8)" % max_trail)
	for i in 300:  # 5 s steady
		tg.pose.pos_y += speed * dt
		cam.update(tg, o, dt)
	t.ok(cam.surge.length() < 0.02, "settles at a steady speed (%.3f m)" % cam.surge.length())
	# a jump (reset) does not trail
	tg.pose.pos_y += 500.0
	cam.update(tg, o, dt)
	t.ok(cam.surge.length() < 0.02, "a pose jump does not trail")
	# lean: heeled 25 deg the target moves toward the masthead side by 0.2 loa sin(phi)
	cam = ChaseCamera.new()
	tg = _target(0.0)
	tg.pose.phi = deg_to_rad(25.0)
	cam.update(tg, o, dt)
	var mast := Frames.boat_basis(0.0, 0.0, tg.pose.phi).y
	t.near(cam.lean.length(), 0.2 * 7.2 * sin(deg_to_rad(25.0)), 1e-3, "lean length")
	t.ok(cam.lean.dot(Vector3(mast.x, 0, mast.z)) > 0.0, "lean toward the masthead side")
	# reduced motion: none of it
	o.reduced_motion = true
	cam = ChaseCamera.new()
	tg = _target(0.0)
	tg.pose.phi = deg_to_rad(25.0)
	cam.update(tg, o, dt)
	for i in 60:
		tg.pose.psi += deg_to_rad(25.0) * dt
		tg.pose.pos_y += 3.0 * dt
		cam.update(tg, o, dt)
	t.ok(cam.bank == 0.0 and cam.surge == Vector3.ZERO and cam.lean == Vector3.ZERO, "reduced motion: no bank, trail or lean")


func test_lens() -> void:
	t.begin("14 lens: depth of field, no vignette")
	var keep_tier := LookFx.tier
	LookFx.tier = SeaQuality.Tier.M
	var tg := _target()
	tg.loa = 7.2
	var rig := _rig()
	rig.course = _course()
	t.ok(rig.find_children("*", "CanvasLayer", true, false).is_empty() and rig.find_children("*", "CanvasItem", true,
		false).is_empty(), "no vignette: the rig has no 2-D layer over the 3-D image")
	rig.frame(tg, CameraInput.new(), 0.016)
	for m in [CameraRig.Mode.CHASE, CameraRig.Mode.ONBOARD, CameraRig.Mode.AERIAL, CameraRig.Mode.FREE]:
		var c := CameraInput.new()
		c.select = m
		rig.frame(tg, c, 0.016)
		rig.frame(tg, CameraInput.new(), 0.016)
		t.ok(rig.camera.attributes == null, "no depth of field on %s" % CameraRig.Mode.keys()[m])
	for m in [CameraRig.Mode.START_LINE, CameraRig.Mode.HELICOPTER]:
		_select_clip(rig, tg, m)
		rig.frame(tg, CameraInput.new(), 0.016)
		t.ok(rig.camera.attributes == null, "no depth of field on %s" % CameraRig.Mode.keys()[m])
	# long lens: sharp around the boat at 150 m
	var v := _select_clip(rig, tg, CameraRig.Mode.LONG_LENS)
	v = rig.frame(tg, CameraInput.new(), 0.016)
	var a := rig.camera.attributes as CameraAttributesPractical
	t.ok(a != null and a.dof_blur_far_enabled and a.dof_blur_near_enabled, "long lens has depth of field")
	if a:
		var zone := CameraRig.DOF_ZONE_LOA * 7.2 + CameraRig.DOF_ZONE_M
		t.near(rig.focus, v.focus, 0.01, "focus on the subject")
		t.near(rig.focus, 150.0, 1.0, "long lens focus about 150 m")
		t.near(a.dof_blur_near_distance, rig.focus - zone, 1e-3, "near blur ends a zone short of the boat")
		t.near(a.dof_blur_far_distance, rig.focus + zone, 1e-3, "far blur starts a zone beyond the boat")
		t.ok(a.dof_blur_near_distance < 150.0 - 3.6 and a.dof_blur_far_distance > 150.0 + 3.6, "the whole boat is sharp")
	# the focus follows the boat as it moves away
	for i in 120:
		tg.pose.pos_y += 0.5
		rig.frame(tg, CameraInput.new(), 1.0 / 60.0)
	t.near(rig.focus, rig.view.focus, 0.5, "focus follows the distance (%.1f m)" % rig.focus)
	# mark shot
	tg = _target()
	_select_clip(rig, tg, CameraRig.Mode.MARK)
	v = rig.frame(tg, CameraInput.new(), 0.016)
	t.ok(rig.camera.attributes != null and v.focus > 0.0, "mark shot has depth of field, focus %.1f m" % v.focus)
	# tier L: none
	LookFx.tier = SeaQuality.Tier.L
	rig.frame(tg, CameraInput.new(), 0.016)
	t.ok(rig.camera.attributes == null, "no depth of field on tier L")
	LookFx.tier = SeaQuality.Tier.H
	rig.frame(tg, CameraInput.new(), 0.016)
	t.ok(rig.camera.attributes != null, "depth of field on tier H")
	LookFx.tier = keep_tier
	rig.queue_free()
