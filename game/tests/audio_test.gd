extends SceneTree
## Audio tests (docs/specs/audio.md §11) run headless:
##   1. formula evaluation (the boat.wake terms of the default map, the other §3 and §4 formulas)
##   2. gates (boat.luff_main: hold 0.2 s both ways, 0.09 never starts it), on the formula and in GameAudio
##   3. triggers (a scripted bow_dz series: slaps at 0, 0.4 and 0.8 s), on the formula and from boat states
##   4. signals through the Hud's hud_event (5-4-1-0: horn, horn, long horn, horn; general recall two horns
##      0.8 s apart; the committee boat copy; the ambience ducking; the penalty for the own boat only)
##   5. swap (a second map plays its own files; a user:// sound set loads at run time; a missing file warns once
##      and the race runs; the synthesised fallback)
##   6. voices (20 boats around the listener: at most 48 players, the own boat's never dropped)
##   plus the buses and the settings' volumes, the pause ducking, the wind pan and beds, and the sail test scene
##   (FakeSim, then a race on the core) with its sound.
##   godot --headless --path game -s res://tests/audio_test.gd

const KN := HudFormat.KNOT
const DT := 1.0 / 60.0

var t := TestLog.new()
var warnings: Array = []


func _init() -> void:
	SoundMap.warn_hook = func(msg: String) -> void: warnings.append(msg)
	await process_frame
	test_formulas()
	test_gates()
	test_triggers()
	test_signals()
	test_swap()
	test_voices()
	test_buses_settings()
	await test_audible()
	await test_scene_fake()
	if CoreSimSource.available():
		await test_scene_core_race()
	else:
		t.ok(false, "the GDExtension is not loaded: core scene test skipped")
	SoundMap.warn_hook = Callable()
	t.finish(self, "audio_test")


func _map() -> SoundMap:
	var m := SoundMap.load_file()
	t.ok(m != null, "default sound map loads")
	return m


## A GameAudio on a stub race with a node per boat at its position; boat 0 at the origin.
func _audio(sim: RaceStubSim, m: SoundMap = null) -> GameAudio:
	var nodes := []
	for b in sim.boat_count():
		var n := Node3D.new()
		var s := sim.state(b)
		n.position = Frames.enu_to_scene(s.pos_x, s.pos_y, 0.0)
		get_root().add_child(n)
		nodes.append(n)
	var a := GameAudio.new()
	get_root().add_child(a)
	a.rng.seed = 5
	a.setup(sim, nodes, 0, m if m != null else _map())
	a.set_meta("nodes", nodes)
	return a


func _free(a: GameAudio) -> void:
	for n in a.get_meta("nodes", []):
		n.free()
	a.free()


func _cam(at: Vector3) -> Camera3D:
	var c := Camera3D.new()
	get_root().add_child(c)
	c.global_position = at
	return c


func _run(a: GameAudio, sim: SimSource, seconds: float, cam: Camera3D = null, hud: Hud = null) -> void:
	var n := int(round(seconds / DT))
	var acc := 0.0
	for i in n:
		acc += DT
		while acc >= SimSource.DT - 1e-9:
			acc -= SimSource.DT
			sim.step()
			if hud:
				hud.tick(sim, 0)
			a.tick()
		a.frame(DT, cam)


func _played(a: GameAudio, id := "", space := "") -> Array:
	return a.played.filter(func(p: Dictionary) -> bool:
		return (id == "" or p["id"] == id) and (space == "" or p["space"] == space))


# ---- 1 -----------------------------------------------------------------------------------------------------------

