extends SceneTree
## The cinematic look's settings (water_render.md §4.5, WM-016.38, WM-124), headless: the sun position from the hour,
## latitude and date, the hour keyframes (anchors and continuity), conditions over the hour, the SkyRig inputs and
## old preset names, the clock's steps, the venue look files, the colour grade (bounds, whites, strength), the
## drawn shadows' strength and the contact shading per tier.
##   godot --headless --path game -s res://tests/look_test.gd

const VENUES := ["practice_waters", "garda", "solent", "fremantle", "trieste"]

var t := TestLog.new()
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false


func _run() -> void:
	test_sun()
	test_keys()
	test_conditions()
	test_look_files()
	var sky: SkyRig = (load("res://scenes/sea/sky_day.tscn") as PackedScene).instantiate()
	root.add_child(sky)
	test_sky(sky)
	test_advance(sky)
	test_grade(sky)
	test_drawn_shadows()
	test_ssao(sky)
	sky.queue_free()
	t.finish(self, "look_test")


func test_sun() -> void:
	t.begin("sun position from the hour, latitude and date")
	# NOAA solar calculator: Greenwich, 21 June, 12:00 UTC: elevation 61.97, azimuth 179.4
	var gw := {"lat": 51.4769, "lon": 0.0, "utc_offset_h": 0.0, "day": Daylight.day_of_year("06-21")}
	var p := Daylight.sun_position(gw, 12.0)
	t.near(p.x, 61.97, 0.2, "Greenwich 21 June 12:00 UTC: %.2f deg high" % p.x)
	t.near(p.y, 179.4, 1.0, "bearing %.1f deg" % p.y)
	# the same instant on a clock two hours ahead (summer time in central Europe) at the same place
	var gw2 := gw.duplicate()
	gw2["utc_offset_h"] = 2.0
	t.near(Daylight.sun_position(gw2, 14.0).x, p.x, 1e-3, "the UTC offset only shifts the clock")
	# southern hemisphere: the noon sun stands to the north
	var fr := VenueLook.load_venue("fremantle").site()
	var noon := Daylight.solar_noon(fr)
	var fn := Daylight.sun_position(fr, noon)
	t.ok(fn.y < 10.0 or fn.y > 350.0, "Fremantle in January: the noon sun to the north (%.0f deg)" % fn.y)
	t.near(fn.z, 0.0, 1e-3, "solar noon found (%s)" % Daylight.hour_text(noon))
	var pw := VenueLook.load_venue("practice_waters").site()
	var am := Daylight.sun_position(pw, 8.0)
	var pm := Daylight.sun_position(pw, 18.0)
	t.ok(am.y > 60.0 and am.y < 120.0 and pm.y > 240.0 and pm.y < 300.0,
		"morning sun in the east (%.0f), evening sun in the west (%.0f)" % [am.y, pm.y])
	var r := Daylight.hour_range(pw)
	t.near(Daylight.sun_position(pw, r.x).x, Daylight.MIN_SUN, 0.01, "range starts with the sun at 6 deg")
	t.near(Daylight.sun_position(pw, r.y).x, Daylight.MIN_SUN, 0.01, "range ends with the sun at 6 deg")
	t.near(Daylight.clamp_hour(pw, 23.0), r.y, 1e-6, "a late hour clamps to the last light (%s)" % Daylight.hour_text(r.y))
	t.near(Daylight.sun_position(pw, Daylight.hour_for_sun(pw, 17.0)).x, 17.0, 0.01, "the hour of the 17 deg sun")
	t.ok(Daylight.parse_hour("14:30") == 14.5 and Daylight.parse_hour("7") == 7.0 and Daylight.parse_hour("25:00") < 0.0
		and Daylight.parse_hour("x") < 0.0, "HH:MM parsed")
	t.ok(Daylight.hour_text(19.5) == "19:30" and Daylight.day_of_year("01-01") == 1 and Daylight.day_of_year("12-31") == 365
		and Daylight.day_of_year("02-30") == -1, "clock text and day of the year")


