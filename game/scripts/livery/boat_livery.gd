class_name BoatLivery
extends RefCounted
## Paints a BoatView in a livery at load (data_format.md §8, sail_visuals.md §11.2) without touching the
## generated meshes. With the class's baked textures (BakedLivery, data_format.md §8.5), the normal case: per boat,
## materials on shaders/boat_baked.gdshader for the hull (topsides, boot stripe and antifouling on the uv1 atlas),
## the transom (its own slot and uv1, the boat's name), the deck (plan uv1, one material for its gelcoat and
## non-slip slots) and the keel, and on shaders/sail_baked.gdshader for each baked sail, all reading the shared
## images; per boat only the uniforms of its name and sail number over them. Without baked textures, the
## procedural fallback: a copy of the shared boat material for each painted slot (topsides with the livery path of
## hull_livery.gdshaderinc, boot stripe, antifouling, keel, the transom in the topsides colour, deck gelcoat and
## non-slip) and a copy of each sail's
## cloth material with the livery uniforms of sail_livery.gdshaderinc. Either way one text texture per boat
## (LiveryText) and surface override materials on the boat's own MeshInstance3Ds; draw calls are unchanged (every
## surface of every boat is its own draw anyway).
##
##   BoatLivery.apply(boat_view, livery)

const BAKED_BOAT := preload("res://shaders/boat_baked.gdshader")
const BAKED_SAIL := preload("res://shaders/sail_baked.gdshader")
## the baked sails' tiling cloth detail (sail_visuals.md §11.2): tile size (m) and strength per cloth
const DETAIL_TILE := 0.125
const DETAIL_AMOUNT := {"dacron": 1.0, "laminate": 0.8, "nylon": 1.0}
## boat.gdshader slot uniforms carried over to the baked materials
const SLOT_KEYS := ["albedo_tex", "mr_tex", "normal_tex", "use_normal_tex", "normal_scale", "roughness", "metallic",
	"specular", "uv_scale", "ao_strength", "albedo_max"]

## sail_visuals.md §11.1 per cloth style: roughness, weave share, fibre amount, back-light
const STYLE_ROUGH := [0.55, 0.38, 0.45]
const STYLE_WEAVE := [0.6, 0.15, 0.2]
const STYLE_FIBRE := [0.0, 0.35, 0.06]
const STYLE_BACKLIGHT := [0.3, 0.2, 0.5]

## class id -> {"sheer": PackedFloat32Array(17), "boot": ..., "vm": float, "len": float, "panels": {id: Vector4}}
static var _geometry := {}
## albedo texture RID -> its mean (linear, grey)
static var _tex_mean := {}


## Paints `bv` in `lv`. Returns the number of surfaces given a livery material.
static func apply(bv: BoatView, lv: Livery) -> int:
	if bv == null or lv == null or bv.model == null:
		return 0
	var text := LiveryText.build(lv)
	bv.livery = lv
	bv.livery_text = text
	bv.livery_materials.clear()
	var geo := hull_geometry(bv)
	var cid := bv.info.id if bv.info else ""
	var hs := BakedLivery.hull_set(cid, lv.look_id)
	var ss: Dictionary = BakedLivery.sail_set(cid).get("sails", {})
	var n := 0
	# every level of detail (sail_visuals.md §11.4): the same part and slot get the same material on each level
	var stack: Array[Node] = []
	for lvl in bv.levels:
		stack.append(lvl["model"])
	if stack.is_empty():
		stack.append(bv.model)
	var sail_nodes := {}
	for sp in bv.sail_parts:
		sail_nodes[sp.node] = sp
	if bv.sheets:
		sail_nodes[bv.sheets.node] = true
	var made := {}
	var deck_m: ShaderMaterial = null
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or sail_nodes.has(mi):
			continue
		var part := String(mi.name)
		# the deck's two walking slots share one material: the non-slip mask of the baked deck picks the detail
		# (one for every level of detail: the levels share the deck's slot materials)
		if part == "deck" and hs.has("deck") and deck_m == null:
			deck_m = baked_deck_material(mi, hs["deck"])
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as ShaderMaterial
			if m == null:
				continue
			var slot := m.resource_name
			var key := "%s/%s/%d" % [part, slot, m.get_instance_id()]
			if made.has(key):
				if made[key] != null:
					mi.set_surface_override_material(s, made[key])
					n += 1
				continue
			made[key] = null
			if slot.begins_with("rope_") and Livery.ROPES.has(slot.trim_prefix("rope_")):
				# the class rope set (data_format.md §8.7): shared by the class, not per boat
				var rm := rope_material(cid, m, slot.trim_prefix("rope_"), lv.ropes)
				made[key] = rm
				mi.set_surface_override_material(s, rm)
				n += 1
				continue
			var bm: ShaderMaterial = null
			if not hs.is_empty():
				if part == "hull" and slot in ["gelcoat", "boottop", "antifouling"]:
					bm = baked_hull_material(m, hs, lv, text, geo)
				elif part == "keel" and slot == "antifouling" and hs.has("keel"):
					bm = baked_view_material(m, hs["keel"], hs["keel_rect"], 1)
				elif part == "deck" and slot in ["gelcoat", "nonslip"] and deck_m != null:
					bm = deck_m
				elif part == "deck" and slot == "transom" and hs.has("transom"):
					bm = baked_transom_material(m, hs["transom"], lv, text, geo)
			if bm != null:
				if not bv.livery_materials.has(bm):
					bv.livery_materials.append(bm)
				made[key] = bm
				mi.set_surface_override_material(s, bm)
				n += 1
				continue
			var c: Variant = null
			if part == "hull" and slot == "gelcoat":
				var tm := topsides_material(m, lv, text, geo)
				bv.livery_materials.append(tm)
				made[key] = tm
				mi.set_surface_override_material(s, tm)
				n += 1
				continue
			if part == "hull" and slot == "boottop":
				c = lv.hull["boot_stripe"]
			elif part == "hull" and slot == "antifouling":
				c = lv.hull["antifouling"]
			elif (part == "keel" or part == "rudder") and slot == "antifouling":
				c = lv.hull["keel"]
			elif part == "deck" and slot == "transom":
				c = lv.hull["topsides"]
			elif part == "deck" and slot == "gelcoat":
				c = lv.deck["gelcoat"]
			elif part == "deck" and slot == "nonslip":
				c = lv.deck["nonslip"]
			if c != null:
				var cm := colour_material(m, c)
				bv.livery_materials.append(cm)
				made[key] = cm
				mi.set_surface_override_material(s, cm)
				n += 1
	if bv.sheets:
		var base := bv.sheets.base_material
		if base != null:
			bv.sheets.set_material(BoatSheets.Surface.HEADSAIL, rope_material(cid, base, "sheet", lv.ropes))
			bv.sheets.set_material(BoatSheets.Surface.FLYING, rope_material(cid, base, "kite_sheet", lv.ropes))
	for sp in bv.sail_parts:
		if sp.mesh == null or sp.mesh.get_surface_count() < 1:
			continue
		var base := sp.mesh.surface_get_material(0) as ShaderMaterial
		if base == null:
			continue
		var bs: Dictionary = ss.get(sp.id, {})
		var m := baked_sail_material(sp, bs, lv, text) if not bs.is_empty() \
				else sail_material(base, sp, lv, text, bv.info.loa if bv.info else 8.0)
		bv.livery_materials.append(m)
		(sp.node as MeshInstance3D).set_surface_override_material(0, m)
		n += 1
	return n