func test_formulas() -> void:
	t.begin("formula evaluation (audio.md §11.1)")
	var m := _map()
	var wake := m.entry("boat.wake")
	var want_v := [0.5, 0.75, 1.0, 1.0]
	var want_p := [0.8, 0.95, 1.1, 1.1]
	var kn := [0.0, 6.67, 13.3, 20.0]
	for i in kn.size():
		var inp := {"v_kn": kn[i]}
		t.near(SoundFormula.value(wake["volume_terms"], inp), want_v[i], 0.005, "wake volume at %.2f kn" % kn[i])
		t.near(SoundFormula.value(wake["pitch_terms"], inp), want_p[i], 0.005, "wake pitch at %.2f kn" % kn[i])
	# the other formulas of §3 and §4 as the map writes them
	var hull := m.entry("boat.hull")
	var bow := m.entry("boat.bow")
	for v in [0.0, 1.0, 2.0, 5.0, 10.0, 15.0]:
		t.near(SoundFormula.value(hull["volume_terms"], {"v_kn": v}), clampf(0.5 + v / 20.0, 0.5, 1.0), 1e-4,
			"hull volume at %.0f kn" % v)
		t.near(SoundFormula.value(bow["volume_terms"], {"v_kn": v}), clampf((v - 2.0) / 8.0, 0.0, 1.0), 1e-4,
			"bow volume at %.0f kn" % v)
	var slap := m.entry("boat.slap")
	for dz in [-0.1, -0.5, -1.5, -3.0]:
		t.near(SoundFormula.value(slap["volume_terms"], {"bow_dz": dz}), clampf(absf(dz) / 1.5, 0.2, 1.0), 1e-3,
			"slap volume at bow_dz %.1f" % dz)
	var rig := m.entry("boat.rig")
	var bed := m.entry("wind.bed")
	var whistle := m.entry("wind.whistle")
	for aws in [2.0, 8.0, 15.0, 22.0, 30.0, 45.0]:
		t.near(float(rig["volume"]) * SoundFormula.value(rig["volume_terms"], {"aws": aws}),
			0.25 * clampf(0.4 + aws / 15.0, 0.4, 1.0), 1e-3, "rig volume at %.0f m/s" % aws)
		for cam in [1.0, 0.4]:
			t.near(SoundFormula.value(bed["volume_terms"], {"aws": aws, "cam_wind": cam}),
				clampf(aws / 40.0, 0.2, 1.0) * cam, 1e-4, "wind bed at %.0f m/s, cam %.1f" % [aws, cam])
			t.near(SoundFormula.value(whistle["volume_terms"], {"aws": aws, "cam_wind": cam}),
				clampf((aws - 12.0) / 10.0, 0.0, 1.0) * cam, 1e-4, "whistle at %.0f m/s" % aws)
	var luff := m.entry("boat.luff_main")
	var kite := m.entry("boat.luff_kite")
	t.near(SoundFormula.value(luff["pitch_terms"], {"tws_kn": 15.0}), 15.0 / 30.0 + 0.7, 1e-3, "luff pitch")
	t.near(SoundFormula.value(kite["pitch_terms"], {"tws_kn": 15.0}), 15.0 / 30.0 + 0.53, 1e-3, "kite flog pitch")
	t.ok(m.has("boat.winch:main") and m.has("boat.winch:front") and m.has("boat.sheet_run:front"),
		"slots expand to one sound per slot")
	t.ok(m.entry("boat.winch:front")["gate"]["in"] == "sail.front.motion", "slot substituted in the gate")
	var w := SoundFormula.bed_weights(10.0, [6, 14, 22], 2.0)
	t.ok(w[1] == 1.0 and w[0] == 0.0 and w[2] == 0.0, "ambience: moderate alone at 10 kn")
	w = SoundFormula.bed_weights(14.0, [6, 14, 22], 2.0)
	t.near(w[1], 0.5, 1e-6, "ambience: half moderate at 14 kn")
	t.near(w[2], 0.5, 1e-6, "ambience: half fresh at 14 kn")
	w = SoundFormula.bed_weights(30.0, [6, 14, 22], 2.0)
	t.ok(w[3] == 1.0 and w[2] == 0.0, "ambience: strong above 23 kn")
	t.near(SoundSynth.pitch_factor("wind", {"aws": 20.0}), 1.0, 1e-6, "synth wind at its reference")
	t.near(SoundSynth.pitch_factor("water", {"v_kn": 5.0}), 900.0 / 1200.0, 1e-6, "synth water filter by pitch")


# ---- 2 -----------------------------------------------------------------------------------------------------------

