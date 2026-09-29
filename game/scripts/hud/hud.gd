class_name Hud
extends Control
## The in-race HUD (hud.md). The boat instruments of the minimal HUD (§2, §3.1, §5: speed, heading, heel, true
## and apparent wind, helm and sheet, sail status, trim gauges) and, while the sim has a race, the race HUD:
## start countdown and flags (§9.1), signal banners, the start line panel with time to burn and bias, OVER and
## OCS (§9.2), the next mark with its rounding side, distance, bearing, leg and ETA (§7), VMG / VMC and targets
## (§4), the layline distance (§6), the shift meter (§3.2), the sail hint, rank, gaps and splits (§10), the
## rules awareness line (§11), the protest and hail prompts, the penalty panel (§12), the radar (§8), the event
## feed and the ranking list and results (§13), each shown per the assist preset (§14).
##
## Numbers refresh at 4 Hz from HudValues and RaceHudValues; bars, needles and the radar every frame. The race
## side reads the sim it is ticked with (SimSource race readers), so a scene only calls tick() and frame(); the
## optional ui_input(raw) feeds the ranking, radar zoom and orientation keys (without it the Hud polls the
## input map). It wires the protest and hail prompts into the PlayerControls it is given. Player-facing text has
## no em dashes.

## race events for audio and anything else that follows the race (RaceHudValues.hud_event)
signal hud_event(kind: String, data: Dictionary)

enum Assist { FULL, STANDARD, MINIMAL }

const REFRESH := 0.25
const FLASH_TIME := 1.2
const MESSAGE_TIME := 3.0
const COLOURS := {
	HudValues.Colour.NONE: Color(0.85, 0.85, 0.85),
	HudValues.Colour.GREEN: Color(0.3, 0.85, 0.35),
	HudValues.Colour.YELLOW: Color(0.95, 0.8, 0.2),
	HudValues.Colour.RED: Color(0.95, 0.3, 0.25),
}
const TINT_COLOURS := {
	RaceHudValues.Tint.WHITE: Color(0.95, 0.95, 0.95),
	RaceHudValues.Tint.RED: Color(1.0, 0.32, 0.26),
	RaceHudValues.Tint.ORANGE: Color(1.0, 0.62, 0.18),
	RaceHudValues.Tint.CYAN: Color(0.3, 0.88, 0.98),
	RaceHudValues.Tint.YELLOW: Color(0.98, 0.85, 0.25),
	RaceHudValues.Tint.GREEN: Color(0.35, 0.92, 0.4),
	RaceHudValues.Tint.GREY: Color(0.7, 0.7, 0.7),
}
## the race labels (keys of `labels`)
const RACE_KEYS := ["clock", "line", "tline", "burn", "bias", "over", "next", "lap", "mark_dist", "bearing",
	"leg", "vmg", "target", "layline", "shift", "hint", "rank", "gap", "ahead", "behind", "rules", "prompt",
	"banner", "pen_head", "pen_turn", "pen_deadline", "pen_dsq"]

var assist := Assist.STANDARD
var values := HudValues.new()
var race := RaceHudValues.new()
## the viewed boat is the player's own: frame() shows its commands from the local controls
var local_commands := true:
	set(on):
		local_commands = on
		if not on:
			values.commands_local = false
## label nodes by key: bsp, sog, hdg, cog, heel, polar, tws, twa, twd, aws, awa, sail, sheet, rudder, message and
## the RACE_KEYS
var labels := {}
var rudder_bar: HudBar
var sheet_bar: HudBar
var gauge_box: HBoxContainer
var gauge_views: Array[TrimGaugeView] = []
## race panels (visible while the sim has a race)
var race_panel: PanelContainer
var next_panel: PanelContainer
var position_panel: PanelContainer
var penalty_panel: PanelContainer
var flags_view: FlagsView
var arrow_view: RoundingArrowView
var ring_view: PenaltyRingView
var radar: RadarView
var feed_box: VBoxContainer
var ranking_panel: PanelContainer
var ranking_grid: GridContainer
var results_panel: PanelContainer
var results_grid: GridContainer
var results_title: Label
## the ranking list is held open (the `rankings` action)
var show_ranking := false

