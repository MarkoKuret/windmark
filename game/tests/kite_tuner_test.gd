extends SceneTree
## Headless test of the kite tuner (scenes/tools/kite_tuner.tscn, sail_visuals.md §12 test 26), run by
## run_ui_tests.sh:
##   godot --headless --path game -s res://tests/kite_tuner_test.gd
## On copies of the class files (game/generated/kite_tuner_test/): the minimal-diff class-file edits (JsonEdit) on
## every class file and generator test class; then on wm9 (a symmetric kite on a pole) and wm7 (an asymmetric one on
## a sprit): the sliders shown for the kite, a slider move reshapes the drawn kite, Save writes only the kite's
## blocks, a second tuner reads the same values back, the game's BoatView draws the saved shape, Revert and Reset
## to defaults, and with every value back at its default Save gives back the class file byte for byte. Nothing
## opens a window.

const SCENE := "res://scenes/tools/kite_tuner.tscn"
const DIR := "res://generated/kite_tuner_test"

var t := TestLog.new()


func _init() -> void:
	_main.call_deferred()


func _main() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var src := BoatClassData.repo_path("data/classes")
	for f in DirAccess.get_files_at(src):
		if f.ends_with(".boat.json"):
			DirAccess.copy_absolute(src.path_join(f), dir.path_join(f))
	_json_edit()
	await _tuner("wm9", dir)
	await _tuner("wm7", dir)
	BoatView.class_dir = ""
	t.finish(self, "kite tuner test")


static func max_move(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var m := 0.0
	for k in mini(a.size(), b.size()):
		m = maxf(m, a[k].distance_to(b[k]))
	return m


## JsonEdit on every class file and generator test class: a set and a removal give back the text; an insert keeps
## every other line; the parsed result has the value.
func _json_edit() -> void:
	t.begin("class file edits")
	var files: Array[String] = []
	for d in [BoatClassData.repo_path("data/classes"), BoatClassData.repo_path("tools/boatgen/tests/fixtures")]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".boat.json"):
				files.append(d.path_join(f))
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var name := path.get_file()
		t.ok(not JsonEdit.parse(text).is_empty(), "%s scans" % name)
		var p := PackedStringArray(["visual", "sails", "kite_x", "set", "forward"])
		var a := JsonEdit.put(text, p, "0.12")
		t.ok(a != "" and JsonEdit.value_at(a, p) == 0.12, "%s: a new kite block inserted" % name)
		var lines_a := a.split("\n")
		var lines_t := text.split("\n")
		var differ := 0
		for i in mini(lines_a.size(), lines_t.size()):
			differ += 1 if lines_a[i] != lines_t[i] else 0
		var grown := lines_a.size() - lines_t.size()
		t.ok((grown == 0 and differ == 1) or grown == 1, "%s: the insert changes one line or adds one (%d, %d)" % [
			name, differ, grown])
		var b := JsonEdit.put(a, PackedStringArray(["visual", "sails", "kite_x", "set", "depth_foot"]), "0.9")
		b = JsonEdit.put(b, p, "0.2")
		t.ok(JsonEdit.value_at(b, p) == 0.2 and JsonEdit.value_at(b, PackedStringArray(["visual", "sails", "kite_x",
			"set", "depth_foot"])) == 0.9, "%s: a value replaced and a second one added" % name)
		var c := JsonEdit.drop(b, PackedStringArray(["visual", "sails", "kite_x", "set", "depth_foot"]), 2)
		c = JsonEdit.drop(c, p, 2)
		t.ok(c == text, "%s: both removed gives back the file byte for byte" % name)
	t.ok(JsonEdit.num(0.42) == "0.42" and JsonEdit.num(1.0) == "1.0" and JsonEdit.num(2.268928) == "2.2689",
		"numbers as the class files write them")


