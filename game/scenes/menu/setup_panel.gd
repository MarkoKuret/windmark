class_name SetupPanel
extends VBoxContainer
## The race and free sail setup (menus.md §1.1): one page walked in steps, Boat, Venue, Race, Start (free sail:
## Boat, Venue, Set sail), with a step bar as its header, the step's rows in a body that scrolls (the race card,
## briefing and course map or venue chart, beside them on the wide steps), and Back and the step's one primary
## action (Next, or Start race / Set sail on the last step) in a footer that does not. write() fills a GameSetup.
## The Weather row offers the venue's modes (Local, Random, Custom); the Custom rows (wind speed, wind from,
## shifts, gusts) show in Custom only. The Time and Sky rows (the light) follow them; with Random weather both show
## Surprise.

signal start_pressed
## Back on the first step: the page closes to the menu
signal closed
signal step_changed(step: int)
## the class or the sail number changed (the showcase boat of menus.md §4.1 follows)
signal boat_changed(class_id: String, livery: String)

## the preview goes under the rows when the page is narrower than this, logical px (menus.md §1.1)
const TWO_COLUMNS_MIN := 760.0
## the page's width on the Boat step (narrow, menus.md §1) and the most a wide page takes, logical px
const NARROW_W := 540.0
const WIDE_MAX := 980.0
## the steps of a race and of a free sail (menus.md §1.1), and their names on the step bar
const STEPS_RACE := ["boat", "venue", "race", "start"]
const STEPS_FREE := ["boat", "venue", "sail"]
const STEP_NAMES := {"boat": "Boat", "venue": "Venue", "race": "Race", "start": "Start", "sail": "Set sail"}
## the Custom weather rows, shown in Custom only (menus.md §1)
const CUSTOM_ROWS := ["wind_kn", "wind_from_deg", "shift", "gusts"]
## the light rows (menus.md §1): GameSetup.light_time (-1: the venue's) and light_conditions ("": the venue's)
const LIGHT_ROWS := ["light_time", "light_conditions"]
const SKY_CHOICES := ["", "clear", "fair", "hazy", "overcast"]
## the one value of both light rows with Random weather
const SURPRISE := "surprise"
## the rows of each step, in order (menus.md §1.1); the Custom rows follow the Weather row
const STEP_ROWS := {
	"boat": ["class_id", "livery"],
	"venue": ["venue", "course"],
	"race": ["fleet_size", "ai_level", "weather", "wind_kn", "wind_from_deg", "shift", "gusts", "light_time",
		"light_conditions"],
	"start": [],
	"sail": ["weather", "wind_kn", "wind_from_deg", "shift", "gusts", "light_time", "light_conditions"],
}

var mode := "race"
var rows := {}
## the steps of this mode and the one shown
var steps: Array = STEPS_RACE
var step := 0
## the footer: Back, Next (every step but the last) and Start race / Set sail (the last step)
var back_button: Button
var next_button: Button
var start_button: Button
## the step bar's buttons, one per step
var step_buttons: Array[Button] = []

## the race card's briefing (a race only, menus.md §1.3): its box, the header and the [label, value] lines
var briefing: PanelContainer
var briefing_header: Label
var briefing_grid: GridContainer
## the race card's preview: the course map (the venue chart on the Venue step) with its caption (laps and legs)
var course_map: CourseMap
## the Boat step's character line and key numbers, the Venue step's character line, the Start step's summary
var class_line: Label
var facts: GridContainer
var venue_line: Label
var summary: GridContainer
var body: BoxContainer
var scroll: ScrollContainer
var _note: Label
var _rows_box: VBoxContainer
var _preview: VBoxContainer
var _classes := []
var _venues := []
## the race seed the setup shows the briefing for and Start passes on (menus.md §1): drawn when it is built
var race_seed := 0
var _tide_cache := {}
## the light picks kept while Random shows Surprise (and remembered): light_time, light_conditions
var _light_keep := {"light_time": -1.0, "light_conditions": ""}
var _looks := {}
var _fact_values := {}


