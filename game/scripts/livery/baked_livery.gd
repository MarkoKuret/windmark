class_name BakedLivery
extends RefCounted
## The baked livery textures of a class (data_format.md §8.5), as staged for import by tools/liverybake into
## res://generated/liveries/<class>/ (game/README.md "Liveries"): the hull set of a livery (hull albedo, normal and
## ORM maps, keel albedo, optional deck albedo, layout.json) and the class sail set (per sail: port and starboard
## albedo, normal and ORM maps; layout.json). Loaded once per class and shared by every boat; a missing set gives
## an empty Dictionary and the procedural fallback.

const ROOT := "res://generated/liveries"
## tests: false makes every set look missing (the procedural path)
static var enabled := true
static var _hulls := {}
static var _sails := {}
static var _detail := {}


## {"albedo", "normal", "orm": Texture2D, "keel": Texture2D or null, "keel_rect": Vector4, "deck", "deck_rect"} of
## the livery `look_id` of the class, or {} when it is not baked.
static func hull_set(class_id: String, look_id: String) -> Dictionary:
	if not enabled:
		return {}
	var key := class_id + "/" + look_id
	if _hulls.has(key):
		return _hulls[key]
	var dir := "%s/%s/%s/" % [ROOT, class_id, look_id]
	var out := {}
	var alb := _tex(dir + "hull_albedo.png")
	if alb != null:
		out["albedo"] = alb
		out["normal"] = _tex(dir + "hull_normal.png")
		out["orm"] = _tex(dir + "hull_orm.png")
		if out["normal"] == null or out["orm"] == null:
			push_error("%s: hull_normal.png or hull_orm.png missing" % dir)
			out = {}
	if not out.is_empty():
		var lay := _json(dir + "layout.json")
		for part in ["keel", "deck"]:
			var t := _tex(dir + part + "_albedo.png")
			var r: Array = lay.get(part, {}).get("rect", [])
			if t != null and r.size() == 4:
				out[part] = t
				out[part + "_rect"] = Vector4(r[0], r[1], r[2], r[3])
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


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
