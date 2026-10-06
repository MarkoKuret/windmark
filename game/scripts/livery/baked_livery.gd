class_name BakedLivery
extends RefCounted
## The baked livery textures of a class (data_format.md §8.5), as staged for import by tools/liverybake into
## res://generated/liveries/<class>/ (game/README.md "Liveries"): the boat atlas of a livery (hull, deck with the
## painted hardware, transom and keel in one albedo, normal and ORM map; atlas.json, layout.json), the class sail set
## (per sail: port and starboard albedo, normal and ORM maps; layout.json) and the class rope set (rig/: a braid tile
## per rope function, §8.7). Loaded once per class and shared by every boat; a missing set gives an empty Dictionary
## and the procedural fallback.

const ROOT := "res://generated/liveries"
## tests: false makes every set look missing (the procedural path)
static var enabled := true
static var _hulls := {}
static var _sails := {}
static var _detail := {}
static var _ropes := {}


## {"atlas": {"albedo", "normal", "orm": Texture2D}, "rects": {region: Vector4 [u0, v0, w, h] in atlas uv},
## "keel_rect": Vector4 (the keel image in the model frame: forward min, top, length, height)} of the livery
## `look_id` of the class: the staged boat atlas (data_format.md §8.5 "Staged boat atlas"), or {} when it is not
## there.
static func hull_set(class_id: String, look_id: String) -> Dictionary:
	if not enabled:
		return {}
	var key := class_id + "/" + look_id
	if _hulls.has(key):
		return _hulls[key]
	var dir := "%s/%s/%s/" % [ROOT, class_id, look_id]
	var out := {}
	var at := {"albedo": _tex(dir + "atlas_albedo.png"), "normal": _tex(dir + "atlas_normal.png"),
		"orm": _tex(dir + "atlas_orm.png")}
	if at["albedo"] != null and at["normal"] != null and at["orm"] != null:
		var aj := _json(dir + "atlas.json")
		var regions: Dictionary = aj.get("regions", aj)
		var rects := {}
		for k in ["hull", "deck", "transom", "keel"]:
			var r: Array = regions.get(k, [])
			if r.size() == 4:
				rects[k] = Vector4(r[0], r[1], r[2], r[3])
		var lay := _json(dir + "layout.json")
		var kr: Array = lay.get("keel", {}).get("rect", [])
		out = {"atlas": at, "rects": rects,
			"keel_rect": Vector4(kr[0], kr[1], kr[2], kr[3]) if kr.size() == 4 else Vector4(0, 0, 1, 1)}
	elif at["albedo"] != null or at["normal"] != null or at["orm"] != null:
		push_error("%s: the boat atlas images are incomplete" % dir)
	_hulls[key] = out
	return out


## {"layout": the sails' layout.json, "sails": {sail id: {"port", "stbd", "normal", "orm": Texture2D, "info":
## the sail's layout entry}}} of the class, or {} when no sail is baked.
static func sail_set(class_id: String) -> Dictionary:
	if not enabled:
		return {}
	if _sails.has(class_id):
		return _sails[class_id]
	var dir := "%s/%s/sails/" % [ROOT, class_id]
	var lay := _json(dir + "layout.json")
	var out := {}
	var sails := {}
	var entries: Dictionary = lay.get("sails", {})
	for id in entries:
		var s := {"port": _tex(dir + id + "_port_albedo.png"), "stbd": _tex(dir + id + "_stbd_albedo.png"),
			"normal": _tex(dir + id + "_normal.png"), "orm": _tex(dir + id + "_orm.png"), "info": entries[id]}
		if s["port"] != null and s["stbd"] != null and s["normal"] != null and s["orm"] != null:
			sails[id] = s
		else:
			push_error("%s: the images of sail %s are incomplete" % [dir, id])
	if not sails.is_empty():
		out = {"layout": lay, "sails": sails}
	_sails[class_id] = out
	return out


## The class rope set (data_format.md §8.7): {"albedo": {function: Texture2D}, "normal", "orm": Texture2D}, or {}
## when the class has no baked ropes. A function without its albedo is left out (it keeps the generator's look).
static func rope_set(class_id: String) -> Dictionary:
	if not enabled:
		return {}
	if _ropes.has(class_id):
		return _ropes[class_id]
	var dir := "%s/%s/rig/" % [ROOT, class_id]
	var out := {}
	var alb := {}
	for fn in Livery.ROPES:
		var t := _tex(dir + "rope_%s_albedo.png" % fn)
		if t != null:
			alb[fn] = t
	if not alb.is_empty():
		out = {"albedo": alb, "normal": _tex(dir + "rope_normal.png"), "orm": _tex(dir + "rope_orm.png")}
	_ropes[class_id] = out
	return out


## The tiling detail of a cloth (dacron, laminate, nylon), or null.
static func detail(cloth: String) -> Texture2D:
	if not _detail.has(cloth):
		_detail[cloth] = _tex("%s/_cloth/%s_detail.png" % [ROOT, cloth])
	return _detail[cloth]


## Forgets the loaded sets (tests).
static func clear() -> void:
	_hulls.clear()
	_sails.clear()
	_detail.clear()
	_ropes.clear()


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
