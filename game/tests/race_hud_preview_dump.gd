extends SceneTree
## Dumps the race HUD laid out at 1280 x 720 for the offline previews (tests/race_hud_preview.py draws it over a
## course preview frame): a race on the core steered by RacePilot at the start, on the first beat and at the
## results, and a scripted incident (rules line, penalty, radar colours, protest prompt) on RaceStubSim.
##   godot --headless --path game -s res://tests/race_hud_preview_dump.gd
## Writes generated/race_hud_preview/<name>.json.

const OUT := "res://generated/race_hud_preview"
const SIZE := Vector2(1280, 720)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _core_race()
	await _incident()
	quit(0)


func _frame_box() -> Control:
	var box := Control.new()
	box.size = SIZE
	get_root().add_child(box)
	return box


func _core_race() -> void:
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": 20260925, "wind_speed": 11.0 * HudFormat.KNOT, "wind_from": 0.2, "shift_preset": 1,
		"free_sailing_s": 10.0}
	sim.create("example_bay")
	for i in 4:
		sim.add_entry("wm7", {"human": true})
	sim.create_race("example_bay/example_wl")
	var box := _frame_box()
	var hud := Hud.new()
	box.add_child(hud)
	hud.race.names = {1: "Nora", 2: "Ivo", 3: "Maja"}
	hud.race.ai_levels = {1: "Expert", 2: "Intermediate", 3: "Pro"}
	var pilot := RacePilot.new(sim)
	var shots := {"start": -42.0, "beat": 95.0}
	var n := 0
	while n < 60000:
		pilot.steer()
		sim.step()
		hud.tick(sim, 0)
		n += 1
		var t := float(sim.race()["race_time"])
		for k in shots.keys():
			if t >= shots[k]:
				shots.erase(k)
				await _shot(hud, k)
		if int(sim.race()["state"]) == RaceText.RaceState.CLOSED:
			for i in 30:
				hud.tick(sim, 0)
			await _shot(hud, "results")
			break
	box.queue_free()


func _incident() -> void:
	var sim := RaceStubSim.new(5)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 212.0
	for b in 5:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.order = PackedInt32Array([2, 0, 1, 3, 4])
	for i in 5:
		sim.boats_d[sim.order[i]]["D"] = 1400.0 + 30.0 * i
	var th := deg_to_rad(42.0)
	sim.put(0, 120.0, 420.0, Frames.wrap_2pi(-th), 3.1)
	sim.put(1, 60.0, 470.0, th, 3.0)
	sim.put(2, 150.0, 500.0, Frames.wrap_2pi(-th), 3.2)
	sim.put(3, 90.0, 360.0, Frames.wrap_2pi(-th), 3.0)
	sim.put(4, 230.0, 380.0, th, 2.9)
	var R := RaceText.Rule
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R10, "kc_state": 1}),
		sim.pair(0, 2, {"kc_giver": 0, "kc_holder": 2, "kc_rule": R.R12, "kc_state": 2}),
		sim.pair(0, 3, {"kc_giver": 3, "kc_holder": 0, "kc_rule": R.R12})]
	sim.rules_d[0] = {"pending": [{"rule": R.R12, "other": 2, "count": 1}], "turn_progress": deg_to_rad(140.0),
		"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 27.0, "received": 1, "turning_for_penalty": true}
	var box := _frame_box()
	var hud := Hud.new()
	box.add_child(hud)
	hud.race.names = {1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine"}
	hud.race.ai_levels = {1: "Expert", 2: "Intermediate", 3: "Pro", 4: "Easy"}
	for i in 60:
		sim.step()
		hud.tick(sim, 0)
	sim.rules_ev = [{"kind": RaceText.Rev.PROTESTABLE, "boat": 1, "other": 0, "rule": R.R10, "deadline": 8.0}]
	sim.step()
	hud.tick(sim, 0)
	sim.rules_ev = []
	for i in 30:
		sim.step()
		hud.tick(sim, 0)
	await _shot(hud, "incident")
	box.queue_free()


func _shot(hud: Hud, name: String) -> void:
	hud.frame(0.25)
	hud.refresh_text()
	hud.frame(0.0)
	await process_frame
	await process_frame
	var items := []
	_collect(hud, items)
	var f := FileAccess.open("%s/%s.json" % [OUT, name], FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [SIZE.x, SIZE.y], "items": items}))
	print("race hud preview: %s (%d items)" % [name, items.size()])


static func _c(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _v(v: Vector2) -> Array:
	return [v.x, v.y]


func _collect(n: Node, items: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var base := {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}
		if c is PanelContainer:
			var sb := c.get_theme_stylebox("panel") as StyleBoxFlat
			base["k"] = "panel"
			base["col"] = _c(sb.bg_color if sb else Color(0, 0, 0, 0.45))
			items.append(base)
		elif c is Label and (c as Label).text != "":
			var l := c as Label
			base["k"] = "label"
			base["text"] = l.text
			base["size"] = l.get_theme_font_size("font_size")
			base["col"] = _c(l.get_theme_color("font_color"))
			base["align"] = l.horizontal_alignment
			base["alpha"] = l.modulate.a
			items.append(base)
		elif c is RadarView:
			base["k"] = "radar"
			var prims := []
			for q in (c as RadarView).primitives():
				var d := {}
				for key in q:
					var v: Variant = q[key]
					if v is Color:
						d[key] = _c(v)
					elif v is Vector2:
						d[key] = _v(v)
					elif v is PackedVector2Array:
						d[key] = Array(v).map(func(p: Vector2) -> Array: return [p.x, p.y])
					else:
						d[key] = v
				prims.append(d)
			base["prims"] = prims
			items.append(base)
		elif c is FlagsView:
			base["k"] = "flags"
			base["flags"] = Array((c as FlagsView).flags)
			items.append(base)
		elif c is RoundingArrowView:
			base["k"] = "arrows"
			base["sides"] = Array((c as RoundingArrowView).sides)
			items.append(base)
		elif c is PenaltyRingView:
			var pr := c as PenaltyRingView
			base["k"] = "ring"
			base["f"] = clampf(pr.turn_deg / maxf(pr.target_deg, 1.0), 0.0, 1.0)
			base["tack"] = pr.tack_done
			base["gybe"] = pr.gybe_done
			items.append(base)
		elif c is TrimGaugeView:
			var g := c as TrimGaugeView
			base["k"] = "gauge"
			base["title"] = g.title + ("  AUTO" if g.auto else "")
			base["needle"] = 0.0 if g.auto else g.needle
			base["col"] = _c(g.colour)
			base["telltale"] = g.telltale
			items.append(base)
		elif c is HudBar:
			var hb := c as HudBar
			base["k"] = "bar"
			base["centred"] = hb.centred
			base["value"] = hb.value
			base["mark"] = hb.mark if not is_nan(hb.mark) else null
			items.append(base)
	for ch in n.get_children():
		_collect(ch, items)