## `last`: the last setup (GameSetup fields) to start from.
func build(race: bool, last: Dictionary) -> void:
	mode = "race" if race else "free"
	steps = STEPS_RACE if race else STEPS_FREE
	name = "QuickRace" if race else "FreeSail"
	race_seed = draw_seed()
	add_theme_constant_override("separation", MenuTheme.LIST_GAP)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_step_bar()
	add_child(MenuTheme.gap(MenuTheme.SECTION_GAP - 2))
	scroll = ScrollContainer.new()
	scroll.name = "Body"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body = BoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL  # the chart grows into the room a tall window gives
	body.add_theme_constant_override("separation", 24)
	scroll.add_child(body)
	_rows_box = MenuTheme.list()
	_rows_box.name = "Rows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.size_flags_stretch_ratio = 1.4
	body.add_child(_rows_box)
	var g := GameSetup.new()
	_classes = MenuData.classes()
	_venues = MenuData.venues()
	var cls: String = last.get("class_id", g.class_id)
	var ven: String = last.get("venue", g.venue)
	# the Boat step: the class picker, its character and key numbers, the sail number (menus.md §1.1)
	_add(MenuRow.picker("class_id", MenuData.ids(_classes), MenuData.names(_classes),
		_pick(MenuData.ids(_classes), cls)))
	class_line = MenuTheme.label("", MenuTheme.ROW_SIZE - 2, MenuTheme.INK, 500)
	class_line.name = "ClassLine"
	class_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	class_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows_box.add_child(_padded(class_line, 6, 10))
	facts = GridContainer.new()
	facts.name = "Facts"
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 24)
	facts.add_theme_constant_override("v_separation", 10)
	for f in [["length", "Length"], ["sail_area", "Sail area"], ["crew", "Crew"], ["kite", "Kite"]]:
		var v := VBoxContainer.new()
		v.name = "Fact_" + f[0]
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.add_child(MenuTheme.caps(f[1], MenuTheme.SMALL_SIZE - 2, MenuTheme.MUTED))
		var val := MenuTheme.label("", MenuTheme.ROW_SIZE + 4, MenuTheme.NAVY, 600)
		val.name = "Value"
		v.add_child(val)
		_fact_values[f[0]] = val
		facts.add_child(v)
	_rows_box.add_child(_padded(facts, 4, 14))
	var lv := MenuData.liveries(str(rows["class_id"].value))
	# the player's boat: sail number and name (menus.md §1; every boat wears the class livery)
	_add(MenuRow.choice("Sail number", "livery", MenuData.ids(lv), MenuData.names(lv),
		_pick(MenuData.ids(lv), str(last.get("livery", g.livery)))))
	# the Venue step: the venue picker, its character, the course (menus.md §1.1)
	_add(MenuRow.picker("venue", MenuData.ids(_venues), MenuData.names(_venues), _pick(MenuData.ids(_venues), ven)))
	venue_line = MenuTheme.label("", MenuTheme.ROW_SIZE - 2, MenuTheme.INK, 500)
	venue_line.name = "VenueLine"
	venue_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	venue_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows_box.add_child(_padded(venue_line, 6, 14))
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
	_light_keep = light_from(last, str(rows["venue"].value), "local")
	var tv := time_choices(str(rows["venue"].value))
	_add(MenuRow.choice(Strings.t("light.time"), "light_time", tv, time_names(tv), _light_keep["light_time"]))
	_add(MenuRow.choice(Strings.t("light.sky"), "light_conditions", SKY_CHOICES, sky_names(),
		_light_keep["light_conditions"]))
	for k in LIGHT_ROWS:
		var key: String = k
		rows[key].changed.connect(func(v: Variant) -> void:
			if typeof(v) != TYPE_STRING or v != SURPRISE:
				_light_keep[key] = v)
	# the Start step's summary (menus.md §1.1)
	summary = GridContainer.new()
	summary.name = "Summary"
	summary.columns = 2
	summary.add_theme_constant_override("h_separation", 16)
	summary.add_theme_constant_override("v_separation", 8)
	_rows_box.add_child(_padded(summary, 8, 8))
	rows["class_id"].changed.connect(func(_v: Variant) -> void: _class_changed())
	rows["livery"].changed.connect(func(_v: Variant) -> void:
		boat_changed.emit(str(rows["class_id"].value), str(rows["livery"].value)))
	rows["venue"].changed.connect(func(_v: Variant) -> void: _venue_changed())
	rows["weather"].changed.connect(func(_v: Variant) -> void: _refresh_weather())
	for k in ["class_id", "venue"]:
		rows[k].accepted.connect(next)
	_build_preview(race)
	for k in rows:
		rows[k].changed.connect(func(_v: Variant) -> void: refresh_preview())
	# the footer (menus.md §1.1, §4): Back on the left, Next or the start on the right, and under it the reason
	# the player cannot go on
	add_child(MenuTheme.gap())
	back_button = MenuTheme.button("Back", MenuTheme.ACTION_SIZE)
	back_button.name = "Back"
	back_button.custom_minimum_size = Vector2(130, MenuTheme.ITEM_H)
	back_button.pressed.connect(back)
	next_button = MenuTheme.button("Next", MenuTheme.ITEM_SIZE)
	next_button.name = "Next"
	next_button.custom_minimum_size = Vector2(220, MenuTheme.ITEM_H)
	next_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuTheme.set_primary(next_button)
	next_button.pressed.connect(next)
	start_button = MenuTheme.button("Start race" if race else "Set sail", MenuTheme.ITEM_SIZE)
	start_button.name = "Start"
	start_button.custom_minimum_size = Vector2(280, MenuTheme.ITEM_H)
	start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuTheme.set_primary(start_button)
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	add_child(MenuTheme.footer([back_button], [next_button, start_button]))
	_note = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.SIGNAL)
	_note.name = "Note"
	add_child(_note)
	for b in [next_button, start_button]:
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(back_button)
		b.focus_neighbor_right = b.get_path_to(b)
	back_button.focus_neighbor_bottom = back_button.get_path_to(back_button)
	back_button.focus_neighbor_left = back_button.get_path_to(back_button)
	_refresh_class()
	venue_line.text = MenuData.venue_line(str(rows["venue"].value))
	_refresh_weather()
	_refresh_courses()
	resized.connect(_layout)
	_rows_box.minimum_size_changed.connect(_fit_height)
	_layout()
	go(0)


