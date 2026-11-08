extends SceneTree
## Headless sweep of the running sheets through their edge cases (docs/specs/sail_visuals.md §11.3 "Rope", §12 test
## 30): every class sailed on the core through a kite hoist, the kite held upwind with its clew flogging, a gybe, let
## fly and an over-sheet, the drop and a tack, drawn at 60 frames a second as the scene does, and every line's
## rings measured each frame: the largest bend between neighbouring segments (a kink or a zig-zag), the largest
## move of a ring beyond what its ends make it move (a jump), segments stretched or squashed against the rope's
## spacing, and NaNs. Run by run_sail_visuals_test.sh.
##   godot --headless --path game -s res://tests/ropes_test.gd [-- probe] [-- wm7 ...] [-- dump <dir>]
##     probe   print every scenario's worst numbers per line (no pass or fail)
##     dump    also write every frame's rings, waypoints and hanging shapes per scenario as JSON into <dir>
##     only=hoist,drop   only those scenarios
##   ROPES_DEBUG=t0,t1 in the environment prints the sails' phases and clews over that window of the recorded frames.

const KNOT := 1852.0 / 3600.0
const FPS := 60.0
const CLASSES := ["wm7", "wm9", "wm10", "wm12", "wm16", "wm21"]
## limits (§12 test 30), sailing (the kite upwind, a gybe, let fly, an over-sheet, a tack) and through a sail change
## (a hoist, a drop: the sails themselves jump, a clew dives under the deck): the bend between neighbouring segments
## away from a contact (deg), the jump of a ring beyond its ends' (m a frame, times the class scale s), a segment
## against the run's mean spacing
const LIMITS := {
	"sailing": {"kink": 50.0, "jump": 0.35, "seg_lo": 0.3, "seg_hi": 1.5},
	"change": {"kink": 90.0, "jump": 1.6, "seg_lo": 0.3, "seg_hi": 3.5},
}

