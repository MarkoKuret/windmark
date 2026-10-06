class_name SetupPanel
extends VBoxContainer
## The quick race and free sail setup (menus.md §1): the race card of §1.1 (a header, the rows, the venue briefing
## of §1.3 and the preview in a body that scrolls, Start in a footer that does not), and write() into a GameSetup.
## The Weather row offers the venue's modes (Local, Random, Custom); the Custom rows (wind speed, wind from,
## shifts, gusts) show in Custom only.

signal start_pressed

## the preview goes under the rows when the page is narrower than this, logical px (menus.md §1.1)
const TWO_COLUMNS_MIN := 760.0

var mode := "race"
var rows := {}
var start_button: Button
## the Custom weather rows, shown in Custom only (menus.md §1)
const CUSTOM_ROWS := ["wind_kn", "wind_from_deg", "shift", "gusts"]

## the race card's briefing (quick race only, menus.md §1.3): its box, the header and the [label, value] lines
var briefing: PanelContainer
var briefing_header: Label
var briefing_grid: GridContainer
## the race card's preview (quick race only): the course map, its caption and the fleet summary
var course_map: CourseMap
var course_text: Label
var fleet_text: Label
var body: BoxContainer
var scroll: ScrollContainer
var _note: Label
var _rows_box: VBoxContainer
var _classes := []
var _venues := []


## `last`: the last setup (GameSetup fields) to start from.
func build(race: bool, last: Dictionary) -> void:
	mode = "race" if race else "free"
	name = "QuickRace" if race else "FreeSail"
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(MenuTheme.heading("Quick race" if race else "Free sail"))
	var sub := MenuTheme.label("Race the AI fleet round a course." if race else
		"Sail on your own, no course and no clock.", MenuTheme.SMALL_SIZE, MenuTheme.MUTED)
	add_child(sub)
	add_child(_gap(8))
	scroll = ScrollContainer.new()
	scroll.name = "Body"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body = BoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	scroll.add_child(body)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.size_flags_stretch_ratio = 1.4
	_rows_box.add_theme_constant_override("separation", 4)
	body.add_child(_rows_box)
	var g := GameSetup.new()
	_classes = MenuData.classes()
	_venues = MenuData.venues()
	var cls: String = last.get("class_id", g.class_id)
	var ven: String = last.get("venue", g.venue)
	_add(MenuRow.choice("Boat", "class_id", MenuData.ids(_classes), MenuData.names(_classes),
		_pick(MenuData.ids(_classes), cls)))
	var lv := MenuData.liveries(str(rows["class_id"].value))
	# the player's boat: sail number and name (menus.md §1; every boat wears the class livery)
	_add(MenuRow.choice("Sail number", "livery", MenuData.ids(lv), MenuData.names(lv),
		_pick(MenuData.ids(lv), str(last.get("livery", g.livery)))))
	_add(MenuRow.choice("Venue", "venue", MenuData.ids(_venues), MenuData.names(_venues),
		_pick(MenuData.ids(_venues), ven)))
	if race:
		_add(MenuRow.choice("Course", "course", [], [], last.get("course", g.course)))
		_add(MenuRow.range_row("Fleet", "fleet_size", 2, 40, 1, float(last.get("fleet_size", g.fleet_size)),
			func(v: float) -> String: return "%d boats" % int(v)))
		_add(MenuRow.choice("AI level", "ai_level", MenuData.AI_LEVELS, MenuData.AI_NAMES,
			last.get("ai_level", g.ai_level)))
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var modes := VenueWeather.modes(vi)
	var cd := VenueWeather.custom_defaults(vi)
	_add(MenuRow.choice(Strings.t("weather.label"), "weather", modes, _mode_names(modes),
		_pick(modes, str(last.get("weather", g.weather)))))
	_add(MenuRow.range_row(Strings.t("weather.wind_speed"), "wind_kn", 4, 25, 1,
		float(last.get("wind_kn", cd["kn"])), func(v: float) -> String: return "%d kn" % int(v)))
	_add(MenuRow.range_row(Strings.t("weather.wind_from"), "wind_from_deg", 0, 355, 5,
		float(last.get("wind_from_deg", cd["from_deg"])),
		func(v: float) -> String: return "%03d°  %s" % [int(v), _compass(v)]))
	_add(MenuRow.choice(Strings.t("weather.shifts"), "shift", VenueWeather.SHIFTS,
		VenueWeather.SHIFTS.map(func(s: String) -> String: return Strings.t("weather.shifts." + s)),
		_pick(VenueWeather.SHIFTS, str(last.get("shift", cd["shift"])))))
	_add(MenuRow.choice(Strings.t("weather.gusts"), "gusts", VenueWeather.GUSTS,
		VenueWeather.GUSTS.map(func(s: String) -> String: return Strings.t(VenueWeather.GUST_NAMES[s])),
		_pick(VenueWeather.GUSTS, str(last.get("gusts", cd["gusts"])))))
	rows["class_id"].changed.connect(func(_v: Variant) -> void: _refresh_courses())
	rows["class_id"].changed.connect(func(_v: Variant) -> void: _refresh_liveries())
	rows["venue"].changed.connect(func(_v: Variant) -> void: _venue_changed())
	rows["weather"].changed.connect(func(_v: Variant) -> void: _refresh_weather())
	if race:
		_build_preview()
		for k in rows:
			rows[k].changed.connect(func(_v: Variant) -> void: refresh_preview())
	# the footer: Start, always visible, and the reason it cannot start
	add_child(_gap(6))
	start_button = MenuTheme.button("Start race" if race else "Set sail")
	start_button.name = "Start"
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start_button.custom_minimum_size = Vector2(220, 0)
	MenuTheme.set_primary(start_button)
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	add_child(start_button)
	_note = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.SIGNAL)
	add_child(_note)
	start_button.focus_neighbor_bottom = start_button.get_path_to(start_button)
	_refresh_weather()
	_refresh_courses()
	resized.connect(_layout)
	_layout()