## The step bar (menus.md §1.1): `1 BOAT  2 VENUE  3 RACE  4 START`, the current step on a yellow bar, the steps done
## navy (a click goes back to one), the steps ahead muted.
func _build_step_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Steps"
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	for i in steps.size():
		var b := Button.new()
		b.name = "Step_" + steps[i]
		b.text = "%d  %s" % [i + 1, String(STEP_NAMES[steps[i]]).to_upper()]
		b.add_theme_font_override("font", MenuTheme.font(600, MenuTheme.LABEL_TRACKING, MenuTheme.SMALL_SIZE + 2))
		b.add_theme_font_size_override("font_size", MenuTheme.SMALL_SIZE + 2)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		var at := i
		b.pressed.connect(func() -> void:
			if at < step:
				go(at)
				first_row().grab_focus())
		bar.add_child(b)
		step_buttons.append(b)


func _style_steps() -> void:
	for i in step_buttons.size():
		var b := step_buttons[i]
		var pad := Vector2(12, 4)
		var on := i == step
		var done := i < step
		var fill := MenuTheme.ACCENT if on else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", MenuTheme.box(fill, 0, 2, pad))
		b.add_theme_stylebox_override("hover", MenuTheme.box(fill if on else (MenuTheme.HOVER_FILL if done
			else Color(0, 0, 0, 0)), 0, 2, pad))
		b.add_theme_stylebox_override("pressed", MenuTheme.box(fill, 0, 2, pad))
		b.add_theme_stylebox_override("disabled", MenuTheme.box(fill, 0, 2, pad))
		var col := MenuTheme.NAVY if (on or done) else Color(MenuTheme.MUTED, 0.8)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
				"font_disabled_color"]:
			b.add_theme_color_override(c, col)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if done else Control.CURSOR_ARROW