func test_gates() -> void:
	t.begin("gates (audio.md §11.2)")
	var m := _map()
	var g := SoundFormula.Gate.new(m.entry("boat.luff_main")["gate"])
	var opened := NAN
	var closed := NAN
	var tt := 0.0
	var dt := 0.01
	while tt < 2.0:
		var luff := 0.5 if tt >= 0.5 - 1e-9 and tt < 1.2 - 1e-9 else 0.0
		var was := g.open
		g.update({"sail.main.luff": luff}, dt)
		if g.open and not was:
			opened = tt
		if was and not g.open:
			closed = tt
		tt += dt
	t.near(opened, 0.7, 0.011, "opens 0.2 s after the luff rises above 0.1")
	t.near(closed, 1.4, 0.011, "closes 0.2 s after it falls")
	var g2 := SoundFormula.Gate.new(m.entry("boat.luff_main")["gate"])
	var ever := false
	for i in 300:
		ever = ever or g2.update({"sail.main.luff": 0.09}, dt)
	t.ok(not ever, "a luff of 0.09 never starts it")
	var g3 := SoundFormula.Gate.new(m.entry("boat.luff_main")["gate"])
	var chatter := false
	for i in 100:  # 0.15 s up, 0.05 s down: never held 0.2 s
		chatter = chatter or g3.update({"sail.main.luff": 0.5 if i % 20 < 15 else 0.0}, dt)
	t.ok(not chatter, "a luff that never holds 0.2 s does not start it")
	var hs := SoundFormula.Gate.new(m.entry("boat.halyard")["gate"])
	t.ok(hs.update({"sail.change.phase": 2.0, "sail.change.furling": 0.0}, dt), "halyard: all conditions")
	var fs := SoundFormula.Gate.new(m.entry("boat.furl")["gate"])
	t.ok(fs.update({"sail.change.phase": 5.0, "sail.change.furling": 1.0}, dt), "furl: equals a list")
	# in GameAudio: the luff sound of the own boat
	var sim := RaceStubSim.new(1)
	var a := _audio(sim, m)
	_run(a, sim, 0.5)
	t.ok(not "boat.luff_main" in a.active_loops(0), "no luff sound while the main is trimmed")
	sim.sv.out[0].luff_shiver = 0.5
	_run(a, sim, 0.15)
	t.ok(not "boat.luff_main" in a.active_loops(0), "not yet after 0.15 s")
	_run(a, sim, 0.15)
	t.ok("boat.luff_main" in a.active_loops(0), "luff sound after 0.3 s")
	t.ok(a.voice_state("boat.luff_main", 0)["bus"] == "own_boat", "own boat on own_boat")
	sim.sv.out[0].luff_shiver = 0.0
	_run(a, sim, 1.0)
	t.ok(not "boat.luff_main" in a.active_loops(0), "stopped after the luff falls")
	sim.sv.out[0].motion = SimSource.Motion.SHEETING
	_run(a, sim, 0.3)
	t.ok("boat.winch:main" in a.active_loops(0), "winch while sheeting the main")
	sim.sv.out[0].motion = SimSource.Motion.IDLE
	_run(a, sim, 0.3)
	t.ok(_played(a, "boat.sheet_load:main").size() == 1, "the sheet takes the load when the winch stops")
	_free(a)


# ---- 3 -----------------------------------------------------------------------------------------------------------

func test_triggers() -> void:
	t.begin("triggers (audio.md §11.3)")
	var m := _map()
	var tr := SoundFormula.Trigger.new(m.entry("boat.slap")["trigger"])
	var fired := []
	for i in range(-1, 21):  # every 0.05 s; below -0.4 at 0, 0.2, 0.4, 0.6, 0.8 s for 0.1 s each
		var tt := i * 0.05
		var dz := -0.6 if i >= 0 and i <= 17 and i % 4 < 2 else 0.0
		if tr.update({"bow_dz": dz}, tt):
			fired.append(snappedf(tt, 0.001))
	t.ok(fired == [0.0, 0.4, 0.8], "slaps at 0, 0.4 and 0.8 s: %s" % str(fired))
	var sign := SoundFormula.Trigger.new(m.entry("boat.boom_cross")["trigger"])
	sign.update({"sail.main.beta": 0.5, "sail.main.beta_rate": 0.0}, 0.0)
	t.ok(not sign.update({"sail.main.beta": -0.5, "sail.main.beta_rate": 0.3}, 0.1), "a slow gybe: no bang")
	t.ok(sign.update({"sail.main.beta": 0.5, "sail.main.beta_rate": 2.0}, 1.5), "a crash gybe bangs")
	# from the boat's states: the bow dropping into the water
	var sim := RaceStubSim.new(1)
	var a := _audio(sim, m)
	_run(a, sim, 0.3)
	var z := 0.0
	var t0 := a.time
	for k in 24:  # per tick: drop 0.6 m/s for 2 ticks, rise for 2 (bow_dz -0.6 at ticks 0, 4, 8, ...)
		z += -0.03 if k % 4 < 2 else 0.03
		sim.states[0].z = z
		sim.step()
		a.tick()
		for f in 3:
			a.frame(SimSource.DT / 3.0)
	var slaps := _played(a, "boat.slap")
	var times := slaps.map(func(p: Dictionary) -> float: return snappedf(float(p["t"]) - t0, 0.01))
	t.ok(times == [0.0, 0.4, 0.8], "slaps from the states at 0, 0.4, 0.8 s: %s" % str(times))
	var files := slaps.map(func(p: Dictionary) -> String: return String(p["file"]))
	var repeat := false
	for i in range(1, files.size()):
		repeat = repeat or files[i] == files[i - 1]
	t.ok(not repeat and files.size() == 3 and String(files[0]).contains("slap_"), "random variants, never twice")
	_free(a)


# ---- 4 -----------------------------------------------------------------------------------------------------------

