class_name ResultsScreen
extends CanvasLayer
## The results screen of a quick race (menus.md §5, hud.md §13): over the live sail scene once the player's race is
## over and the finish card has run (RaceHudValues.results_due). The title in the logo's styles (a Wordmark with the
## place and the result in words), and a cloth panel with the results table (the player's row in the accent), the
## live finishing rows until the race closes, the player's race summary (hud.md §13.3) and the actions: Race again
## (this setup, a new seed), Change setup (the main menu's race card with this setup) and Main menu. The panel sits
## beside the title, or under it in a narrow or portrait window; table and summary scroll, heading and footer do
## not. It fades in; the scene changes fade (SceneFade). The pause menu opens over it as in the race.
##
## Under the summary one line from the race history (menus.md §5 Best line, §6): her best on this course and class,
## a new best, or a first race here. The player's result goes into the history once (menus.md §5 Recording): when the
## results are final, or from her row as it stands when she leaves the screen before that; never after an abandoned
## race.
##
## A child of the sail scene (`host`, duck typed: hud, rig, runner, session_setup(), venue, course, class_id); with
## `act` off (tests) the actions do everything but change the scene.

signal action_requested(action: String)

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
const SAIL_SCENE := "res://scenes/sail_test.tscn"
const FADE_IN_S := 0.5
## narrower than this (logical px) the panel goes under the title (menus.md §5)
const NARROW := 1100.0
const MARGIN := MenuTheme.MARGIN
## the panel's width beside the title, px
const PANEL_W := 760.0
## the table's columns: header, width (0: takes the rest, at least BOAT_MIN), right-aligned
const COLUMNS := [["Place", 40, true], ["Sail", 48, true], ["Boat", 0, false], ["Skipper", 140, false],
	["Time", 140, true], ["Gap", 56, true], ["Code", 46, false], ["Points", 50, true]]
const BOAT_MIN := 100.0
const CELL_SIZE := 18
const HEAD_SIZE := 13
const SCROLL_STEP := 48

## tests: false keeps the actions from changing the scene (action_requested still fires, the setup is written)
var act := true
var host: Node
var is_open := false
var buttons := {}
## the title lockup (the place and the result in words)
var title: Wordmark
var heading_label: Label
var line_label: Label
## after a Random race, the conditions it had (menus.md §5): `Today: 18 kn from the SW · Shifty · Very strong gusts`
var today_label: Label
var summary_box: GridContainer
var summary_heading: Label
## the best line under the summary (menus.md §5), hidden when there is nothing to say
var best_label: Label
## the race history as it was before this race (read when the screen opens), and whether this race is recorded
var history: RaceHistory
var recorded := false
## the history file ("": RaceHistory.path)
var history_path := ""
var table: VBoxContainer
## the table's rows as shown: [[cells...], ...] (tests), and the index of the player's row (-1 none)
var shown_rows: Array = []
var own_row := -1
var wide := true