## The step shown: its id (menus.md §1.1).
func step_id() -> String:
	return steps[step]


func is_last_step() -> bool:
	return step == steps.size() - 1


## The page's width on this step: narrow on the Boat step (the stage shows the boat), wide otherwise (menus.md §1).
func narrow_page() -> bool:
	return step_id() == "boat"


## Shows a step: its rows, the preview beside them, the footer's primary action.
func go(i: int) -> void:
	step = clampi(i, 0, steps.size() - 1)
	var id := step_id()
	var shown: Array = STEP_ROWS[id]
	for k in rows:
		rows[k].visible = shown.has(k)
	class_line.get_parent().visible = id == "boat"
	facts.get_parent().visible = id == "boat"
	venue_line.get_parent().visible = id == "venue"
	summary.get_parent().visible = id in ["start", "sail"]
	_preview.visible = id != "boat"
	# the venue chart takes more of the page on the Venue step; the Boat step's page hugs its content
	var chart := id in ["venue", "sail"]
	_rows_box.size_flags_stretch_ratio = 1.15 if chart else 1.4
	_preview.size_flags_stretch_ratio = 1.0
	course_map.custom_minimum_size = Vector2(300, 300 if chart else 220)
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if narrow_page() else Control.SIZE_EXPAND_FILL
	size_flags_vertical = scroll.size_flags_vertical
	_fit_height()
	next_button.visible = not is_last_step()
	start_button.visible = is_last_step()
	_style_steps()
	_refresh_weather()
	_refresh_courses()
	refresh_preview()
	refresh_summary()
	scroll.scroll_vertical = 0
	step_changed.emit(step)


## On the narrow Boat step the body is as tall as its rows (the page hugs its content, menus.md §1); the other
## steps fill the page and scroll.
func _fit_height() -> void:
	if not narrow_page() or scroll == null:
		return
	var h := _rows_box.get_combined_minimum_size().y
	if absf(scroll.custom_minimum_size.y - h) > 0.5:
		scroll.custom_minimum_size = Vector2(0, h)


## The focus for the step: the picker, the first row, or the primary action when the step has no row (Start).
func first_row() -> Control:
	for r in _rows_box.get_children():
		if r is MenuRow and r.visible:
			return r
	return primary()


## The step's primary action: Next, or Start race / Set sail on the last step.
func primary() -> Button:
	return start_button if is_last_step() else next_button


## Next (menus.md §1.1): the next step, when the player can go on.
func next() -> void:
	if is_last_step():
		if can_start():
			start_pressed.emit()
		return
	if next_button.disabled:
		return
	go(step + 1)
	first_row().grab_focus()


## Back (menus.md §1.1): the step before, or the menu from the first.
func back() -> void:
	if step == 0:
		closed.emit()
		return
	go(step - 1)
	first_row().grab_focus()


## Rows beside the preview, or the preview under the rows on a narrow page (menus.md §1.1).
func _layout() -> void:
	if body == null:
		return
	var narrow := size.x > 0.0 and size.x < TWO_COLUMNS_MIN
	if body.vertical != narrow:
		body.vertical = narrow


func _build_preview(race: bool) -> void:
	_preview = VBoxContainer.new()
	_preview.name = "Preview"
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.add_theme_constant_override("separation", 6)
	body.add_child(_preview)
	if race:
		_build_briefing(_preview)
	course_map = CourseMap.new()
	course_map.name = "CourseMap"
	course_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.add_child(course_map)


## The briefing box at the top of the preview column (menus.md §1.3): dark like the course map, the header in the
## page's heading style, the labels dim and the values in paper, one line each; the Tip may wrap.
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


