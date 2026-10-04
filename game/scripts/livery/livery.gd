class_name Livery
extends RefCounted
## One boat's look and identity (docs/specs/data_format.md §8): the class livery (hull and deck colours, the hull
## graphic) and the class sail set, which every boat of the class shares, and the boat's own name, sail number and
## nation. Loaded from data/liveries/<class>.liveries.json with `load_class` (one entry per boat of the file's
## `boats`); a fleet gets its boats with `assign` (the §8.4 fleet rule, deterministic from the race seed).

const SCHEMA := "windmark.liveries/2"
## data_format.md §3.7 and §8: no channel above 231 (a linear albedo of 0.8)
const MAX_CHANNEL := 231
const GRAPHICS := ["none", "stripes", "two_tone", "swoosh", "gradient", "bow"]
const DESIGNS := ["plain", "bands", "head", "panels", "diagonal", "gores"]
const CLOTHS := ["dacron", "laminate", "nylon"]
const ROLES := ["main", "headsail", "code_zero", "spinnaker"]
## data_format.md §8.7: the class rope set by function, with each function's default braid and fleck colours
const ROPES := {
	"mainsheet": ["#1f2b45", "#d8d8d2"],
	"sheet": ["#d2d2cb", "#b3242a"],
	"kite_sheet": ["#2b62a6", "#dadad4"],
	"halyard": ["#d4d4cd", "#2d7a40"],
	"control": ["#1d1e21", "#c9a227"],
}
const ROPE_PATTERNS := ["fleck", "tracer", "twill", "solid"]

## the boat's id in the file's `boats`, and what the menus show ("7  Kestrel")
var id := ""
var name := ""
var boat_name := ""
var sail_number := ""
var nation := ""
## the class insignia text (from the file's top level)
var insignia := ""
var class_id := ""
## the livery worn (its id names the texture folder, data_format.md §8.5)
var look_id := ""
## hull: topsides, boot_stripe, antifouling, keel, text (Color, sRGB)
var hull := {}
## hull graphic: {"type": String, "colors": Array[Color], other keys as given}
var graphic := {"type": "none", "colors": []}
## deck: gelcoat, nonslip
var deck := {}
## sails by role: {"cloth": String ("" = the sail type's default), "color", "fibre", "number": Color,
## "design": String, "colors": Array[Color], other keys as given}
var sails := {}
## ropes by function (ROPES): {"color", "fleck": Color, "pattern": String}
var ropes := {}


## The sail entry for a sail type (main, jib, genoa, code_zero, spinnaker_asym, spinnaker_sym).
func sail_for(sail_type: String) -> Dictionary:
	var role := "main"
	if sail_type == "jib" or sail_type == "genoa":
		role = "headsail"
	elif sail_type == "code_zero":
		role = "code_zero"
	elif sail_type.begins_with("spinnaker"):
		role = "spinnaker"
	return sails.get(role, _sail({}, "", []))


## A copy with another boat name and sail number (a repeat in a large fleet, §8).
func repeat(n: int) -> Livery:
	var l := Livery.new()
	for k in ["id", "name", "nation", "insignia", "class_id", "look_id"]:
		l.set(k, get(k))
	l.hull = hull
	l.graphic = graphic
	l.deck = deck
	l.sails = sails
	l.ropes = ropes
	l.boat_name = boat_name + " " + roman(n + 1)
	l.sail_number = str(1000 * n + sail_number.to_int())
	return l