func _tuner(id: String, dir: String) -> void:
	t.begin("kite tuner: %s" % id)
	var path := dir.path_join("%s.boat.json" % id)
	var original := FileAccess.get_file_as_string(path)
	var tu: Node = load(SCENE).instantiate()
	tu.set("class_dir", dir)
	tu.set("read_args", false)
	root.add_child(tu)
	await process_frame
	t.ok(id in tu.list_classes(), "%s listed" % id)
	t.ok(tu.select_class(id), "%s loads" % id)
	await process_frame
	var kite: String = tu.kite_id
	if tu.model == "loft":
		await _tuner_loft(tu, id, path, original, dir)
		return
	var pole: bool = tu.kite_part.mode == BoatView.Mode.POLE
	var asym: bool = tu.kite_type == "spinnaker_asym"
	t.ok(tu.rows.has("camber") and tu.rows.has("depth_foot") and tu.rows.has("forward"), "%s: the shape sliders" % id)
	t.ok(tu.rows.has("stay_clear") == pole, "%s: the forestay sliders %s" % [id, "shown on a pole" if pole else "hidden"])
	t.ok(tu.rows.has("twist_awa_lo") == asym, "%s: the twist by AWA sliders %s" % [id, "shown" if asym else "hidden"])
	var base: PackedVector3Array = tu.kite_mid().duplicate()
	t.ok(base.size() > 0, "%s: the kite is drawn" % id)
	# a slider move reshapes the kite
	var sl: HSlider = tu.rows["depth_foot"]["slider"]
	sl.value = sl.value - 0.25
	await process_frame
	var moved := max_move(base, tu.kite_mid())
	t.ok(moved > 0.05, "%s: the foot depth slider moves the kite (%.3f m)" % [id, moved])
	var tw: HSlider = tu.rows["twist_top"]["slider"]  # in degrees on the slider, radians in the file
	tw.value = 12.0
	sl = tu.rows["forward"]["slider"]
	sl.value = 0.1
	await process_frame
	var shaped: PackedVector3Array = tu.kite_mid().duplicate()
	t.ok(max_move(base, shaped) > 0.1, "%s: twist and forward move it further" % id)
	var want_foot: float = tu.values["depth_foot"]
	# save: only the kite's blocks change
	t.ok(tu.save(), "%s: saved" % id)
	var text := FileAccess.get_file_as_string(path)
	var differ := 0
	var la := text.split("\n")
	var lb := original.split("\n")
	for i in mini(la.size(), lb.size()):
		differ += 1 if la[i] != lb[i] else 0
	t.ok(la.size() == lb.size() and differ == 1, "%s: one line of the class file changed (%d)" % [id, differ])
	var cls: Variant = JSON.parse_string(text)
	var entry := KiteSet.class_entry(cls, kite)
	t.ok(entry.get("set") is Dictionary and absf(float(entry["set"].get("depth_foot", -1.0)) - want_foot) < 1e-4 \
		and absf(float(entry["set"].get("forward", -1.0)) - 0.1) < 1e-4, "%s: the set block saved: %s" % [id, entry.get("set")])
	t.ok(entry.get("look") is Dictionary and absf(float(entry["look"].get("twist_top", -1.0)) - deg_to_rad(12.0)) < 1e-3,
		"%s: twist_top saved in radians in the look block: %s" % [id, entry.get("look")])
	t.ok(not (entry["set"] as Dictionary).has("depth_head"), "%s: keys at their default not written" % id)
	# a second tuner reads the same values
	var tu2: Node = load(SCENE).instantiate()
	tu2.set("class_dir", dir)
	tu2.set("read_args", false)
	root.add_child(tu2)
	await process_frame
	tu2.select_class(id, kite)
	var same := true
	for k in tu.values:
		same = same and absf(float(tu.effective()[k]) - float(tu2.effective()[k])) < 1e-4
	t.ok(same, "%s: save and reload give the same values" % id)
	t.ok(max_move(shaped, tu2.kite_mid()) < 1e-3, "%s: and the same kite (%.5f m)" % [id, max_move(shaped, tu2.kite_mid())])
	tu2.queue_free()
	# the game draws the saved shape: a BoatView on the saved class file, same wind and trims
	BoatView.class_dir = dir
	var bv := BoatView.create(tu.data.info, 0.5)
	root.add_child(bv)
	for k in 3:
		bv.apply_sails(tu.sv, tu.sv, 1.0, 1.0 / 60.0)
	var game_mid := PackedVector3Array()
	for sp in bv.sail_parts:
		if sp.id == kite:
			game_mid = sp.shape.mid()
	t.ok(game_mid.size() > 0 and max_move(game_mid, shaped) < 1e-3,
		"%s: the game's BoatView draws the saved shape (%.5f m)" % [id, max_move(game_mid, shaped)])
	bv.free()
	BoatView.class_dir = ""
	# revert and reset
	tu.set_value("depth_head", 0.3)
	tu.revert()
	t.ok(absf(float(tu.values["depth_head"]) - float(tu.defaults["depth_head"])) < 1e-9 \
		and absf(float(tu.values["forward"]) - 0.1) < 1e-4, "%s: Revert gives back the saved values" % id)
	var copied: String = tu.copy_values()
	var cj: Variant = JSON.parse_string(copied)
	t.ok(cj is Dictionary and (cj as Dictionary).has(kite) and cj[kite]["set"].has("forward"), "%s: Copy values: %s" % [id, copied])
	tu.reset_defaults()
	await process_frame
	t.ok(max_move(base, tu.kite_mid()) < 1e-5, "%s: Reset to defaults draws the default kite (%.7f m)" % [
		id, max_move(base, tu.kite_mid())])
	t.ok(tu.save() and FileAccess.get_file_as_string(path) == original,
		"%s: saved at the defaults, the class file is as it was, byte for byte" % id)
	# the camera views
	for v in ["windward", "leeward", "ahead", "above", "chase"]:
		tu.set_view(v)
		var cam: Camera3D = tu.camera
		t.ok(cam.position.distance_to(tu.target) > 3.0 and is_finite(cam.position.x), "%s: %s view" % [id, v])
	tu.queue_free()
	await process_frame