## A baked-livery material for a boat slot: the slot's tiling detail and factors on shaders/boat_baked.gdshader.
static func _baked_slot(src: ShaderMaterial) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BAKED_BOAT
	m.resource_name = src.resource_name
	for k in SLOT_KEYS:
		var v: Variant = src.get_shader_parameter(k)
		if v != null:
			m.set_shader_parameter(k, v)
	m.set_shader_parameter("bk_detail_mean", texture_mean(src.get_shader_parameter("albedo_tex")))
	m.set_shader_parameter("bk_rough_mean", channel_mean(src.get_shader_parameter("mr_tex"), 1))
	return m


## The hull's topsides, boot stripe or antifouling from the baked hull set, with the boat's name and number.
static func baked_hull_material(src: ShaderMaterial, hs: Dictionary, lv: Livery, text: LiveryText,
		geo: Dictionary) -> ShaderMaterial:
	var m := _baked_slot(src)
	m.set_shader_parameter("bk_albedo", hs["albedo"])
	m.set_shader_parameter("bk_normal", hs["normal"])
	m.set_shader_parameter("bk_orm", hs["orm"])
	m.set_shader_parameter("bk_proj", 0)
	m.set_shader_parameter("bk_maps", true)
	var boxes := PackedVector4Array()
	var rects := PackedVector4Array()
	var length: float = geo["len"]
	var pd: Dictionary = geo["panels_d"]
	for side in ["stbd", "port"]:
		for k in [["name", LiveryText.Row.NAME, false], ["number", LiveryText.Row.NUMBER, true]]:
			var pan: Vector4 = geo["panels_uv"].get(side, {}).get(k[0], Vector4.ZERO)
			var d: Vector2 = pd.get(k[0], Vector2(0.1, 0.4))
			var pw := (pan.z - pan.x) * length
			var ph := d.y - d.x
			var asp := text.aspect(k[1], k[2])
			# the panel is laid out at its middle station: keep a margin below the sheer's graphics at its ends
			var bh := minf(ph * (0.84 if k[2] else 0.92), 0.9 * pw / asp)
			var du := 0.5 * bh * asp / maxf(length, 1e-3)
			var dv := 0.5 * bh / maxf(ph, 1e-3) * (pan.w - pan.y)
			var cu := 0.5 * (pan.x + pan.z)
			var cv := pan.y + 0.55 * (pan.w - pan.y)
			boxes.append(Vector4(cu - du, cv - dv, cu + du, cv + dv))
			rects.append(text.rect(k[1], k[2]) if not text.rows[k[1]]["empty"] else Vector4.ZERO)
	m.set_shader_parameter("ov_on", 1)
	m.set_shader_parameter("ov_color", _lin(lv.hull["text"]))
	m.set_shader_parameter("ov_box", boxes)
	m.set_shader_parameter("ov_tex", rects)
	m.set_shader_parameter("livery_text", text.texture)
	return m