## The Time row's values for a venue (menus.md §1): -1 (Venue default), then its race window in 30 min steps.
static func time_choices(venue: String) -> Array:
	var w := VenueLook.load_venue(venue).race_window
	var out: Array = [-1.0]
	var n := int(floor((w.y - w.x) / VenueLook.RANDOM_STEP_H + 1e-6))
	for i in n + 1:
		out.append(w.x + VenueLook.RANDOM_STEP_H * i)
	return out


static func time_names(vals: Array) -> Array:
	return vals.map(func(h: float) -> String:
		return Strings.t("light.venue_default") if h < 0.0 else Daylight.hour_text(h))


static func sky_names() -> Array:
	return SKY_CHOICES.map(func(c: String) -> String:
		return Strings.t("light.venue_default") if c == "" else Strings.t("light.sky." + c))


## The light picks of a remembered setup on a venue, as {light_time, light_conditions}: a time the venue's window
## lacks, or unknown conditions, give the venue's (-1, ""); Random weather always the venue's (the seed decides).
static func light_from(last: Dictionary, venue: String, weather: String) -> Dictionary:
	var out := {"light_time": -1.0, "light_conditions": ""}
	if weather == "random":
		return out
	var lt: Variant = last.get("light_time", -1.0)
	if typeof(lt) in [TYPE_INT, TYPE_FLOAT]:
		for h in time_choices(venue):
			if absf(float(h) - float(lt)) < 1e-4:
				out["light_time"] = h
	var lc := str(last.get("light_conditions", ""))
	if SKY_CHOICES.has(lc):
		out["light_conditions"] = lc
	return out


## The light the race will have (the briefing's Light line): {hour, conditions}, the venue's for Venue default.
func light_resolved() -> Dictionary:
	var venue := str(rows["venue"].value)
	if not _looks.has(venue):
		_looks[venue] = VenueLook.load_venue(venue)
	var look: VenueLook = _looks[venue]
	var h := float(_light_keep["light_time"])
	var c := str(_light_keep["light_conditions"])
	return {"hour": h if h >= 0.0 else look.time, "conditions": c if c != "" else look.conditions}


## The Time and Sky rows: Surprise with Random weather, else the venue's list with the kept picks (a time the
## venue's window lacks: Venue default).
func _refresh_light() -> void:
	if not rows.has("light_time"):
		return
	if str(rows["weather"].value) == "random":
		for k in LIGHT_ROWS:
			rows[k].set_choices([SURPRISE], [Strings.t("light.surprise")])
			rows[k].set_value(SURPRISE)
		return
	var tv := time_choices(str(rows["venue"].value))
	_light_keep = light_from(_light_keep, str(rows["venue"].value), "local")
	rows["light_time"].set_choices(tv, time_names(tv))
	rows["light_time"].set_value(_light_keep["light_time"])
	rows["light_conditions"].set_choices(SKY_CHOICES, sky_names())
	rows["light_conditions"].set_value(_light_keep["light_conditions"])


## The current Custom picks: {kn, from_deg, shift, gusts}.
func custom_picks() -> Dictionary:
	return {"kn": float(rows["wind_kn"].value), "from_deg": float(rows["wind_from_deg"].value),
		"shift": str(rows["shift"].value), "gusts": str(rows["gusts"].value)}


## A new non-zero race seed from the clock (menus.md §1).
static func draw_seed() -> int:
	return 1 + (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0)) % 2000000000


## The briefing for the rows (menus.md §1.3): the venue, the weather mode, the Custom picks, the course's timing and,
## at a tidal venue, the tide the setup's race seed gives at the start signal.
func briefing_lines() -> Array:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	if vi.is_empty():
		return []
	var wmode := str(rows["weather"].value)
	var out := VenueWeather.lines(vi, wmode, custom_picks(), _timing(vi))
	if wmode == "random" or not rows.has("light_time"):
		return out
	# the Light line, before the Tip
	var li := light_resolved()
	var line := [Strings.t("briefing.label.light"), Strings.t("briefing.line.light",
		{"time": Daylight.hour_text(li["hour"]), "sky": Strings.t("briefing.sky." + str(li["conditions"]))})]
	var at := out.size()
	if at > 0 and out[at - 1][0] == Strings.t("briefing.label.tip"):
		at -= 1
	out.insert(at, line)
	return out