func test_signals() -> void:
	t.begin("signals (audio.md §11.4) through Hud.hud_event")
	var sim := RaceStubSim.new(2)
	sim.put(1, 50.0, -50.0, 0.0, 3.0)
	var a := _audio(sim)
	var h := Hud.new()
	get_root().add_child(h)
	h.hud_event.connect(a.on_hud_event)
	h.tick(sim, 0)
	_run(a, sim, 0.2, null, h)
	var kinds := [RaceText.SignalKind.WARNING, RaceText.SignalKind.PREP_UP, RaceText.SignalKind.PREP_DOWN,
		RaceText.SignalKind.START]
	var at := []
	for k in kinds:
		sim.race_ev = [_rev(RaceText.Ev.SIGNAL, {"signal": k, "flag": RaceText.Flag.P})]
		_run(a, sim, SimSource.DT, null, h)
		at.append(a.time)
		sim.race_ev = []
		_run(a, sim, 3.0, null, h)
	var two := _played(a, "", "2d").filter(func(p: Dictionary) -> bool: return String(p["id"]).begins_with("race."))
	t.ok(two.map(func(p: Dictionary) -> String: return p["id"]) == ["race.horn", "race.horn", "race.horn_long",
		"race.horn"], "5-4-1-0: horn, horn, long horn, horn: %s" % str(two.map(func(p: Dictionary) -> String:
			return p["id"])))
	var at_ok := two.size() == 4
	for i in mini(two.size(), 4):
		at_ok = at_ok and absf(float(two[i]["t"]) - float(at[i])) < 0.05
	t.ok(at_ok, "each at its signal tick")
	var three := _played(a, "", "3d").filter(func(p: Dictionary) -> bool: return String(p["id"]).begins_with("race."))
	t.ok(three.size() == 4 and three.all(func(p: Dictionary) -> bool: return p["bus"] == "race"),
		"and at the committee boat, on the race bus")
	# general recall: two horns 0.8 s apart; the ambience ducks
	a.played.clear()
	sim.race_ev = [_rev(RaceText.Ev.SIGNAL, {"signal": RaceText.SignalKind.GENERAL_RECALL})]
	_run(a, sim, SimSource.DT, null, h)
	sim.race_ev = []
	_run(a, sim, 0.5, null, h)
	t.ok(AudioBuses.duck("ambience") < -4.0 and AudioBuses.duck("venue") < -4.0, "a signal ducks the ambience %.1f dB"
		% AudioBuses.duck("ambience"))
	t.ok(AudioBuses.duck("own_boat") > -0.1, "and nothing else")
	_run(a, sim, 3.0, null, h)
	var rec := _played(a, "race.horn", "2d")
	t.ok(rec.size() == 2, "general recall: two horns (%d)" % rec.size())
	if rec.size() == 2:
		t.near(float(rec[1]["t"]) - float(rec[0]["t"]), 0.8, 0.02, "0.8 s apart")
	t.ok(AudioBuses.duck("ambience") > -0.5, "the ducking ends")
	# penalties: the own boat only
	a.played.clear()
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY, {"boat": 1, "other": 0, "rule": RaceText.Rule.R10})]
	_run(a, sim, SimSource.DT, null, h)
	sim.rules_ev = []
	_run(a, sim, 0.2, null, h)
	t.ok(_played(a, "race.penalty").is_empty(), "another boat's penalty is silent")
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY, {"boat": 0, "other": 1, "rule": RaceText.Rule.R10})]
	_run(a, sim, SimSource.DT, null, h)
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_SERVED, {"boat": 0})]
	_run(a, sim, SimSource.DT, null, h)
	sim.rules_ev = []
	_run(a, sim, 0.2, null, h)
	t.ok(_played(a, "race.penalty").size() == 1, "the own penalty sounds")
	t.ok(_played(a, "race.penalty_done").size() == 1, "and penalty done")
	# OCS (§5): the own boat's plays race.ocs once, another boat's nothing
	a.played.clear()
	sim.race_ev = [_rev(RaceText.Ev.BOAT_OCS, {"boat": 1, "flag": RaceText.Flag.P})]
	_run(a, sim, SimSource.DT, null, h)
	sim.race_ev = []
	_run(a, sim, 0.2, null, h)
	t.ok(_played(a, "race.ocs").is_empty(), "another boat's OCS is silent")
	sim.race_ev = [_rev(RaceText.Ev.BOAT_OCS, {"boat": 0, "flag": RaceText.Flag.P})]
	_run(a, sim, SimSource.DT, null, h)
	sim.race_ev = []
	_run(a, sim, 0.2, null, h)
	var ocs := _played(a, "race.ocs")
	t.ok(ocs.size() == 1 and ocs[0]["bus"] == "race" and ocs[0]["file"] != "", "the own OCS sounds: %s" % str(ocs))
	# a rule warning with the own boat holding right of way: no voice files in the default set, so silent
	sim.rules_ev = [_uev(RaceText.Rev.RULE_WARNING, {"boat": 1, "other": 0, "rule": RaceText.Rule.R10})]
	_run(a, sim, SimSource.DT, null, h)
	sim.rules_ev = []
	t.ok(_played(a, "voice.hail_starboard").is_empty() and warnings.is_empty(), "hails silent without files")
	# countdown beeps (§5, hud.md §14): Full and Standard, not Minimal
	t.ok(GameAudio.beeps_at(Hud.Assist.FULL) and GameAudio.beeps_at(Hud.Assist.STANDARD)
		and not GameAudio.beeps_at(Hud.Assist.MINIMAL), "countdown beeps at Full and Standard, not Minimal")
	a.played.clear()
	a.countdown_beeps = GameAudio.beeps_at(Hud.Assist.STANDARD)
	sim.race_d["state"] = RaceText.RaceState.SEQUENCE
	for i in 700:  # race time -32 s to +3 s
		sim.race_d["race_time"] = -32.0 + i * SimSource.DT
		sim.step()
		a.tick()
		a.frame(SimSource.DT)
	t.ok(_played(a, "race.beep").size() == 8, "countdown beeps at 30, 20, 10, 5 to 1 s (%d)"
		% _played(a, "race.beep").size())
	h.free()
	_free(a)