var _root: Control
var _margin: MarginContainer
var _body: VBoxContainer
var _row: BoxContainer
var _left: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer
var _footer: HBoxContainer
var _fade_t := 0.0
var _sig := ""
var _sum_sig := ""
var _last_focus: Control
var _hud_was := true
## the menu sounds (menus.md §4), heard while the screen is open
var sounds: MenuSounds


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	if host == null:
		host = get_parent()
	_root = Control.new()
	_root.name = "Root"
	_root.theme = MenuTheme.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(MenuTheme.SEA_DEEP, 0.22)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	_root.add_child(margin)
	_row = BoxContainer.new()
	_row.add_theme_constant_override("separation", 24)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_row)
	_left = VBoxContainer.new()
	_left.name = "Left"
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_left)
	title = Wordmark.new()
	title.name = "Title"
	title.text = "RESULTS"
	title.tagline_text = ""
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left.add_child(title)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_row.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := MenuTheme.heading("Results")
	heading_label = head.get_child(0) as Label
	col.add_child(head)
	line_label = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, 500)
	line_label.name = "Line"
	col.add_child(line_label)
	today_label = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, 500)
	today_label.name = "Today"
	today_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	today_label.visible = false
	col.add_child(today_label)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = false
	col.add_child(_scroll)
	var body := VBoxContainer.new()
	_body = body
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_scroll.add_child(body)
	table = VBoxContainer.new()
	table.name = "Table"
	table.add_theme_constant_override("separation", 0)
	body.add_child(table)
	summary_heading = MenuTheme.subheading("Your race")
	summary_heading.name = "SummaryHeading"
	body.add_child(summary_heading)
	summary_box = GridContainer.new()
	summary_box.name = "Summary"
	summary_box.columns = 2
	summary_box.add_theme_constant_override("h_separation", 18)
	summary_box.add_theme_constant_override("v_separation", 4)
	body.add_child(summary_box)
	best_label = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, 500)
	best_label.name = "Best"
	best_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	best_label.visible = false
	body.add_child(best_label)
	# the footer (menus.md §5): no way back here, so the actions run from the primary, Race again, on the left
	var actions := []
	for e in [["again", "Race again"], ["setup", "Change setup"], ["menu", "Main menu"]]:
		var b := MenuTheme.button(e[1], MenuTheme.ACTION_SIZE)
		b.name = e[1].replace(" ", "")
		var id: String = e[0]
		b.pressed.connect(func() -> void: press(id))
		b.focus_entered.connect(func() -> void: _last_focus = b)
		actions.append(b)
		buttons[id] = b
	MenuTheme.set_primary(buttons["again"])
	col.add_child(MenuTheme.gap(MenuTheme.SECTION_GAP - 6))
	_footer = MenuTheme.footer(actions, [])
	col.add_child(_footer)
	_root.visible = false
	sounds = MenuSounds.new()
	sounds.name = "Sounds"
	sounds.active = false
	add_child(sounds)
	_fit()
	get_viewport().size_changed.connect(_fit)


func _race() -> RaceHudValues:
	var h: Variant = host.get("hud") if host != null else null
	return (h as Hud).race if h is Hud else null


func _process(dt: float) -> void:
	var r := _race()
	if r == null:
		return
	if not is_open:
		if r.results_due():
			open()
		return
	_fade_t += dt
	_root.modulate.a = clampf(_fade_t / FADE_IN_S, 0.0, 1.0)
	refresh()
	if not _pause_open():
		var fo := get_viewport().gui_get_focus_owner()
		if fo == null or not _root.is_ancestor_of(fo):
			(_last_focus if _last_focus != null else buttons["again"] as Control).grab_focus()


## the host's pause menu is open (its runner paused)
func _pause_open() -> bool:
	var rn: Variant = host.get("runner") if host != null else null
	return rn is SimRunner and (rn as SimRunner).paused


## Shows the screen (fading in), hides the HUD, frames the boat clear of the panel, focuses Race again.
func open() -> void:
	if is_open:
		return
	is_open = true
	_fade_t = 0.0
	_root.modulate.a = 0.0
	_root.visible = true
	var h: Variant = host.get("hud")
	if h is CanvasItem:
		_hud_was = (h as CanvasItem).visible
		(h as CanvasItem).visible = false
	_fit()
	history = RaceHistory.load_from(history_path)
	refresh()
	sounds.active = true
	sounds.quiet_next_focus()
	buttons["again"].grab_focus.call_deferred()


# ---- content ----

## The title's words (menus.md §5): [title, tagline]
func title_words() -> Array:
	var r := _race()
	if r == null:
		return ["RESULTS", ""]
	var row := _own()
	match r.end_reason:
		"finished":
			var place := int(row.get("place", 0))
			var t := HudFormat.finish_time(float(row.get("time", NAN))) if not is_nan(float(row.get("time", NAN))) else ""
			if place == 1:
				return ["1ST", "WINNER  %s" % t]
			if place > 0:
				var g := float(row.get("gap", NAN))
				return [RaceText.ordinal(place).to_upper(),
					("FINISHED  %s  %s" % [t, HudFormat.gap(g) if not is_nan(g) else ""]).strip_edges()]
			var code := str(row.get("code", ""))
			return [code if code != "" else "OCS", "FINISHED, SCORED %s" % (code if code != "" else "OCS")]
		"retired":
			return ["RET", "RETIRED"]
		"dsq", "ghost":
			var c := str(row.get("code", ""))
			if c == "DNS":
				return [c, "DID NOT START"]
			if c == "DNC":
				return [c, "DID NOT COMPETE"]
			return [c if c != "" else "DSQ", "DISQUALIFIED"]
		"dnf":
			return ["DNF", "DID NOT FINISH"]
		"abandoned":
			return ["NO RACE", "RACE ABANDONED"]
	return ["RESULTS", ""]