## The deck from the livery's baked deck set on its plan uv1: one material for the deck's gelcoat and non-slip
## surfaces, the gelcoat slot's detail and the non-slip slot's picked per pixel by the non-slip mask (ORM blue).
static func baked_deck_material(mi: MeshInstance3D, ds: Dictionary) -> ShaderMaterial:
	var gel: ShaderMaterial = null
	var nsm: ShaderMaterial = null
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as ShaderMaterial
		if m == null:
			continue
		if m.resource_name == "gelcoat":
			gel = m
		elif m.resource_name == "nonslip":
			nsm = m
	if gel == null:
		gel = nsm
	if gel == null:
		return null
	var m := _baked_slot(gel)
	m.resource_name = "deck"
	m.set_shader_parameter("bk_albedo", ds["albedo"])
	m.set_shader_parameter("bk_normal", ds["normal"])
	m.set_shader_parameter("bk_orm", ds["orm"])
	m.set_shader_parameter("bk_proj", 0)
	m.set_shader_parameter("bk_maps", true)
	m.set_shader_parameter("bk_mask", nsm != null)
	if nsm != null:
		m.set_shader_parameter("ns_albedo_tex", nsm.get_shader_parameter("albedo_tex"))
		m.set_shader_parameter("ns_mr_tex", nsm.get_shader_parameter("mr_tex"))
		m.set_shader_parameter("ns_normal_tex", nsm.get_shader_parameter("normal_tex"))
		m.set_shader_parameter("ns_use_normal", nsm.get_shader_parameter("use_normal_tex") == true)
		var nsc: Variant = nsm.get_shader_parameter("normal_scale")
		m.set_shader_parameter("ns_normal_scale", nsc if nsc != null else 1.0)
		var uvs: Variant = nsm.get_shader_parameter("uv_scale")
		m.set_shader_parameter("ns_uv_scale", uvs if uvs != null else Vector2.ONE)
		m.set_shader_parameter("ns_detail_mean", texture_mean(nsm.get_shader_parameter("albedo_tex")))
		m.set_shader_parameter("ns_rough_mean", channel_mean(nsm.get_shader_parameter("mr_tex"), 1))
	return m


## The transom from the livery's baked transom set on its uv1, with the boat's name in the transom's name panel
## (the generator's `livery_transom`): one box, set in all four overlay slots so the hull's lookup finds it.
static func baked_transom_material(src: ShaderMaterial, ts: Dictionary, lv: Livery, text: LiveryText,
		geo: Dictionary) -> ShaderMaterial:
	var m := _baked_slot(src)
	m.set_shader_parameter("bk_albedo", ts["albedo"])
	m.set_shader_parameter("bk_normal", ts["normal"])
	m.set_shader_parameter("bk_orm", ts["orm"])
	m.set_shader_parameter("bk_proj", 0)
	m.set_shader_parameter("bk_maps", true)
	var box := transom_name_box(geo, text)
	var boxes := PackedVector4Array([box, box, box, box])
	var r := text.rect(LiveryText.Row.NAME, false) if not text.rows[LiveryText.Row.NAME]["empty"] else Vector4.ZERO
	m.set_shader_parameter("ov_on", 1 if box != Vector4.ZERO else 0)
	m.set_shader_parameter("ov_color", _lin(lv.hull["text"]))
	m.set_shader_parameter("ov_box", boxes)
	m.set_shader_parameter("ov_tex", PackedVector4Array([r, r, r, r]))
	m.set_shader_parameter("livery_text", text.texture)
	return m


## The boat name's box on the transom's uv1 (u0, v0, u1, v1): centred in the name panel, 0.7 of its height, shrunk
## to 0.9 of its width when wider. Zero without a panel.
static func transom_name_box(geo: Dictionary, text: LiveryText) -> Vector4:
	var pan: Dictionary = geo.get("transom", {})
	var uv: Array = pan.get("uv1", [])
	var size: Array = pan.get("size", [])
	if uv.size() != 4 or size.size() != 2 or float(size[0]) <= 0.0 or float(size[1]) <= 0.0:
		return Vector4.ZERO
	var w := float(size[0])
	var h := float(size[1])
	var asp := text.aspect(LiveryText.Row.NAME, false)
	var bh := minf(0.7 * h, 0.9 * w / maxf(asp, 1e-3))
	var du := 0.5 * bh * asp / w * (float(uv[2]) - float(uv[0]))
	var dv := 0.5 * bh / h * (float(uv[3]) - float(uv[1]))
	var cu := 0.5 * (float(uv[0]) + float(uv[2]))
	var cv := 0.5 * (float(uv[1]) + float(uv[3]))
	return Vector4(cu - du, cv - dv, cu + du, cv + dv)


## The keel from its baked albedo in side view (proj 1).
static func baked_view_material(src: ShaderMaterial, tex: Texture2D, rect: Vector4, proj: int) -> ShaderMaterial:
	var m := _baked_slot(src)
	m.set_shader_parameter("bk_albedo", tex)
	m.set_shader_parameter("bk_proj", proj)
	m.set_shader_parameter("bk_rect", rect)
	m.set_shader_parameter("bk_maps", false)
	return m


