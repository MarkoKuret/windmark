extends SceneTree
## The scene builds behind the navy fade (menus.md §5, WM-180, WM-206), headless: from the engine's start, the
## sail scene as a quick race (the player sailing, pause menu and results screen, as Start race builds it) or the
## main menu with its live backdrop, built `--runs` times in one process (the first build cold, the later ones as
## Race again or a second Main menu finds the caches), each timed from the load of the scene file to the end of
## its `_ready`, with the sail scene's own parts (`build_ms`). The GPU does nothing headless: pipeline compilation
## is not in these numbers.
##   godot --headless --path game -s res://tests/load_cost.gd -- [--scene=race|free|menu] [--fleet=16] [--runs=3]

const SAIL := "res://scenes/sail_test.tscn"
const MENU := "res://scenes/menu/main_menu.tscn"

var which := "race"
var fleet := 16
var runs := 3


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			which = a.trim_prefix("--scene=")
		elif a.begins_with("--fleet="):
			fleet = a.trim_prefix("--fleet=").to_int()
		elif a.begins_with("--runs="):
			runs = maxi(1, a.trim_prefix("--runs=").to_int())
	_main()


func _main() -> void:
	await process_frame
	if which != "menu" and not CoreSimSource.available():
		print("load cost: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	for r in runs:
		var t0 := Time.get_ticks_usec()
		var sc := _build()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var parts := ""
		var bm: Variant = sc.get("build_ms")
		if bm is Dictionary and not (bm as Dictionary).is_empty():
			parts = "  " + " ".join((bm as Dictionary).keys().map(
					func(k: String) -> String: return "%s %.0f" % [k, bm[k]]))
		await process_frame
		var tw := Time.get_ticks_usec()
		var w := ShaderWarmup.start(sc)
		parts += "  (warm-up copies %d in %.1f ms)" % [w.copies.size(), (Time.get_ticks_usec() - tw) / 1000.0]
		print("load cost: %s run %d %.0f ms%s" % [which, r + 1, ms, parts])
		for i in 2:
			await process_frame
		w.finish()
		sc.queue_free()
		await process_frame
		await process_frame
	quit(0)


func _build() -> Node:
	if which == "menu":
		var m := (load(MENU) as PackedScene).instantiate()
		root.add_child(m)
		return m
	var sc := (load(SAIL) as PackedScene).instantiate()
	var g := GameSetup.new()
	g.mode = "free" if which == "free" else "race"
	g.fleet_size = 1 if which == "free" else fleet
	g.ai_level = "intermediate"
	g.seed = 7
	sc.setup = g
	sc.sim_kind = sc.SimKind.CORE
	root.add_child(sc)
	return sc