func _own() -> Dictionary:
	var r := _race()
	if r == null:
		return {}
	for row in r.result_rows:
		if int(row["boat"]) == r.own_boat:
			return row
	return {}


## The best line under the summary (menus.md §5) from the history before this race; "" without one or after an
## abandoned race.
func best_text() -> String:
	var r := _race()
	if r == null or history == null or host == null or _abandoned():
		return ""
	var row := _own()
	var place := int(row.get("place", 0))
	var t := float(row.get("time", NAN))
	if str(row.get("code", "")) != "" or bool(row.get("projected", false)):
		place = 0
	return history.best_line(str(host.get("course")), str(host.get("class_id")), place, t)


func _abandoned() -> bool:
	var r := _race()
	return r != null and (r.state == RaceText.RaceState.ABANDONED or r.end_reason == "abandoned")


## This race's result as a history entry (menus.md §6), from her row and the session; {} when there is nothing to
## record (no race, not open, an abandoned race).
func history_entry() -> Dictionary:
	var r := _race()
	if r == null or host == null or not is_open or _abandoned():
		return {}
	var row := _own()
	if row.is_empty():
		return {}
	var code := str(row.get("code", ""))
	if code == "":
		code = {"retired": "RET", "dnf": "DNF", "dsq": "DSQ", "ghost": "DSQ"}.get(r.end_reason, "")
	var place := int(row.get("place", 0)) if code == "" else 0
	var t := float(row.get("time", NAN)) if place > 0 else NAN
	var g := float(row.get("gap", NAN)) if place > 0 else NAN
	var s: GameSetup = host.call("session_setup")
	return RaceHistory.entry(s.class_id, s.venue, s.course, r.result_rows.size(), s.ai_level,
		s.weather if s.weather != "" else "custom", place, code, t, 0.0 if place == 1 else g)


## Writes this race into the history once (menus.md §5 Recording): at the close, or when she leaves before it.
func record() -> void:
	if recorded or history == null:
		return
	var e := history_entry()
	if e.is_empty():
		return
	recorded = true
	var h := RaceHistory.load_from(history_path)  # the file as it is now, so nothing written since is lost
	h.record(e, history_path)


func _exit_tree() -> void:
	record()


## The heading and the line under it: final results, or finishing with the count home (menus.md §5)
func heading_text() -> Array:
	var r := _race()
	var n := r.result_rows.size() if r != null else 0
	if r != null and r.state == RaceText.RaceState.ABANDONED:
		return ["Race abandoned", "No results: no boat finished within the time limit"]
	if r == null or r.results_final:
		return ["Results", _course_line(n)]
	var home := 0
	for row in r.result_rows:
		if not is_nan(float(row["time"])):
			home += 1
	return ["Finishing", "%d of %d home · results when the race closes" % [home, n]]


## The Today line after a Random race (menus.md §5), from the race's resolved settings; "" after Local and Custom.
func today_text() -> String:
	if host == null:
		return ""
	var ws: Variant = host.get("weather_settings")
	if not (ws is Dictionary) or str(ws.get("weather_mode", "")) != "random":
		return ""
	return VenueWeather.today(ws)


func _course_line(n: int) -> String:
	if host == null:
		return ""
	var ven := str(host.get("venue"))
	var parts: Array[String] = [MenuData.name_of(MenuData.venues(), ven)]
	var cid := str(host.get("course"))
	var cname := MenuData.name_of(MenuData.courses(ven, str(host.get("class_id"))), cid)
	if cname.begins_with(parts[0]) and cname.length() > parts[0].length():
		parts[0] = cname
	elif cname != "":
		parts.append(cname)
	parts.append("%d boats" % n)
	return " · ".join(parts)