## A sail from the class's baked sail set, with the boat's nation letters and sail number in the layout's slots.
static func baked_sail_material(sp: BoatView.SailPart, bs: Dictionary, lv: Livery, text: LiveryText) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BAKED_SAIL
	var info: Dictionary = bs["info"]
	m.set_shader_parameter("sk_albedo_port", bs["port"])
	m.set_shader_parameter("sk_albedo_stbd", bs["stbd"])
	m.set_shader_parameter("sk_normal", bs["normal"])
	m.set_shader_parameter("sk_orm", bs["orm"])
	var sh: Array = info.get("shear", [0.0, 1.0])
	var r: Array = info.get("rect", [0.0, 10.0, 4.0, 10.0])
	m.set_shader_parameter("sk_shear", Vector2(sh[0], sh[1]))
	m.set_shader_parameter("sk_rect", Vector4(r[0], r[1], r[2], r[3]))
	var cloth: String = info.get("cloth", "dacron")
	m.set_shader_parameter("sk_detail", BakedLivery.detail(cloth))
	m.set_shader_parameter("sk_detail_tile", DETAIL_TILE)
	m.set_shader_parameter("sk_detail_amount", DETAIL_AMOUNT.get(cloth, 1.0) if BakedLivery.detail(cloth) else 0.0)
	m.set_shader_parameter("sl_layer_n", sp.rows * sp.cols)
	m.set_shader_parameter("livery_text", text.texture)
	m.set_shader_parameter("sn_color", _lin(lv.sail_for(sp.type)["number"]))
	var lay := baked_sail_rows(info, lv, text)
	m.set_shader_parameter("sn_rows", lay["rows"])
	m.set_shader_parameter("sn_axis", lay["axis"])
	m.set_shader_parameter("sn_up", lay["up"])
	m.set_shader_parameter("sn_tack", lay["tack"])
	m.set_shader_parameter("sn_box", lay["box"])
	m.set_shader_parameter("sn_tex", lay["tex"])
	m.set_meta("livery_layout", lay)
	return m


## The boat's nation and number rows in the slots of a baked sail's layout (sail_visuals.md §11.2): per side the
## present rows top down, each centred in its slot at the slot's height, shrunk to the slot's width when wider.
## Boxes 0, 1 port, 2, 3 starboard. Also "h", "slots" (the layout's rows) and "baked".
static func baked_sail_rows(info: Dictionary, lv: Livery, text: LiveryText) -> Dictionary:
	var tx: Dictionary = info.get("text", {})
	var ax: Array = tx.get("axis", [1.0, 0.0])
	var up: Array = tx.get("up", [0.0, 1.0])
	var tk: Array = tx.get("tack", [0.0, 0.0])
	var box := PackedVector4Array()
	var tex := PackedVector4Array()
	box.resize(4)
	tex.resize(4)
	var n := 0
	for row in tx.get("rows", []):
		var kind: String = row.get("kind", "")
		var tr := LiveryText.Row.NUMBER if kind == "number" else LiveryText.Row.NATION
		if kind == "insignia" or (kind == "nation" and lv.nation == "") or n >= 2:
			continue
		var asp := text.aspect(tr, true)
		for side in 2:
			var b: Array = row["port" if side == 0 else "stbd"]
			var hh: float = b[3]
			var hw := hh * asp
			if hw > float(b[2]):
				hh *= float(b[2]) / hw
				hw = b[2]
			box[n + 2 * side] = Vector4(b[0], b[1], hw, hh)
			tex[n + 2 * side] = text.rect(tr, true)
		n += 1
	return {"rows": n, "axis": Vector2(ax[0], ax[1]), "up": Vector2(up[0], up[1]), "tack": Vector2(tk[0], tk[1]),
		"box": box, "tex": tex, "h": tx.get("h", 0.0), "slots": tx.get("rows", []), "baked": true}


## class/function/colours -> the class's rope material (data_format.md §8.7), shared by its boats
static var _rope_mats := {}


## The rope material of a function for a class: the class's baked braid (BakedLivery.rope_set: albedo, normal and
## ORM on the slot's tile) on the boat shader, or without it the slot material `base` tinted to the function's mean
## braid colour (`ropes`: Livery.ropes, empty for the defaults).
static func rope_material(class_id: String, base: ShaderMaterial, fn: String, ropes: Dictionary) -> ShaderMaterial:
	var rs := BakedLivery.rope_set(class_id)
	var r: Dictionary = ropes.get(fn, {}) if ropes.has(fn) else Livery.rope_set_of({}, [])[fn]
	var baked: bool = rs.get("albedo", {}).has(fn)
	var key := "%s/%s/%s/%s/%d" % [class_id, fn, "baked" if baked else Livery.rope_mean(r).to_html(false),
		base.shader.resource_path, base.get_instance_id()]
	if _rope_mats.has(key):
		return _rope_mats[key]
	var m: ShaderMaterial
	if baked:
		m = base.duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo_tex", rs["albedo"][fn])
		m.set_shader_parameter("albedo_color", Color.WHITE)
		if rs.get("orm") != null:
			m.set_shader_parameter("mr_tex", rs["orm"])
			m.set_shader_parameter("roughness", 1.0)
			m.set_shader_parameter("metallic", 0.0)
		if rs.get("normal") != null:
			m.set_shader_parameter("normal_tex", rs["normal"])
			m.set_shader_parameter("use_normal_tex", true)
			m.set_shader_parameter("normal_scale", 1.0)
	else:
		m = colour_material(base, Livery.rope_mean(r))
	m.resource_name = "rope_" + fn
	_rope_mats[key] = m
	return m