## Rows beside the preview, or the preview under the rows on a narrow page (menus.md §1.1).
func _layout() -> void:
	if body == null:
		return
	var narrow := size.x > 0.0 and size.x < TWO_COLUMNS_MIN
	if body.vertical != narrow:
		body.vertical = narrow


func _build_preview() -> void:
	var v := VBoxContainer.new()
	v.name = "Preview"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	body.add_child(v)
	_build_briefing(v)
	course_map = CourseMap.new()
	course_map.name = "CourseMap"
	v.add_child(course_map)
	course_text = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.INK, 600)
	course_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(course_text)
	v.add_child(MenuTheme.caps("Fleet", MenuTheme.SMALL_SIZE - 2, MenuTheme.MUTED))
	fleet_text = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.INK, 600)
	fleet_text.name = "FleetSummary"
	fleet_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fleet_text)


## The briefing box at the top of the preview column (menus.md §1.3): dark like the course map, the header in the
## card's heading style, the labels dim and the values in paper, one line each; the Tip may wrap.
func _build_briefing(parent: Control) -> void:
	briefing = PanelContainer.new()
	briefing.name = "Briefing"
	briefing.add_theme_stylebox_override("panel", MenuTheme.box(CourseMap.INK, 0, 2, Vector2(14, 10)))
	parent.add_child(briefing)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	briefing.add_child(v)
	briefing_header = MenuTheme.label("", MenuTheme.SMALL_SIZE + 2, CourseMap.PAPER, 700, MenuTheme.LABEL_TRACKING)
	briefing_header.name = "BriefingHeader"
	briefing_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(briefing_header)
	briefing_grid = GridContainer.new()
	briefing_grid.name = "BriefingLines"
	briefing_grid.columns = 2
	briefing_grid.add_theme_constant_override("h_separation", 14)
	briefing_grid.add_theme_constant_override("v_separation", 2)
	v.add_child(briefing_grid)


