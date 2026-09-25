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
	test_aerial_up()
	test_presets()
	test_shake()
	test_free()
	test_switching()
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