## A copy of a boat slot material in another colour (sRGB), keeping its texture's detail.
static func colour_material(src: ShaderMaterial, c: Color) -> ShaderMaterial:
	var m := src.duplicate() as ShaderMaterial
	var mean := texture_mean(src.get_shader_parameter("albedo_tex"))
	var lin := c.srgb_to_linear()
	m.set_shader_parameter("albedo_color", Color(lin.r / mean, lin.g / mean, lin.b / mean).linear_to_srgb())
	return m


## The topsides material: the gelcoat slot with the hull livery path on.
static func topsides_material(src: ShaderMaterial, lv: Livery, text: LiveryText, geo: Dictionary) -> ShaderMaterial:
	var m := src.duplicate() as ShaderMaterial
	m.set_shader_parameter("hl_on", 1)
	m.set_shader_parameter("hl_tex_mean", texture_mean(src.get_shader_parameter("albedo_tex")))
	m.set_shader_parameter("hl_sheer", geo["sheer"])
	m.set_shader_parameter("hl_boot", geo["boot"])
	m.set_shader_parameter("hl_vm", geo["vm"])
	m.set_shader_parameter("hl_len", geo["len"])
	m.set_shader_parameter("hl_top", _lin(lv.hull["topsides"]))
	m.set_shader_parameter("hl_text_color", _lin(lv.hull["text"]))
	m.set_shader_parameter("livery_text", text.texture)
	var g: Dictionary = lv.graphic
	var cols: Array = g.get("colors", [])
	var c0: Color = cols[0] if cols.size() > 0 else lv.hull["text"]
	var c1: Color = cols[1] if cols.size() > 1 else c0
	m.set_shader_parameter("hl_c0", _lin(c0))
	m.set_shader_parameter("hl_c1", _lin(c1))
	var p := Vector4.ZERO
	var q := Vector4.ZERO
	var t: String = g.get("type", "none")
	match t:
		"stripes":
			var dep: Array = g.get("depth", [0.08, 0.17])
			var wid: Array = g.get("width", [0.05, 0.02])
			var two := cols.size() > 1 and dep.size() > 1 and wid.size() > 1
			p = Vector4(float(dep[0]), float(wid[0]), float(dep[1]) if two else 0.0, float(wid[1]) if two else 0.0)
			q = Vector4(float(g.get("from", 0.04)), float(g.get("to", 0.96)), 0.0, 0.0)
		"two_tone":
			p = Vector4(float(g.get("split", 0.45)), float(g.get("rise", -0.15)), float(g.get("pinstripe", 0.025)), 0.0)
			if cols.size() < 2:
				p.z = 0.0
		"swoosh":
			var a: Array = g.get("aft", [0.04, 0.8])
			var f: Array = g.get("fwd", [0.96, 0.1])
			var w: Array = g.get("width", [0.24, 0.03])
			p = Vector4(float(a[0]), float(a[1]), float(f[0]), float(f[1]))
			q = Vector4(float(w[0]), float(w[1]), 0.0, 0.0)
		"gradient":
			p = Vector4(float(g.get("from", 0.25)), float(g.get("to", 0.85)), float(g.get("slant", 0.12)), 0.0)
		"bow":
			p = Vector4(float(g.get("at", 0.78)), float(g.get("slant", 0.10)), float(g.get("line", 0.03)), 0.0)
			if cols.size() < 2:
				p.z = 0.0
	m.set_shader_parameter("hl_graphic", Livery.GRAPHICS.find(t))
	m.set_shader_parameter("hl_p", p)
	m.set_shader_parameter("hl_q", q)
	# name aft and number forward in the generator's livery panels, centred, fitted to the panel
	var panels: Dictionary = geo["panels"]
	for k in [["name", LiveryText.Row.NAME, false], ["num", LiveryText.Row.NUMBER, true]]:
		var pan: Vector4 = panels.get("name" if k[0] == "name" else "number", Vector4(0.1, 0.1, 0.3, 0.3))
		var pw := (pan.z - pan.x) * float(geo["len"])
		var ph := pan.w - pan.y
		var asp := text.aspect(k[1], k[2])
		var bh := minf(ph * (0.92 if k[2] else 1.0), 0.9 * pw / asp)
		var bw := bh * asp
		var box := Vector4(0.5 - 0.5 * bw / pw, 0.5 - 0.5 * bh / ph, 0.5 + 0.5 * bw / pw, 0.5 + 0.5 * bh / ph)
		m.set_shader_parameter("hl_%s_panel" % k[0], pan)
		m.set_shader_parameter("hl_%s_box" % k[0], box)
		m.set_shader_parameter("hl_%s_tex" % k[0], text.rect(k[1], k[2]) if not text.rows[k[1]]["empty"] else Vector4.ZERO)
	return m


