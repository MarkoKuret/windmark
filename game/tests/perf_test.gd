extends SceneTree
## Frame-time overlay and CSV log tests (hud.md §17): the statistics, the sections, and the sail scene running
## with the overlay shown and a log for a few real frames' seconds (the core's race when the GDExtension is
## loaded, FakeSim otherwise). GPU times may be 0 headless. Headless.
##   godot --headless --path game -s res://tests/perf_test.gd

const LOG := "user://perf_test.csv"
const RUN_S := 2.6

var t := TestLog.new()


func _init() -> void:
	test_stats()
	await test_scene()
	t.finish(self, "perf")


func test_stats() -> void:
	t.begin("statistics and sections")
	var times := []
	for i in 100:
		times.append(float(i + 1))
	t.near(PerfMonitor.worst_1pct(times), 99.0, 1e-9, "1 % worst of 1..100 ms is 99 ms")
	times.shuffle()
	times.append(500.0)
	t.near(PerfMonitor.worst_1pct(times), 100.0, 1e-9, "one 500 ms hitch in 101 frames: 1 % worst 100 ms")
	t.near(PerfMonitor.worst_1pct([]), 0.0, 0.0, "no frames: 0")
	PerfStats.enabled = false
	PerfStats.take()
	PerfStats.add(&"sim", 100)
	t.ok(PerfStats.take().is_empty(), "nothing kept while no monitor measures")
	PerfStats.enabled = true
	PerfStats.add(&"sim", 100)
	PerfStats.add(&"sim", 50)
	PerfStats.add(&"hud", 7)
	var d := PerfStats.take()
	t.ok(d.get(&"sim") == 150 and d.get(&"hud") == 7 and PerfStats.take().is_empty(), "sums per frame: %s" % [d])
	PerfStats.enabled = false
	t.ok(PerfMonitor.resolve_path("user://a.csv") == "user://a.csv", "user:// path kept")
	t.ok(PerfMonitor.resolve_path("/tmp/a.csv") == "/tmp/a.csv", "absolute path kept")
	var pwd := OS.get_environment("PWD")
	if pwd != "":
		t.ok(PerfMonitor.resolve_path("perf/a.csv") == pwd.path_join("perf/a.csv"), "relative to the shell's folder")
	var txt := PerfMonitor.text({"fps": 60.0, "frame_ms": 16.7, "sim_ms": 1.25, "render_scale": 0.67})
	t.ok(txt.contains("FPS 60") and txt.contains("sim 1.25") and txt.contains("67 %"), "panel text:\n%s" % txt)
	t.ok(not txt.contains("—"), "no em dashes on the panel")


func test_scene() -> void:
	var core := CoreSimSource.available()
	t.begin("sail scene with the overlay and the log (%s)" % ("core race" if core else "FakeSim"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	if core:
		sc.sim_kind = sc.SimKind.CORE
		sc.race_mode = true
		sc.fleet_size = 3
	else:
		sc.sim_kind = sc.SimKind.FAKE
	sc.with_pause_menu = false
	sc.apply_settings = false
	sc.perf_overlay = true
	sc.perf_log = LOG
	sc.perf_seconds = RUN_S
	root.add_child(sc)
	await process_frame
	var perf: PerfMonitor = sc.perf
	perf.quit_when_done = false
	var done := [false]
	perf.finished.connect(func() -> void: done[0] = true)
	var frames := 0
	while not done[0] and frames < 200000:
		await process_frame
		frames += 1
	t.ok(done[0], "finished after %.1f s (%d frames)" % [RUN_S, frames])
	t.ok(PerfStats.enabled, "measuring while shown")
	var label := perf.get_node("PerfPanel/PerfText") as Label
	t.ok(perf.get_node("PerfPanel").visible and label.text.contains("FPS"), "overlay shown:\n%s" % label.text)
	var last := perf.last
	t.ok(float(last.get("fps", 0.0)) > 0.0 and float(last.get("frame_ms", 0.0)) > 0.0, "fps and frame time: %s, %s ms"
		% [last.get("fps"), last.get("frame_ms")])
	t.ok(float(last.get("frame_p99_ms", 0.0)) >= float(last.get("frame_ms", 0.0)) * 0.5, "1 % worst measured")
	t.ok(float(last.get("process_ms", 0.0)) > 0.0, "CPU process time: %s ms" % last.get("process_ms"))
	t.ok(last.has("gpu_ms") and float(last["gpu_ms"]) >= 0.0, "GPU time read (%s ms; 0 headless)" % last.get("gpu_ms"))
	t.ok(last.get("boats") == sc.sim.boat_count() and last.get("quality") == "M", "set-up: %d boats, tier %s" % [
		last.get("boats"), last.get("quality")])
	t.ok(float(last.get("boats_ms", 0.0)) > 0.0 and float(last.get("sails_ms", 0.0)) > 0.0
		and float(last.get("hud_ms", 0.0)) > 0.0 and float(last.get("sim_ms", 0.0)) > 0.0
		and float(last.get("sea_ms", 0.0)) > 0.0, "sections timed: sim %s, sails %s, boats %s, hud %s, sea %s, audio %s"
		% [last.get("sim_ms"), last.get("sails_ms"), last.get("boats_ms"), last.get("hud_ms"), last.get("sea_ms"),
		last.get("audio_ms")])
	# the log
	var f := FileAccess.open(LOG, FileAccess.READ)
	t.ok(f != null, "log written")
	if f != null:
		var rows := f.get_as_text().strip_edges().split("\n")
		f.close()
		t.ok(rows[0] == ",".join(PerfMonitor.COLUMNS), "header: the columns")
		t.ok(rows.size() >= 3, "one line per second: %d lines in %.1f s" % [rows.size() - 1, RUN_S])
		var ok_cols := true
		for i in range(1, rows.size()):
			ok_cols = ok_cols and rows[i].split(",").size() == PerfMonitor.COLUMNS.size()
		t.ok(ok_cols, "every line has %d fields" % PerfMonitor.COLUMNS.size())
		print("  %s\n  %s" % [rows[0], rows[-1]])
	t.ok(perf.lines >= 2, "lines counted: %d" % perf.lines)
	# F9 hides the panel and stops measuring (no log open any more)
	var k := InputEventKey.new()
	k.keycode = KEY_F9
	k.pressed = true
	root.push_input(k)
	await process_frame
	t.ok(not perf.get_node("PerfPanel").visible and not PerfStats.enabled, "F9 hides it, nothing measured")
	sc.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