func _rev(kind: int, fields: Dictionary) -> Dictionary:
	var e := {"kind": kind, "tick": 0, "boat": -1, "signal": 0, "flag": 0, "step": -1, "buoy": -1, "t": 0.0,
		"t_us": 0, "place": 0, "block": 0, "ghost": 0, "value": 0.0}
	e.merge(fields, true)
	return e


func _uev(kind: int, fields: Dictionary) -> Dictionary:
	var e := {"kind": kind, "tick": 0, "boat": -1, "other": -1, "rule": 0, "count": 1, "contact": false,
		"mark": -1, "deadline": 0.0}
	e.merge(fields, true)
	return e


# ---- 5 -----------------------------------------------------------------------------------------------------------

func _write_map(path: String, edit: Callable) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SoundMap.DEFAULT_PATH))
	edit.call(d)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func test_swap() -> void:
	t.begin("swap (audio.md §11.5)")
	# a second map with other files: no code change
	_write_map("user://audio_test_swap.json", func(d: Dictionary) -> void:
		d["root"] = "res://audio/default"
		d["sounds"]["race.horn"]["files"] = ["race/horn_finish.ogg"]
		d["sounds"]["boat.hull"]["files"] = ["venue/buoy_loop.ogg"])
	var m2 := SoundMap.load_file("user://audio_test_swap.json")
	t.ok(m2 != null, "second map loads")
	var sim := RaceStubSim.new(1)
	var a := _audio(sim, m2)
	a.race_signal(RaceText.SignalKind.WARNING)
	_run(a, sim, 0.3)
	var p := _played(a, "race.horn", "2d")
	t.ok(p.size() == 1 and String(p[0]["file"]) == "res://audio/default/race/horn_finish.ogg",
		"the horn plays the second map's file")
	t.ok(a.voice_state("boat.hull", 0).get("file", "") == "res://audio/default/venue/buoy_loop.ogg",
		"the hull loop plays the second map's file")
	_free(a)
	# a sound set outside res:// loads at run time
	DirAccess.make_dir_recursive_absolute("user://audio_test_set/race")
	var src := FileAccess.get_file_as_bytes("res://audio/default/race/horn.ogg")
	var f := FileAccess.open("user://audio_test_set/race/signal.ogg", FileAccess.WRITE)
	f.store_buffer(src)
	f.close()
	_write_map("user://audio_test_set/map.json", func(d: Dictionary) -> void:
		d["root"] = "."
		d["sounds"] = {"race.horn": {"files": ["race/signal.ogg"], "bus": "race", "space": "2d"}}
		d["ambience"] = {})
	var m3 := SoundMap.load_file("user://audio_test_set/map.json")
	sim = RaceStubSim.new(1)
	a = _audio(sim, m3)
	a.race_signal(RaceText.SignalKind.START)
	p = _played(a, "race.horn", "2d")
	t.ok(src.size() > 0 and p.size() == 1 and String(p[0]["file"]).ends_with("audio_test_set/race/signal.ogg"),
		"a user:// sound set plays through AudioStreamOggVorbis.load_from_file")
	t.ok(warnings.is_empty(), "no warnings for a set without the boat sounds: %s" % str(warnings))
	_free(a)
	# a missing file: one warning, the rest plays, the race runs
	warnings.clear()
	SoundMap.reset_warnings()
	_write_map("user://audio_test_missing.json", func(d: Dictionary) -> void:
		d["root"] = "res://audio/default"
		d["sounds"]["race.horn"]["files"] = ["race/no_such_horn.ogg"]
		d["sounds"]["race.horn"].erase("synth")
		d["sounds"]["boat.wake"]["files"] = ["boat/no_such_wake.ogg"]
		d["sounds"]["boat.wake"].erase("synth"))
	var m4 := SoundMap.load_file("user://audio_test_missing.json")
	sim = RaceStubSim.new(2)
	sim.put(0, 0.0, 0.0, 0.0, 4.0)
	a = _audio(sim, m4)
	for k in [RaceText.SignalKind.WARNING, RaceText.SignalKind.PREP_UP, RaceText.SignalKind.START]:
		a.race_signal(k)
		_run(a, sim, 1.0)
	var horn_warn := warnings.filter(func(w: String) -> bool: return w.contains("no_such_horn"))
	var wake_warn := warnings.filter(func(w: String) -> bool: return w.contains("no_such_wake"))
	t.ok(horn_warn.size() == 1 and wake_warn.size() == 1, "one warning per missing file: %s" % str(warnings))
	t.ok(_played(a, "race.horn").is_empty(), "the missing horn is disabled")
	a.race_signal(RaceText.SignalKind.PREP_DOWN)
	t.ok(_played(a, "race.horn_long").size() == 2, "the long horn still plays")
	t.ok("boat.hull" in a.active_loops(0) and not "boat.wake" in a.active_loops(0), "the hull plays, the wake not")
	t.ok(sim.tick() > 50, "the race ran (%d ticks)" % sim.tick())
	_free(a)
	# the synthesised fallback: the same entry without files
	warnings.clear()
	SoundMap.reset_warnings()
	_write_map("user://audio_test_synth.json", func(d: Dictionary) -> void:
		d["root"] = "res://audio/default"
		d["sounds"]["race.horn"]["files"] = ["race/gone.ogg"]
		d["sounds"]["wind.bed"]["files"] = ["wind/gone.ogg"]
		d["sounds"]["boat.wake"]["files"] = ["boat/gone.ogg"])
	var m5 := SoundMap.load_file("user://audio_test_synth.json")
	sim = RaceStubSim.new(1)
	sim.put(0, 0.0, 0.0, 0.0, 10.0 * KN)
	sim.states[0].aws = 20.0
	a = _audio(sim, m5)
	a.race_signal(RaceText.SignalKind.WARNING)
	_run(a, sim, 1.0)
	p = _played(a, "race.horn", "2d")
	t.ok(p.size() == 1 and p[0]["file"] == "synth:horn", "the horn falls back to the synthesised horn")
	var bed := a.voice_state("wind.bed")
	t.ok(bed.get("file", "") == "synth:wind" and bed.get("active", false), "wind falls back to filtered noise")
	t.near(float(bed.get("pitch", 0.0)), 1.0 * 1.05, 0.02, "the wind's filter at 300 + 25 aws by pitch")
	var wake := a.voice_state("boat.wake", 0)
	t.ok(wake.get("file", "") == "synth:water" and wake.get("active", false), "water falls back to brown noise")
	t.near(float(wake.get("pitch", 0.0)), (0.8 + 0.0225 * 10.0) * (1200.0 / 1200.0), 0.02, "water filter by pitch")
	t.ok(warnings.size() == 3, "and each missing file warns once (%d)" % warnings.size())
	warnings.clear()
	_free(a)