## The briefing as text, the header then one line per entry, label and value separated by a tab (tests).
func briefing_text() -> String:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	if vi.is_empty():
		return ""
	var parts := PackedStringArray()
	if str(rows["weather"].value) != "random":
		parts.append(VenueWeather.header(vi))
	for l in briefing_lines():
		parts.append("%s\t%s" % [l[0], l[1]])
	return "\n".join(parts)


func _timing(vi: Dictionary) -> Dictionary:
	var tm := VenueWeather.timing(_course_doc())
	if vi.get("conditions", {}).get("tide", {}).is_empty():
		return tm
	var venue := str(rows["venue"].value)
	var course := str(rows["course"].value) if mode == "race" and not _course_doc().is_empty() else ""
	var key := "%s|%s|%d" % [venue, course, race_seed]
	if not _tide_cache.has(key):
		# the tide's phase is the same in Local and Custom (race.md §2.1): resolve Local for the setup's seed
		var r := CoreSimSource.resolve_settings({"race_seed": race_seed, "weather": 0}, venue, course)
		_tide_cache[key] = null if r.is_empty() else VenueWeather.tide_at_gun(r, float(tm["t_gun"]))
	if _tide_cache[key] != null:
		tm["tide_factor"] = _tide_cache[key]
	return tm


func _course_doc() -> Dictionary:
	if not rows.has("course") or rows["course"].value == null:
		return {}
	var cid := str(rows["course"].value)
	return MenuData.course_file(cid) if rows["course"].choices.has(cid) else {}


func refresh_briefing() -> void:
	if briefing == null:
		return
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var wmode := str(rows["weather"].value)
	briefing_header.visible = wmode != "random" and not vi.is_empty()
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


## The wind the course map shows (menus.md §1.1.1): Local the venue's typical direction and the middle of its
## range, Custom the chosen values, Random the typical direction with no arrow; [from_deg, kn, shown].
func map_wind() -> Array:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	var wmode := str(rows["weather"].value)
	if wmode == "custom" or vi.is_empty() or not vi.get("has_conditions", false):
		return [float(rows["wind_from_deg"].value), float(rows["wind_kn"].value), true]
	var c: Dictionary = vi["conditions"]
	var mid: float = 0.5 * (c["speed"][0] + c["speed"][1]) / VenueWeather.KNOT
	return [rad_to_deg(c["from"]), mid, wmode == "local"]


## Whether the map shows the venue chart (the venue's extent and land, menus.md §1.1.1): the Venue step and the
## free sail's last step; the course's extent on the Race and Start steps.
func venue_chart() -> bool:
	return step_id() in ["venue", "sail"]


## The course map (or the venue chart), its caption and the briefing from the rows (menus.md §1.1.1).
func refresh_preview() -> void:
	if course_map == null:
		return
	var c := _course_doc()
	var mw := map_wind()
	var shapes := MenuData.venue_shapes(str(rows["venue"].value))
	course_map.caption = course_caption()
	course_map.show_course(c, mw[0], mw[1], mw[2], shapes["land"], shapes["bounds"] if venue_chart() else Rect2())
	refresh_briefing()


## The map's caption: the course's laps and legs (`2 laps, 6 legs`), "" without a course.
func course_caption() -> String:
	var c := _course_doc()
	if c.is_empty():
		return ""
	var ll := CourseMap.laps_legs(c)
	return "%d %s, %d legs" % [ll.x, "lap" if ll.x == 1 else "laps", ll.y]


