extends SceneTree
## Headless checks of the liveries (data_format.md §8, sail_visuals.md §11.2, WM-014, WM-081): the class livery
## files load and follow the rules (the first livery baked, the others tints of it worn by the boats that name
## them), bad files are refused, the fleet rule is distinct and deterministic from the seed (a 16-boat fleet in
## several liveries, repeats in the next one), the baked textures are there (in data/liveries and staged for
## import, the atlas with its colour masks and the sails with their cloth zones) with their layouts, and a fleet
## of every class is painted: on the baked path (the staged boat atlas on the boat material, sail_baked for the
## sails, per-boat name and number over them in the layout's slots, the starboard stack uppermost, the tint
## uniforms on a boat in a tinted livery and none on the default boat) and on the procedural fallback, each at a
## measured cost. Run by tests/run_livery_test.sh (needs the generated boats and the staged textures).

const CLASSES := ["wm7", "wm12", "wm9", "wm16", "wm21", "wm10"]
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
		var bases := {}
		var bright := 0
		var sails_ok := true
		for l in list:
			ids[l.id] = true
			nums[l.sail_number] = true
			looks[l.look_id] = true
			bases[l.base_id] = true
			for c in [l.hull["topsides"], l.hull["boot_stripe"], l.hull["antifouling"], l.deck["gelcoat"], l.deck["nonslip"]]:
				if maxi(maxi(c.r8, c.g8), c.b8) > Livery.MAX_CHANNEL:
					bright += 1
			for role in Livery.ROLES:
				var e: Dictionary = l.sails[role]
				var ce: Dictionary = l.class_sails[role]
				sails_ok = sails_ok and e["cloth"] == ce["cloth"] and e.has("color") and e.has("number")
				for c in [e["color"], e["number"]] + e["colors"]:
					if maxi(maxi(c.r8, c.g8), c.b8) > Livery.MAX_CHANNEL:
						bright += 1
		check(ids.size() == list.size() and nums.size() == list.size(), "%s: boat ids and sail numbers unique" % id)
		var first: Livery = list[0]
		var file_looks := Livery.looks_of(id)
		check(first.look_id == file_looks[0].look_id and first.base_id == first.look_id and first.look_index == 0,
			"%s: the first boat wears the first livery, the baked one (%s)" % [id, first.look_id])
		check(bases.size() == 1 and bases.has(first.look_id), "%s: every livery is drawn on the class livery's textures" % id)
		check(looks.size() >= 6 and file_looks.size() >= 6, "%s: %d liveries, %d worn (at least 6)" % [id, file_looks.size(), looks.size()])
		check(sails_ok, "%s: every boat's sails keep the class cloth, with colours per livery" % id)
		var tinted := 0
		for l in list:
			if l.look_id != l.base_id:
				tinted += 1
				check(l.base_hull == first.hull and l.class_sails == first.sails, "%s %s: the base colours are the class livery's" % [id, l.id])
				break
		check(tinted == 1, "%s: a boat in a tinted livery" % id)
		check(bright == 0, "%s: no hull, deck or sail colour above a linear albedo of 0.8" % id)


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
		"unknown boat livery": func(d: Dictionary) -> void: d["boats"][3]["livery"] = "tartan",
		"first boat in another livery": func(d: Dictionary) -> void: d["boats"][0]["livery"] = d["liveries"][1]["id"],
		"unknown base": func(d: Dictionary) -> void: d["liveries"][1]["base"] = "tartan",
		"bright livery sail": func(d: Dictionary) -> void: d["liveries"][1]["sails"] = {"main": {"color": "#ffffff"}},
		"unknown livery sail design": func(d: Dictionary) -> void: d["liveries"][1]["sails"] = {"spinnaker": {"design": "flames"}},
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
	var orig: Livery = null
	for l in list:
		if l.id == rep.id:
			orig = l
	var file_looks := Livery.looks_of("wm7")
	var next_look: Livery = file_looks[(orig.look_index + 1) % file_looks.size()]
	check(rep.boat_name.ends_with(" II") and rep.sail_number.to_int() > 1000 and rep.look_id == next_look.look_id
		and rep.hull == next_look.hull and rep.base_id == orig.base_id,
		"a repeat: \"%s\" %s in the next livery (%s after %s)" % [rep.boat_name, rep.sail_number, rep.look_id, orig.look_id])
	# a 16-boat race reads as different boats: several hull colours and sail colours among them
	var race := []
	for i in 16:
		race.append({"human": i == 0, "choice": ""})
	var r16 := Livery.assign(list, race, 2026)
	var hulls := {}
	var mains := {}
	var kites := {}
	for l in r16:
		hulls[l.hull["topsides"].to_html(false)] = true
		mains[l.sails["main"]["color"].to_html(false)] = true
		kites[l.sails["spinnaker"]["color"].to_html(false) + l.sails["spinnaker"]["design"]] = true
	check(hulls.size() >= 6 and mains.size() >= 2 and kites.size() >= 5,
		"a 16-boat fleet: %d hull colours, %d sail colours, %d spinnakers" % [hulls.size(), mains.size(), kites.size()])
	check(Livery.roman(2) == "II" and Livery.roman(4) == "IV" and Livery.roman(9) == "IX", "roman numerals")