# ---- 6 -----------------------------------------------------------------------------------------------------------

func test_voices() -> void:
	t.begin("voices (audio.md §11.6)")
	var sim := RaceStubSim.new(20)
	sim.put(0, 0.0, 0.0, 0.0, 8.0 * KN)
	for b in range(1, 20):  # a spiral from 30 m to 570 m
		var ang := b * 0.9
		var r := 30.0 * b
		sim.put(b, r * sin(ang), r * cos(ang), ang, 8.0 * KN)
	for s in sim.states:
		s.aws = 9.0
		s.tws = 7.0
	for i in 2:  # main and jib luffing and sheeting, the code zero going up on its halyard
		sim.sv.out[i].luff_shiver = 0.5
		sim.sv.out[i].motion = SimSource.Motion.SHEETING
	sim.sv.sails[2].phase = SimSource.Phase.HOISTING
	sim.sv.sails[2].progress = 0.4
	sim.sv.queue = [SimSource.SailStep.new(2, SimSource.Phase.HOISTING)]
	sim.sv.queue_len = 1
	sim.sv.queue_pos = 0
	var a := _audio(sim)
	var cam := _cam(Vector3(0.0, 3.0, 8.0))
	_run(a, sim, 1.0, cam)
	var want_total := 0
	for b in 20:
		want_total += a.wanted_loops(b).size()
	var own_want := a.wanted_loops(0)
	var own_active := a.active_loops(0)
	print("  voices: %d wanted boat loops, %d active players, own %d/%d" % [want_total, a.active_voices(),
		own_active.size(), own_want.size()])
	t.ok(want_total > GameAudio.MAX_VOICES, "the scene asks for more than 48 voices (%d)" % want_total)
	t.ok(a.active_voices() <= GameAudio.MAX_VOICES, "at most 48 players (%d)" % a.active_voices())
	t.ok(own_want.size() >= 8 and own_active.size() == own_want.size(), "every own boat sound plays: %s"
		% str(own_active))
	var voiced := 0
	var far_ok := true
	for b in range(1, 20):
		var act := a.active_loops(b)
		if not act.is_empty():
			voiced += 1
		var d: float = a.get_meta("nodes")[b].global_position.distance_to(cam.global_position)
		if d > GameAudio.FULL_RANGE:
			far_ok = far_ok and act.all(func(id: String) -> bool: return id == "boat.wake")
	t.ok(voiced <= GameAudio.MAX_OTHER and voiced >= 3, "at most the 6 nearest other boats voiced (%d)" % voiced)
	t.ok(far_ok, "beyond 150 m only the wake")
	var t0 := Time.get_ticks_usec()
	_run(a, sim, 1.0, cam)
	print("  cost: %.0f us per frame and tick share, 20 boats" % ((Time.get_ticks_usec() - t0) / 60.0))
	# a burst of one-shots (signals, contacts) takes voices from the farthest boats, never from the own boat
	for k in 6:
		a.race_signal(RaceText.SignalKind.GENERAL_RECALL)
		a.play("boat.collide_boat", {"boat": 3, "at": Vector3(10, 0, 10), "priority": 2.0})
	_run(a, sim, 0.9, cam)
	t.ok(a.active_voices() <= GameAudio.MAX_VOICES, "still at most 48 with the one-shots (%d)" % a.active_voices())
	t.ok(a.active_loops(0).size() == a.wanted_loops(0).size(), "the own boat keeps all its sounds")
	cam.free()
	_free(a)


