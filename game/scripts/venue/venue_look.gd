class_name VenueLook
extends RefCounted
## A venue's look file (data_format.md §6.11, `data/venues/<venue>.look.json`, `windmark.look/1`): so far its
## daylight defaults (water_render.md §4.5): the date and UTC offset of the sun formula, the typical race window, the
## default hour and conditions and the conditions a Random race draws from. The latitude and longitude are the venue
## file's origin. Presentation only. A venue without a look file, or a key missing, takes the defaults below.

const SCHEMA := "windmark.look/1"
const DEFAULT_DATE := "07-15"
const DEFAULT_UTC_OFFSET := 2.0
const DEFAULT_WINDOW := Vector2(11.0, 17.0)
const DEFAULT_TIME := 14.5
const DEFAULT_CONDITIONS := "fair"
const DEFAULT_TYPICAL := ["clear", "fair", "hazy"]
## the venue whose origin open water (no venue file) uses
const OPEN_WATER_VENUE := "practice_waters"
## a Random race's hour steps (h)
const RANDOM_STEP_H := 0.5

var venue := ""
var lat: float = Daylight.DEFAULT_SITE["lat"]
var lon: float = Daylight.DEFAULT_SITE["lon"]
var date := DEFAULT_DATE
var utc_offset_h := DEFAULT_UTC_OFFSET
var race_window := DEFAULT_WINDOW
var time := DEFAULT_TIME
var conditions := DEFAULT_CONDITIONS
var typical: Array = DEFAULT_TYPICAL.duplicate()
## what did not load, for the tests and a warning (empty when the file is fine or absent)
var problems: Array[String] = []
var has_file := false


## The look of a venue id (or "" for open water). Never null.
static func load_venue(id: String) -> VenueLook:
	var l := VenueLook.new()
	l.venue = id
	var o := origin(id if id != "" else OPEN_WATER_VENUE)
	if o.x == o.x:
		l.lat = o.x
		l.lon = o.y
	if id == "":
		id = OPEN_WATER_VENUE
	var path := BoatClassData.repo_path("data/venues/%s.look.json" % id)
	var d: Variant = BoatClassData._read_json(path)
	if d is Dictionary:
		l.has_file = true
		l._read(d)
	return l


## The venue file's origin (lat, lon) without parsing the whole file: it sits in the header. NAN when absent.
static func origin(id: String) -> Vector2:
	var path := BoatClassData.repo_path("data/venues/%s.venue.json" % id)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Vector2(NAN, NAN)
	var head := f.get_buffer(mini(4096, f.get_length())).get_string_from_utf8()
	var re := RegEx.create_from_string("\"origin\"\\s*:\\s*(\\{[^}]*\\})")
	var m := re.search(head)
	if m == null:
		return Vector2(NAN, NAN)
	var o: Variant = JSON.parse_string(m.get_string(1))
	if not (o is Dictionary and o.has("lat") and o.has("lon")):
		return Vector2(NAN, NAN)
	return Vector2(float(o["lat"]), float(o["lon"]))


func _read(d: Dictionary) -> void:
	if d.get("schema", "") != SCHEMA:
		problems.append("schema is not %s" % SCHEMA)
	var li: Variant = d.get("light", {})
	if not li is Dictionary:
		problems.append("light is not an object")
		return
	if li.has("date"):
		if Daylight.day_of_year(str(li["date"])) > 0:
			date = str(li["date"])
		else:
			problems.append("date %s is not MM-DD" % li["date"])
	if li.has("utc_offset_h"):
		utc_offset_h = float(li["utc_offset_h"])
	if li.has("race_window"):
		var w: Variant = li["race_window"]
		var a := Daylight.parse_hour(str(w[0])) if w is Array and w.size() == 2 else -1.0
		var b := Daylight.parse_hour(str(w[1])) if w is Array and w.size() == 2 else -1.0
		if a >= 0.0 and b > a:
			race_window = Vector2(a, b)
		else:
			problems.append("race_window %s is not two increasing HH:MM" % str(w))
	if li.has("time"):
		var h := Daylight.parse_hour(str(li["time"]))
		if h >= 0.0:
			time = h
		else:
			problems.append("time %s is not HH:MM" % li["time"])
	if li.has("conditions"):
		if Daylight.is_condition(str(li["conditions"])):
			conditions = str(li["conditions"])
		else:
			problems.append("unknown conditions %s" % li["conditions"])
	if li.has("typical"):
		var ty: Array = []
		for c in li["typical"]:
			if Daylight.is_condition(str(c)):
				ty.append(str(c))
			else:
				problems.append("unknown typical conditions %s" % c)
		if not ty.is_empty():
			typical = ty


## The sun formula's site (Daylight.sun_position).
func site() -> Dictionary:
	return {"lat": lat, "lon": lon, "utc_offset_h": utc_offset_h, "day": Daylight.day_of_year(date)}


## The light of a race (water_render.md §4.5): {hour, conditions}. Local and Custom take the defaults; Random
## draws an hour in the race window (30 min steps) and one of the typical conditions from the seed.
func pick(weather: String, seed: int) -> Dictionary:
	if weather != "random":
		return {"hour": time, "conditions": conditions}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "light"])
	var steps := maxi(int(floor((race_window.y - race_window.x) / RANDOM_STEP_H)), 0)
	var h := race_window.x + RANDOM_STEP_H * rng.randi_range(0, steps)
	var c: String = typical[rng.randi_range(0, typical.size() - 1)]
	return {"hour": h, "conditions": c}