static func roman(n: int) -> String:
	var vals := [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
	var s := ""
	for v in vals:
		while n >= v[0]:
			s += v[1]
			n -= v[0]
	return s


static var _cache := {}


## The boats of a class in file order (the first is the class default), each in the class livery and sail set;
## empty with an error pushed when the file is missing or invalid.
static func load_class(class_id: String) -> Array[Livery]:
	if _cache.has(class_id):
		return _cache[class_id]
	var path := BoatClassData.repo_path("data/liveries/%s.liveries.json" % class_id)
	var out: Array[Livery] = []
	var errors := []
	var d: Variant = BoatClassData._read_json(path)
	if not (d is Dictionary):
		push_error("%s: missing or not JSON" % path)
		return out
	out = parse(d, class_id, errors)
	for e in errors:
		push_error("%s: %s" % [path, e])
	if not errors.is_empty():
		out.clear()
	_cache[class_id] = out
	return out


## Validates and parses a livery file (data_format.md §8): one Livery per entry of `boats`, each in the class
## livery (`liveries[0]`) and the class sail set. Problems go to `errors` as "<json path>: <reason>".
static func parse(d: Dictionary, class_id: String, errors: Array) -> Array[Livery]:
	var out: Array[Livery] = []
	if d.get("schema", "") != SCHEMA:
		errors.append("schema: expected %s" % SCHEMA)
		return out
	if class_id != "" and d.get("class", "") != class_id:
		errors.append("class: expected %s" % class_id)
	var ins: String = str(d.get("insignia", {}).get("text", "")) if d.get("insignia") is Dictionary else ""
	if not RegEx.create_from_string("^[A-Z0-9]{1,4}$").search(ins):
		errors.append("insignia.text: 1 to 4 capital letters and digits")
	var re_id := RegEx.create_from_string("^[a-z0-9_]+$")
	var re_name := RegEx.create_from_string("^[A-Za-z0-9 '\\-.]{1,20}$")
	var re_nat := RegEx.create_from_string("^[A-Z]{3}$")
	# the class livery (data_format.md §8.1): every boat wears the first; the others are checked and kept for later
	var list: Variant = d.get("liveries")
	if not (list is Array) or (list as Array).is_empty():
		errors.append("liveries: at least 1")
		return out
	var looks := []
	var look_ids := {}
	for i in (list as Array).size():
		var e: Variant = list[i]
		var at := "liveries[%d]" % i
		if not (e is Dictionary):
			errors.append(at + ": not an object")
			continue
		var l := Livery.new()
		l.look_id = str(e.get("id", ""))
		if not re_id.search(l.look_id) or look_ids.has(l.look_id):
			errors.append(at + ".id: missing, not [a-z0-9_] or not unique")
		look_ids[l.look_id] = true
		if str(e.get("name", "")) == "":
			errors.append(at + ".name: missing")
		var h: Dictionary = e.get("hull", {}) if e.get("hull") is Dictionary else {}
		l.hull["topsides"] = _color(h, "topsides", "", at + ".hull", errors)
		l.hull["boot_stripe"] = _color(h, "boot_stripe", "#e0e0dc", at + ".hull", errors)
		l.hull["antifouling"] = _color(h, "antifouling", "#1a1d24", at + ".hull", errors)
		l.hull["keel"] = _color(h, "keel", "#" + l.hull["antifouling"].to_html(false), at + ".hull", errors)
		l.hull["text"] = _color(h, "text", "", at + ".hull", errors)
		var g: Dictionary = h.get("graphic", {}) if h.get("graphic") is Dictionary else {}
		l.graphic = g.duplicate()
		l.graphic["type"] = str(g.get("type", "none"))
		if not GRAPHICS.has(l.graphic["type"]):
			errors.append(at + ".hull.graphic.type: one of " + ", ".join(GRAPHICS))
		l.graphic["colors"] = _colors(g, at + ".hull.graphic", errors)
		var dk: Dictionary = e.get("deck", {}) if e.get("deck") is Dictionary else {}
		l.deck["gelcoat"] = _color(dk, "gelcoat", "#e2e2dc", at + ".deck", errors)
		l.deck["nonslip"] = _color(dk, "nonslip", "#a8a8a0", at + ".deck", errors)
		looks.append(l)
	# the class sail set (§8.3)
	var sail_set := {}
	var ss: Dictionary = d.get("sails", {}) if d.get("sails") is Dictionary else {}
	for role in ROLES:
		var s: Dictionary = ss.get(role, {}) if ss.get(role) is Dictionary else {}
		sail_set[role] = _sail(s, "sails." + role, errors)
	# the class rope set (§8.7)
	var rope_set := rope_set_of(d.get("ropes", {}) if d.get("ropes") is Dictionary else {}, errors)
	# the boats (§8.4)
	var boats: Variant = d.get("boats")
	if not (boats is Array) or (boats as Array).size() < 12:
		errors.append("boats: at least 12")
		return out
	if looks.is_empty():
		return out
	var look: Livery = looks[0]
	var ids := {}
	var numbers := {}
	for i in (boats as Array).size():
		var e: Variant = boats[i]
		var at := "boats[%d]" % i
		if not (e is Dictionary):
			errors.append(at + ": not an object")
			continue
		var l := Livery.new()
		l.class_id = str(d.get("class", class_id))
		l.insignia = ins
		l.look_id = look.look_id
		l.hull = look.hull
		l.graphic = look.graphic
		l.deck = look.deck
		l.sails = sail_set
		l.ropes = rope_set
		l.id = str(e.get("id", ""))
		if not re_id.search(l.id) or ids.has(l.id):
			errors.append(at + ".id: missing, not [a-z0-9_] or not unique")
		ids[l.id] = true
		l.boat_name = str(e.get("boat_name", ""))
		if not re_name.search(l.boat_name):
			errors.append(at + ".boat_name: 1 to 20 of A-Z a-z 0-9 space ' - .")
		l.sail_number = str(e.get("sail_number", ""))
		var n := l.sail_number.to_int()
		if not l.sail_number.is_valid_int() or n < 1 or n > 999 or str(n) != l.sail_number or numbers.has(n):
			errors.append(at + ".sail_number: \"1\" to \"999\", unique")
		numbers[n] = true
		l.nation = str(e.get("nation", ""))
		if l.nation != "" and not re_nat.search(l.nation):
			errors.append(at + ".nation: 3 capital letters")
		l.name = "%s  %s" % [l.sail_number, l.boat_name]
		out.append(l)
	return out


## The rope set of a livery file's `ropes` block (§8.7): every function, with its defaults filled in.
static func rope_set_of(rs: Dictionary, errors: Array) -> Dictionary:
	var out := {}
	for k in rs:
		if not ROPES.has(k):
			errors.append("ropes.%s: one of %s" % [k, ", ".join(ROPES.keys())])
	for fn in ROPES:
		var e: Dictionary = rs.get(fn, {}) if rs.get(fn) is Dictionary else {}
		var at: String = "ropes." + fn
		var o := {"color": _color(e, "color", ROPES[fn][0], at, errors),
			"fleck": _color(e, "fleck", ROPES[fn][1], at, errors), "pattern": str(e.get("pattern", "fleck"))}
		if not ROPE_PATTERNS.has(o["pattern"]):
			errors.append(at + ".pattern: one of " + ", ".join(ROPE_PATTERNS))
		out[fn] = o
	return out


## The mean colour of a rope function's braid (sRGB): 14 of 16 carriers in the main colour and 2 in the fleck
## (one with `tracer`, half with `twill`, none with `solid`).
static func rope_mean(r: Dictionary) -> Color:
	var shares := {"fleck": 2.0 / 16.0, "tracer": 1.0 / 16.0, "twill": 0.5, "solid": 0.0}
	var share: float = shares.get(r.get("pattern", "fleck"), 0.125)
	var a := (r["color"] as Color).srgb_to_linear()
	var b := (r["fleck"] as Color).srgb_to_linear()
	return a.lerp(b, share).linear_to_srgb()


static func _sail(s: Dictionary, at: String, errors: Variant) -> Dictionary:
	var errs: Array = errors if errors is Array else []
	var o := s.duplicate()
	o["cloth"] = str(s.get("cloth", ""))
	if o["cloth"] != "" and not CLOTHS.has(o["cloth"]):
		errs.append(at + ".cloth: one of " + ", ".join(CLOTHS))
	o["color"] = _color(s, "color", "#e4e4de", at, errs)
	o["fibre"] = _color(s, "fibre", "#1e1f21", at, errs)
	o["number"] = _color(s, "number", "#14213d", at, errs)
	o["design"] = str(s.get("design", "plain"))
	if not DESIGNS.has(o["design"]):
		errs.append(at + ".design: one of " + ", ".join(DESIGNS))
	o["colors"] = _colors(s, at, errs)
	return o


static func _color(d: Dictionary, key: String, def: String, at: String, errors: Array) -> Color:
	var v: String = str(d.get(key, def))
	if v == "" or not v.begins_with("#") or v.length() != 7 or not Color.html_is_valid(v):
		errors.append("%s.%s: \"#rrggbb\" required" % [at, key])
		return Color.MAGENTA
	var c := Color.html(v)
	if maxi(maxi(c.r8, c.g8), c.b8) > MAX_CHANNEL:
		errors.append("%s.%s: %s brighter than #e7 in a channel (linear albedo 0.8)" % [at, key, v])
	return c


static func _colors(d: Dictionary, at: String, errors: Array) -> Array:
	var out := []
	var list: Variant = d.get("colors", [])
	if not (list is Array):
		errors.append(at + ".colors: a list")
		return out
	for i in (list as Array).size():
		out.append(_color({"c": list[i]}, "c", "", "%s.colors[%d]" % [at, i], errors))
	return out


## 32-bit FNV-1a of the UTF-8 text (§8 fleet rule).
static func fnv1a32(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xffffffff
	return h


## The seeded order of a class's liveries (§8 rule 1): indices into `list`.
static func seeded_order(list: Array, seed_value: int) -> Array:
	var keys := []
	for i in list.size():
		keys.append([fnv1a32("%d:%s" % [seed_value, list[i].id]), i])
	keys.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keys.map(func(k: Array) -> int: return k[1])


## The fleet rule (data_format.md §8.4): one boat identity per entry, all in the class livery. `entries`: per boat
## {"human": bool, "choice": boat id or ""}; `list`: the class's boats (load_class). Repeats in fleets larger than
## the list carry a numbered name and a sail number of 1000 * repeat + number.
static func assign(list: Array, entries: Array, seed_value: int) -> Array[Livery]:
	var out: Array[Livery] = []
	out.resize(entries.size())
	if list.is_empty():
		return out
	var order := seeded_order(list, seed_value)
	var taken := {}
	var by_id := {}
	for i in list.size():
		by_id[list[i].id] = i
	for b in entries.size():
		if not entries[b].get("human", false):
			continue
		var want: String = str(entries[b].get("choice", ""))
		var k: int = by_id.get(want, 0) if want != "" else 0
		if taken.has(k):
			k = -1
			for o in order:
				if not taken.has(o):
					k = o
					break
		if k < 0:
			out[b] = list[order[0]].repeat(1)
			continue
		taken[k] = true
		out[b] = list[k]
	var free := order.filter(func(o: int) -> bool: return not taken.has(o))
	var next := 0
	var rep := 0
	for b in entries.size():
		if out[b] != null:
			continue
		if next >= free.size():
			free = order.duplicate()
			next = 0
			rep += 1
		var l: Livery = list[free[next]]
		out[b] = l if rep == 0 else l.repeat(rep)
		next += 1
	return out
