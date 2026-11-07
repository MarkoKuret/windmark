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


## Boat classes: data/classes/<id>.boat.json, smallest first (by length over all, then name: the picker walks
## the fleet from the sportsboat up to the classic yacht, menus.md §1.1).
static func classes() -> Array:
	var dir := BoatClassData.repo_path("data/classes")
	var out := []
	for f in _files(dir, ".boat.json"):
		var d := _read(dir.path_join(f))
		var id := f.trim_suffix(".boat.json")
		out.append({"id": id, "name": str(d.get("name", id)), "loa": float(d.get("hull", {}).get("loa", 0.0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["loa"] < b["loa"] if absf(a["loa"] - b["loa"]) > 1e-6 else a["name"] < b["name"])
	for e in out:
		e.erase("loa")
	return out


## The boats of a class in file order (the default first), named "<sail number>  <boat name>":
## data/liveries/<class>.liveries.json `boats` (every boat wears the class livery).
static func liveries(class_id: String) -> Array:
	return Livery.load_class(class_id).map(func(l: Livery) -> Dictionary: return {"id": l.id, "name": l.name})


## Venues: data/venues/<id>.venue.json, the practice venue first (the default, where a new player starts) and
## the rest by name.
static func venues() -> Array:
	var dir := BoatClassData.repo_path("data/venues")
	var out := []
	for f in _files(dir, ".venue.json"):
		var d := _read(dir.path_join(f))
		var id := f.trim_suffix(".venue.json")
		out.append({"id": id, "name": str(d.get("name", id))})
	_sorted(out)
	for i in out.size():
		if out[i]["id"] == "practice_waters":  # GameSetup.venue's default
			out.push_front(out.pop_at(i))
			break
	return out


## the venues' weather read once per file (VenueWeather.info), by path
static var _venue_info := {}


## A venue's weather and briefing (VenueWeather.info of data/venues/<id>.venue.json), {} when the file is missing.
static func venue_info(id: String) -> Dictionary:
	var p := BoatClassData.repo_path("data/venues/%s.venue.json" % id)
	if not _venue_info.has(p):
		if not FileAccess.file_exists(p):
			return {}
		_venue_info[p] = VenueWeather.info(_read(p))
	return _venue_info[p]


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


## One hand-written character line per shipped class (menus.md §1.1, the Boat step); a class without one gets
## class_line()'s generic line.
const CLASS_LINES := {
	"wm7": "Modern sportsboat: light, quick to plane, asymmetric kite, tiller.",
	"wm9": "Classic keelboat: narrow and long, symmetric kite on a pole, tiller.",
	"wm10": "Shorthanded offshore racer: chined hull, twin rudders, code zero and asymmetric kite, tiller.",
	"wm12": "Fast one-design keelboat for a crew of eight: code zero and asymmetric kite, wheel.",
	"wm16": "Grand prix racer: a powerful rig, a big asymmetric kite, a crew of thirteen, twin wheels.",
	"wm21": "Classic yacht: long and elegant, genoa and symmetric kite, a crew of eleven, wheel.",
}

## One character line per shipped venue (menus.md §1.1, the Venue step); a venue without one gets its briefing tag.
const VENUE_LINES := {
	"practice_waters": "Open water and one island: a steady breeze and a light current. Learn the boat and the rules.",
	"garda": "The north end of Lake Garda: the afternoon Ora between the mountains, stronger along one shore, no current.",
	"solent": "The Solent off Cowes: a moderate south-westerly over a strong tide, hardest in mid-channel.",
	"fremantle": "Gage Roads off Fremantle: the Doctor sea breeze, strong and swinging left all afternoon, ocean swell.",
	"trieste": "The Gulf of Trieste in a bora: gusty offshore wind off the Karst, big fast shifts, flat water inshore.",
}

## the classes' files read once, by id
static var _class_docs := {}


## The class file of a class (data/classes/<id>.boat.json), {} when missing.
static func class_doc(id: String) -> Dictionary:
	if not _class_docs.has(id):
		_class_docs[id] = _read(BoatClassData.repo_path("data/classes/%s.boat.json" % id))
	return _class_docs[id]


## The Boat step's key numbers (menus.md §1.1): {loa (m), sail_area (m², the main and the headsail), crew,
## kite ("asym", "sym" or ""), kite_area (m²), steering ("tiller" or "wheel"), mast_height (m)}.
static func class_facts(id: String) -> Dictionary:
	var d := class_doc(id)
	var out := {"loa": 0.0, "sail_area": 0.0, "crew": 0, "kite": "", "kite_area": 0.0, "steering": "tiller",
		"mast_height": 0.0}
	if d.is_empty():
		return out
	out["loa"] = float(d.get("hull", {}).get("loa", 0.0))
	out["crew"] = int(d.get("crew", {}).get("count", 0))
	out["steering"] = str(d.get("visual", {}).get("deck", {}).get("steering", "tiller"))
	out["mast_height"] = float(d.get("rig", {}).get("mast_height", 0.0))
	for s in d.get("sails", []):
		var t := str(s.get("type", ""))
		var a := float(s.get("area", 0.0))
		if t == "main" or t == "jib" or t == "genoa":
			out["sail_area"] += a
		elif t.begins_with("spinnaker") and a > out["kite_area"]:
			out["kite"] = "asym" if t == "spinnaker_asym" else "sym"
			out["kite_area"] = a
	return out


## The tallest mast among the classes (m): the showcase camera's reference (menus.md §4.1), so every class
## shows at the same scale; 0 without classes.
static func tallest_mast() -> float:
	var out := 0.0
	for c in classes():
		out = maxf(out, float(class_facts(c["id"])["mast_height"]))
	return out


## The class's character line: the hand-written one, else `<crew> crew, <kite> kite, <tiller|wheel>` from its file.
static func class_line(id: String) -> String:
	if CLASS_LINES.has(id):
		return CLASS_LINES[id]
	var f := class_facts(id)
	var kite := "no kite" if f["kite"] == "" else ("asymmetric kite" if f["kite"] == "asym" else "symmetric kite")
	return "%d crew, %s, %s." % [f["crew"], kite, f["steering"]]


## The venue's character line: the hand-written one, else its briefing tag.
static func venue_line(id: String) -> String:
	if VENUE_LINES.has(id):
		return VENUE_LINES[id]
	var vi := venue_info(id)
	return str(vi.get("tag", ""))


## the venues' bounds and land read once, by id
static var _venue_shapes := {}


## The venue's bounds (world ENU m, data_format.md §6.1) and land polygons (§6.5), for the venue chart:
## {bounds: Rect2, land: [PackedVector2Array]}; an empty Rect2 and no land when the file is missing.
static func venue_shapes(id: String) -> Dictionary:
	if _venue_shapes.has(id):
		return _venue_shapes[id]
	var out := {"bounds": Rect2(), "land": []}
	var p := BoatClassData.repo_path("data/venues/%s.venue.json" % id)
	if FileAccess.file_exists(p):
		var d := _read(p)
		var b: Variant = d.get("bounds", null)
		if b is Array and (b as Array).size() == 4:
			out["bounds"] = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
		var shapes := VenueShapes.from_file(p)
		for l in shapes.land:
			out["land"].append(l["points"])
	_venue_shapes[id] = out
	return out