# ---- buses, settings, pause, wind -----------------------------------------------------------------------------

func test_buses_settings() -> void:
	t.begin("buses, settings volumes, pause ducking, wind pan and beds (audio.md §1.1, §4, §6)")
	AudioBuses.ensure()
	for n in AudioBuses.NAMES:
		var i := AudioServer.get_bus_index(n)
		t.ok(i >= 0 and AudioServer.get_bus_send(i) == &"Master", "bus %s feeds Master" % n)
	var count := AudioServer.bus_count
	AudioBuses.ensure()
	t.ok(AudioServer.bus_count == count, "ensure() adds nothing twice")
	var s := Settings.new()
	s.effects_volume = 0.5
	s.signals_volume = 0.0
	s.ambience_volume = 0.8
	s.interface_volume = 0.6
	s.apply_audio()
	for pair in [["own_boat", 0.5], ["fleet", 0.5], ["wind", 0.5], ["ambience", 0.8],
			["venue", 0.8], ["ui", 0.6]]:
		t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(pair[0])), linear_to_db(pair[1]), 1e-3,
			"%s volume from the settings" % pair[0])
	t.ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("race")) and AudioServer.is_bus_mute(
		AudioServer.get_bus_index("voice")), "signals at 0 mute the race and voice buses")
	Settings.new().apply_audio()
	# pause
	var sim := RaceStubSim.new(1)
	sim.put(0, 0.0, 0.0, 0.0, 5.0 * KN)
	sim.states[0].aws = 12.0
	sim.states[0].tws = 2.0
	var a := _audio(sim)
	_run(a, sim, 0.5)
	a.paused = true
	_run(a, sim, 1.0)
	t.near(AudioBuses.duck("own_boat"), -12.0, 0.1, "pause ducks own_boat 12 dB")
	t.near(AudioBuses.duck("race"), -12.0, 0.1, "and race")
	t.near(AudioBuses.duck("ambience"), 0.0, 0.1, "not the ambience")
	t.near(AudioBuses.duck("ui"), 0.0, 0.1, "nor the ui")
	a.paused = false
	_run(a, sim, 1.0)
	t.near(AudioBuses.duck("own_boat"), 0.0, 0.1, "unpaused")
	# wind: onboard, the ear facing the apparent wind (wind from the east, looking north: the right ear)
	var cam := _cam(Vector3(0.0, 2.0, 0.0))
	cam.look_at(Vector3(0.0, 2.0, -10.0))
	sim.states[0].awd_from = PI / 2.0
	for i in 60:
		a.frame(DT, cam, true)
	t.near(AudioBuses.wind_pan(), 0.6, 0.02, "wind pan 0.6 to the right onboard")
	t.near(float(a.voice_state("wind.bed")["vol"]), 0.3, 0.01, "wind bed onboard: 12/40")
	for i in 60:
		a.frame(DT, cam, false)
	t.near(AudioBuses.wind_pan(), 0.0, 0.02, "centred in the other cameras")
	t.near(float(a.voice_state("wind.bed")["vol"]), 0.3 * 0.8, 0.01, "wind bed from a chase height: x0.8")
	var bed1 := a.voice_state("amb.bed1")
	var bed0 := a.voice_state("amb.bed0")
	t.ok(bed0.get("active", false) and not bed1.get("active", false), "calm bed below 6 kn: %s" % str(bed0))
	t.near(float(bed0["vol"]), 0.4, 0.01, "bed volume 0.4")
	cam.free()
	_free(a)
	# §6.1 the menu ambience: the default map has its sounds; a race's signal duck does not follow into the menu
	var m := _map()
	t.ok(MenuAmbience.ONE_SHOTS.all(func(id: String) -> bool: return m.has(id) and not m.variants(id).is_empty())
		and m.has("wind.bed"), "the menu ambience's sounds are in the default map")
	AudioBuses.set_duck("ambience", -6.0)
	var amb := MenuAmbience.new()
	root.add_child(amb)
	t.near(AudioBuses.duck("ambience"), 0.0, 1e-6, "the menu ambience clears the ambience duck")
	t.ok(amb.beds.size() == 2 and amb.players().all(func(p: AudioStreamPlayer) -> bool: return p.bus == "ambience"),
		"two beds on the ambience bus")
	t.ok(amb.played.is_empty() and amb.fade == 0.0, "nothing before the first frame, faded in from silence")
	amb.free()