var _refresh_t := INF
var _flash_t := 0.0
var _message_t := 0.0
var _since_tick := 0.0
var _ui_fed := false
var _wired: PlayerControls = null
var _results_shown := -1


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	race.hud_event.connect(func(k: String, d: Dictionary) -> void: hud_event.emit(k, d))
	var left_col := _column("Left", Control.PRESET_TOP_LEFT)
	var left := _box(_panel("Instruments", left_col))
	for k in ["bsp", "sog", "hdg", "cog", "heel", "polar", "vmg", "target"]:
		_label(left, k)
	position_panel = _panel("Position", left_col)
	var pos_box := _box(position_panel)
	_label(pos_box, "rank", 22)
	for k in ["gap", "ahead", "behind"]:
		_label(pos_box, k)
	penalty_panel = _panel("Penalty", left_col)
	var pen_box := _box(penalty_panel)
	_label(pen_box, "pen_head")
	var ring_row := HBoxContainer.new()
	pen_box.add_child(ring_row)
	ring_view = PenaltyRingView.new()
	ring_row.add_child(ring_view)
	var ring_text := VBoxContainer.new()
	ring_row.add_child(ring_text)
	_label(ring_text, "pen_turn")
	_label(ring_text, "pen_deadline")
	_label(pen_box, "pen_dsq")
	var right_col := _column("Right", Control.PRESET_TOP_RIGHT)
	var right := _box(_panel("Wind", right_col))
	for k in ["tws", "twa", "twd", "aws", "awa", "shift"]:
		_label(right, k)
	next_panel = _panel("NextMark", right_col)
	var nb := _box(next_panel)
	_label(nb, "next", 20)
	_label(nb, "lap")
	var dist_row := HBoxContainer.new()
	nb.add_child(dist_row)
	arrow_view = RoundingArrowView.new()
	dist_row.add_child(arrow_view)
	_label(dist_row, "mark_dist", 20)
	for k in ["bearing", "leg", "layline", "hint"]:
		_label(nb, k)
	var top := _column("Top", Control.PRESET_CENTER_TOP)
	race_panel = _panel("Race", top)
	var rb := _box(race_panel)
	_label(rb, "clock", 30).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flags_view = FlagsView.new()
	flags_view.name = "Flags"
	rb.add_child(flags_view)
	for k in ["line", "tline", "burn", "bias"]:
		_label(rb, k)
	_label(rb, "over", 24).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for k in ["banner", "rules", "prompt"]:
		var l := _label(top, k, 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 6)
	var bottom := _panel("Boat", self, Control.PRESET_CENTER_BOTTOM)
	var bb := _box(bottom)
	_label(bb, "sail")
	_label(bb, "rudder")
	rudder_bar = HudBar.new()
	rudder_bar.name = "RudderBar"
	rudder_bar.centred = true
	bb.add_child(rudder_bar)
	_label(bb, "sheet")
	sheet_bar = HudBar.new()
	sheet_bar.name = "SheetBar"
	bb.add_child(sheet_bar)
	gauge_box = HBoxContainer.new()
	gauge_box.name = "TrimGauges"
	gauge_box.add_theme_constant_override("separation", 16)
	bb.add_child(gauge_box)
	_label(bb, "message")
	radar = RadarView.new()
	radar.name = "Radar"
	radar.values = race
	add_child(radar)
	radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	radar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	radar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed_box = VBoxContainer.new()
	feed_box.name = "Feed"
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed_box)
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	feed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ranking_panel = _panel("Ranking", self, Control.PRESET_CENTER)
	ranking_grid = _grid(ranking_panel, 5)
	results_panel = _panel("Results", self, Control.PRESET_CENTER)
	results_title = Label.new()
	results_title.add_theme_font_size_override("font_size", 24)
	_box(results_panel).add_child(results_title)
	results_grid = _grid(results_panel, 8)
	_show_race(false)


