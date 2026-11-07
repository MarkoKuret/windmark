class_name RaceHistory
extends RefCounted
## The player's race history (menus.md §6): the last results of her quick races, her best finishing time per course
## and class, and races and wins per class, kept in one ConfigFile with a version (user://history.cfg). Written by
## the results screen once per race (menus.md §5 Recording), read there for the best line.
##
## Robust by design: a missing, unreadable or corrupt file or an unknown version reads as an empty history (the next
## save writes a fresh file); an entry of the wrong shape is dropped; the results never pass CAP. A save writes a
## temporary file and moves it over the old one.

const VERSION := 1
const DEFAULT_PATH := "user://history.cfg"
## the results kept (menus.md §6)
const CAP := 50

## where load_file() reads and save_file() writes (tests point it at a temporary file)
static var path := DEFAULT_PATH

## [{date, class, venue, course, fleet, ai_level, weather, place, code, time, gap}], oldest first; time and gap in
## seconds, -1 without one; place 0 without one
var results: Array[Dictionary] = []
## "<course>|<class>" -> the best finishing time in seconds
var bests := {}
## class id -> races recorded / wins
var races := {}
var wins := {}

## the fields of a result and their types
const FIELDS := {"date": TYPE_STRING, "class": TYPE_STRING, "venue": TYPE_STRING, "course": TYPE_STRING,
	"fleet": TYPE_INT, "ai_level": TYPE_STRING, "weather": TYPE_STRING, "place": TYPE_INT, "code": TYPE_STRING,
	"time": TYPE_FLOAT, "gap": TYPE_FLOAT}


## The history in `p` (default `path`); empty when there is none or it cannot be read.
static func load_from(p := "") -> RaceHistory:
	var h := RaceHistory.new()
	h.load_file(p)
	return h


static func key(course: String, class_id: String) -> String:
	return "%s|%s" % [course, class_id]


## A result entry from its parts (the results screen's own row); a missing time or gap is NAN or negative.
static func entry(class_id: String, venue: String, course: String, fleet: int, ai_level: String, weather: String,
		place: int, code: String, time: float, gap: float, date := "") -> Dictionary:
	if date == "":
		var d := Time.get_datetime_dict_from_system()
		date = "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
	return {"date": date, "class": class_id, "venue": venue, "course": course, "fleet": fleet, "ai_level": ai_level,
		"weather": weather, "place": maxi(place, 0), "code": code,
		"time": time if not is_nan(time) and time >= 0.0 else -1.0,
		"gap": gap if not is_nan(gap) and gap >= 0.0 else -1.0}


## Reads `p`; anything it cannot use leaves the history empty (or drops that entry). OK when the file was read.
func load_file(p := "") -> Error:
	if p == "":
		p = path
	results.clear()
	bests.clear()
	races.clear()
	wins.clear()
	if not FileAccess.file_exists(p):
		return ERR_FILE_NOT_FOUND
	var cf := ConfigFile.new()
	var err := cf.load(p)
	if err != OK:
		return err
	var v: Variant = cf.get_value("history", "version", -1)
	if typeof(v) != TYPE_INT or int(v) != VERSION:
		return ERR_FILE_UNRECOGNIZED
	var list: Variant = cf.get_value("history", "results", [])
	if list is Array:
		for e: Variant in list:
			var ok := _entry_ok(e)
			if not ok.is_empty():
				results.append(ok)
	if results.size() > CAP:
		results = results.slice(results.size() - CAP)
	if cf.has_section("best"):
		for k in cf.get_section_keys("best"):
			var t: Variant = cf.get_value("best", k)
			if (typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_INT) and float(t) > 0.0 and k.contains("|"):
				bests[k] = float(t)
	for sec: String in ["races", "wins"]:
		if not cf.has_section(sec):
			continue
		var into: Dictionary = races if sec == "races" else wins
		for k in cf.get_section_keys(sec):
			var n: Variant = cf.get_value(sec, k)
			if typeof(n) == TYPE_INT and int(n) >= 0:
				into[k] = int(n)
	return OK