## A kite on the lofted model (sail_visuals.md §6.5, wm7): only the loft's sliders, a slider moves the kite, the
## switch to the hinge model and back, Save writes the model and the slider, a second tuner and the game's BoatView
## read them back, and at the defaults Save gives back the class file byte for byte.
func _tuner_loft(tu: Node, id: String, path: String, original: String, dir: String) -> void:
	var kite: String = tu.kite_id
	t.ok(tu.can_loft() and tu.kite_part.shape.is_loft(), "%s: the kite is drawn lofted" % id)
	t.ok(tu.rows.has("loft_depth") and tu.rows.has("loft_trim") and not tu.rows.has("depth_foot") \
		and not tu.rows.has("camber"), "%s: only the loft's sliders (%s)" % [id, ", ".join(tu.rows.keys())])
	var base: PackedVector3Array = tu.kite_mid().duplicate()
	var sl: HSlider = tu.rows["loft_depth"]["slider"]
	sl.value = 0.8
	await process_frame
	t.ok(max_move(base, tu.kite_mid()) > 0.05, "%s: the depth slider moves the kite (%.3f m)" % [id,
		max_move(base, tu.kite_mid())])
	var tr: HSlider = tu.rows["loft_trim"]["slider"]  # degrees on the slider, radians in the file
	tr.value = 5.0
	await process_frame
	var shaped: PackedVector3Array = tu.kite_mid().duplicate()
	t.ok(max_move(base, shaped) > 0.1, "%s: the trim turns it further" % id)
	tu.set_model("hinge")
	await process_frame
	t.ok(not tu.kite_part.shape.is_loft() and tu.rows.has("depth_foot") and not tu.rows.has("loft_depth"),
		"%s: switched to the hinge model, its sliders shown" % id)
	t.ok(max_move(shaped, tu.kite_mid()) > 0.1, "%s: the hinge model draws another kite" % id)
	tu.set_model("loft")
	await process_frame
	t.ok(tu.kite_part.shape.is_loft() and max_move(shaped, tu.kite_mid()) < 1e-4, "%s: and back to the loft" % id)
	t.ok(tu.save(), "%s: saved" % id)
	var cls: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var entry := KiteSet.class_entry(cls, kite)
	var st: Dictionary = entry.get("set", {})
	t.ok(st.get("model") == "loft" and absf(float(st.get("loft_depth", -1.0)) - 0.8) < 1e-4 \
		and absf(float(st.get("loft_trim", 0.0)) - deg_to_rad(5.0)) < 1e-3 and not st.has("depth_foot"),
		"%s: the set block saved: %s" % [id, st])
	var tu2: Node = load(SCENE).instantiate()
	tu2.set("class_dir", dir)
	tu2.set("read_args", false)
	root.add_child(tu2)
	await process_frame
	tu2.select_class(id, kite)
	t.ok(tu2.model == "loft" and max_move(shaped, tu2.kite_mid()) < 1e-3, "%s: a second tuner reads it back (%.5f m)" % [
		id, max_move(shaped, tu2.kite_mid())])
	tu2.queue_free()
	BoatView.class_dir = dir
	var bv := BoatView.create(tu.data.info, 0.5)
	root.add_child(bv)
	for k in 3:
		bv.apply_sails(tu.sv, tu.sv, 1.0, 1.0 / 60.0)
	var game_mid := PackedVector3Array()
	for sp in bv.sail_parts:
		if sp.id == kite:
			game_mid = sp.shape.mid()
	t.ok(game_mid.size() > 0 and max_move(game_mid, shaped) < 1e-3,
		"%s: the game's BoatView draws the saved shape (%.5f m)" % [id, max_move(game_mid, shaped)])
	bv.free()
	BoatView.class_dir = ""
	tu.reset_defaults()
	await process_frame
	t.ok(max_move(base, tu.kite_mid()) < 1e-5, "%s: Reset to defaults draws the default kite" % id)
	t.ok(tu.save() and FileAccess.get_file_as_string(path) == original,
		"%s: saved at the defaults, the class file is as it was, byte for byte" % id)
	tu.queue_free()
	await process_frame