func _column(n: String, preset: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = n
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	match preset:
		Control.PRESET_TOP_RIGHT:
			v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return v


func _panel(n: String, parent: Control, preset := -1) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = n
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# in a column each panel keeps its own width
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if parent.name == "Top" \
		else Control.SIZE_SHRINK_END if parent.name == "Right" else Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	if preset >= 0:
		pc.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		if preset == Control.PRESET_CENTER_BOTTOM:
			pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
		elif preset == Control.PRESET_CENTER:
			pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(190, 0)
	pc.add_child(v)
	return pc


func _box(pc: PanelContainer) -> VBoxContainer:
	return pc.get_child(0)


func _grid(pc: PanelContainer, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 18)
	_box(pc).add_child(g)
	return g


func _label(parent: Node, key: String, size_px := 18) -> Label:
	var l := Label.new()
	l.name = key.capitalize().replace(" ", "")
	l.add_theme_font_size_override("font_size", size_px)
	parent.add_child(l)
	labels[key] = l
	return l


func text_of(key: String) -> String:
	return (labels[key] as Label).text


## Once per simulation tick.
func tick(sim: SimSource, boat: int) -> void:
	values.tick(sim, boat)
	race.tick(sim, boat)
	radar.sim = sim
	_since_tick = 0.0


## The ranking, radar zoom and radar orientation keys of this frame (controls.md §2). Optional: without it
## frame() polls the input map.
func ui_input(raw: RawInput) -> void:
	_ui_fed = true
	show_ranking = raw.is_held(&"rankings")
	if raw.was_pressed(&"radar_zoom_in"):
		radar.zoom(-1)
	if raw.was_pressed(&"radar_zoom_out"):
		radar.zoom(1)
	if raw.was_pressed(&"radar_orientation"):
		radar.toggle_orientation()


func _poll_input() -> void:
	if _ui_fed or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	show_ranking = InputMap.has_action(&"rankings") and Input.is_action_pressed(&"rankings")
	if InputMap.has_action(&"radar_zoom_in") and Input.is_action_just_pressed(&"radar_zoom_in"):
		radar.zoom(-1)
	if InputMap.has_action(&"radar_zoom_out") and Input.is_action_just_pressed(&"radar_zoom_out"):
		radar.zoom(1)
	if InputMap.has_action(&"radar_orientation") and Input.is_action_just_pressed(&"radar_orientation"):
		radar.toggle_orientation()


## Once per rendered frame. `controls` (optional) supplies the HUD feedback of the controls and, while
## `local_commands` is on (the viewed boat is the player's own), the helm and sheet commands: the local command
## of this frame, not the one the sim applied, so the helm mark, the sheet bar and the sheet text answer at once
## (the core shows a queued command only after its next step).
func frame(dt: float, controls: PlayerControls = null) -> void:
	_poll_input()
	_ui_fed = false
	if controls != null:
		_wire(controls)
		if local_commands and values.set_commands(controls):
			refresh_text()
		if controls.busy_flash:
			controls.busy_flash = false
			_flash_t = FLASH_TIME
		if not controls.messages.is_empty():
			labels["message"].text = controls.messages.back()
			controls.messages.clear()
			_message_t = MESSAGE_TIME
	_flash_t = maxf(_flash_t - dt, 0.0)
	_message_t = maxf(_message_t - dt, 0.0)
	if _message_t <= 0.0:
		labels["message"].text = ""
	var sail_label: Label = labels["sail"]
	sail_label.modulate.a = 1.0 if _flash_t <= 0.0 or fmod(_flash_t, 0.3) > 0.15 else 0.35
	_refresh_t += dt
	if _refresh_t >= REFRESH:
		_refresh_t = 0.0
		refresh_text()
	_bars()
	_since_tick += dt
	radar.alpha = clampf(_since_tick / SimSource.DT, 0.0, 1.0)
	radar.twd = values.twd
	radar.tws = values.tws
	radar.colours = shows("radar_colours")
	radar.laylines = shows("laylines")
	radar.advance(dt)
	_race_frame()


## PlayerControls asks the HUD whether the protest prompt shows and whether a hail can be made or answered.
func _wire(c: PlayerControls) -> void:
	if c == _wired:
		return
	_wired = c
	c.protest_prompt = func() -> bool: return race.active and race.protest_prompt()
	c.hail_available = func() -> bool: return race.active and race.hail_available
	c.hailed = func() -> bool: return race.active and race.hailed_by >= 0


## Rewrites every number from the values of the last tick (hud.md §1 formats).
func refresh_text() -> void:
	var v := values
	labels["bsp"].text = "BSP  %s kn" % HudFormat.speed_kn(v.bsp)
	labels["sog"].text = "SOG  %s kn" % HudFormat.speed_kn(v.sog)
	labels["hdg"].text = "HDG  %s" % HudFormat.compass_deg(v.hdg)
	labels["cog"].text = "COG  %s" % HudFormat.compass_deg(v.cog) if v.sog / HudFormat.KNOT > 0.3 else "COG  ---"
	labels["heel"].text = "Heel  %s" % HudFormat.side_angle(v.heel, "S", "P")
	labels["polar"].text = "Polar  --" if is_nan(v.polar_pct) else "Polar  %s %%" % HudFormat.percent(v.polar_pct)
	labels["tws"].text = "TWS  %s kn" % HudFormat.speed_kn(v.tws)
	labels["twa"].text = "TWA  %s" % HudFormat.side_angle(v.twa, "S", "P")
	labels["twd"].text = "TWD  %s" % HudFormat.compass_deg(v.twd)
	labels["aws"].text = "AWS  %s kn" % HudFormat.speed_kn(v.aws)
	labels["awa"].text = "AWA  %s" % HudFormat.side_angle(v.awa, "S", "P")
	var sail := _sail_name(v.sail_up) if v.sail_up != "" else "Main only"
	if v.sail_hoisting != "":
		sail += ", hoisting %s %s %%" % [_sail_name(v.sail_hoisting), HudFormat.percent(100.0 * v.hoist_progress)]
	labels["sail"].text = "Sail  %s" % sail
	labels["rudder"].text = "Helm  %s" % _signed_pct(v.h)
	var sheet := "AUTO" if v.auto_trim else "%s %%" % HudFormat.percent(100.0 * v.sheet_cmd)
	labels["sheet"].text = "Sheet  %s%s" % [sheet, "   LET FLY" if v.let_fly else ""]
	_race_text()


static func _sail_name(n: String) -> String:
	return n.capitalize()


static func _signed_pct(h: float) -> String:
	var p := int(HudFormat.round_half_away(100.0 * absf(h)))
	if p == 0:
		return "0"
	return "%d %s" % [p, "S" if h > 0.0 else "P"]


func _bars() -> void:
	var v := values
	rudder_bar.value = v.h
	rudder_bar.mark = v.h_cmd
	rudder_bar.queue_redraw()
	sheet_bar.visible = not v.auto_trim
	sheet_bar.value = v.sheet_cmd
	sheet_bar.mark = NAN
	sheet_bar.queue_redraw()
	while gauge_views.size() < v.gauges.size():
		var gv := TrimGaugeView.new()
		gauge_box.add_child(gv)
		gauge_views.append(gv)
	for i in gauge_views.size():
		var gv := gauge_views[i]
		gv.visible = i < v.gauges.size()
		if not gv.visible:
			continue
		var g: HudValues.Gauge = v.gauges[i]
		gv.name = "Gauge" + g.name.capitalize().replace(" ", "")
		gv.title = g.name.capitalize()
		gv.auto = g.auto
		gv.greyed = g.greyed
		gv.needle = g.needle
		gv.show_needle = assist != Assist.MINIMAL
		gv.colour = COLOURS[HudValues.Colour.NONE] if (g.auto or assist == Assist.MINIMAL) else COLOURS[g.colour]
		gv.telltale = g.telltale
		gv.queue_redraw()


func toggle_hidden() -> void:
	visible = not visible


# ---- race -----------------------------------------------------------------------------------------------------

func _show_race(on: bool) -> void:
	for p in [race_panel, next_panel, position_panel, radar, feed_box]:
		p.visible = on
	if not on:
		penalty_panel.visible = false
		ranking_panel.visible = false
		results_panel.visible = false
		for k in ["vmg", "target", "shift", "banner", "rules", "prompt"]:
			labels[k].visible = false


func _put(key: String, text: String, colour := Color(0.95, 0.95, 0.95)) -> void:
	var l: Label = labels[key]
	l.text = text
	l.visible = text != ""
	l.add_theme_color_override("font_color", colour)


## hud.md §14: whether the assist preset shows a race element ("laylines", "layline_distance", "zone",
## "radar_colours", "shift", "burn_bias", "sail_hint", "shadow_view"; everything else always)
func shows(what: String) -> bool:
	match what:
		"laylines", "layline_distance", "zone", "radar_colours", "shift", "burn_bias":
			return assist != Assist.MINIMAL
		"sail_hint", "shadow_view":
			return assist == Assist.FULL
	return true


## Every frame: visibility, the parts that move, the prompt countdown, the banner and the feed.
func _race_frame() -> void:
	var r := race
	if not r.active:
		if race_panel.visible:
			_show_race(false)
		return
	if not race_panel.visible:
		_show_race(true)
		refresh_text()
	flags_view.flags = r.flags
	flags_view.visible = not r.flags.is_empty()
	flags_view.queue_redraw()
	arrow_view.sides = r.next_sides
	arrow_view.visible = r.next_step > 0
	arrow_view.queue_redraw()
	ring_view.turn_deg = r.turn_deg
	ring_view.target_deg = r.turn_target
	ring_view.tack_done = r.turn_tack
	ring_view.gybe_done = r.turn_gybe
	ring_view.queue_redraw()
	penalty_panel.visible = r.penalty_visible
	# the prompt (protest, hail) and the banner answer at once
	var prompt := ""
	if r.protest_prompt():
		prompt = "Protest %s (rule %s)? [P]  %d" % [r.name_of(r.protest_culprit), RaceText.code(r.protest_rule),
			ceili(r.protest_ticks * SimSource.DT)]
	elif r.hailed_by >= 0:
		prompt = "%s hails for room to tack: tack, or reply [H] you tack" % r.name_of(r.hailed_by)
	elif r.hail_available:
		prompt = "Hail: room to tack [H]"
	_put("prompt", prompt, TINT_COLOURS[RaceHudValues.Tint.YELLOW])
	if r.banner != null:
		_put("banner", r.banner.text, TINT_COLOURS[r.banner.tint])
		labels["banner"].add_theme_font_size_override("font_size", 34 if r.banner.full else 24)
	else:
		_put("banner", "")
	var m := r.message
	if m != null and (assist != Assist.MINIMAL or m.breach):
		_put("rules", m.text, TINT_COLOURS[m.tint])
	else:
		_put("rules", "")
	_feed()
	_ranking()
	_results()


func _feed() -> void:
	var lines := race.feed
	while feed_box.get_child_count() < RaceHudValues.FEED_LINES:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		feed_box.add_child(l)
	for i in feed_box.get_child_count():
		var l: Label = feed_box.get_child(i)
		l.text = lines[i].text if i < lines.size() else ""
		l.modulate.a = clampf(lines[i].ticks / 20.0, 0.0, 1.0) if i < lines.size() else 0.0


## the feed lines shown now (tests, previews)
func feed_text() -> Array[String]:
	var out: Array[String] = []
	for l in race.feed:
		out.append(l.text)
	return out


func _ranking() -> void:
	ranking_panel.visible = show_ranking and not results_panel.visible
	if not ranking_panel.visible:
		return
	var cells := []
	for rw in race.ranking_rows():
		cells.append_array([str(rw["rank"]), rw["name"], rw["ai"], rw["gap"], rw["status"]])
	_fill(ranking_grid, cells, 0)


## the ranking list as text rows (tests, previews)
func ranking_text() -> Array[String]:
	var out: Array[String] = []
	for rw in race.ranking_rows():
		out.append("%d  %s%s  %s  %s" % [rw["rank"], rw["name"], "  [%s]" % rw["ai"] if rw["ai"] != "" else "",
			rw["gap"], rw["status"]])
	return out


func _results() -> void:
	results_panel.visible = race.results_visible and (race.results_final or race.banner == null)
	if not results_panel.visible:
		return
	var key := race.result_rows.size() * 2 + (1 if race.results_final else 0)
	if key == _results_shown:
		return
	_results_shown = key
	results_title.text = "Results" if race.results_final else "Provisional results"
	var cells := ["Place", "Boat", "Skipper", "", "Time", "Gap", "Code", "Points"]
	for row in results_text_rows():
		cells.append_array(row)
	_fill(results_grid, cells, 8)


## hud.md §13 results rows as text cells: place, boat, skipper, AI badge, finish time, gap, code, points
func results_text_rows() -> Array:
	var out := []
	for r in race.result_rows:
		var place := str(r["place"]) if int(r["place"]) > 0 else ""
		var t := "" if is_nan(r["time"]) else HudFormat.finish_time(r["time"])
		if bool(r["projected"]) and t != "":
			t += " proj."
		var g := "" if is_nan(r["gap"]) or float(r["gap"]) <= 0.0 else HudFormat.gap(r["gap"])
		var pts := ""
		if not is_nan(r["points"]):
			pts = "%d" % int(r["points"]) if fmod(r["points"], 1.0) == 0.0 else "%.1f" % r["points"]
		out.append([place, r["name"], r["skipper"], r["ai"], t, g, r["code"], pts])
	return out


func _fill(g: GridContainer, cells: Array, header_cells: int) -> void:
	while g.get_child_count() < cells.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		g.add_child(l)
	for i in g.get_child_count():
		var l: Label = g.get_child(i)
		l.visible = i < cells.size()
		l.text = str(cells[i]) if i < cells.size() else ""
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65) if i < header_cells else Color(1, 1, 1))