## The current Custom picks: {kn, from_deg, shift, gusts}.
func custom_picks() -> Dictionary:
	return {"kn": float(rows["wind_kn"].value), "from_deg": float(rows["wind_from_deg"].value),
		"shift": str(rows["shift"].value), "gusts": str(rows["gusts"].value)}


## The briefing for the rows (menus.md §1.3): the venue, the weather mode, the Custom picks and the course's timing.
func briefing_lines() -> Array:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	if vi.is_empty():
		return []
	return VenueWeather.lines(vi, str(rows["weather"].value), custom_picks(), VenueWeather.timing(_course_doc()))


func briefing_text() -> String:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	if vi.is_empty():
		return ""
	return VenueWeather.text(vi, str(rows["weather"].value), custom_picks(), VenueWeather.timing(_course_doc()))


func _course_doc() -> Dictionary:
	if not rows.has("course") or rows["course"].value == null:
		return {}
	var cid := str(rows["course"].value)
	return MenuData.course_file(cid) if rows["course"].choices.has(cid) else {}


func refresh_briefing() -> void:
	if briefing == null:
		return
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var mode := str(rows["weather"].value)
	briefing_header.visible = mode != "random" and not vi.is_empty()
	briefing_header.text = VenueWeather.header(vi) if not vi.is_empty() else ""
	for c in briefing_grid.get_children():
		briefing_grid.remove_child(c)
		c.queue_free()
	for l in briefing_lines():
		var k := MenuTheme.label(str(l[0]), MenuTheme.SMALL_SIZE, CourseMap.MIST, 500)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		briefing_grid.add_child(k)
		var val := MenuTheme.label(str(l[1]), MenuTheme.SMALL_SIZE, CourseMap.PAPER, 600)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size = Vector2(120, 0)
		briefing_grid.add_child(val)


## The wind the course map shows (menus.md §1.1): Local the venue's typical direction and the middle of its range,
## Custom the chosen values, Random the typical direction with no arrow; [from_deg, kn, shown].
func map_wind() -> Array:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var mode := str(rows["weather"].value)
	if mode == "custom" or vi.is_empty() or not vi.get("has_conditions", false):
		return [float(rows["wind_from_deg"].value), float(rows["wind_kn"].value), true]
	var c: Dictionary = vi["conditions"]
	var mid: float = 0.5 * (c["speed"][0] + c["speed"][1]) / VenueWeather.KNOT
	return [rad_to_deg(c["from"]), mid, mode == "local"]


## The course map, the briefing and the fleet summary from the rows (menus.md §1.1).
func refresh_preview() -> void:
	if course_map == null:
		return
	var c := _course_doc()
	var cid := str(rows["course"].value) if rows["course"].value != null else ""
	var mw := map_wind()
	course_map.show_course(c, mw[0], mw[1], mw[2])
	refresh_briefing()
	if c.is_empty():
		course_text.text = "No course"
	else:
		var ll := CourseMap.laps_legs(c)
		course_text.text = "%s\n%d %s, %d legs" % [str(c.get("name", cid)), ll.x, "lap" if ll.x == 1 else "laps", ll.y]
	fleet_text.text = fleet_summary()


## "10 boats: you and 9 AI\nIntermediate AI\nWindmark 7 Sportsboat"
func fleet_summary() -> String:
	var n := int(rows["fleet_size"].value)
	var lvl: String = MenuData.AI_NAMES[maxi(MenuData.AI_LEVELS.find(rows["ai_level"].value), 0)]
	return "%d boats: you and %d AI\n%s AI\n%s" % [n, n - 1, lvl,
		MenuData.name_of(_classes, str(rows["class_id"].value))]


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## `want` when the list has it, else the GameSetup default when the list has that (a remembered setup that no longer
## fits falls back to the defaults, menus.md §1), else the first.
static func _pick(ids: Array, want: String) -> String:
	if ids.has(want) or ids.is_empty():
		return want
	var d := GameSetup.new()
	for k in ["venue", "class_id", "weather", "shift", "gusts", "ai_level"]:
		if ids.has(str(d.get(k))):
			return str(d.get(k))
	return ids[0]