## The sail's cloth material for this boat: cloth style and colours, design and the numbers (§11.2).
static func sail_material(base: ShaderMaterial, sp: BoatView.SailPart, lv: Livery, text: LiveryText,
		loa: float) -> ShaderMaterial:
	var m := base.duplicate() as ShaderMaterial
	var e := lv.sail_for(sp.type)
	var cloth: String = e.get("cloth", "")
	if cloth != "":
		var st := Livery.CLOTHS.find(cloth)
		m.set_shader_parameter("cloth_style", st)
		m.set_shader_parameter("roughness", STYLE_ROUGH[st])
		m.set_shader_parameter("weave", STYLE_WEAVE[st])
		m.set_shader_parameter("fibre_amount", STYLE_FIBRE[st])
		m.set_shader_parameter("backlight", STYLE_BACKLIGHT[st])
		m.set_shader_parameter("cloth_panel", [0.9, 1.1, 0.9 + 0.03 * clampf(loa - 7.0, 0.0, 10.0)][st])
	m.set_shader_parameter("albedo_color", e["color"])
	m.set_shader_parameter("fibre_color", e["fibre"])
	m.set_shader_parameter("livery_text", text.texture)
	m.set_shader_parameter("sl_on", 1)
	m.set_shader_parameter("sl_layer_n", sp.rows * sp.cols)
	var cols: Array = e.get("colors", [])
	var c0: Color = cols[0] if cols.size() > 0 else e["color"]
	var c1: Color = cols[1] if cols.size() > 1 else c0
	m.set_shader_parameter("sl_c0", _lin(c0))
	m.set_shader_parameter("sl_c1", _lin(c1))
	var design: String = e.get("design", "plain")
	var dp := Vector4.ZERO
	match design:
		"bands":
			var stops: Array = e.get("stops", [0.35, 0.7])
			dp = Vector4(float(stops[0]), float(stops[1]) if stops.size() > 1 else 2.0, 1.0 if cols.size() > 1 else 0.0, 0.0)
		"head":
			dp = Vector4(float(e.get("radius", 0.3)), float(e.get("corner", 0.0)) if cols.size() > 1 else 0.0, 0.0, 0.0)
		"panels":
			dp = Vector4(1.0 + mini(cols.size(), 2), 0.0, 0.0, 0.0)
		"diagonal":
			dp = Vector4(float(e.get("luff", 0.25)), float(e.get("leech", 0.75)), float(e.get("band", 0.25)),
					1.0 if cols.size() > 1 else 0.0)
		"gores":
			dp = Vector4(float(e.get("count", 9)), 1.0 + mini(cols.size(), 2), 0.0, 0.0)
	m.set_shader_parameter("sl_design", Livery.DESIGNS.find(design))
	m.set_shader_parameter("sl_dp", dp)
	m.set_shader_parameter("sl_text_color", _lin(e["number"]))
	var lay := sail_layout(m, sp, lv, text, loa)
	m.set_shader_parameter("sl_axis", lay["axis"])
	m.set_shader_parameter("sl_up", lay["up"])
	m.set_shader_parameter("sl_height", lay["height"])
	m.set_shader_parameter("sl_rows", lay["rows"])
	m.set_shader_parameter("sl_box", lay["box"])
	m.set_shader_parameter("sl_tex", lay["tex"])
	m.set_meta("livery_layout", lay)
	return m


## Character height by LOA (racing rules Appendix G1.2), m.
static func number_height(loa: float) -> float:
	if loa < 3.5:
		return 0.23
	if loa <= 8.5:
		return 0.30
	if loa <= 11.0:
		return 0.375
	return 0.45


## The text rows of a sail by type (§11.2): [LiveryText.Row, height factor, cap] top to bottom.
static func sail_rows(sail_type: String, lv: Livery) -> Array:
	var out := []
	if sail_type == "jib":
		return out
	if sail_type == "main" and lv.insignia != "":
		out.append([LiveryText.Row.INSIGNIA, 1.5, false])
	if lv.nation != "":
		out.append([LiveryText.Row.NATION, 1.0, true])
	out.append([LiveryText.Row.NUMBER, 1.0, true])
	return out