var t := TestLog.new()
var probe := false
var dump_dir := ""
var worst := {}


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	if not CoreSimSource.available():
		print("ropes test: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	probe = args.has("probe")
	var i := args.find("dump")
	if i >= 0 and i + 1 < args.size():
		dump_dir = args[i + 1]
		DirAccess.make_dir_recursive_absolute(dump_dir)
	var classes := []
	for c in CLASSES:
		if args.has(c):
			classes.append(c)
	if classes.is_empty():
		classes = CLASSES
	for id in classes:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			t.ok(false, "%s generated (run tests/run_boat_import_test.sh)" % id)
			continue
		_class(id)
	print("summary (worst per class): kink deg, jump m, accel m, seg max, seg min")
	for id in worst:
		var w: Dictionary = worst[id]
		print("  %s: kink %.1f (%s), jump %.3f (%s), accel %.3f, seg %.2f..%.2f, nan %d" % [id, w["kink"], w["kink_at"],
			w["jump"], w["jump_at"], w["acc"], w["seg_hi"], w["seg_lo"], w["nan"]])
	if probe:
		quit(0)
		return
	t.finish(self, "ropes test")


## The scenarios of one class: [name, legs]; a leg {t (s), twa (deg, held by a helm controller), req (sail name at the
## leg's start), until (stop condition), auto, sheet, let_fly, rec (record this leg)}.
static func scenarios(kite: String, front: String) -> Array:
	return [
		["hoist", [{"t": 6.0, "twa": 120.0}, {"t": 30.0, "twa": 120.0, "req": kite, "until": "idle:" + kite, "rec": true},
			{"t": 3.0, "twa": 120.0, "rec": true}]],
		["kite_upwind", [{"t": 6.0, "twa": 110.0}, {"t": 30.0, "twa": 110.0, "req": kite, "until": "idle:" + kite},
			{"t": 4.0, "twa": 110.0}, {"t": 4.0, "twa": 70.0, "rec": true}, {"t": 10.0, "twa": 45.0, "rec": true}]],
		["gybe", [{"t": 6.0, "twa": 145.0}, {"t": 30.0, "twa": 145.0, "req": kite, "until": "idle:" + kite},
			{"t": 6.0, "twa": 145.0}, {"t": 10.0, "twa": -145.0, "rec": true}]],
		["let_fly", [{"t": 6.0, "twa": 110.0}, {"t": 30.0, "twa": 110.0, "req": kite, "until": "idle:" + kite},
			{"t": 6.0, "twa": 110.0}, {"t": 4.0, "twa": 110.0, "let_fly": true, "rec": true},
			{"t": 5.0, "twa": 110.0, "rec": true}]],
		["over_sheet", [{"t": 6.0, "twa": 110.0}, {"t": 30.0, "twa": 110.0, "req": kite, "until": "idle:" + kite},
			{"t": 6.0, "twa": 110.0}, {"t": 4.0, "twa": 110.0, "auto": false, "sheet": 0.0, "rec": true},
			{"t": 4.0, "twa": 110.0, "auto": false, "sheet": 1.0, "rec": true}]],
		["drop", [{"t": 6.0, "twa": 140.0}, {"t": 30.0, "twa": 140.0, "req": kite, "until": "idle:" + kite},
			{"t": 6.0, "twa": 140.0}, {"t": 30.0, "twa": 140.0, "req": front, "until": "down:" + kite, "rec": true},
			{"t": 3.0, "twa": 140.0, "rec": true}]],
		["tack", [{"t": 12.0, "twa": 42.0}, {"t": 10.0, "twa": -42.0, "rec": true}]],
	]


func _class(id: String) -> void:
	t.begin("%s ropes through the edge cases" % id)
	var probe_sim := CoreSimSource.new()
	probe_sim.settings = {"wind_speed": 12.0 * KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false, "seed": 11}
	probe_sim.create()
	var info := probe_sim.class_info(probe_sim.add_boat(id, 0.0, 0.0, 0.0))
	var kite := ""
	var front := ""
	for s in info.sails:
		if BoatView.is_flying(s.type) and s.type != "code_zero":
			kite = s.name
		elif s.type != "main" and not BoatView.is_flying(s.type) and front == "":
			front = s.name
	var w := {"kink": 0.0, "kink_at": "", "jump": 0.0, "jump_at": "", "acc": 0.0, "seg_hi": 0.0, "seg_lo": INF,
		"nan": 0}
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	for sc in scenarios(kite, front):
		if not only.is_empty() and not only.has(sc[0]):
			continue
		var r := run(id, sc[0], sc[1], 12.0, dump_dir)
		if r.is_empty():
			t.ok(false, "%s %s ran" % [id, sc[0]])
			continue
		var s := pow(info.loa / 12.0, 0.7)
		print("  %s %-11s frames %4d  kink %5.1f deg (%s)  jump %.3f m (%s)  accel %.3f  seg %.2f..%.2f  contact %.0f deg  start jump %.2f m  sail jumps %d  clew under deck %d  nan %d" % [
				id, sc[0], r["frames"], r["kink"], r["kink_at"], r["jump"], r["jump_at"], r["acc"], r["seg_lo"],
				r["seg_hi"], r["contact"], r["clew"], r["snaps"], r["under"], r["nan"]])
		if r["kink"] > w["kink"]:
			w["kink"] = r["kink"]
			w["kink_at"] = "%s %s" % [sc[0], r["kink_at"]]
		if r["jump"] > w["jump"]:
			w["jump"] = r["jump"]
			w["jump_at"] = "%s %s" % [sc[0], r["jump_at"]]
		w["acc"] = maxf(w["acc"], r["acc"])
		w["seg_hi"] = maxf(w["seg_hi"], r["seg_hi"])
		w["seg_lo"] = minf(w["seg_lo"], r["seg_lo"])
		w["nan"] += r["nan"]
		if not probe:
			var lim: Dictionary = LIMITS["change" if sc[0] in ["hoist", "drop"] else "sailing"]
			t.ok(r["nan"] == 0, "%s %s: no NaN in any ring" % [id, sc[0]])
			t.ok(r["kink"] <= lim["kink"], "%s %s: no bend between neighbouring segments over %.0f deg (worst %.1f, %s)" % [
				id, sc[0], lim["kink"], r["kink"], r["kink_at"]])
			t.ok(r["jump"] <= lim["jump"] * s, "%s %s: no ring jumps more than %.3f m a frame beyond its ends (worst %.3f, %s)" % [
				id, sc[0], lim["jump"] * s, r["jump"], r["jump_at"]])
			t.ok(r["seg_hi"] <= lim["seg_hi"] and r["seg_lo"] >= lim["seg_lo"],
				"%s %s: segments within %.1f..%.1f of the run's spacing (%.2f..%.2f)" % [id, sc[0], lim["seg_lo"],
				lim["seg_hi"], r["seg_lo"], r["seg_hi"]])
	worst[id] = w


## Sails `id` on the core through `legs` at `tws_kn`, drawing the boat at FPS, and measures the recorded legs' lines.
## With `dir`, every recorded frame's rings go to <dir>/<id>_<name>.json.
## `shot`, when valid, is called as shot.call(bv, sim, boat, frame) on every recorded frame (the preview dumps).
static func run(id: String, name: String, legs: Array, tws_kn: float, dir := "", shot := Callable()) -> Dictionary:
	var sim := CoreSimSource.new()
	sim.settings = {"wind_speed": tws_kn * KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false, "seed": 11}
	if not sim.create():
		return {}
	var twa0 := float(legs[0].get("twa", 90.0))
	var b := sim.add_boat(id, 0.0, 0.0, Frames.wrap_2pi(-deg_to_rad(twa0)))
	var info := sim.class_info(b)
	var idx := {}
	for i in info.sails.size():
		idx[info.sails[i].name] = i
	var bv := BoatView.create(info, info.rudder_max)
	var sh := bv.sheets
	if sh == null:
		bv.free()
		return {}
	var prev := sim.sails(b)
	var cur := prev
	var m := Metrics.new()
	var frames := []
	var sub := int(round(FPS * SimSource.DT))
	for leg in legs:
		var ticks := int(float(leg["t"]) / SimSource.DT)
		var req := InputFrame.SAIL_NONE
		if leg.has("req"):
			req = InputFrame.hoist_req(idx[leg["req"]])
		for k in ticks:
			var s := sim.state(b)
			var f := InputFrame.new()
			f.tick = sim.tick()
			f.h_cmd = clampf(1.5 * Frames.angle_diff(s.twa, deg_to_rad(float(leg["twa"]))), -1.0, 1.0)
			f.flags = InputFrame.FLAG_AUTO_TRIM if leg.get("auto", true) else 0
			if leg.get("let_fly", false):
				f.flags |= InputFrame.FLAG_LET_FLY
			f.sheet_cmd = float(leg.get("sheet", 0.5))
			f.sail_req = req if k == 0 else InputFrame.SAIL_NONE
			var res := sim.apply_input(b, f)
			if k == 0 and leg.has("req") and res != SimSource.Request.ACCEPTED:
				print("  %s %s: the request for %s was not accepted (%d)" % [id, name, leg["req"], res])
			sim.step()
			prev = cur
			cur = sim.sails(b)
			for j in sub:
				var alpha := float(j + 1) / float(sub)
				bv.apply(sim.render_pose(b, alpha))
				bv.apply_sails(prev, cur, alpha, 1.0 / FPS)
				if leg.get("rec", false):
					if OS.has_environment("ROPES_DEBUG"):
						var win := OS.get_environment("ROPES_DEBUG").split(",")
						var tt := m.n / FPS
						if tt >= float(win[0]) and tt <= float(win[1]):
							var parts := []
							for sp in bv.sail_parts:
								if sp.shape != null and sp.node.visible:
									var cn: PackedVector3Array = sp.shape.mid_points(PackedInt32Array([sp.cols - 1, 0]))
									parts.append("%s ph%d sh%.2f b%.0f clew %s" % [sp.id, sp.phase, sp.shiver, rad_to_deg(sp.beta), cn[0]])
							print("%.3f %s" % [tt, " | ".join(parts)])
					if shot.is_valid():
						shot.call(bv, sim, b, m.n)
					m.frame(sh, "%.2f s" % (m.n / FPS))
					if dir != "":
						frames.append(_rings(sh))
			if _until(String(leg.get("until", "")), cur, idx):
				break
	bv.free()
	if dir != "":
		var fo := FileAccess.open(dir.path_join("%s_%s.json" % [id, name]), FileAccess.WRITE)
		fo.store_string(JSON.stringify({"class": id, "scenario": name, "fps": FPS, "frames": frames}))
	return m.result()


static func _until(cond: String, cur: SimSource.SailsView, idx: Dictionary) -> bool:
	if cond == "":
		return false
	var p := cond.split(":")
	var s: SimSource.SailState = cur.sails[idx[p[1]]]
	if p[0] == "up":
		return s.phase == SimSource.Phase.UP
	if p[0] == "idle":  # the sail up and every other front sail down (the change finished)
		for i in cur.sails.size():
			if i != 0 and i != idx[p[1]] and cur.sails[i].phase != SimSource.Phase.DOWN:
				return false
		return s.phase == SimSource.Phase.UP
	if p[0] == "down":
		return s.phase == SimSource.Phase.DOWN
	return false


## Every shown line's free and lead rings this frame: [[surface, line, [x, y, z, ...]], ...].
static func _rings(sh: BoatSheets) -> Array:
	var out := []
	for surf in 2:
		var shape: Variant = sh.shapes[surf]
		if shape == null:
			continue
		for i in (sh.line_specs[surf] as Array).size():
			var c: PackedVector3Array = shape.centre(i)
			var spec: Dictionary = sh.line_specs[surf][i]
			var n: int = spec["free_rings"] + spec["lead_rings"]
			var flat := []
			for k in n:
				flat.append_array([snappedf(c[k].x, 1e-4), snappedf(c[k].y, 1e-4), snappedf(c[k].z, 1e-4)])
			var ways: PackedVector3Array = sh.last_ways[surf]
			var slots: int = ways.size() / (sh.line_specs[surf] as Array).size()
			var wf := []
			for j in slots:
				if not is_nan(ways[i * slots + j].x):
					wf.append_array([ways[i * slots + j].x, ways[i * slots + j].y, ways[i * slots + j].z])
			var hang := []
			if shape.has_method("hanging"):
				for q in shape.hanging(i):
					hang.append_array([snappedf(q.x, 1e-4), snappedf(q.y, 1e-4), snappedf(q.z, 1e-4)])
			out.append([surf, i, flat, wf, spec["free_rings"], hang])
	return out


## The per-frame measures of every shown line (sail_visuals.md §12 test 30). A bend at a ring within a ring spacing
## (in plan) of one of the line's waypoints is its contact with an obstacle (round the forestay, the mast, the boom
## end) and is not a kink, nor is a bend between segments shorter than 0.15 m (nor a segment across a contact
## measured against the spacing: it cuts the corner); a frame in which a line's start jumps more than SheetRopes' snap share of the run (the sail
## itself jumped) is counted, and its jump not measured.
class Metrics:
	const SNAP := 0.3
	const SHORT := 0.15
	const SEG_ABS := 0.05
	var n := 0
	var prev := {}
	var prev2 := {}
	var r := {"frames": 0, "kink": 0.0, "kink_at": "", "jump": 0.0, "jump_at": "", "acc": 0.0, "seg_hi": 1.0,
		"seg_lo": 1.0, "clew": 0.0, "nan": 0, "snaps": 0, "contact": 0.0, "under": 0}

	func frame(sh: BoatSheets, when: String) -> void:
		n += 1
		r["frames"] = n
		var seen := {}
		for surf in 2:
			var shape: Variant = sh.shapes[surf]
			if shape == null:
				continue
			var nlines: int = (sh.line_specs[surf] as Array).size()
			var ways: PackedVector3Array = sh.last_ways[surf]
			var slots: int = ways.size() / nlines if nlines > 0 else 0
			for i in nlines:
				var spec: Dictionary = sh.line_specs[surf][i]
				var nf: int = spec["free_rings"]
				var nl: int = spec["lead_rings"]
				var c: PackedVector3Array = shape.centre(i)
				var key := "%d.%d" % [surf, i]
				var what := "%s line %s" % [when, ["jib", "kite"][surf] + ["0", "1", "tack"][i]]
				var nan := false
				for k in c.size():
					if is_nan(c[k].x) or is_nan(c[k].y) or is_nan(c[k].z):
						nan = true
				if nan:
					r["nan"] += 1
					continue
				var pts := c.slice(0, nf + nl)
				var total := 0.0
				for k in range(1, nf):
					total += pts[k].distance_to(pts[k - 1])
				if total < 1e-4:
					prev.erase(key)  # hidden: collapsed to a point
					prev2.erase(key)
					continue
				seen[key] = true
				var mean := total / float(nf - 1)
				# the sail's corner under the deck (a sail coming down into the boat): the line starts on the deck
				# above it and bends there; counted, not measured
				var raw: Vector3 = (sh.last_starts[surf] as PackedVector3Array)[i]
				var under := pts[0].y - raw.y > 0.01
				if under:
					r["under"] += 1
				var wl := []
				for j in slots:
					var w := ways[i * slots + j]
					if not is_nan(w.x):
						wl.append(Vector2(w.x, w.z))
				# bends: every inner ring of the free run and of the lead run, not the lead block between them
				for k in range(1, pts.size() - 1):
					if k == nf - 1:
						continue
					var a := pts[k] - pts[k - 1]
					var b := pts[k + 1] - pts[k]
					if minf(a.length(), b.length()) < SHORT:
						continue  # a bend between segments under SHORT (round a fitting by the winch) shows as a curve
					var ang := rad_to_deg(a.angle_to(b))
					var contact := under and k <= 2
					if k < nf - 1:
						for w in wl:
							contact = contact or (w as Vector2).distance_to(Vector2(pts[k].x, pts[k].z)) <= mean
					if contact:
						r["contact"] = maxf(r["contact"], ang)
					elif ang > r["kink"]:
						r["kink"] = ang
						r["kink_at"] = "%s ring %d" % [what, k]
				# segments of the free run against its mean spacing
				for k in range(1, nf):
					var sl := pts[k].distance_to(pts[k - 1])
					if absf(sl - mean) < SEG_ABS:
						continue  # within a few cm of the spacing (a short line, the start lifted onto the deck)
					var across := false  # the chord across a contact (round the forestay) is short by its corner
					for w in wl:
						across = across or (w as Vector2).distance_to(Vector2(pts[k].x, pts[k].z)) <= mean \
							or (w as Vector2).distance_to(Vector2(pts[k - 1].x, pts[k - 1].z)) <= mean
					if across:
						continue
					r["seg_hi"] = maxf(r["seg_hi"], sl / mean)
					r["seg_lo"] = minf(r["seg_lo"], sl / mean)
				# jumps beyond the ends: a ring's move less the move its place between the ends would make
				if prev.has(key):
					var p: PackedVector3Array = prev[key]
					var d0 := pts[0].distance_to(p[0])
					r["clew"] = maxf(r["clew"], d0)
					if d0 > SNAP * total:
						r["snaps"] += 1
						prev2.erase(key)
					else:
						for k in range(1, nf):
							var u := float(k) / float(nf - 1)
							var ex := pts[k].distance_to(p[k]) - (1.0 - u) * d0
							if ex > r["jump"]:
								r["jump"] = ex
								r["jump_at"] = "%s ring %d" % [what, k]
						if prev2.has(key):
							var pp: PackedVector3Array = prev2[key]
							for k in range(1, nf):
								r["acc"] = maxf(r["acc"], (pts[k] - 2.0 * p[k] + pp[k]).length())
						prev2[key] = p
				prev[key] = pts
		for key in prev.keys():
			if not seen.has(key):
				prev.erase(key)
				prev2.erase(key)

	func result() -> Dictionary:
		return r