## A result entry with the right fields and types (ints may come as whole floats), else {}.
static func _entry_ok(e: Variant) -> Dictionary:
	if not (e is Dictionary):
		return {}
	var out := {}
	for f: String in FIELDS:
		if not (e as Dictionary).has(f):
			return {}
		var x: Variant = e[f]
		match FIELDS[f]:
			TYPE_STRING:
				if typeof(x) != TYPE_STRING:
					return {}
				out[f] = x
			TYPE_INT:
				if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
					return {}
				out[f] = int(x)
			TYPE_FLOAT:
				if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
					return {}
				out[f] = float(x)
	return out


## Writes the whole history to `p` (default `path`): a temporary file, then moved over the old one.
func save_file(p := "") -> Error:
	if p == "":
		p = path
	if p == DEFAULT_PATH and _scripted_run():
		return ERR_UNAUTHORIZED
	var cf := ConfigFile.new()
	cf.set_value("history", "version", VERSION)
	if results.size() > CAP:
		results = results.slice(results.size() - CAP)
	cf.set_value("history", "results", results)
	for k: String in bests:
		cf.set_value("best", k, bests[k])
	for k: String in races:
		cf.set_value("races", k, races[k])
	for k: String in wins:
		cf.set_value("wins", k, wins[k])
	var tmp := p + ".tmp"
	var err := cf.save(tmp)
	if err != OK:
		return err
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(p))
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		err = cf.save(p)
	return err


## A headless test or tool run (`godot -s <script>`: the main loop has a script, or is not set yet while the
## script's _init runs). It never writes the player's own file: a test that records points `path` at a temporary file.
static func _scripted_run() -> bool:
	var ml := Engine.get_main_loop()
	return ml == null or ml.get_script() != null


## Adds a result (an entry()): the results capped, the best of its course and class, the races and wins of its class.
func add(e: Dictionary) -> void:
	var ok := _entry_ok(e)
	if ok.is_empty():
		return
	results.append(ok)
	if results.size() > CAP:
		results = results.slice(results.size() - CAP)
	var cls: String = ok["class"]
	races[cls] = int(races.get(cls, 0)) + 1
	if int(ok["place"]) == 1:
		wins[cls] = int(wins.get(cls, 0)) + 1
	var t: float = ok["time"]
	if _finished(ok):
		var k := key(ok["course"], cls)
		if not bests.has(k) or t < float(bests[k]):
			bests[k] = t


## Adds a result and saves; the save's error.
func record(e: Dictionary, p := "") -> Error:
	add(e)
	return save_file(p)


## A finish that counts for a best: a place and a time (a finish scored with a code does not).
static func _finished(e: Dictionary) -> bool:
	return int(e.get("place", 0)) > 0 and float(e.get("time", -1.0)) > 0.0


## The best finishing time on this course in this class, NAN without one.
func best(course: String, class_id: String) -> float:
	return float(bests.get(key(course, class_id), NAN))


## Whether a result on this course in this class is recorded (in the kept results, or as a best).
func raced(course: String, class_id: String) -> bool:
	if bests.has(key(course, class_id)):
		return true
	for e in results:
		if e["course"] == course and e["class"] == class_id:
			return true
	return false


## The results screen's best line (menus.md §5) for a race on this course and class with this result, from the
## history before it: "" when there is none to show.
func best_line(course: String, class_id: String, place: int, time: float) -> String:
	var b := best(course, class_id)
	var finished := place > 0 and not is_nan(time) and time > 0.0
	if not is_nan(b):
		if finished and time < b:
			return Strings.t("results.new_best", {"time": HudFormat.finish_time(time), "old": HudFormat.finish_time(b)})
		return Strings.t("results.best", {"time": HudFormat.finish_time(b)})
	if not raced(course, class_id):
		return Strings.t("results.first_race")
	return Strings.t("results.first_finish") if finished else ""