## Places the number stacks of a sail (sail_visuals.md §11.2) in its flat plan. Returns the frame (axis, up,
## height), the rows per side, and per row (port 0..2, starboard 3..5) the box and texture rectangle, plus the
## character height used and whether every row is within the rules' arc ("arc_ok").
static func sail_layout(m: ShaderMaterial, sp: BoatView.SailPart, lv: Livery, text: LiveryText, loa: float) -> Dictionary:
	var box := PackedVector4Array()
	var tex := PackedVector4Array()
	box.resize(6)
	tex.resize(6)
	var out := {"axis": Vector2(1, 0), "up": Vector2(0, 1), "height": 1.0, "rows": 0, "box": box, "tex": tex,
		"h": 0.0, "arc_ok": true, "placed": true}
	var uv: PackedVector2Array = sp.uv0
	var rows := sp.rows
	var cols := sp.cols
	if uv.size() < rows * cols or rows < 2:
		return out
	var shear: Vector2 = m.get_shader_parameter("cloth_shear")
	var plan := func(a: Vector2) -> Vector2: return Vector2(a.x * shear.y, a.y + a.x * shear.x)
	var tack: Vector2 = plan.call(uv[0])
	var clew: Vector2 = plan.call(uv[cols - 1])
	var head: Vector2 = plan.call(uv[(rows - 1) * cols])
	var axis := (clew - tack).normalized()
	var up := Vector2(-axis.y, axis.x)
	if up.dot(head - tack) < 0.0:
		up = -up
	var fr := func(p: Vector2) -> Vector2: return Vector2((p - tack).dot(axis), (p - tack).dot(up))
	var poly := PackedVector2Array()
	for i in rows:
		poly.append(fr.call(plan.call(uv[i * cols])))
	for i in range(rows - 1, -1, -1):
		poly.append(fr.call(plan.call(uv[i * cols + cols - 1])))
	var hf: Vector2 = fr.call(head)
	var top := -INF
	for q in poly:
		top = maxf(top, q.y)
	out["axis"] = axis
	out["up"] = up
	out["height"] = top
	var list := sail_rows(sp.type, lv)
	if list.is_empty():
		return out
	# where the stacks start and the arc they must stay outside of (headsails, spinnakers) or inside (main)
	var luff_len := head.distance_to(tack)
	var r_min := 0.0
	var r_max := INF
	if sp.type == "main":
		var leech := 0.0
		for i in rows - 1:
			leech += plan.call(uv[i * cols + cols - 1]).distance_to(plan.call(uv[(i + 1) * cols + cols - 1]))
		r_max = 0.6 * leech
	elif sp.type.begins_with("spinnaker"):
		r_min = 0.4 * head.distance_to(0.5 * (tack + clew))
	else:
		r_min = 0.5 * luff_len
	var h := number_height(loa)
	for attempt in 6:
		var res := _stack(poly, hf, list, text, h, r_min)
		if not res.is_empty():
			out["rows"] = list.size()
			out["h"] = h
			for k in list.size():
				for side in 2:
					var b: Vector4 = res[side * list.size() + k]
					box[k + 3 * (1 - side)] = b
					tex[k + 3 * (1 - side)] = text.rect(list[k][0], list[k][2])
					var corners := [Vector2(b.x - b.z, b.y - b.w), Vector2(b.x + b.z, b.y - b.w),
						Vector2(b.x - b.z, b.y + b.w), Vector2(b.x + b.z, b.y + b.w)]
					for c in corners:
						if c.distance_to(hf) > r_max:
							out["arc_ok"] = false
			out["box"] = box
			out["tex"] = tex
			return out
		h *= 0.9
	out["placed"] = false
	return out


## The two stacks (starboard first, then port), top down: boxes (centre along, centre up, half width, half height),
## or [] when they do not fit above the foot.
static func _stack(poly: PackedVector2Array, head: Vector2, list: Array, text: LiveryText, h: float, r_min: float) -> Array:
	var res := []
	var gap := 0.2 * h
	var y := head.y - 0.3 * h
	if r_min > 0.0:
		y = head.y - r_min
	for side in 2:
		for k in list.size():
			var bh: float = h * float(list[k][1])
			var bw: float = bh * text.aspect(list[k][0], list[k][2])
			var cy := y - 0.5 * bh
			var placed := false
			while cy - 0.5 * bh > 0.4 * h:
				var cx := _fit(poly, cy, 0.5 * bw, 0.5 * bh, h)
				if not is_nan(cx) and (r_min <= 0.0 or _min_dist(Vector2(cx, cy), 0.5 * bw, 0.5 * bh, head) >= r_min):
					res.append(Vector4(cx, cy, 0.5 * bw, 0.5 * bh))
					y = cy - 0.5 * bh - gap
					placed = true
					break
				cy -= 0.02
			if not placed:
				return []
	return res


static func _min_dist(c: Vector2, hw: float, hh: float, p: Vector2) -> float:
	var d := INF
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		d = minf(d, (c + Vector2(hw, hh) * s).distance_to(p))
	return d


## The centre along the row of a box at height cy that fits inside the outline with the margins (luff 0.6 h,
## leech 0.4 h, foot 0.4 h), NAN when it does not.
static func _fit(poly: PackedVector2Array, cy: float, hw: float, hh: float, h: float) -> float:
	var xa := -INF
	var xb := INF
	for y in [cy - hh - 0.4 * h, cy - hh, cy, cy + hh]:
		var s := _slice(poly, y)
		if s.x > s.y:
			return NAN
		xa = maxf(xa, s.x + 0.6 * h)
		xb = minf(xb, s.y - 0.4 * h)
	if xb - xa < 2.0 * hw:
		return NAN
	return 0.5 * (xa + xb)