static func _mode_names(modes: Array) -> Array:
	return modes.map(func(m: String) -> String: return Strings.t("weather.mode." + m))


static func _compass(deg: float) -> String:
	var pts := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
	return pts[posmod(roundi(deg / 22.5), 16)]


func _add(r: MenuRow) -> void:
	rows[r.key] = r
	_rows_box.add_child(r)


## A new venue: its weather modes, and the Custom rows on its defaults (menus.md §1).
func _venue_changed() -> void:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var modes := VenueWeather.modes(vi)
	rows["weather"].set_choices(modes, _mode_names(modes))
	var cd := VenueWeather.custom_defaults(vi)
	rows["wind_kn"].set_value(cd["kn"])
	rows["wind_from_deg"].set_value(cd["from_deg"])
	rows["shift"].set_value(cd["shift"])
	rows["gusts"].set_value(cd["gusts"])
	_refresh_weather()
	_refresh_courses()


## The Custom rows show in Custom only; down from the last shown row is Start, up from Start that row (§1.1).
func _refresh_weather() -> void:
	var custom := str(rows["weather"].value) == "custom"
	for k in CUSTOM_ROWS:
		rows[k].visible = custom
	if start_button == null:
		return
	var last_row: MenuRow = null
	for r in _rows_box.get_children():
		if r is MenuRow and r.visible:
			r.focus_neighbor_bottom = NodePath()
			last_row = r
	if last_row != null:
		last_row.focus_neighbor_bottom = last_row.get_path_to(start_button)
		start_button.focus_neighbor_top = start_button.get_path_to(last_row)


## The last row shown above Start.
func last_row() -> MenuRow:
	var out: MenuRow = null
	for r in _rows_box.get_children():
		if r is MenuRow and r.visible:
			out = r
	return out


## The sail number list (the class's boats) follows the class (menus.md §1).
func _refresh_liveries() -> void:
	var lv := MenuData.liveries(str(rows["class_id"].value))
	rows["livery"].set_choices(MenuData.ids(lv), MenuData.names(lv))


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
	refresh_preview()


## Takes the remembered choices that fit (menus.md §1).
func load_from(last: Dictionary) -> void:
	if last.has("venue") and rows["venue"].choices.has(last["venue"]):
		rows["venue"].set_value(last["venue"])
		_venue_changed()
	for k in last:
		if rows.has(k) and k != "course" and k != "venue":
			var r: MenuRow = rows[k]
			if r.kind != MenuRow.Kind.CHOICE or r.choices.has(last[k]):
				r.set_value(last[k])
	_refresh_weather()
	_refresh_courses()
	if rows.has("course") and rows["course"].choices.has(last.get("course", "")):
		rows["course"].set_value(last["course"])
	refresh_preview()


func can_start() -> bool:
	return start_button != null and not start_button.disabled


func first_row() -> Control:
	return rows["class_id"]


## The chosen setup into `g` (menus.md §1).
func write(g: GameSetup) -> void:
	g.mode = mode
	g.class_id = str(rows["class_id"].value)
	g.livery = str(rows["livery"].value) if rows["livery"].value != null else ""
	g.venue = str(rows["venue"].value)
	if mode == "race":
		g.course = str(rows["course"].value)
		g.fleet_size = int(rows["fleet_size"].value)
		g.ai_level = str(rows["ai_level"].value)
	g.weather = str(rows["weather"].value)
	g.wind_kn = float(rows["wind_kn"].value)
	g.wind_from_deg = float(rows["wind_from_deg"].value)
	g.shift = str(rows["shift"].value)
	g.gusts = str(rows["gusts"].value)
	g.seed = 0


## The rows as GameSetup fields (remembered for the next visit).
func to_dict() -> Dictionary:
	var d := {}
	for k in rows:
		d[k] = rows[k].value
	return d