## The Start step's summary lines (menus.md §1.1), [label, value].
func summary_lines() -> Array:
	var out := []
	var cls := MenuData.name_of(_classes, str(rows["class_id"].value))
	var boat := str(rows["livery"].value_text()).strip_edges() if rows["livery"].value != null else ""
	out.append(["Boat", "%s · %s" % [cls, boat] if boat != "" else cls])
	out.append(["Venue", MenuData.name_of(_venues, str(rows["venue"].value))])
	if mode == "race":
		out.append(["Course", rows["course"].value_text() if not _course_doc().is_empty() else "None"])
		out.append(["Fleet", "%s · %s" % [rows["fleet_size"].value_text(), rows["ai_level"].value_text()]])
	var wmode := str(rows["weather"].value)
	var w: String = rows["weather"].value_text()
	if wmode == "custom":
		var gusts: String = Strings.t("results.today.no_gusts") if str(rows["gusts"].value) == "none" \
			else Strings.t("results.today.gusts", {"word": rows["gusts"].value_text()})
		w = "%s · %d kn from the %s · %s · %s" % [w, int(rows["wind_kn"].value),
			_compass(float(rows["wind_from_deg"].value)), rows["shift"].value_text(), gusts]
	out.append([Strings.t("weather.label"), w])
	var light: String = Strings.t("light.surprise")
	if wmode != "random":
		var h := float(_light_keep["light_time"])
		var sky := str(_light_keep["light_conditions"])
		if h < 0.0 and sky == "":
			light = Strings.t("light.venue_default")
		else:
			var sky_t: String = Strings.t("light.sky." + sky) if sky != "" else Strings.t("light.venue_default")
			light = "%s, %s" % [Daylight.hour_text(h) if h >= 0.0 else Strings.t("light.venue_default"),
				sky_t.to_lower()]
	out.append(["Light", light])
	return out


func refresh_summary() -> void:
	if summary == null or not summary.get_parent().visible:
		return
	for c in summary.get_children():
		summary.remove_child(c)
		c.queue_free()
	for l in summary_lines():
		var k := MenuTheme.caps(str(l[0]), MenuTheme.SMALL_SIZE - 1, MenuTheme.MUTED)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		k.custom_minimum_size = Vector2(90, 0)
		summary.add_child(k)
		var v := MenuTheme.label(str(l[1]), MenuTheme.ROW_SIZE, MenuTheme.NAVY, 600)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_child(v)