## The table rows as text cells (menus.md §5): place, sail, boat, skipper (You or the AI badge), time, gap, code, points
func table_rows() -> Array:
	var r := _race()
	var out := []
	if r == null:
		return out
	for row in r.result_rows:
		var b := int(row["boat"])
		var place := str(row["place"]) if int(row["place"]) > 0 else ""
		var t := "" if is_nan(float(row["time"])) else HudFormat.finish_time(row["time"])
		if bool(row["projected"]) and t != "":
			t += " proj."
		var g := "" if is_nan(float(row["gap"])) or float(row["gap"]) <= 0.0 else HudFormat.gap(row["gap"])
		var pts := ""
		if not is_nan(float(row["points"])):
			pts = HudFormat.points(float(row["points"]))
		var skipper := "You" if b == r.own_boat else ""
		var ai := str(row.get("ai", ""))
		if skipper == "" and ai != "":
			skipper = "AI · %s" % ai
		elif skipper == "":
			skipper = str(row.get("skipper", ""))
		var code := str(row.get("code", ""))
		var status := str(row.get("status", ""))
		if code == "" and status != "":
			code = status
		out.append([place, str(r.sail_numbers.get(b, "")), str(r.boat_names.get(b, row["name"])), skipper, t, g, code,
			pts])
	return out


## Rebuilds what changed: the title, the heading, the table and the summary.
func refresh() -> void:
	var r := _race()
	if r == null:
		return
	var tw := title_words()
	if tw[0] != title.text or tw[1] != title.tagline_text:
		title.set_words(tw[0], tw[1])
		_fit_title()
	var ht := heading_text()
	heading_label.text = String(ht[0]).to_upper()
	line_label.text = ht[1]
	var today := today_text()
	today_label.text = today
	today_label.visible = today != ""
	var rows := table_rows()
	var own := -1
	for i in r.result_rows.size():
		if int(r.result_rows[i]["boat"]) == r.own_boat:
			own = i
	var sig := str(rows) + str(own)
	if sig != _sig:
		_sig = sig
		shown_rows = rows
		own_row = own
		_build_table(rows, own)
	var lines := r.summary_lines()
	var ss := str(lines)
	if ss != _sum_sig:
		_sum_sig = ss
		_build_summary(lines)
	var bt := best_text()
	best_label.text = bt
	best_label.visible = bt != ""
	if r.results_final:
		record()
	_fit_height()


func _cell(text: String, w: float, right: bool, colour: Color, size := CELL_SIZE, weight := 600, tracking := 0.0) -> Label:
	var l := MenuTheme.label(text, size, colour, weight, tracking)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if w > 0.0:
		l.custom_minimum_size = Vector2(w, 0)
	else:
		l.custom_minimum_size = Vector2(BOAT_MIN, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## the Code column is centred, clear of the gap before it
static func _align(l: Label, j: int) -> Label:
	if j == 6:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _line_box(fill: Color, edge := 0) -> StyleBoxFlat:
	return MenuTheme.box(fill, edge, 2, Vector2(10, 3))


func _build_table(rows: Array, own: int) -> void:
	for c in table.get_children():
		table.remove_child(c)
		c.queue_free()
	var head := PanelContainer.new()
	head.name = "Header"
	head.add_theme_stylebox_override("panel", _line_box(Color(0, 0, 0, 0)))
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 6)
	head.add_child(hh)
	for j in COLUMNS.size():
		var c: Array = COLUMNS[j]
		hh.add_child(_align(_cell(String(c[0]).to_upper(), c[1], c[2], MenuTheme.MUTED, HEAD_SIZE, 600,
			MenuTheme.LABEL_TRACKING), j))
	table.add_child(head)
	for i in rows.size():
		var p := PanelContainer.new()
		p.name = "Row%d" % i
		var mine := i == own
		var fill := MenuTheme.ACCENT if mine else (Color(MenuTheme.NAVY, 0.045) if i % 2 == 1 else Color(0, 0, 0, 0))
		p.add_theme_stylebox_override("panel", _line_box(fill, MenuTheme.FOCUS_EDGE if mine else 0))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		p.add_child(h)
		var cells: Array = rows[i]
		for j in COLUMNS.size():
			var colour := MenuTheme.NAVY
			var weight := 600
			if (j == 1 or (j == 3 and String(cells[j]).begins_with("AI"))) and not mine:
				colour = MenuTheme.MUTED
			if j == 4 and String(cells[j]).ends_with("proj.") and not mine:
				colour = MenuTheme.MUTED
			if j == 6 and cells[j] != "" and cells[j] != "Racing" and not mine:
				colour = MenuTheme.SIGNAL
			if mine:
				weight = 700
			h.add_child(_align(_cell(str(cells[j]), COLUMNS[j][1], COLUMNS[j][2], colour, CELL_SIZE, weight), j))
		table.add_child(p)


