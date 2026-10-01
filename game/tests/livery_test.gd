extends SceneTree
## Headless checks of the liveries (data_format.md §8, sail_visuals.md §11.2, WM-014): the class livery files load
## and follow the rules, bad files are refused, the fleet rule is distinct and deterministic from the seed, and a
## fleet of both classes is painted (per-boat materials over the shared meshes, the text texture, the hull and
## sail livery uniforms, the sail number stacks placed by Appendix G with the starboard stack uppermost) at a
## measured cost. Run by tests/run_livery_test.sh (needs the generated boats).

const CLASSES := ["wm7", "wm12"]

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
	check_paint()
	print("livery checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)


func check_files() -> void:
	for id in CLASSES:
		var list := Livery.load_class(id)
		check(list.size() >= 12, "%s: %d liveries load (at least 12)" % [id, list.size()])
		var ids := {}
		var nums := {}
		var looks := {}
		var bright := 0
		for l in list:
			ids[l.id] = true
			nums[l.sail_number] = true
			looks["%s|%s|%s" % [l.hull["topsides"].to_html(false), l.graphic["type"], l.sails["spinnaker"]["color"].to_html(false)]] = true
			for c in [l.hull["topsides"], l.hull["boot_stripe"], l.hull["antifouling"], l.deck["gelcoat"], l.deck["nonslip"]]:
				if maxi(maxi(c.r8, c.g8), c.b8) > Livery.MAX_CHANNEL:
					bright += 1
		check(ids.size() == list.size() and nums.size() == list.size(), "%s: ids and sail numbers unique" % id)
		check(looks.size() == list.size(), "%s: every livery looks different (topsides, graphic, kite)" % id)
		check(bright == 0, "%s: no hull or deck colour above a linear albedo of 0.8" % id)
		var graphics := {}
		var designs := {}
		var cloths := {}
		for l in list:
			graphics[l.graphic["type"]] = true
			for r in Livery.ROLES:
				designs[l.sails[r]["design"]] = true
				cloths[l.sails[r]["cloth"]] = true
		check(graphics.size() >= 5, "%s: %d hull graphics used" % [id, graphics.size()])
		check(designs.size() >= 5, "%s: %d sail designs used" % [id, designs.size()])
		check(cloths.has("laminate") and cloths.has("nylon"), "%s: laminate and nylon cloths used" % id)


func _doc() -> Dictionary:
	var d: Dictionary = BoatClassData._read_json(BoatClassData.repo_path("data/liveries/wm7.liveries.json"))
	return d.duplicate(true)


func check_parse_errors() -> void:
	var errs := []
	Livery.parse(_doc(), "wm7", errs)
	check(errs.is_empty(), "the wm7 file parses without errors (%s)" % ", ".join(errs))
	var cases := {
		"bright topsides": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["topsides"] = "#f0f0f0",
		"duplicate sail number": func(d: Dictionary) -> void: d["liveries"][1]["sail_number"] = d["liveries"][0]["sail_number"],
		"bad schema": func(d: Dictionary) -> void: d["schema"] = "windmark.liveries/2",
		"too few liveries": func(d: Dictionary) -> void: d["liveries"].resize(5),
		"unknown graphic": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["graphic"]["type"] = "flames",
		"bad boat name": func(d: Dictionary) -> void: d["liveries"][0]["boat_name"] = "A name far too long for it",
		"bad colour": func(d: Dictionary) -> void: d["liveries"][0]["hull"]["text"] = "navy",
		"bright sail": func(d: Dictionary) -> void: d["liveries"][0]["sails"]["main"]["color"] = "#ffffff",
		"unknown cloth": func(d: Dictionary) -> void: d["liveries"][0]["sails"]["main"]["cloth"] = "kevlar",
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
	var entries := [{"human": true, "choice": "royal_blue"}]
	for i in 9:
		entries.append({"human": false})
	var a := Livery.assign(list, entries, 1234)
	var b := Livery.assign(list, entries, 1234)
	var c := Livery.assign(list, entries, 99)
	var ids := {}
	var same := true
	var diff := false
	for i in a.size():
		ids[a[i].id] = true
		same = same and a[i].id == b[i].id
		diff = diff or a[i].id != c[i].id
	check(a[0].id == "royal_blue", "the player's choice is kept")
	check(ids.size() == 10, "10 boats, 10 distinct liveries")
	check(same, "the same seed gives the same fleet")
	check(diff, "another seed gives another fleet")
	var two := Livery.assign(list, [{"human": true, "choice": "sky"}, {"human": true, "choice": "sky"}, {"human": false}], 5)
	check(two[0].id == "sky" and two[1].id != "sky" and two[2].id != two[1].id and two[2].id != "sky",
		"a second human with a taken livery gets the first free one")
	var dflt := Livery.assign(list, [{"human": true, "choice": ""}], 5)
	check(dflt[0].id == list[0].id, "no choice gives the class default (the first)")
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
	check(rep.boat_name.ends_with(" II") and rep.sail_number.to_int() > 1000, "a repeat: \"%s\" %s" % [rep.boat_name, rep.sail_number])
	check(Livery.roman(2) == "II" and Livery.roman(4) == "IV" and Livery.roman(9) == "IX", "roman numerals")


func check_shaders() -> void:
	for path in ["res://shaders/boat.gdshader", "res://shaders/sail.gdshader"]:
		var s := load(path) as Shader
		var names := []
		for u in s.get_shader_uniform_list():
			names.append(u["name"])
		var want := ["hl_on", "hl_sheer", "livery_text", "hl_name_tex"] if path.ends_with("boat.gdshader") else \
			["sl_on", "sl_box", "sl_tex", "livery_text", "cloth_chord"]
		var ok := true
		for n in want:
			ok = ok and names.has(n)
		check(ok, "%s parses with the livery uniforms (%d uniforms)" % [path.get_file(), names.size()])


func check_paint() -> void:
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
		var views := []
		for k in 4:
			var bv := BoatView.create(data.info, data.info.rudder_max, true)
			fleet.add_child(bv)
			var t0 := Time.get_ticks_usec()
			bv.set_livery(list[k])
			usec += Time.get_ticks_usec() - t0
			views.append(bv)
		print("      %s: livery applied in %.1f ms per boat" % [id, usec / 4000.0])
		var bv: BoatView = views[0]
		var lv: Livery = list[0]
		var img := bv.livery_text.image
		check(img.get_width() == 1024 and img.get_height() == 512 and img.get_format() == Image.FORMAT_R8 and img.has_mipmaps(),
			"%s: text texture 1024 x 512, one channel, mipmapped (%.0f kB)" % [id, img.get_data().size() / 1024.0])
		for row in [LiveryText.Row.NAME, LiveryText.Row.NUMBER, LiveryText.Row.INSIGNIA]:
			var ink := _ink(img, row)
			check(ink > 0.02, "%s: text row %d has ink (%.3f)" % [id, row, ink])
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
		check(top != null and colours == 2, "%s: topsides on the livery path, boot stripe and antifouling recoloured" % id)
		if top:
			var tc: Vector3 = top.get_shader_parameter("hl_top")
			var want := lv.hull["topsides"].srgb_to_linear() as Color
			check(Vector3(want.r, want.g, want.b).distance_to(tc) < 1e-4, "%s: topsides colour from the livery" % id)
			var sh: PackedFloat32Array = top.get_shader_parameter("hl_sheer")
			var bt: PackedFloat32Array = top.get_shader_parameter("hl_boot")
			var ok := sh.size() == 17
			for i in range(2, 15):
				ok = ok and bt[i] > sh[i] + 0.02 and sh[i] >= -0.001 and bt[i] <= 0.5
			check(ok, "%s: sheer and boot stripe curves (v %.3f..%.3f amidships)" % [id, sh[8], bt[8]])
			check(top.get_shader_parameter("livery_text") == bv.livery_text.texture, "%s: topsides read the boat's text texture" % id)
			check(top.shader == BoatMaterials.SHADER, "%s: topsides on the shared boat shader" % id)
		var plain_hull := plain.model.find_child("hull", true, false) as MeshInstance3D
		var untouched := true
		for s in plain_hull.mesh.get_surface_count():
			untouched = untouched and plain_hull.get_surface_override_material(s) == null
		check(untouched and plain_hull.mesh == hull.mesh, "%s: the shared hull mesh is unchanged, a boat without livery keeps the class look" % id)
		var deck := bv.model.find_child("deck", true, false) as MeshInstance3D
		var deck_n := 0
		for s in deck.mesh.get_surface_count():
			if deck.get_surface_override_material(s) != null:
				deck_n += 1
		check(deck_n == 2, "%s: deck gelcoat and non-slip recoloured" % id)
		# sails
		for sp in bv.sail_parts:
			var m := (sp.node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
			if m == null:
				check(false, "%s %s: livery sail material" % [id, sp.id])
				continue
			var lay: Dictionary = m.get_meta("livery_layout")
			var e := lv.sail_for(sp.type)
			var style := int(m.get_shader_parameter("cloth_style"))
			var cloth: String = e["cloth"]
			check(m.get_shader_parameter("sl_on") == 1 and m.get_shader_parameter("sl_layer_n") == sp.rows * sp.cols
				and (cloth == "" or style == Livery.CLOTHS.find(cloth)),
				"%s %s: livery cloth (%s, style %d) and layer split at %d" % [id, sp.id, cloth, style, sp.rows * sp.cols])
			var n_rows := int(lay["rows"])
			if sp.type == "jib":
				check(n_rows == 0, "%s %s: no number on a jib" % [id, sp.id])
				continue
			var want_rows := BoatLivery.sail_rows(sp.type, lv).size()
			check(lay["placed"] and n_rows == want_rows, "%s %s: %d rows a side placed, h %.3f m" % [id, sp.id, n_rows, lay["h"]])
			if n_rows == 0:
				continue
			var box: PackedVector4Array = lay["box"]
			var port_top := box[0].y + box[0].w
			var stbd_bottom := box[3 + n_rows - 1].y - box[3 + n_rows - 1].w
			check(stbd_bottom > port_top, "%s %s: starboard stack uppermost (%.2f m above the port stack)" % [id, sp.id, stbd_bottom - port_top])
			var ok := true
			for k in 6:
				if k % 3 >= n_rows:
					continue
				ok = ok and box[k].z > 0.0 and box[k].w > 0.0
			check(ok, "%s %s: every row has a box" % [id, sp.id])
			if sp.type == "main":
				check(lay["h"] >= 0.99 * BoatLivery.number_height(data.info.loa), "%s main: numbers at the Appendix G height %.3f m" % [id, lay["h"]])
				check(lay["arc_ok"], "%s main: numbers within the 60 %% leech arc from the head" % id)
	var tex_kb := 1024.0 * 512.0 * 4.0 / 3.0 / 1024.0
	print("      cost: one text texture per boat (%.0f kB with mipmaps), materials per boat: topsides, boot stripe, antifouling, keel, deck x2, one per sail; draw calls unchanged" % tex_kb)
	fleet.queue_free()


func _ink(img: Image, row: int) -> float:
	var s := 0.0
	var n := 0
	for y in range(row * 128, row * 128 + 128, 4):
		for x in range(0, 512, 4):
			s += img.get_pixel(x, y).r
			n += 1
	return s / n