func check_shaders() -> void:
	var want := {
		"res://shaders/boat.gdshader": ["hl_on", "hl_sheer", "livery_text", "hl_name_tex"],
		"res://shaders/sail.gdshader": ["sl_on", "sl_box", "sl_tex", "livery_text", "cloth_chord"],
		"res://shaders/boat_atlas.gdshader": ["bk_albedo", "bk_normal", "bk_orm", "bk_rect", "bk_keel", "ov_box", "tr_box",
			"livery_text", "slot_color", "tile_color", "hl_on", "hl_sheer", "tn_on", "tn_from", "tn_to", "tn_k"],
		"res://shaders/sail_baked.gdshader": ["sk_albedo_port", "sk_albedo_stbd", "sk_orm", "sk_detail", "sn_box", "sl_layer_n",
			"st_on", "st_from", "sd_design", "sd_cloth", "sd_clew", "sd_head"],
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
		var rects: Dictionary = hs.get("rects", {})
		check(hs.has("atlas") and rects.size() == 4 and ss.get("sails", {}).size() == data.info.sails.size(),
			"%s: staged and imported (the boat atlas with %d regions, %d sails)" % [id, rects.size(), ss.get("sails", {}).size()])
		if hs.has("atlas"):
			var at: Texture2D = hs["atlas"]["albedo"]
			check(at.get_width() == 2048 and at.get_height() == 2048, "%s: boat atlas 2048 x 2048 (data_format.md §8.5)" % id)
			_check_masks(id, look, rects)
			var inside := true
			for k in rects:
				var r: Vector4 = rects[k]
				inside = inside and r.x >= 0.0 and r.y >= 0.0 and r.x + r.z <= 1.0 + 1e-5 and r.y + r.w <= 1.0 + 1e-5 and r.z > 0.0
			check(inside, "%s: the atlas regions lie inside it" % id)
		for sid in ss.get("sails", {}):
			var t: Texture2D = ss["sails"][sid]["port"]
			check(maxi(t.get_width(), t.get_height()) == 1024, "%s %s: sail staged at 1024 (%d x %d)" % [id, sid,
				t.get_width(), t.get_height()])
		for d in ["dacron", "laminate", "nylon"]:
			check(BakedLivery.detail(d) != null, "cloth detail %s staged" % d)


## The colour masks of the staged atlas (data_format.md §8.5 "Staged boat atlas"): on the hull region the ORM's
## blue is the paint coverage (the topsides about half of the band, none below the boot stripe) and its red the
## zone levels; the staged sails carry the cloth zone in their albedo's alpha, mostly cloth.
func _check_masks(id: String, look: String, rects: Dictionary) -> void:
	var dir := "res://generated/liveries/%s/" % id
	var orm := Image.load_from_file(ProjectSettings.globalize_path(dir + look + "/atlas_orm.png"))
	var r: Vector4 = rects["hull"]
	var w := orm.get_width()
	var h := orm.get_height()
	var x0 := int(r.x * w)
	var y0 := int(r.y * h)
	var hw := int(r.z * w)
	var hh := int(r.w * h)
	var paint := 0.0
	var levels := {}
	var n := 0
	var bottom := 0.0
	var nb := 0
	for y in range(y0, y0 + hh, 8):
		for x in range(x0, x0 + hw, 8):
			var c := orm.get_pixel(x, y)
			paint += c.b
			levels[roundi(c.r * 3.0)] = true
			n += 1
			# the lowest rows of the starboard band: the keel line, antifouling
			if y > y0 + hh / 2 - 8 and y < y0 + hh / 2:
				bottom += c.b
				nb += 1
	check(paint / n > 0.3 and paint / n < 0.7 and bottom / maxi(nb, 1) < 0.05 and levels.size() >= 3,
		"%s: atlas colour masks: paint %.2f of the hull region, none at the keel line, %d zone levels" % [id, paint / n, levels.size()])
	var sail := Image.load_from_file(ProjectSettings.globalize_path(dir + "sails/main_port_albedo.png"))
	var cloth := 0.0
	var ns := 0
	for y in range(0, sail.get_height(), 8):
		for x in range(0, sail.get_width(), 8):
			cloth += 1.0 if sail.get_pixel(x, y).a > 0.9 else 0.0
			ns += 1
	check(sail.get_format() == Image.FORMAT_RGBA8 and cloth / ns > 0.9,
		"%s: staged main with the cloth zone in its alpha (%.2f cloth)" % [id, cloth / ns])


## The transom (the boat's name in the transom's name panel) and the deck (the deck region with the painted hardware
## and the non-slip mask), data_format.md §8.5, on the boat's material.
func _check_baked_transom_deck(id: String, bv: BoatView, other: BoatView, bm: ShaderMaterial, bm2: ShaderMaterial) -> void:
	var box: Vector4 = bm.get_shader_parameter("tr_box")
	var pan: Dictionary = BoatLivery.hull_geometry(bv)["transom"]
	var uv: Array = pan.get("uv1", [0, 0, 0, 0])
	var inside := box.z > box.x and box.w > box.y and box.x >= float(uv[0]) - 1e-4 and box.z <= float(uv[2]) + 1e-4 \
		and box.y >= float(uv[1]) - 1e-4 and box.w <= float(uv[3]) + 1e-4
	check(inside and bm.get_shader_parameter("tr_on") == 1 and bm2.get_shader_parameter("livery_text") == other.livery_text.texture,
		"%s baked: the boat's name in the transom's name panel (%.2f..%.2f of u), per boat over the shared atlas" % [id, box.x, box.z])
	var deck := bv.model.find_child("body", true, false) as MeshInstance3D
	check(deck != null and deck.get_surface_override_material(0) == bm and not BoatMaterials.part_surfaces(bv.model, "deck").is_empty(),
		"%s baked: the deck on the boat's material (the deck region, the non-slip by the mask)" % id)


## The boat's material on every non-sail surface of every level (sail_visuals.md §11.4): one per boat.
func _boat_material(bv: BoatView) -> Array:
	var mats := {}
	var n := 0
	for lv in bv.levels:
		for mi in (lv["model"] as Node).find_children("*", "MeshInstance3D", true, false):
			var nm := String(mi.name)
			if nm.begins_with("sail_") or nm.begins_with("shadow") or nm == "sheets":
				continue
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				n += 1
				var o = (mi as MeshInstance3D).get_surface_override_material(s)
				mats[o] = true
	return [mats.keys(), n]


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
		var hull := bv.model.find_child("body", true, false) as MeshInstance3D
		var plain_hull := plain.model.find_child("body", true, false) as MeshInstance3D
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
	var got := _boat_material(bv)
	var bm: ShaderMaterial = got[0][0] if got[0].size() == 1 else null
	var bm2: ShaderMaterial = _boat_material(other)[0][0]
	check(bm != null and bm.shader == BoatMaterials.ATLAS_SHADER and bm.get_shader_parameter("bk_on") == true,
		"%s baked: every boat surface of every level (%d) on one material with the boat atlas" % [id, got[1]])
	if bm == null:
		return
	var hs := BakedLivery.hull_set(id, lv.look_id)
	check(bm2 != bm and bm.get_shader_parameter("bk_albedo") == hs["atlas"]["albedo"]
		and bm2.get_shader_parameter("bk_albedo") == bm.get_shader_parameter("bk_albedo")
		and bm.get_shader_parameter("livery_text") == bv.livery_text.texture,
		"%s baked: the atlas shared by the fleet, the name and number per boat" % id)
	# the default boat as baked; a boat in another livery tinted on the same atlas (§8.5 "Tinted liveries")
	check(bm.get_shader_parameter("tn_on") == 0, "%s baked: the default boat shows the atlas as baked (no tint)" % id)
	var tinted: BoatView = null
	for v in views:
		if (v as BoatView).livery.look_id != lv.look_id:
			tinted = v
			break
	if tinted == null:
		check(false, "%s baked: a boat in a tinted livery among the first four" % id)
	else:
		var tm: ShaderMaterial = _boat_material(tinted)[0][0]
		var to: PackedVector3Array = tm.get_shader_parameter("tn_to")
		var from: PackedVector3Array = tm.get_shader_parameter("tn_from")
		var k: PackedFloat32Array = tm.get_shader_parameter("tn_k")
		var want := (tinted.livery.hull["topsides"] as Color).srgb_to_linear()
		var base := (lv.hull["topsides"] as Color).srgb_to_linear()
		check(tm.get_shader_parameter("tn_on") == 1 and tm.get_shader_parameter("bk_albedo") == hs["atlas"]["albedo"]
			and to.size() == 6 and from.size() == 6 and k.size() == 6
			and to[4].is_equal_approx(Vector3(want.r, want.g, want.b)) and from[4].is_equal_approx(Vector3(base.r, base.g, base.b))
			and k[4] > 0.0 and k[4] <= 1.0,
			"%s baked: \"%s\" (%s) tinted on the class atlas, topsides %s over %s, k %.2f" % [id, tinted.livery.boat_name,
			tinted.livery.look_id, tinted.livery.hull["topsides"].to_html(false), lv.hull["topsides"].to_html(false), k[4]])
		var kite_tinted := false
		var kite_any := false
		for sp in tinted.sail_parts:
			if not sp.type.begins_with("spinnaker"):
				continue
			kite_any = true
			var sm := (sp.node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
			if sm == null or sm.shader != BoatLivery.BAKED_SAIL:
				continue
			var e := tinted.livery.sail_for(sp.type)
			var on: bool = sm.get_shader_parameter("st_on") == 1
			kite_tinted = kite_tinted or (on and sm.get_shader_parameter("sd_design") == Livery.DESIGNS.find(e["design"])
				and (sm.get_shader_parameter("sd_height") as float) > 1.0)
		check(kite_tinted or not kite_any, "%s baked: the tinted boat's spinnaker in its livery's colours and design" % id)
	var boxes: PackedVector4Array = bm.get_shader_parameter("ov_box")
	var boxes_ok := boxes.size() == 4
	for k in boxes.size():
		var b := boxes[k]
		# 0, 1 starboard (v < 0.5), name aft of the number; 2, 3 port (v > 0.5)
		boxes_ok = boxes_ok and b.z > b.x and b.w > b.y and (b.w < 0.5 if k < 2 else b.y > 0.5)
	boxes_ok = boxes_ok and boxes[0].z < boxes[1].x and boxes[3].z < boxes[2].x
	check(boxes_ok, "%s baked: name aft and number forward in the livery panels of both sides" % id)
	var rects: PackedVector4Array = bm.get_shader_parameter("bk_rect")
	check(rects.size() == 5 and rects[1].z > 0.9 and rects[2].z > 0.9 and rects[3].z > 0.0 and rects[4].z > 0.0,
		"%s baked: hull, deck, transom and keel regions of the atlas" % id)
	var kr: Vector4 = bm.get_shader_parameter("bk_keel")
	var aabb := AABB()
	var first := true
	for e in BoatMaterials.part_surfaces(bv.model, "keel"):
		for i in (e["indices"] as PackedInt32Array):
			var q: Vector3 = (e["positions"] as PackedVector3Array)[i]
			aabb = AABB(q, Vector3.ZERO) if first else aabb.expand(q)
			first = false
	# the side view's rectangle (forward min, top, length, height) holds the keel mesh
	var holds := kr.z > 0.0 and aabb.position.z >= kr.x - 1e-3 and aabb.end.z <= kr.x + kr.z + 1e-3 \
		and aabb.end.y <= kr.y + 1e-3 and aabb.position.y >= kr.y - kr.w - 1e-3
	check(holds, "%s baked: keel in side view, its rectangle holds the keel (%.2f..%.2f m fwd)" % [id, aabb.position.z, aabb.end.z])
	_check_baked_transom_deck(id, bv, other, bm, bm2)
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
	var got := _boat_material(bv)
	var top: ShaderMaterial = got[0][0] if got[0].size() == 1 else null
	check(top != null and top.shader == BoatMaterials.ATLAS_SHADER and top.get_shader_parameter("hl_on") == 1
		and top.get_shader_parameter("bk_on") != true,
		"%s procedural: the boat's material with the topsides on the livery path, no atlas" % id)
	if top == null:
		return
	var sh: PackedFloat32Array = top.get_shader_parameter("hl_sheer")
	var bt: PackedFloat32Array = top.get_shader_parameter("hl_boot")
	var ok := sh.size() == 17
	for i in range(2, 15):
		ok = ok and bt[i] > sh[i] + 0.02 and sh[i] >= -0.001 and bt[i] <= 0.5
	check(ok, "%s procedural: sheer and boot stripe curves (v %.3f..%.3f amidships)" % [id, sh[8], bt[8]])
	var col: PackedVector4Array = top.get_shader_parameter("slot_color")
	var want := {"transom": lv.hull["topsides"], "hull_boottop": lv.hull["boot_stripe"],
		"hull_antifouling": lv.hull["antifouling"], "keel": lv.hull["keel"], "deck_nonslip": lv.deck["nonslip"]}
	var all := true
	for k in want:
		var c: Color = (want[k] as Color).srgb_to_linear()
		var v := col[BoatMaterials.slot_id(k)]
		all = all and absf(v.x - c.r) < 0.01 and absf(v.y - c.g) < 0.01 and absf(v.z - c.b) < 0.01
	check(all, "%s procedural: transom in the topsides colour, boot stripe, antifouling, keel and deck recoloured" % id)
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
