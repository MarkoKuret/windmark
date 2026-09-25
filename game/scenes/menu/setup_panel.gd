class_name SetupPanel
extends VBoxContainer
## The quick race and free sail setup (menus.md §1): the rows, and write() into a GameSetup.

signal start_pressed

var mode := "race"
var rows := {}
var start_button: Button
var _note: Label
var _classes := []
var _venues := []


## `last`: the last setup (GameSetup fields) to start from.
func build(race: bool, last: Dictionary) -> void:
	mode = "race" if race else "free"
	name = "QuickRace" if race else "FreeSail"
	add_theme_constant_override("separation", 4)
	add_child(MenuTheme.heading("Quick race" if race else "Free sail"))
	var sub := MenuTheme.label("Race the AI fleet round a course." if race else
		"Sail on your own, no course and no clock.", MenuTheme.SMALL_SIZE, MenuTheme.MUTED)
	add_child(sub)
	add_child(_gap(10))
	var g := GameSetup.new()
	_classes = MenuData.classes()
	_venues = MenuData.venues()
	var cls: String = last.get("class_id", g.class_id)
	var ven: String = last.get("venue", g.venue)
	_add(MenuRow.choice("Boat", "class_id", MenuData.ids(_classes), MenuData.names(_classes),
		_pick(MenuData.ids(_classes), cls)))
	_add(MenuRow.choice("Venue", "venue", MenuData.ids(_venues), MenuData.names(_venues),
		_pick(MenuData.ids(_venues), ven)))
	if race:
		_add(MenuRow.choice("Course", "course", [], [], last.get("course", g.course)))
		_add(MenuRow.range_row("Fleet", "fleet_size", 2, 40, 1, float(last.get("fleet_size", g.fleet_size)),
			func(v: float) -> String: return "%d boats" % int(v)))
		_add(MenuRow.choice("AI level", "ai_level", MenuData.AI_LEVELS, MenuData.AI_NAMES,
			last.get("ai_level", g.ai_level)))
	_add(MenuRow.range_row("Wind speed", "wind_kn", 4, 25, 1, float(last.get("wind_kn", g.wind_kn)),
		func(v: float) -> String: return "%d kn" % int(v)))
	_add(MenuRow.range_row("Wind from", "wind_from_deg", 0, 355, 5, float(last.get("wind_from_deg", g.wind_from_deg)),
		func(v: float) -> String: return "%03d°  %s" % [int(v), _compass(v)]))
	rows["class_id"].changed.connect(func(_v: Variant) -> void: _refresh_courses())
	rows["venue"].changed.connect(func(_v: Variant) -> void: _refresh_courses())
	_refresh_courses()
	add_child(_gap(14))
	start_button = MenuTheme.button("Start race" if race else "Set sail")
	start_button.name = "Start"
	start_button.add_theme_color_override("font_color", MenuTheme.ACCENT)
	start_button.add_theme_color_override("font_focus_color", MenuTheme.ACCENT)
	start_button.add_theme_color_override("font_hover_color", MenuTheme.ACCENT)
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	add_child(start_button)
	_note = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.ACCENT)
	add_child(_note)
	_refresh_courses()


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func _pick(ids: Array, want: String) -> String:
	return want if ids.has(want) or ids.is_empty() else ids[0]


static func _compass(deg: float) -> String:
	var pts := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
	return pts[posmod(roundi(deg / 22.5), 16)]


func _add(r: MenuRow) -> void:
	rows[r.key] = r
	add_child(r)


func _refresh_courses() -> void:
	if not rows.has("course"):
		return
	var list := MenuData.courses(str(rows["venue"].value), str(rows["class_id"].value))
	rows["course"].set_choices(MenuData.ids(list), MenuData.names(list))
	if list.is_empty():
		rows["course"].set_value("", false)
		rows["course"]._value.text = "No course for this boat"
	if start_button != null:
		start_button.disabled = list.is_empty()
		start_button.focus_mode = Control.FOCUS_NONE if list.is_empty() else Control.FOCUS_ALL
		_note.text = "This venue has no course for this boat yet." if list.is_empty() else ""


## Takes the remembered choices that fit (menus.md §1).
func load_from(last: Dictionary) -> void:
	for k in last:
		if rows.has(k) and k != "course":
			var r: MenuRow = rows[k]
			if r.kind != MenuRow.Kind.CHOICE or r.choices.has(last[k]):
				r.set_value(last[k])
	_refresh_courses()
	if rows.has("course") and rows["course"].choices.has(last.get("course", "")):
		rows["course"].set_value(last["course"])


func can_start() -> bool:
	return start_button != null and not start_button.disabled


func first_row() -> Control:
	return rows["class_id"]


## The chosen setup into `g` (menus.md §1).
func write(g: GameSetup) -> void:
	g.mode = mode
	g.class_id = str(rows["class_id"].value)
	g.venue = str(rows["venue"].value)
	if mode == "race":
		g.course = str(rows["course"].value)
		g.fleet_size = int(rows["fleet_size"].value)
		g.ai_level = str(rows["ai_level"].value)
	g.wind_kn = float(rows["wind_kn"].value)
	g.wind_from_deg = float(rows["wind_from_deg"].value)
	g.seed = 0


## The rows as GameSetup fields (remembered for the next visit).
func to_dict() -> Dictionary:
	var d := {}
	for k in rows:
		d[k] = rows[k].value
	return d