func test_keys() -> void:
	t.begin("hour keyframes: anchors and continuity")
	var pw := VenueLook.load_venue("practice_waters").site()
	# anchors: midday fair is WM-080's fair, the afternoon 17 deg sun the former late preset
	var mid := Daylight.light(pw, Daylight.solar_noon(pw) + 1.3, "fair")
	t.ok(mid["sun_elevation_deg"] >= 38.0, "early afternoon sun above 38 deg (%.0f)" % mid["sun_elevation_deg"])
	t.ok(mid["sun_color"] == Color(1.0, 0.92, 0.80) and is_equal_approx(mid["sun_energy"], 3.6)
		and is_equal_approx(mid["exposure"], 0.5) and mid["horizon"] == Color(0.50, 0.74, 1.10)
		and mid["zenith"] == Color(0.05, 0.18, 0.62) and is_equal_approx(mid["cloud_cover"], 0.4)
		and is_equal_approx(mid["haze_max"], 0.6) and is_equal_approx(mid["haze_begin"], 200.0),
		"midday fair: sun 3.6, exposure 0.50, the fair sky, cumulus 0.4, haze 0.60")
	var late := Daylight.light(pw, Daylight.hour_for_sun(pw, 17.0), "fair")
	t.ok(late["sun_color"].is_equal_approx(Color(1.0, 0.72, 0.44)) and is_equal_approx(late["sun_energy"], 3.8)
		and is_equal_approx(late["exposure"], 0.60) and late["horizon"].is_equal_approx(Color(0.60, 0.70, 0.94))
		and is_equal_approx(late["haze_max"], 0.65) and is_equal_approx(late["cloud_cover"], 0.30),
		"afternoon 17 deg fair: the former late preset (sun 3.8, exposure 0.60, haze 0.65, clouds 0.30)")
	var hz := Daylight.light(pw, Daylight.solar_noon(pw) + 1.3, "hazy")
	t.ok(hz["horizon"].is_equal_approx(Color(0.80, 0.88, 1.00)) and hz["zenith"].is_equal_approx(Color(0.24, 0.40, 0.74))
		and hz["sun_color"].is_equal_approx(Color(1.0, 0.95, 0.88)) and is_equal_approx(hz["sun_energy"], 2.8)
		and is_equal_approx(hz["exposure"], 0.55) and is_equal_approx(hz["haze_max"], 0.8),
		"midday hazy: the former hazy preset")
	# morning cooler than afternoon at the same elevation
	var am := Daylight.light(pw, Daylight.hour_for_sun(pw, 17.0, false), "fair")
	t.ok(am["sun_color"].b > late["sun_color"].b and (am["grade"]["warm"] as Vector3).x < (late["grade"]["warm"] as Vector3).x,
		"17 deg morning sun cooler and its grade less warm than the afternoon's")
	var gold := Daylight.light(pw, Daylight.hour_for_sun(pw, 8.0), "fair")
	t.ok(gold["sun_color"].g < late["sun_color"].g and (gold["grade"]["warm"] as Vector3).x > (late["grade"]["warm"] as Vector3).x
		and gold["exposure"] > late["exposure"], "golden hour warmer still, exposure up")
	# continuity: every value over the day in one-minute steps, every venue and conditions
	var keys := ["sun_energy", "exposure", "cloud_cover", "haze_max"]
	var worst := {}
	for v in VENUES:
		var site := VenueLook.load_venue(v).site()
		var r := Daylight.hour_range(site)
		for c in Daylight.CONDITION_NAMES:
			var prev := {}
			var h := r.x
			while h <= r.y:
				var l := Daylight.light(site, h, c)
				if not prev.is_empty():
					for k in keys:
						worst[k] = maxf(worst.get(k, 0.0), absf(float(l[k]) - float(prev[k])))
					for k in ["sun_color", "horizon", "zenith"]:
						var a: Color = l[k]
						var b: Color = prev[k]
						worst[k] = maxf(worst.get(k, 0.0), maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
					var ga: Dictionary = l["grade"]
					var gb: Dictionary = prev["grade"]
					worst["grade"] = maxf(worst.get("grade", 0.0), maxf(absf(ga["contrast"] - gb["contrast"]),
						maxf((ga["warm"] - gb["warm"]).abs().length(), absf(ga["white_keep"] - gb["white_keep"]))))
					worst["sun_el"] = maxf(worst.get("sun_el", 0.0), absf(l["sun_elevation_deg"] - prev["sun_elevation_deg"]))
				prev = l
				h += 1.0 / 60.0
	var lim := {"sun_energy": 0.02, "exposure": 0.01, "cloud_cover": 0.01, "haze_max": 0.01, "sun_color": 0.01,
		"horizon": 0.01, "zenith": 0.01, "grade": 0.01, "sun_el": 0.3}
	for k in lim:
		t.ok(worst[k] <= lim[k], "continuous through the day: %s moves at most %.4f a minute (limit %.3f)"
			% [k, worst[k], lim[k]])


func test_conditions() -> void:
	t.begin("conditions over the hour")
	var pw := VenueLook.load_venue("practice_waters").site()
	var r := Daylight.hour_range(pw)
	var ok_haze := true
	var ok_cloud := true
	var ok_sun := true
	var ok_pale := true
	var h := r.x
	while h <= r.y:
		var cl := Daylight.light(pw, h, "clear")
		var fa := Daylight.light(pw, h, "fair")
		var hz := Daylight.light(pw, h, "hazy")
		var oc := Daylight.light(pw, h, "overcast")
		ok_haze = ok_haze and cl["haze_max"] < fa["haze_max"] and fa["haze_max"] < hz["haze_max"] \
			and hz["haze_max"] <= Daylight.HAZE_MAX_CAP
		ok_cloud = ok_cloud and cl["cloud_cover"] == 0.0 and is_equal_approx(oc["cloud_cover"], 0.88) \
			and fa["cloud_cover"] > hz["cloud_cover"]
		ok_sun = ok_sun and oc["sun_energy"] < hz["sun_energy"] and hz["sun_energy"] < fa["sun_energy"] \
			and oc["exposure"] > fa["exposure"] and oc["shadow"] < hz["shadow"] and hz["shadow"] < fa["shadow"]
		# hazy is paler (the horizon's blue less above its red) than fair at every hour
		var hb: Color = hz["horizon"]
		var fb: Color = fa["horizon"]
		ok_pale = ok_pale and (hb.b - hb.r) < (fb.b - fb.r)
		h += 0.5
	t.ok(ok_haze, "haze: clear < fair < hazy at every hour, never over 0.9")
	t.ok(ok_cloud, "clouds: clear none, overcast 0.88 all day, fair more cumulus than hazy")
	t.ok(ok_sun, "sun: overcast < hazy < fair, overcast exposed up, drawn shadows fainter")
	t.ok(ok_pale, "hazy horizon paler than fair's at every hour")
	# overcast is diffuse (water_render.md §4.5): the sun about a tenth of the light on a level deck at 14:00, the
	# deck drawn diffuse, a grey sky brighter overhead, the sea body greyer and darker, soft shadows, puffs boosted
	var oc14 := Daylight.light(pw, 14.0, "overcast")
	var sun_lev := float(oc14["sun_energy"]) * sin(deg_to_rad(oc14["sun_elevation_deg"]))
	var sky_lev := (oc14["horizon"] as Color).lerp(oc14["zenith"], 0.5).get_luminance()
	t.ok(sun_lev / (sun_lev + sky_lev) < 0.2, "overcast: the sun %.0f %% of the light" % [100.0 * sun_lev / (sun_lev + sky_lev)])
	t.ok(oc14["diffuse"] == 1.0 and Daylight.light(pw, 14.0, "fair")["diffuse"] == 0.0, "overcast deck diffuse, fair not")
	t.ok((oc14["zenith"] as Color).get_luminance() > (oc14["horizon"] as Color).get_luminance(), "overcast: brighter overhead")
	t.ok((Daylight.light(pw, 18.5, "overcast")["horizon"] as Color).get_luminance()
		< (oc14["horizon"] as Color).get_luminance(), "overcast: the deck dims as the sun drops")
	var sc_f := Daylight.sea_colors(1.0, 1.0)
	var sc_o := Daylight.sea_colors(oc14["sea_saturation"], oc14["sea_value"])
	var df: Vector3 = sc_f["col_deep"]
	var do: Vector3 = sc_o["col_deep"]
	t.ok(df.is_equal_approx(Daylight.SEA_DEEP) and (do.z - do.x) < 0.6 * (df.z - df.x) and do.dot(Daylight.LUMA) < df.dot(Daylight.LUMA),
		"overcast sea body greyer and darker")
	t.ok(oc14["shadow_blur_k"] > 1.0 and oc14["shadow"] <= 0.15 and oc14["puff_k"] > 1.0,
		"overcast: soft faint shadows, puffs boosted")
	var am := Daylight.light(pw, 8.0, "fair")
	var md := Daylight.light(pw, 13.0, "fair")
	t.ok(am["cloud_cover"] < md["cloud_cover"], "cumulus build through the day (%.2f at 08:00, %.2f at 13:00)"
		% [am["cloud_cover"], md["cloud_cover"]])
	var unknown := Daylight.light(pw, 13.0, "foggy")
	t.ok(unknown["cloud_cover"] == md["cloud_cover"], "unknown conditions: fair")


func test_look_files() -> void:
	t.begin("venue look files")
	for v in VENUES:
		var l := VenueLook.load_venue(v)
		t.ok(l.has_file and l.problems.is_empty(), "%s: loads (%s)" % [v, ", ".join(l.problems)])
		var r10 := Daylight.hour_range(l.site(), Daylight.MIN_RACE_SUN)
		t.ok(l.race_window.x >= r10.x and l.race_window.y <= r10.y,
			"%s: window %s to %s with the sun at 10 deg or more (%s to %s)" % [v, Daylight.hour_text(l.race_window.x),
			Daylight.hour_text(l.race_window.y), Daylight.hour_text(r10.x), Daylight.hour_text(r10.y)])
		t.ok(l.time >= l.race_window.x and l.time <= l.race_window.y and l.typical.has(l.conditions),
			"%s: default %s %s inside the window and typical, sun %.0f deg" % [v, Daylight.hour_text(l.time), l.conditions,
			Daylight.sun_position(l.site(), l.time).x])
		var p1 := l.pick("random", 7)
		var p2 := l.pick("random", 7)
		var inside := true
		for s in 30:
			var p := l.pick("random", s)
			inside = inside and p["hour"] >= l.race_window.x and p["hour"] <= l.race_window.y \
				and l.typical.has(p["conditions"])
		t.ok(p1 == p2 and inside, "%s: a Random race draws from the seed, in the window and the typical conditions" % v)
		t.ok(l.pick("local", 7) == {"hour": l.time, "conditions": l.conditions}, "%s: Local takes the defaults" % v)
	var none := VenueLook.load_venue("")
	t.ok(none.lat == 45.5 and none.site()["day"] > 0, "open water: Practice Waters' site")
	var bad := VenueLook.new()
	bad._read({"schema": "x", "light": {"date": "13-01", "time": "noon", "conditions": "foggy", "race_window": ["18:00", "10:00"]}})
	t.ok(bad.problems.size() == 5 and bad.time == VenueLook.DEFAULT_TIME and bad.conditions == "fair",
		"a bad file keeps the defaults and names its 5 problems")


func test_sky(sky: SkyRig) -> void:
	t.begin("SkyRig: time of day and conditions")
	t.ok(sky.conditions == "fair" and sky.hour == VenueLook.DEFAULT_TIME, "fair at 14:30 by default")
	var env := sky.environment()
	sky.set_light(18.0, "hazy")
	var d := sky.sun_direction()
	t.near_v(sky.sun().global_basis.z, d, 1e-4, "the light shines from the sun of 18:00")
	t.near(rad_to_deg(asin(d.y)), Daylight.sun_position(sky.site, 18.0).x, 0.01, "at its elevation")
	t.near(env.tonemap_exposure, sky.exposure, 1e-6, "the exposure on the environment")
	t.near(env.fog_density, sky.haze_max, 1e-6, "the haze on the environment")
	var m := env.sky.sky_material as ShaderMaterial
	t.ok(is_equal_approx(m.get_shader_parameter("cloud_cover"), sky.cloud_cover), "the clouds on the sky shader")
	t.ok(env.adjustment_color_correction == LookFx.lut(LookFx.scaled(sky.grade, 1.0)), "the light's grade on the environment")
	t.ok(sky.set_preset_name("late"), "late is an old preset name")
	t.near(sky.sun_elevation_deg, 17.0, 0.02, "late: afternoon sun 17 deg (%.2f)" % sky.sun_elevation_deg)
	t.ok(sky.conditions == "fair" and sky.preset_name() == "late", "late: fair, and it reads back as late")
	t.near(sky.exposure, 0.60, 1e-4, "late exposure 0.60")
	t.ok(sky.set_preset_name("hazy") and sky.conditions == "hazy" and absf(sky.sun_elevation_deg - 38.0) < 0.05,
		"hazy: hazy at the 38 deg afternoon sun")
	t.ok(not sky.set_preset_name("dusk") and sky.conditions == "hazy", "unknown names refused")
	sky.hour = 23.5
	t.near(sky.sun_elevation_deg, Daylight.MIN_SUN, 0.02, "a late hour clamps to the 6 deg sun")
	t.ok(sky.hour < 23.0, "the hour itself clamped (%s)" % Daylight.hour_text(sky.hour))
	var tr := VenueLook.load_venue("trieste")
	sky.set_site(tr.site())
	sky.set_preset_name("fair")
	t.near(sky.hour, Daylight.solar_noon(tr.site()), 1e-3, "Trieste in October never reaches 38 deg: fair at noon")
	sky.set_site(Daylight.DEFAULT_SITE)
	sky.set_light(VenueLook.DEFAULT_TIME, "fair")


func test_advance(sky: SkyRig) -> void:
	t.begin("the clock runs in steps")
	sky.set_light(17.5, "fair")
	var lut0 := sky.environment().adjustment_color_correction
	sky.light_advance = 60.0  # a game minute per real second
	sky._process(4.0)
	t.near(sky.hour, 17.5, 1e-9, "no step before 5 s of real time")
	sky._process(1.5)
	t.near(sky.hour, 17.5 + 5.5 / 60.0, 1e-6, "a step after 5 s: the hour moved 5.5 game minutes")
	t.ok(sky.environment().adjustment_color_correction == lut0, "the grade waits for a quarter hour")
	for i in 3:
		sky._process(5.0)
	t.ok(sky.hour > 17.75 and sky.environment().adjustment_color_correction != lut0,
		"after a quarter hour the grade follows (%s)" % Daylight.hour_text(sky.hour))
	sky.light_advance = 1.0
	var h0 := sky.hour
	sky._process(10.0)
	t.near(sky.hour, h0, 1e-9, "real time: no step until the hour moved a game minute")
	sky.light_advance = 0.0
	sky._process(100.0)
	t.near(sky.hour, h0, 1e-9, "fixed by default")
	sky.set_light(VenueLook.DEFAULT_TIME, "fair")


func test_grade(sky: SkyRig) -> void:
	t.begin("colour grade")
	var env := sky.environment()
	var pw := VenueLook.load_venue("practice_waters").site()
	var cases := {
		"midday fair": Daylight.light(pw, 14.0, "fair")["grade"],
		"morning fair": Daylight.light(pw, 8.5, "fair")["grade"],
		"golden fair": Daylight.light(pw, 19.0, "fair")["grade"],
		"midday hazy": Daylight.light(pw, 14.0, "hazy")["grade"],
		"midday overcast": Daylight.light(pw, 14.0, "overcast")["grade"],
	}
	for name in cases:
		var g: Dictionary = cases[name]
		t.ok(LookFx.grade(Vector3.ZERO, g).length() < 1e-6, "%s: black stays black" % name)
		t.ok(LookFx.grade(Vector3.ONE, g).distance_to(Vector3.ONE) < 1e-6, "%s: white stays white" % name)
		var lo := LookFx.grade(Vector3(0.2, 0.2, 0.2), g)
		var sea := LookFx.grade(Vector3(0.55, 0.45, 0.35), g)
		t.ok(lo.z > lo.x, "%s: shadows cooler (%.3f %.3f %.3f)" % [name, lo.x, lo.y, lo.z])
		t.ok(sea.x - sea.z > 0.20, "%s: the light warmer (%.3f %.3f %.3f)" % [name, sea.x, sea.y, sea.z])
		var mono := true
		var prev := -1.0
		var worst := 0.0
		for i in 33:
			var x := i / 32.0
			var y := LookFx.grade(Vector3(x, x, x), g)
			mono = mono and y.dot(LookFx.LUMA) >= prev - 1e-6
			prev = y.dot(LookFx.LUMA)
			for c in [Vector3(x, x, x), Vector3(x, 0.3, 0.6), Vector3(0.8, x, 0.2), Vector3(0.1, 0.5, x)]:
				var dv: Vector3 = (LookFx.grade(c, g) - c).abs()
				worst = maxf(worst, dv[dv.max_axis_index()])
		t.ok(mono, "%s: the grey ramp stays in order" % name)
		var least := 0.02 if name.ends_with("overcast") else 0.06  # overcast: a flat, low-contrast grade
		t.ok(worst > least and worst <= 0.16, "%s: clearly visible but bounded: values move up to %.3f" % [name, worst])
	# whites at midday: a white or light grey sail stays neutral, at strength 1 and 1.5
	for k in [1.0, 1.5]:
		var g := LookFx.scaled(cases["midday fair"], k)
		var worst_c := 0.0
		var darker := 0.0
		for i in 9:
			var x := 0.6 + 0.05 * i
			var y := LookFx.grade(Vector3(x, x, x), g)
			worst_c = maxf(worst_c, y[y.max_axis_index()] - y[y.min_axis_index()])
			darker = maxf(darker, x - y.dot(LookFx.LUMA))
		t.ok(worst_c <= 0.02 and darker <= 0.02, "midday whites (0.6 to 1) stay white at strength %.1f: tint %.3f, darker by %.3f"
			% [k, worst_c, darker])
	var gold := LookFx.grade(Vector3(0.85, 0.85, 0.85), cases["golden fair"])
	t.ok(gold.x - gold.z > 0.01, "golden hour lets the sails warm (%.3f)" % (gold.x - gold.z))
	var m := LookFx.grade(Vector3(0.5, 0.45, 0.4), cases["morning fair"])
	var a := LookFx.grade(Vector3(0.5, 0.45, 0.4), cases["golden fair"])
	t.ok(m.x - m.z < a.x - a.z, "morning cleaner and cooler than golden hour")
	# strength: 0 off, 1 the grade, 1.5 more
	var g1: Dictionary = cases["midday fair"]
	var c0 := Vector3(0.3, 0.5, 0.7)
	t.ok(LookFx.grade(c0, LookFx.scaled(g1, 0.0)).distance_to(c0) < 1e-6, "strength 0: no change")
	t.ok(LookFx.grade(c0, LookFx.scaled(g1, 1.5)).distance_to(c0) > LookFx.grade(c0, g1).distance_to(c0),
		"strength 1.5 stronger than 1")
	LookFx.grade_strength = 0.0
	sky.apply_grade()
	t.ok(not env.adjustment_enabled, "strength 0: the LUT skipped")
	LookFx.grade_strength = 1.0
	sky.apply_grade()
	t.ok(env.adjustment_enabled and env.adjustment_brightness == 1.0 and env.adjustment_contrast == 1.0
		and env.adjustment_saturation == 1.0, "strength 1: the LUT, brightness, contrast and saturation at 1")
	var imgs := LookFx.lut_images(g1)
	t.ok(imgs.size() == LookFx.LUT_SIZE and imgs[0].get_width() == LookFx.LUT_SIZE, "33 slices of 33 x 33")
	var c := imgs[20].get_pixel(5, 30)
	var want := LookFx.grade(Vector3(LookFx.lut_coord(5), LookFx.lut_coord(30), LookFx.lut_coord(20)), g1)
	t.near_v(Vector3(c.r, c.g, c.b), want, 1.0 / 255.0, "a texel holds the grade of its sampling point")
	t.near(LookFx.lut_coord(16), 16.5 / 33.0, 1e-9, "texel i read at (i + 0.5)/N")
	t.ok(LookFx.lut_coord(0) == 0.0 and LookFx.lut_coord(32) == 1.0, "end texels hold black and white")
	t.ok(LookFx.lut(g1) == LookFx.lut(g1.duplicate()), "a LUT reused for the same grade")
	LookFx.enabled = false
	sky.apply_grade()
	t.ok(not env.adjustment_enabled, "--look=off: no grade")
	LookFx.enabled = true
	sky.apply_grade()
	t.ok(env.adjustment_enabled, "grade back on")


func test_drawn_shadows() -> void:
	t.begin("drawn shadows")
	t.near(BoatShadows.keep_for(1.0).x, BoatShadows.KEEP.x, 1e-9, "drawn shadows: full sun keeps the matched factor")
	t.ok(BoatShadows.keep_for(0.35).y > BoatShadows.KEEP.y and BoatShadows.keep_for(0.0) == Vector3.ONE,
		"overcast drawn shadows fainter, none without sun")


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
