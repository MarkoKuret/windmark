extends SceneTree
## Headless checks of the liveries (data_format.md §8, sail_visuals.md §11.2, WM-014, WM-081): the class livery
## files load and follow the rules, bad files are refused, the fleet rule is distinct and deterministic from the
## seed, the baked textures are there (in data/liveries and staged for import) with their layouts, and a fleet of
## both classes is painted: on the baked path (shared images on boat_baked and sail_baked, per-boat name and number
## over them in the layout's slots, the starboard stack uppermost) and on the procedural fallback, each at a
## measured cost. Run by tests/run_livery_test.sh (needs the generated boats and the staged textures).

const CLASSES := ["wm7", "wm12"]
const SAIL_FILES := ["_port_albedo.png", "_stbd_albedo.png", "_normal.png", "_orm.png"]

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _init() -> void:
	await process_frame
	print("livery checks")
	check_files()
	check_parse_errors()
	check_assign()
	check_shaders()
	check_baked_files()
	check_paint(true)
	check_paint(false)
	print("livery checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)


func check_files() -> void:
	for id in CLASSES:
		var list := Livery.load_class(id)
		check(list.size() >= 12, "%s: %d boats load (at least 12)" % [id, list.size()])
		var ids := {}
		var nums := {}
		var looks := {}
		var bright := 0
		for l in list:
			ids[l.id] = true
			nums[l.sail_number] = true
			looks[l.look_id] = true
			for c in [l.hull["topsides"], l.hull["boot_stripe"], l.hull["antifouling"], l.deck["gelcoat"], l.deck["nonslip"]]:
				if maxi(maxi(c.r8, c.g8), c.b8) > Livery.MAX_CHANNEL:
					bright += 1
		check(ids.size() == list.size() and nums.size() == list.size(), "%s: boat ids and sail numbers unique" % id)
		check(looks.size() == 1 and list[0].look_id != "", "%s: every boat wears the class livery (%s)" % [id, list[0].look_id])
		check(list[0].sails == list[-1].sails, "%s: one class sail set" % id)
		check(bright == 0, "%s: no hull or deck colour above a linear albedo of 0.8" % id)


func _doc() -> Dictionary:
	var d: Dictionary = BoatClassData._read_json(BoatClassData.repo_path("data/liveries/wm7.liveries.json"))
	return d.duplicate(true)


func check_parse_errors() -> void:
	var errs := []
	Livery.parse(_doc(), "wm7", errs)
	check(errs.is_empty(), "the wm7 file parses without errors (%s)" % ", ".join(errs))
	var cases := {
		"bright topsides": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["topsides"] = "#f0f0f0",
		"duplicate sail number": func(d: Dictionary) -> void: d["boats"][1]["sail_number"] = d["boats"][0]["sail_number"],
		"old schema": func(d: Dictionary) -> void: d["schema"] = "windmark.liveries/1",
		"no livery": func(d: Dictionary) -> void: d["liveries"].clear(),
		"too few boats": func(d: Dictionary) -> void: d["boats"].resize(5),
		"unknown graphic": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["graphic"]["type"] = "flames",
		"bad boat name": func(d: Dictionary) -> void: d["boats"][0]["boat_name"] = "A name far too long for it",
		"bad nation": func(d: Dictionary) -> void: d["boats"][0]["nation"] = "Slo",
		"bad colour": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["text"] = "navy",
		"bright sail": func(d: Dictionary) -> void: d["sails"]["main"]["color"] = "#ffffff",
		"unknown cloth": func(d: Dictionary) -> void: d["sails"]["main"]["cloth"] = "kevlar",
	}
	for name in cases:
		var d := _doc()
		cases[name].call(d)
		var e := []
		Livery.parse(d, "wm7", e)
		check(not e.is_empty(), "refused: %s (%s)" % [name, e[0] if not e.is_empty() else "accepted"])


func check_assign() -> void:
	check(Livery.fnv1a32("") == 2166136261 and Livery.fnv1a32("a") == 0xe40c292c and Livery.fnv1a32("foobar") == 0xbf9cf968,
		"fnv1a32 reference values")
	var list := Livery.load_class("wm7")
	var entries := [{"human": true, "choice": "swift"}]
	for i in 9:
		entries.append({"human": false})
	var a := Livery.assign(list, entries, 1234)
	var b := Livery.assign(list, entries, 1234)
	var c := Livery.assign(list, entries, 99)
	var ids := {}
	var same := true
	var diff := false
	for i in a.size():
		ids[a[i].sail_number] = true
		same = same and a[i].id == b[i].id
		diff = diff or a[i].id != c[i].id
	check(a[0].id == "swift", "the player's choice is kept")
	check(ids.size() == 10, "10 boats, 10 distinct sail numbers")
	check(same, "the same seed gives the same fleet")
	check(diff, "another seed gives another fleet")
	var two := Livery.assign(list, [{"human": true, "choice": "tern"}, {"human": true, "choice": "tern"}, {"human": false}], 5)
	check(two[0].id == "tern" and two[1].id != "tern" and two[2].id != two[1].id and two[2].id != "tern",
		"a second human with a taken boat gets the first free one")
	var dflt := Livery.assign(list, [{"human": true, "choice": ""}], 5)
	check(dflt[0].id == list[0].id, "no choice gives the first boat of the file")
	var big := []
	for i in 40:
		big.append({"human": i == 0, "choice": ""})
	var f := Livery.assign(list, big, 77)
	var nums := {}
	var names := {}
	for l in f:
		nums[l.sail_number] = true
		names[l.boat_name] = true
	check(nums.size() == 40 and names.size() == 40, "40 boats: sail numbers and names unique (%d, %d)" % [nums.size(), names.size()])
	var rep: Livery = f[list.size()]
	check(rep.boat_name.ends_with(" II") and rep.sail_number.to_int() > 1000 and rep.look_id == list[0].look_id,
		"a repeat: \"%s\" %s in the class livery" % [rep.boat_name, rep.sail_number])
	check(Livery.roman(2) == "II" and Livery.roman(4) == "IV" and Livery.roman(9) == "IX", "roman numerals")


func check_shaders() -> void:
	var want := {
		"res://shaders/boat.gdshader": ["hl_on", "hl_sheer", "livery_text", "hl_name_tex"],
		"res://shaders/sail.gdshader": ["sl_on", "sl_box", "sl_tex", "livery_text", "cloth_chord"],
		"res://shaders/boat_baked.gdshader": ["bk_albedo", "bk_normal", "bk_orm", "ov_box", "livery_text", "albedo_tex"],
		"res://shaders/sail_baked.gdshader": ["sk_albedo_port", "sk_albedo_stbd", "sk_orm", "sk_detail", "sn_box", "sl_layer_n"],
	}
	for path in want:
		var s := load(path) as Shader
		var names := []
		for u in s.get_shader_uniform_list():
			names.append(u["name"])
		var ok := true
		for n in want[path]:
			ok = ok and names.has(n)
		check(ok, "%s parses with the livery uniforms (%d uniforms)" % [path.get_file(), names.size()])
	var sb := (load("res://shaders/sail_baked.gdshader") as Shader).code
	check(not sb.contains("sail_cloth") and not sb.contains("sail_livery") and sb.contains("void light()"),
		"sail_baked.gdshader: no procedural cloth or livery, the sails' light")
	var bb := (load("res://shaders/boat_baked.gdshader") as Shader).code
	check(not bb.contains("hull_livery"), "boat_baked.gdshader: no procedural hull livery")


## The baked textures (data_format.md §8.5): in the repository and staged for import, with layouts that fit the
## class.
func check_baked_files() -> void:
	for id in CLASSES:
		var list := Livery.load_class(id)
		if list.is_empty():
			continue
		var look := list[0].look_id
		var data := BoatClassData.load_class(id)
		var hdir := BoatClassData.repo_path("data/liveries/%s/%s" % [id, look]) + "/"
		var sdir := BoatClassData.repo_path("data/liveries/%s/sails" % id) + "/"
		var ok := true
		for f in ["hull_albedo.png", "hull_normal.png", "hull_orm.png", "keel_albedo.png", "layout.json",
				"transom_albedo.png", "transom_normal.png", "transom_orm.png", "deck_albedo.png", "deck_normal.png",
				"deck_orm.png"]:
			ok = ok and FileAccess.file_exists(hdir + f)
		check(ok, "%s: hull, keel, transom and deck sets in data/liveries/%s/%s" % [id, id, look])
		var hlay: Dictionary = BoatClassData._read_json(hdir + "layout.json") if ok else {}
		var tim := Image.load_from_file(hdir + "transom_albedo.png") if ok else null
		var dim := Image.load_from_file(hdir + "deck_albedo.png") if ok else null
		var tsz: Array = hlay.get("transom", {}).get("size", [])
		var dsz: Array = hlay.get("deck", {}).get("size", [])
		check(tim != null and tim.get_width() == 2048 and tsz.size() == 2 and tim.get_height() == int(tsz[1])
			and dim != null and dim.get_width() == 4096 and dsz.size() == 2 and dim.get_height() == int(dsz[1]),
			"%s: transom 2048 and deck 4096 wide, as in the layout" % id)
		var img := Image.load_from_file(hdir + "hull_albedo.png") if ok else null
		check(img != null and img.get_width() == 4096 and img.get_height() == 2048, "%s: hull atlas 4096 x 2048" % id)
		var lay: Dictionary = BoatClassData._read_json(sdir + "layout.json") if FileAccess.file_exists(sdir + "layout.json") else {}
		var sails: Dictionary = lay.get("sails", {})
		var all := true
		for s in data.info.sails:
			var sid: String = s.name
			var has := sails.has(sid)
			for f in SAIL_FILES:
				has = has and FileAccess.file_exists(sdir + sid + f)
			all = all and has
			if has:
				var im := Image.load_from_file(sdir + sid + "_port_albedo.png")
				var sz: Array = sails[sid]["size"]
				check(maxi(im.get_width(), im.get_height()) == 2048 and im.get_width() == int(sz[0]),
					"%s %s: sail images %d x %d, as in the layout (%s)" % [id, sid, im.get_width(), im.get_height(), sails[sid]["cloth"]])
		check(all, "%s: every class sail baked with its four images" % id)
		var hs := BakedLivery.hull_set(id, look)
		var ss := BakedLivery.sail_set(id)
		check(hs.has("albedo") and hs.has("keel") and hs.has("transom") and hs.has("deck")
			and ss.get("sails", {}).size() == data.info.sails.size(),
			"%s: staged and imported (hull, keel, transom, deck, %d sails)" % [id, ss.get("sails", {}).size()])
		for d in ["dacron", "laminate", "nylon"]:
			check(BakedLivery.detail(d) != null, "cloth detail %s staged" % d)


## The transom (its own slot: the baked transom set, the boat's name in the name panel) and the deck (one baked
## material with the non-slip mask on the gelcoat and non-slip slots), data_format.md §8.5.
func _check_baked_transom_deck(id: String, bv: BoatView, other: BoatView) -> void:
	var deck := bv.model.find_child("deck", true, false) as MeshInstance3D
	var deck2 := other.model.find_child("deck", true, false) as MeshInstance3D
	var tm: ShaderMaterial = null
	var tm2: ShaderMaterial = null
	var dms := {}
	for s in deck.mesh.get_surface_count():
		var slot := deck.mesh.surface_get_material(s).resource_name
		var o := deck.get_surface_override_material(s) as ShaderMaterial
		if slot == "transom":
			tm = o
			tm2 = deck2.get_surface_override_material(s) as ShaderMaterial
		elif slot in ["gelcoat", "nonslip"]:
			dms[slot] = o
	var hs := BakedLivery.hull_set(id, bv.livery.look_id)
	var box: Vector4 = (tm.get_shader_parameter("ov_box") as PackedVector4Array)[0] if tm else Vector4.ZERO
	var pan: Dictionary = BoatLivery.hull_geometry(bv)["transom"]
	var uv: Array = pan.get("uv1", [0, 0, 0, 0])
	var inside := box.z > box.x and box.w > box.y and box.x >= float(uv[0]) - 1e-4 and box.z <= float(uv[2]) + 1e-4 \
		and box.y >= float(uv[1]) - 1e-4 and box.w <= float(uv[3]) + 1e-4
	check(tm != null and tm.shader == BoatLivery.BAKED_BOAT and tm.get_shader_parameter("bk_albedo") == hs["transom"]["albedo"]
		and tm.get_shader_parameter("bk_proj") == 0 and tm.get_shader_parameter("ov_on") == 1,
		"%s baked: the transom on its own slot with the baked transom set" % id)
	check(inside and tm2 != null and tm2 != tm and tm2.get_shader_parameter("livery_text") == other.livery_text.texture
		and tm2.get_shader_parameter("bk_albedo") == tm.get_shader_parameter("bk_albedo"),
		"%s baked: the boat's name in the transom's name panel (%.2f..%.2f of u), per boat over the shared images" % [id, box.x, box.z])
	var dm: ShaderMaterial = dms.get("gelcoat")
	check(dm != null and dms.get("nonslip") == dm and dm.shader == BoatLivery.BAKED_BOAT
		and dm.get_shader_parameter("bk_albedo") == hs["deck"]["albedo"] and dm.get_shader_parameter("bk_orm") == hs["deck"]["orm"]
		and dm.get_shader_parameter("bk_mask") == true and dm.get_shader_parameter("ns_albedo_tex") != null,
		"%s baked: the deck's gelcoat and non-slip on the baked deck set, the non-slip detail by the mask" % id)


func check_paint(baked: bool) -> void:
	BakedLivery.enabled = baked
	BakedLivery.clear()
	var path := "baked" if baked else "procedural"
	var fleet := Node3D.new()
	root.add_child(fleet)
	for id in CLASSES:
		var data := BoatClassData.load_class(id)
		if data == null or not ResourceLoader.exists("res://generated/boats/%s.glb" % id):
			check(false, "%s generated (run tests/run_boat_import_test.sh)" % id)
			continue
		var list := Livery.load_class(id)
		var plain := BoatView.create(data.info, data.info.rudder_max, true)
		fleet.add_child(plain)
		var usec := 0
		var first := 0
		var views := []
		for k in 4:
			var bv := BoatView.create(data.info, data.info.rudder_max, true)
			fleet.add_child(bv)
			var t0 := Time.get_ticks_usec()
			bv.set_livery(list[k])
			var dt := Time.get_ticks_usec() - t0
			if k == 0:
				first = dt
			else:
				usec += dt
			views.append(bv)
		print("      %s %s: livery applied in %.1f ms for the first boat (loads the class set), %.1f ms per further boat"
			% [id, path, first / 1000.0, usec / 3000.0])
		var bv: BoatView = views[0]
		var lv: Livery = list[0]
		var img := bv.livery_text.image
		check(img.get_width() == 1024 and img.get_height() == 512 and img.get_format() == Image.FORMAT_R8 and img.has_mipmaps(),
			"%s %s: text texture 1024 x 512, one channel, mipmapped (%.0f kB)" % [id, path, img.get_data().size() / 1024.0])
		for row in [LiveryText.Row.NAME, LiveryText.Row.NUMBER]:
			check(_ink(img, row) > 0.02, "%s %s: text row %d has ink" % [id, path, row])
		var hull := bv.model.find_child("hull", true, false) as MeshInstance3D
		var plain_hull := plain.model.find_child("hull", true, false) as MeshInstance3D
		var untouched := true
		for s in plain_hull.mesh.get_surface_count():
			untouched = untouched and plain_hull.get_surface_override_material(s) == null
		check(untouched and plain_hull.mesh == hull.mesh, "%s %s: the shared hull mesh is unchanged, a boat without livery keeps the class look" % [id, path])
		if baked:
			_check_baked_boat(id, views, lv)
		else:
			_check_procedural_boat(id, bv, lv, data)
	fleet.queue_free()
	BakedLivery.enabled = true


func _check_baked_boat(id: String, views: Array, lv: Livery) -> void:
	var bv: BoatView = views[0]
	var other: BoatView = views[1]
	var hull := bv.model.find_child("hull", true, false) as MeshInstance3D
	var n := 0
	var shared := true
	var boxes_ok := true
	for s in hull.mesh.get_surface_count():
		var o := hull.get_surface_override_material(s) as ShaderMaterial
		var o2 := (other.model.find_child("hull", true, false) as MeshInstance3D).get_surface_override_material(s) as ShaderMaterial
		if o == null or o.shader != BoatLivery.BAKED_BOAT:
			continue
		n += 1
		shared = shared and o2 != null and o != o2 and o.get_shader_parameter("bk_albedo") == o2.get_shader_parameter("bk_albedo") \
			and o.get_shader_parameter("livery_text") == bv.livery_text.texture \
			and o2.get_shader_parameter("livery_text") == other.livery_text.texture
		var boxes: PackedVector4Array = o.get_shader_parameter("ov_box")
		boxes_ok = boxes_ok and boxes.size() == 4
		for k in boxes.size():
			var b := boxes[k]
			# 0, 1 starboard (v < 0.5), name aft of the number; 2, 3 port (v > 0.5)
			boxes_ok = boxes_ok and b.z > b.x and b.w > b.y and (b.w < 0.5 if k < 2 else b.y > 0.5)
		boxes_ok = boxes_ok and boxes[0].z < boxes[1].x and boxes[3].z < boxes[2].x
	check(n == 3, "%s baked: topsides, boot stripe and antifouling on boat_baked.gdshader" % id)
	check(shared, "%s baked: the hull images shared by the fleet, the name and number per boat" % id)
	check(boxes_ok, "%s baked: name aft and number forward in the livery panels of both sides" % id)
	var keel := bv.model.find_child("keel", true, false) as MeshInstance3D
	var km := keel.get_surface_override_material(0) as ShaderMaterial if keel else null
	var kr: Vector4 = km.get_shader_parameter("bk_rect") if km else Vector4.ZERO
	var aabb := keel.mesh.get_aabb() if keel else AABB()
	# the side view's rectangle (forward min, top, length, height) holds the keel mesh
	var holds := kr.z > 0.0 and aabb.position.z >= kr.x - 1e-3 and aabb.end.z <= kr.x + kr.z + 1e-3 \
		and aabb.end.y <= kr.y + 1e-3 and aabb.position.y >= kr.y - kr.w - 1e-3
	check(km != null and km.get_shader_parameter("bk_proj") == 1 and holds,
		"%s baked: keel in side view, its rectangle holds the keel (%.2f..%.2f m fwd)" % [id, aabb.position.z, aabb.end.z])
	_check_baked_transom_deck(id, bv, other)
	for sp in bv.sail_parts:
		var m := (sp.node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		var m2 := (other.sail_parts[sp.index].node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if m == null or m.shader != BoatLivery.BAKED_SAIL:
			check(false, "%s %s: baked sail material" % [id, sp.id])
			continue
		check(m.get_shader_parameter("sl_layer_n") == sp.rows * sp.cols and m.get_shader_parameter("sk_albedo_port") == m2.get_shader_parameter("sk_albedo_port")
			and m.get_shader_parameter("sk_detail") != null,
			"%s %s: baked sail, images shared, cloth detail, layer split at %d" % [id, sp.id, sp.rows * sp.cols])
		var lay: Dictionary = m.get_meta("livery_layout")
		var n_rows := int(lay["rows"])
		if sp.type == "jib":
			check(n_rows == 0, "%s %s: no number on a jib" % [id, sp.id])
			continue
		var want := 2 if lv.nation != "" else 1
		check(n_rows == want, "%s %s: %d rows a side (nation and number) in the layout's slots" % [id, sp.id, n_rows])
		if n_rows == 0:
			continue
		var box: PackedVector4Array = lay["box"]
		var port_top := box[0].y + box[0].w
		var stbd_bottom := box[2 + n_rows - 1].y - box[2 + n_rows - 1].w
		check(stbd_bottom > port_top, "%s %s: starboard stack uppermost (%.2f m above the port stack)" % [id, sp.id, stbd_bottom - port_top])
		var fits := true
		var slots: Array = lay["slots"]
		var k := 0
		for row in slots:
			if row["kind"] == "insignia" or (row["kind"] == "nation" and lv.nation == ""):
				continue
			for side in 2:
				var sl: Array = row["port" if side == 0 else "stbd"]
				var b := box[k + 2 * side]
				fits = fits and b.z <= float(sl[2]) + 1e-4 and b.w <= float(sl[3]) + 1e-4 and absf(b.x - float(sl[0])) < 1e-4
			k += 1
		check(fits, "%s %s: the boat's rows fit their slots" % [id, sp.id])
		if sp.type == "main":
			check(float(lay["h"]) >= 0.99 * BoatLivery.number_height(bv.info.loa), "%s main: numbers at the Appendix G height %.3f m" % [id, lay["h"]])
			var has_ins := false
			for row in slots:
				has_ins = has_ins or row["kind"] == "insignia"
			check(has_ins, "%s main: the insignia is baked above the numbers" % id)


func _check_procedural_boat(id: String, bv: BoatView, lv: Livery, data: BoatClassData) -> void:
	var hull := bv.model.find_child("hull", true, false) as MeshInstance3D
	var top: ShaderMaterial = null
	var colours := 0
	for s in hull.mesh.get_surface_count():
		var o := hull.get_surface_override_material(s) as ShaderMaterial
		if o == null:
			continue
		if o.get_shader_parameter("hl_on") == 1:
			top = o
		else:
			colours += 1
	check(top != null and colours == 2, "%s procedural: topsides on the livery path, boot stripe and antifouling recoloured" % id)
	if top:
		var sh: PackedFloat32Array = top.get_shader_parameter("hl_sheer")
		var bt: PackedFloat32Array = top.get_shader_parameter("hl_boot")
		var ok := sh.size() == 17
		for i in range(2, 15):
			ok = ok and bt[i] > sh[i] + 0.02 and sh[i] >= -0.001 and bt[i] <= 0.5
		check(ok, "%s procedural: sheer and boot stripe curves (v %.3f..%.3f amidships)" % [id, sh[8], bt[8]])
		check(top.shader == BoatMaterials.SHADER, "%s procedural: topsides on the shared boat shader" % id)
	var deck := bv.model.find_child("deck", true, false) as MeshInstance3D
	var tr_ok := false
	for s in deck.mesh.get_surface_count():
		if deck.mesh.surface_get_material(s).resource_name == "transom":
			var o := deck.get_surface_override_material(s) as ShaderMaterial
			var c: Variant = o.get_shader_parameter("albedo_color") if o else null
			var mean := BoatLivery.texture_mean(o.get_shader_parameter("albedo_tex")) if o else 1.0
			if c is Color:
				var lin := (c as Color).srgb_to_linear()
				var want: Color = (lv.hull["topsides"] as Color).srgb_to_linear()
				tr_ok = absf(lin.b * mean - want.b) < 0.01 and absf(lin.r * mean - want.r) < 0.01
	check(tr_ok, "%s procedural: the transom in the topsides colour" % id)
	for sp in bv.sail_parts:
		var m := (sp.node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if m == null:
			check(false, "%s %s: procedural sail material" % [id, sp.id])
			continue
		var lay: Dictionary = m.get_meta("livery_layout")
		var n_rows := int(lay["rows"])
		if sp.type == "jib":
			check(n_rows == 0 and m.get_shader_parameter("sl_on") == 1, "%s %s procedural: no number on a jib" % [id, sp.id])
			continue
		check(lay["placed"] and n_rows == BoatLivery.sail_rows(sp.type, lv).size(), "%s %s procedural: %d rows a side placed" % [id, sp.id, n_rows])
		var box: PackedVector4Array = lay["box"]
		check(box[3 + n_rows - 1].y - box[3 + n_rows - 1].w > box[0].y + box[0].w, "%s %s procedural: starboard stack uppermost" % [id, sp.id])
		if sp.type == "main":
			check(lay["arc_ok"], "%s main procedural: numbers within the 60 %% leech arc from the head" % id)


func _ink(img: Image, row: int) -> float:
	var s := 0.0
	var n := 0
	for y in range(row * 128, row * 128 + 128, 4):
		for x in range(0, 512, 4):
			s += img.get_pixel(x, y).r
			n += 1
	return s / n