func _build_summary(lines: Array) -> void:
	for c in summary_box.get_children():
		summary_box.remove_child(c)
		c.queue_free()
	summary_heading.visible = not lines.is_empty()
	for ln in lines:
		var k := MenuTheme.caps(str(ln[0]), HEAD_SIZE, MenuTheme.MUTED)
		k.custom_minimum_size = Vector2(130, 0)
		summary_box.add_child(k)
		var v := MenuTheme.label(str(ln[1]), CELL_SIZE - 1, MenuTheme.INK, 500)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size = Vector2(160, 0)
		summary_box.add_child(v)


# ---- layout ----

## The panel beside the title, or under it when narrow or portrait (menus.md §5); the finish view frames the boat
## clear of the panel when it is beside the title.
func _fit() -> void:
	if _row == null:
		return
	var s := get_viewport().get_visible_rect().size
	wide = s.x >= NARROW and s.x > s.y
	_row.vertical = not wide
	# portrait (the capture window): inside the HUD's portrait margins (hud.md §16.5)
	var mg := Vector4(MARGIN, MARGIN, MARGIN, MARGIN)
	if HudStyle.portrait(s):
		var hm := HudStyle.margins(s)
		mg = Vector4(hm.x, hm.y, hm.x, HudStyle.bottom_margin(s))
	for i in 4:
		_margin.add_theme_constant_override(["margin_left", "margin_top", "margin_right", "margin_bottom"][i],
			roundi(mg[i]))
	if wide:
		_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_left.size_flags_vertical = Control.SIZE_FILL
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_panel.custom_minimum_size = Vector2(minf(PANEL_W, s.x - 2 * MARGIN - 300.0), 0)
	else:
		_left.size_flags_horizontal = Control.SIZE_FILL
		_left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_panel.custom_minimum_size = Vector2.ZERO
	_fit_title()
	var rig: Variant = host.get("rig") if host != null else null
	if rig is CameraRig and is_open:
		(rig as CameraRig).finish.offset = FinishCamera.PANEL_OFFSET if wide else 0.0


## The panel as tall as its content, at most what the window leaves (then the table and summary scroll).
func _fit_height() -> void:
	var s := get_viewport().get_visible_rect().size
	var avail := s.y - _margin.get_theme_constant("margin_top") - _margin.get_theme_constant("margin_bottom")
	if not wide:
		avail -= title.get_combined_minimum_size().y + _row.get_theme_constant("separation")
	var chrome := _panel.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var want := minf(_body.get_combined_minimum_size().y, maxf(avail - chrome, 80.0))
	if absf(want - _scroll.custom_minimum_size.y) > 0.5:
		_scroll.custom_minimum_size.y = want


func _fit_title() -> void:
	var s := get_viewport().get_visible_rect().size
	var room := s.x - 2 * MARGIN
	if wide:
		room -= _panel.custom_minimum_size.x + _row.get_theme_constant("separation")
	title.fit_width(room)


# ---- input and actions ----

func _input(e: InputEvent) -> void:
	if not is_open or _pause_open():
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo == null or not _footer.is_ancestor_of(fo):
		return
	if e.is_action_pressed("ui_up", true) or e.is_action_pressed("ui_down", true):
		_scroll.scroll_vertical += SCROLL_STEP * (-1 if e.is_action("ui_up") else 1)
		get_viewport().set_input_as_handled()


## The actions (menus.md §5): "again" (this setup, a new seed), "setup" (this setup remembered, the main menu on the
## race card), "menu".
func press(id: String) -> void:
	record()
	action_requested.emit(id)
	match id:
		"again":
			GameSetup.next = (host.call("session_setup") as GameSetup).again()
			_change(host.scene_file_path if host != null and host.scene_file_path != "" else SAIL_SCENE)
		"setup":
			remember_setup()
			MainMenu.open_on = "quick"
			_change(MAIN_MENU)
		"menu":
			MainMenu.open_on = ""
			_change(MAIN_MENU)


## This session's setup becomes the remembered one (menus.md §1), saved.
func remember_setup() -> void:
	var s := Settings.current()
	var last := s.last_setup.duplicate()
	var g: GameSetup = host.call("session_setup")
	last.merge(g.to_dict(), true)
	last["mode"] = "race"
	s.last_setup = last
	s.save_file()


func _change(path: String) -> void:
	if act:
		SceneFade.change(get_tree(), path)