# ---- real players -----------------------------------------------------------------------------------------------

func test_audible() -> void:
	t.begin("real players (audible): loops and one-shots play through the audio server")
	var sim := RaceStubSim.new(1)
	sim.put(0, 0.0, 0.0, 0.0, 6.0 * KN)
	sim.states[0].aws = 8.0
	var a := _audio(sim)
	a.audible = true
	_run(a, sim, 0.3)
	a.race_signal(RaceText.SignalKind.WARNING)
	_run(a, sim, 0.1)
	var playing := 0
	var loops := 0
	for n in a.find_children("*", "AudioStreamPlayer3D", true, false) + a.find_children("*", "AudioStreamPlayer",
			true, false):
		playing += 1 if n.get("playing") else 0
	for n in a.get_meta("nodes")[0].find_children("*", "AudioStreamPlayer3D", true, false):
		loops += 1 if (n as AudioStreamPlayer3D).playing else 0
	t.ok(playing >= 3, "wind, bed and horn players playing (%d)" % playing)
	t.ok(loops >= 3 and loops == a.active_loops(0).size(), "the boat's loops playing (%d)" % loops)
	_free(a)
	await create_timer(0.3).timeout  # the audio server frees the playbacks


# ---- the sail test scene ---------------------------------------------------------------------------------------

func test_scene_fake() -> void:
	t.begin("sail test scene with its sound (FakeSim)")
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 2)  # FAKE
	sc.set("with_pause_menu", false)
	sc.set("apply_settings", false)
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	for i in 180:
		sc.call("step_frame", 1.0 / 60.0)
	var a: GameAudio = sc.get("audio")
	t.ok(a != null and a.map != null, "the scene has its audio")
	var loops := a.active_loops(0)
	t.ok("boat.hull" in loops and "boat.wake" in loops and "boat.rig" in loops, "hull, wake, rig: %s" % str(loops))
	t.ok(a.voice_state("wind.bed").get("active", false), "wind at the listener")
	var beds := 0
	for i in 4:
		beds += 1 if a.voice_state("amb.bed%d" % i).get("active", false) else 0
	t.ok(beds >= 1, "an ambience bed")
	t.ok(a.active_voices() <= GameAudio.MAX_VOICES, "voices within the limit")
	sc.queue_free()
	await process_frame


func test_scene_core_race() -> void:
	t.begin("sail test scene in race mode on the core: signals, fleet, course objects")
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", true)
	sc.set("fleet_size", 4)
	sc.set("ai_level", "expert")
	sc.set("with_pause_menu", false)
	sc.set("apply_settings", false)
	sc.set("core_settings", {"free_sailing_s": 5.0})
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	for i in 400:
		sc.call("step_frame", 1.0 / 30.0)
	var a: GameAudio = sc.get("audio")
	var horns := _played(a, "race.horn")
	t.ok(horns.filter(func(p: Dictionary) -> bool: return p["space"] == "2d").size() == 1,
		"the warning signal's horn (%d)" % horns.size())
	t.ok(horns.filter(func(p: Dictionary) -> bool: return p["space"] == "3d").size() == 1,
		"and from the committee boat")
	t.ok("boat.wake" in a.active_loops(0), "own wake")
	var fleet_bus := false
	for b in range(1, 4):
		for id in a.active_loops(b):
			fleet_bus = fleet_bus or a.voice_state(id, b)["bus"] == "fleet"
	t.ok(fleet_bus, "other boats on the fleet bus")
	t.ok(a.voice_state("venue.committee").get("want", false) or a.voice_state("venue.buoy").size() > 0,
		"course objects")
	t.ok(a.active_voices() <= GameAudio.MAX_VOICES, "voices within the limit (%d)" % a.active_voices())
	sc.call("reset_boat")
	for i in 30:
		sc.call("step_frame", 1.0 / 30.0)
	t.ok("boat.wake" in a.active_loops(0), "sound again after the race restarts")
	sc.queue_free()
	await process_frame