## The race numbers at 4 Hz (hud.md §1 formats, §14 assists).
func _race_text() -> void:
	var r := race
	if not r.active:
		return
	var red: Color = TINT_COLOURS[RaceHudValues.Tint.RED]
	var white: Color = TINT_COLOURS[RaceHudValues.Tint.WHITE]
	# clock (§9.1)
	var clock := ""
	if r.state <= RaceText.RaceState.FREE_SAILING or (r.state == RaceText.RaceState.SEQUENCE
			and r.race_time < -r.warning_time):
		clock = "Warning in %s" % HudFormat.countdown(-r.race_time - r.warning_time)
	elif r.state == RaceText.RaceState.SEQUENCE:
		clock = "Start in %s" % HudFormat.countdown(-r.race_time)
	elif r.finished:
		clock = "Finished  %s" % HudFormat.finish_time(r.t_finish)
	elif r.state == RaceText.RaceState.ABANDONED:
		clock = "Abandoned"
	else:
		clock = "Race  %s" % HudFormat.clock(r.race_time)
	_put("clock", clock)
	# start line panel (§9.2)
	if r.start_panel:
		var d := "Line  %s" % HudFormat.signed_distance(r.line_dist) if not r.line_end \
			else "Line  %s (end)" % HudFormat.distance(r.line_dist)
		_put("line", d)
		var full := shows("burn_bias")
		_put("tline", ("To line  %s" % ("--" if is_nan(r.t_line) else HudFormat.clock(r.t_line))) if full else "")
		var burn := ""
		if full and r.race_time < 0.0:
			burn = "Burn  --" if is_nan(r.burn) else "Burn  %s" % signed_seconds(r.burn)
		_put("burn", burn, white if is_nan(r.burn) or r.burn >= 0.0 else TINT_COLOURS[RaceHudValues.Tint.ORANGE])
		var bias := ""
		if full and r.bias_end != "":
			bias = "Bias  %s +%d° · %s" % [r.bias_end, int(HudFormat.round_half_away(rad_to_deg(r.bias))),
				HudFormat.distance(r.bias_m)]
		_put("bias", bias)
	else:
		for k in ["line", "tline", "burn", "bias"]:
			_put(k, "")
	_put("over", "OVER  %s" % r.over_text if r.over else "", red)
	# next mark (§7) and performance (§4, §6, §3.2)
	if r.next_step > 0:
		_put("next", r.next_name, TINT_COLOURS[RaceHudValues.Tint.YELLOW])
		_put("lap", "Lap %d/%d · Leg %d/%d" % [r.lap, r.laps, r.leg, r.legs])
		_put("mark_dist", HudFormat.distance(r.next_dist))
		_put("bearing", "Bearing  %s  (%s)" % [HudFormat.compass_deg(r.next_bearing),
			HudFormat.relative_bearing(r.next_rel)])
		var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
		_put("leg", "%s  ·  ETA %s" % [r.leg_type.capitalize(), eta])
		if r.leg_type == "reach":
			_put("vmg", "VMC  %s kn" % HudFormat.speed_kn(r.vmc))
			_put("target", "Target  %s kn" % HudFormat.speed_kn(r.target_speed))
		else:
			_put("vmg", "VMG  %s kn  %s %%" % [HudFormat.speed_kn(r.vmg), HudFormat.percent(r.vmg_pct)])
			var tt := "" if is_nan(r.target_twa) else "  %d°" % int(HudFormat.round_half_away(rad_to_deg(r.target_twa)))
			_put("target", "Target  %s kn%s" % [HudFormat.speed_kn(r.target_speed), tt])
		var lay := ""
		if shows("layline_distance"):
			if not is_nan(r.overstood):
				lay = "OVERSTOOD %s" % HudFormat.distance(r.overstood)
			elif not is_nan(r.layline_dist):
				lay = "Layline %s · %s" % [HudFormat.distance(r.layline_dist), HudFormat.clock(r.layline_time)]
		_put("layline", lay, red if lay.begins_with("OVER") else white)
		var sh := ""
		if shows("shift") and r.leg_type != "reach":
			sh = "Shift  --"
			if r.shift_kind != "":
				sh = "%s %d°" % [r.shift_kind.to_upper(), int(HudFormat.round_half_away(rad_to_deg(absf(r.shift))))]
		var sh_col := white
		if r.shift_kind == "lift":
			sh_col = TINT_COLOURS[RaceHudValues.Tint.GREEN]
		elif r.shift_kind == "header":
			sh_col = red
		_put("shift", sh, sh_col)
		_put("hint", r.sail_hint if shows("sail_hint") else "", TINT_COLOURS[RaceHudValues.Tint.CYAN])
		next_panel.visible = true
	else:
		next_panel.visible = false
		for k in ["vmg", "target", "shift"]:
			_put(k, "")
	# position (§10)
	position_panel.visible = r.fleet > 0
	_put("rank", "%d / %d" % [r.rank, r.fleet] if r.rank > 0 else "")
	var gap := ""
	if r.leader >= 0 and r.leader != r.boat and r.started:
		gap = "Leader  +%s" % HudFormat.distance(r.gap_dist)
		if not is_nan(r.gap_time):
			gap += "  %s%s%s" % ["~" if r.gap_estimate else "", HudFormat.gap(r.gap_time),
				" @ %s" % r.gap_at if r.gap_at != "" and not r.gap_estimate else ""]
	elif r.leader == r.boat and r.started and r.fleet > 1:
		gap = "Leading"
	_put("gap", gap)
	_put("ahead", "Ahead  %s  %s" % [r.name_of(r.ahead), HudFormat.signed_distance(r.ahead_dist)]
		if r.ahead >= 0 and r.started else "")
	_put("behind", "Behind  %s  %s" % [r.name_of(r.behind), HudFormat.signed_distance(r.behind_dist)]
		if r.behind >= 0 and r.started else "")
	# penalties (§12.1)
	if r.pending > 0:
		var other := " (%s)" % r.name_of(r.penalty_other) if r.penalty_other >= 0 else ""
		var head := "Penalty" if r.pending == 1 else "Penalty 1 of %d" % r.pending
		_put("pen_head", "%s: %s%s" % [head, RaceText.rule_text(r.penalty_rule), other], red)
	else:
		_put("pen_head", "Penalty done" if r.penalty_visible else "")
	_put("pen_turn", r.turn_text)
	var dl := ""
	if r.deadline >= 0.0 and r.pending > 0:
		dl = "Deadline  %s" % HudFormat.clock(r.deadline)
	_put("pen_deadline", dl, red if r.deadline < 10.0 else white)
	_put("pen_dsq", "One more penalty = disqualification" if r.dsq_warning and r.pending > 0 else "", red)


## "+10 s", "-3 s"
static func signed_seconds(s: float) -> String:
	var t := int(HudFormat.round_half_away(absf(s)))
	return "%s%d s" % ["-" if s < 0.0 and t > 0 else "+", t]
