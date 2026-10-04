extends SceneTree
## The cinematic look's settings (water_render.md §4.5, WM-016.38), headless: the light presets (late afternoon),
## the colour grade per preset (the environment's LUT and the formula), the contact shading per tier.
##   godot --headless --path game -s res://tests/look_test.gd

var t := TestLog.new()


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false


func _run() -> void:
	var sky: SkyRig = (load("res://scenes/sea/sky_day.tscn") as PackedScene).instantiate()
	root.add_child(sky)
	test_presets(sky)
	test_grade(sky)
	test_ssao(sky)
	sky.queue_free()
	t.finish(self, "look_test")


func test_presets(sky: SkyRig) -> void:
	t.begin("light presets")
	t.ok(sky.preset == SkyRig.Preset.FAIR, "fair is the default")
	var fair_sun := sky.sun_color
	t.ok(sky.set_preset_name("late"), "late is a preset name")
	t.ok(sky.sun_elevation_deg >= 15.0 and sky.sun_elevation_deg <= 20.0,
		"late sun 15 to 20 deg high (%.0f)" % sky.sun_elevation_deg)
	t.ok(sky.sun_color.b / sky.sun_color.r < fair_sun.b / fair_sun.r, "late sun warmer than fair's")
	var d := sky.sun_direction()
	var sun := sky.sun()
	t.near_v(sun.global_basis.z, d, 1e-4, "the light shines from the low sun")
	t.near(rad_to_deg(asin(d.y)), 17.0, 0.01, "sun direction 17 deg up")
	t.near(sky.exposure, 0.60, 1e-6, "late exposure")
	t.ok(sky.set_preset_name("fair"), "back to fair")
	t.near(sky.sun_elevation_deg, 38.0, 1e-6, "fair puts the sun back at 38 deg")
	t.near(sky.sun_azimuth_deg, 200.0, 1e-6, "and bearing 200")
	t.ok(not sky.set_preset_name("dusk"), "unknown names refused")


func test_grade(sky: SkyRig) -> void:
	t.begin("colour grade")
	var env := sky.environment()
	for name in SkyRig.PRESET_NAMES:
		sky.set_preset_name(name)
		var p: int = SkyRig.PRESET_NAMES[name]
		t.ok(env.adjustment_enabled and env.adjustment_color_correction == LookFx.lut(p), "%s: its LUT on the environment" % name)
		t.ok(env.adjustment_brightness == 1.0 and env.adjustment_contrast == 1.0 and env.adjustment_saturation == 1.0,
			"%s: brightness, contrast, saturation at 1" % name)
		var g: Dictionary = LookFx.GRADES[p]
		t.ok(LookFx.grade(Vector3.ZERO, g).length() < 1e-6, "%s: black stays black" % name)
		t.ok(LookFx.grade(Vector3.ONE, g).distance_to(Vector3.ONE) < 1e-6, "%s: white stays white" % name)
		var lo := LookFx.grade(Vector3(0.2, 0.2, 0.2), g)
		var hi := LookFx.grade(Vector3(0.75, 0.75, 0.75), g)
		t.ok(lo.z > lo.x, "%s: shadows cooler (%.3f %.3f %.3f)" % [name, lo.x, lo.y, lo.z])
		t.ok(hi.x > hi.z, "%s: light warmer (%.3f %.3f %.3f)" % [name, hi.x, hi.y, hi.z])
		t.ok(lo.dot(LookFx.LUMA) < 0.2 and hi.dot(LookFx.LUMA) > 0.75, "%s: richer contrast" % name)
		var worst := 0.0
		var mono := true
		var prev := -1.0
		for i in 33:
			var x := i / 32.0
			var y := LookFx.grade(Vector3(x, x, x), g)
			mono = mono and y.dot(LookFx.LUMA) >= prev
			prev = y.dot(LookFx.LUMA)
			for c in [Vector3(x, x, x), Vector3(x, 0.3, 0.6), Vector3(0.8, x, 0.2), Vector3(0.1, 0.5, x)]:
				worst = maxf(worst, (LookFx.grade(c, g) - c).abs()[(LookFx.grade(c, g) - c).abs().max_axis_index()])
		t.ok(mono, "%s: the grey ramp stays in order" % name)
		t.ok(worst <= 0.06, "%s: gentle: every value moves by at most 0.06 (%.3f)" % [name, worst])
	var imgs := LookFx.lut_images(LookFx.GRADES[SkyRig.Preset.FAIR])
	t.ok(imgs.size() == LookFx.LUT_SIZE and imgs[0].get_width() == LookFx.LUT_SIZE, "33 slices of 33 x 33")
	var c := imgs[20].get_pixel(5, 30)
	var want := LookFx.grade(Vector3(LookFx.lut_coord(5), LookFx.lut_coord(30), LookFx.lut_coord(20)),
		LookFx.GRADES[SkyRig.Preset.FAIR])
	t.near_v(Vector3(c.r, c.g, c.b), want, 1.0 / 255.0, "a texel holds the grade of its sampling point")
	t.near(LookFx.lut_coord(16), 16.5 / 33.0, 1e-9, "texel i read at (i + 0.5)/N")
	t.ok(LookFx.lut_coord(0) == 0.0 and LookFx.lut_coord(32) == 1.0, "end texels hold black and white")
	LookFx.enabled = false
	LookFx.apply_grade(env, sky.preset)
	t.ok(not env.adjustment_enabled, "--look=off: no grade")
	LookFx.enabled = true
	LookFx.apply_grade(env, sky.preset)
	t.ok(env.adjustment_enabled, "grade back on")
	sky.set_preset_name("fair")


func test_ssao(sky: SkyRig) -> void:
	t.begin("contact shading per tier")
	var env := sky.environment()
	for tier in [SeaQuality.Tier.L, SeaQuality.Tier.M]:
		sky.apply_quality(tier)
		t.ok(not env.ssao_enabled, "no SSAO on tier %s" % "LMH"[tier])
		t.ok(LookFx.tier == tier, "the look knows tier %s" % "LMH"[tier])
	t.ok(not LookFx.dof_allowed() or LookFx.tier != SeaQuality.Tier.L, "no depth of field on L")
	sky.apply_quality(SeaQuality.Tier.H)
	t.ok(env.ssao_enabled, "SSAO on tier H")
	t.ok(env.ssao_light_affect == 0.0 and env.ssao_ao_channel_affect == 0.0, "ambient only (light and AO channel 0)")
	t.near(env.ssao_radius, 0.8, 1e-6, "radius 0.8 m")
	t.near(env.ssao_intensity, 1.6, 1e-6, "intensity 1.6")
	LookFx.ssao_override = 1
	sky.apply_quality(SeaQuality.Tier.M)
	t.ok(env.ssao_enabled, "--ssao=on tries it on M")
	LookFx.ssao_override = 0
	sky.apply_quality(SeaQuality.Tier.H)
	t.ok(not env.ssao_enabled, "--ssao=off on H")
	LookFx.ssao_override = -1
	sky.apply_quality(SeaQuality.Tier.L)
	t.ok(not LookFx.dof_allowed(), "tier L: no depth of field")
	sky.apply_quality(SeaQuality.Tier.M)
	t.ok(LookFx.dof_allowed(), "tier M: depth of field allowed")