## The outline's extent along the row at height y: (min, max), min > max when the line misses it.
static func _slice(poly: PackedVector2Array, y: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if (a.y - y) * (b.y - y) > 0.0 or a.y == b.y:
			continue
		var x := a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return Vector2(lo, hi)


## The class's topsides geometry for the hull livery, from the imported hull: per 1/16 of the length the
## starboard band's v at the sheer and at the top of the boot stripe, metres of girth per unit of v and the hull
## length (from the generator's livery panels), and the panels as (x0, d0, x1, d1).
static func hull_geometry(bv: BoatView) -> Dictionary:
	var key := bv.info.id if bv.info else "?"
	if _geometry.has(key):
		return _geometry[key]
	var sheer := PackedFloat32Array()
	var boot := PackedFloat32Array()
	sheer.resize(17)
	boot.resize(17)
	sheer.fill(INF)
	boot.fill(-INF)
	var hull := bv.model.find_child("hull", true, false) as MeshInstance3D
	if hull and hull.mesh:
		for s in hull.mesh.get_surface_count():
			var m := hull.mesh.surface_get_material(s)
			if m == null or m.resource_name != "gelcoat":
				continue
			var arr := hull.mesh.surface_get_arrays(s)
			var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in uv2.size():
				var t := uv2[k]
				if k < nrm.size() and absf(nrm[k].z) > 0.7:
					continue  # the transom and the stem face, not the topsides
				# glTF +X is port: the side, not v, decides (the port sheer meets v = 0.5 amidships); on the centreline
				# (stem, transom) v does
				var port := pos[k].x > 1e-4 or (absf(pos[k].x) <= 1e-4 and t.y >= 0.5)
				var x := 1.0 - t.x if port else t.x
				var v := t.y - 0.5 if port else t.y
				var i := clampi(roundi(x * 16.0), 0, 16)
				if absf(x * 16.0 - i) > 0.2:
					continue  # only the stations close to the sample point (a curved sheer would bias a wide bin)
				sheer[i] = minf(sheer[i], v)
				boot[i] = maxf(boot[i], v)
	_fill_gaps(sheer, 0.0)
	_fill_gaps(boot, 0.25)
	# the end stations carry the transom and stem faces: extrapolate them from their neighbours
	for c in [sheer, boot]:
		c[0] = clampf(2.0 * c[1] - c[2], 0.0, 0.5)
		c[16] = clampf(2.0 * c[15] - c[14], 0.0, 0.5)
	var extras: Dictionary = bv.model.get_meta("extras", {}) if bv.model.has_meta("extras") else {}
	var panels := {}
	var panels_uv := {"stbd": {}, "port": {}}
	var panels_d := {}
	var vm := 3.0
	var length := bv.info.loa if bv.info else 7.0
	for pn in extras.get("livery_panels", []):
		var u: Array = pn["uv1"]
		var x: Array = pn["x"]
		var d: Array = pn["below_sheer"]
		panels_uv[pn.get("side", "stbd")][pn["id"]] = Vector4(u[0], u[1], u[2], u[3])
		panels_d[pn["id"]] = Vector2(d[0], d[1])
		if pn.get("side", "") != "stbd":
			continue
		panels[pn["id"]] = Vector4(u[0], d[0], u[2], d[1])
		if pn["id"] == "number":
			vm = (float(d[1]) - float(d[0])) / maxf(float(u[3]) - float(u[1]), 1e-4)
			length = (float(x[1]) - float(x[0])) / maxf(float(u[2]) - float(u[0]), 1e-4)
	var g := {"sheer": sheer, "boot": boot, "vm": vm, "len": length, "panels": panels, "panels_uv": panels_uv,
		"panels_d": panels_d, "transom": extras.get("livery_transom", {}).get("panel", {})}
	_geometry[key] = g
	return g


static func _fill_gaps(a: PackedFloat32Array, def: float) -> void:
	var known := []
	for i in a.size():
		if is_finite(a[i]):
			known.append(i)
	if known.is_empty():
		a.fill(def)
		return
	for i in a.size():
		if is_finite(a[i]):
			continue
		var lo := -1
		var hi := -1
		for k in known:
			if k < i:
				lo = k
			elif hi < 0:
				hi = k
		if lo < 0:
			a[i] = a[hi]
		elif hi < 0:
			a[i] = a[lo]
		else:
			a[i] = lerpf(a[lo], a[hi], float(i - lo) / float(hi - lo))


## The mean (linear grey) of an albedo texture, 1 without one.
static func texture_mean(t: Variant) -> float:
	if not (t is Texture2D):
		return 1.0
	var rid: RID = (t as Texture2D).get_rid()
	if _tex_mean.has(rid):
		return _tex_mean[rid]
	var img := (t as Texture2D).get_image()
	var mean := 1.0
	if img != null and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(16, 16, Image.INTERPOLATE_TRILINEAR)
		var s := 0.0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(x, y).srgb_to_linear()
				s += (c.r + c.g + c.b) / 3.0
		mean = clampf(s / 256.0, 0.2, 1.0)
	_tex_mean[rid] = mean
	return mean


## The mean of one channel (0 R, 1 G, 2 B) of a data texture, as stored (no colour conversion); 1 without one.
static func channel_mean(t: Variant, ch: int) -> float:
	if not (t is Texture2D):
		return 1.0
	var key := "%s/%d" % [(t as Texture2D).get_rid(), ch]
	if _tex_mean.has(key):
		return _tex_mean[key]
	var img := (t as Texture2D).get_image()
	var mean := 1.0
	if img != null and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(16, 16, Image.INTERPOLATE_TRILINEAR)
		var s := 0.0
		for y in 16:
			for x in 16:
				s += img.get_pixel(x, y)[ch]
		mean = clampf(s / 256.0, 0.05, 1.0)
	_tex_mean[key] = mean
	return mean


static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)
