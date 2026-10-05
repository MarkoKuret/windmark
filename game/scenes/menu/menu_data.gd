class_name MenuData
extends RefCounted
## What the menus offer, read from the data on disk (menus.md §1): boat classes (data/classes), venues
## (data/venues), courses (game/data/courses/<venue>) and liveries (data/liveries). Each entry is {"id", "name"},
## sorted by name (liveries in file order).

const AI_LEVELS := ["easy", "intermediate", "expert", "pro"]
const AI_NAMES := ["Easy", "Intermediate", "Expert", "Pro"]


static func _read(p: String) -> Dictionary:
	var v: Variant = BoatClassData._read_json(p)
	return v if v is Dictionary else {}


static func _files(dir: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(suffix):
			out.append(f)
	out.sort()
	return out


static func _sorted(list: Array) -> Array:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return list


## Boat classes: data/classes/<id>.boat.json.
static func classes() -> Array:
	var dir := BoatClassData.repo_path("data/classes")
	var out := []
	for f in _files(dir, ".boat.json"):
		var d := _read(dir.path_join(f))
		var id := f.trim_suffix(".boat.json")
		out.append({"id": id, "name": str(d.get("name", id))})
	return _sorted(out)


## The boats of a class in file order (the default first), named "<sail number>  <boat name>":
## data/liveries/<class>.liveries.json `boats` (every boat wears the class livery).
static func liveries(class_id: String) -> Array:
	return Livery.load_class(class_id).map(func(l: Livery) -> Dictionary: return {"id": l.id, "name": l.name})


## Venues: data/venues/<id>.venue.json.
static func venues() -> Array:
	var dir := BoatClassData.repo_path("data/venues")
	var out := []
	for f in _files(dir, ".venue.json"):
		var d := _read(dir.path_join(f))
		var id := f.trim_suffix(".venue.json")
		out.append({"id": id, "name": str(d.get("name", id))})
	return _sorted(out)


## Courses of a venue for a class, ids "<venue>/<course id>": those whose `classes` list the class, and those
## without a `classes` list.
static func courses(venue: String, class_id: String) -> Array:
	var dir := "res://data/courses".path_join(venue)
	var fit := []
	for f in _files(dir, ".course.json"):
		var d := _read(ProjectSettings.globalize_path(dir.path_join(f)))
		var id := f.trim_suffix(".course.json")
		var e := {"id": venue + "/" + id, "name": str(d.get("name", id))}
		var cls: Variant = d.get("classes", null)
		if not (cls is Array) or (cls as Array).has(class_id):
			fit.append(e)
	return _sorted(fit)


static func ids(list: Array) -> Array:
	return list.map(func(e: Dictionary) -> String: return e["id"])


static func names(list: Array) -> Array:
	return list.map(func(e: Dictionary) -> String: return e["name"])


## The course file of "<venue>/<course id>" (game/data/courses/<venue>/<id>.course.json), {} when missing.
static func course_file(id: String) -> Dictionary:
	if id == "" or not id.contains("/"):
		return {}
	var p := "res://data/courses".path_join(id + ".course.json")
	if not FileAccess.file_exists(p):
		return {}
	return _read(ProjectSettings.globalize_path(p))


## The display name of an id in a list ({"id", "name"}), the id when it is not there.
static func name_of(list: Array, id: String) -> String:
	for e in list:
		if e["id"] == id:
			return e["name"]
	return id