## `c` with a margin above and below (and the row's side padding).
static func _padded(c: Control, top: float, bottom: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.name = c.name + "Pad"
	m.add_theme_constant_override("margin_top", int(top))
	m.add_theme_constant_override("margin_bottom", int(bottom))
	m.add_theme_constant_override("margin_left", int(MenuTheme.ROW_PAD.x))
	m.add_theme_constant_override("margin_right", int(MenuTheme.ROW_PAD.x))
	m.add_child(c)
	return m


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


## A new class (menus.md §1.1): its character and numbers, its boats, its courses; the showcase boat follows.
func _class_changed() -> void:
	_refresh_class()
	_refresh_liveries()
	_refresh_courses()
	boat_changed.emit(str(rows["class_id"].value), str(rows["livery"].value))


## The Boat step's character line and key numbers (menus.md §1.1) for the chosen class.
func _refresh_class() -> void:
	var id := str(rows["class_id"].value)
	class_line.text = MenuData.class_line(id)
	var f := MenuData.class_facts(id)
	_fact_values["length"].text = "%.1f m" % f["loa"]
	_fact_values["sail_area"].text = "%d m²" % roundi(f["sail_area"])
	_fact_values["crew"].text = str(f["crew"])
	if f["kite"] == "":
		_fact_values["kite"].text = "None"
	else:
		_fact_values["kite"].text = "%s %d m²" % ["Asymmetric" if f["kite"] == "asym" else "Symmetric",
			roundi(f["kite_area"])]


## A new venue: its character, its weather modes, and the Custom rows on its defaults (menus.md §1).
func _venue_changed() -> void:
	var vi := MenuData.venue_info(str(rows["venue"].value))
	venue_line.text = MenuData.venue_line(str(rows["venue"].value))
	var modes := VenueWeather.modes(vi)
	rows["weather"].set_choices(modes, _mode_names(modes))
	var cd := VenueWeather.custom_defaults(vi)
	rows["wind_kn"].set_value(cd["kn"])
	rows["wind_from_deg"].set_value(cd["from_deg"])
	rows["shift"].set_value(cd["shift"])
	rows["gusts"].set_value(cd["gusts"])
	_refresh_weather()
	_refresh_courses()


## The Custom rows show in Custom (on the steps that have them); down from the last shown row is the primary
## action, up from it that row (menus.md §1.1).
func _refresh_weather() -> void:
	var custom := str(rows["weather"].value) == "custom"
	var shown: Array = STEP_ROWS[step_id()]
	for k in CUSTOM_ROWS:
		rows[k].visible = custom and shown.has(k)
	_refresh_light()
	if start_button == null:
		return
	var first: MenuRow = null
	var last_r: MenuRow = null
	for r in _rows_box.get_children():
		if r is MenuRow and r.visible:
			r.focus_neighbor_bottom = NodePath()
			r.focus_neighbor_top = NodePath()
			if first == null:
				first = r
			last_r = r
	var p := primary()
	if first != null:
		first.focus_neighbor_top = first.get_path_to(first)
	if last_r != null:
		last_r.focus_neighbor_bottom = last_r.get_path_to(p)
		p.focus_neighbor_top = p.get_path_to(last_r)
		back_button.focus_neighbor_top = back_button.get_path_to(last_r)
	else:
		p.focus_neighbor_top = p.get_path_to(p)
		back_button.focus_neighbor_top = back_button.get_path_to(back_button)
	back_button.focus_neighbor_right = back_button.get_path_to(p)


## The last row shown above the footer.
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
		var blocked := list.is_empty()
		start_button.disabled = blocked
		start_button.focus_mode = Control.FOCUS_NONE if blocked else Control.FOCUS_ALL
		# Next stops on the Venue step until a course fits (menus.md §1.1)
		var stop := blocked and step_id() == "venue"
		next_button.disabled = stop
		next_button.focus_mode = Control.FOCUS_NONE if stop else Control.FOCUS_ALL
		_note.text = "This venue has no course for this boat yet." if blocked and step_id() != "boat" else ""
	refresh_preview()


## Takes the remembered choices that fit (menus.md §1).
func load_from(last: Dictionary) -> void:
	if last.has("venue") and rows["venue"].choices.has(last["venue"]):
		rows["venue"].set_value(last["venue"])
		_venue_changed()
	_light_keep = light_from(last, str(rows["venue"].value), "local")
	for k in last:
		if rows.has(k) and k != "course" and k != "venue" and not LIGHT_ROWS.has(k):
			var r: MenuRow = rows[k]
			if r.kind != MenuRow.Kind.CHOICE or r.choices.has(last[k]):
				r.set_value(last[k])
	_refresh_class()
	venue_line.text = MenuData.venue_line(str(rows["venue"].value))
	_refresh_liveries()
	if last.has("livery") and rows["livery"].choices.has(last["livery"]):
		rows["livery"].set_value(last["livery"])
	_refresh_weather()
	_refresh_courses()
	if rows.has("course") and rows["course"].choices.has(last.get("course", "")):
		rows["course"].set_value(last["course"])
	refresh_preview()


func can_start() -> bool:
	return start_button != null and not start_button.disabled


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
	# the light: the picks, or the venue's (-1, "") for Venue default and with Random weather (the seed decides)
	var random := g.weather == "random"
	g.light_time = -1.0 if random else float(_light_keep["light_time"])
	g.light_conditions = "" if random else str(_light_keep["light_conditions"])
	g.seed = race_seed  # the seed the briefing was computed for
	race_seed = draw_seed()  # the next start from this setup is another race
	_tide_cache.clear()


## The rows as GameSetup fields (remembered for the next visit).
func to_dict() -> Dictionary:
	var d := {}
	for k in rows:
		d[k] = rows[k].value
	for k in LIGHT_ROWS:
		d[k] = _light_keep[k]  # the picks, not Surprise
	return d
