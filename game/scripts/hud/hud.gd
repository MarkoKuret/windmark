class_name Hud
extends Control
## The in-race HUD (hud.md). The boat instruments (§2, §3.1, §5: speed, heading, heel, true and apparent wind, helm
## and sheet, sail status, trim gauges) and, while the sim has a race, the race HUD: start countdown and flags
## (§9.1), signal banners, the start numbers with time to burn and bias, OVER and OCS (§9.2), the next mark tag
## with its rounding side, distance, bearing and ETA (§7), VMG / VMC and targets (§4), the tack point (§6), the
## shift meter (§3.2), the sail hint, rank, gaps and splits (§10), the rules line (§11), the protest and hail
## prompts, the penalty panel and the turn on the water (§12), the radar (§8) and the course map (§8.1, M), the
## event feed and the ranking list and results (§13), each shown per the assist preset (§14) and the instrument
## density (§16.1).
##
## The look is hud.md §16 and docs/design/hud_direction.md: glass instrument pages, Barlow Semi Condensed with
## tabular figures, the colour tokens of HudStyle; every block is a HudCanvas painted by HudPaint. World tags
## (mark tag, tack point, name tags, edge pointers, penalty turn, the selected boat's bracket) need the scene's
## camera (`camera_rig`, or `camera`); without one the mark tag is docked under the race bug and the rest is left
## out. A boat picked with a click or tap, or boat_select, gets her tag, a bracket and the boat card (§16.4.1,
## §16.7).
##
## Numbers refresh at 4 Hz from HudValues and RaceHudValues into `texts` (key -> {text, col, value, unit}: `text`
## is the full line, value and unit what the cells show); dials, bars and the radar move every frame. The race
## side reads the sim it is ticked with (SimSource race readers), so a scene only calls tick() and frame(); the
## optional ui_input(raw) feeds the HUD keys (without it the Hud polls the input map). It wires the protest and hail
## prompts into the PlayerControls it is given. Player-facing text has no em dashes.

## race events for audio and anything else that follows the race (RaceHudValues.hud_event)
signal hud_event(kind: String, data: Dictionary)
## the player changed the instrument density (Settings stores it)
signal density_changed(level: int)

enum Assist { FULL, STANDARD, MINIMAL }
enum Density { GLANCE, RACE, DATA }

const DENSITY_NAMES := ["GLANCE", "RACE", "DATA"]
const REFRESH := 0.25
const FLASH_TIME := 1.2
const MESSAGE_TIME := 3.0
## the notes of the `boat_names` states (hud.md §16.4)
const NOTE_NAMES_ALL := "Name tags: every boat nearby"
const NOTE_NAMES_OFF := "Name tags: off"
const NOTE_NAMES_WATCH := "Name tags: boats to watch"
const TOAST_TIME := 1.5
const ROUNDING_TIME := 6.0
## hud.md §16.4: name tags within this range of the viewed boat, m
const TAG_RANGE := 50.0
## hud.md §16.4.1: a click or tap within this many px of a boat's hull and rig triangle picks her (design px)
const PICK_RADIUS := 40.0
## hud.md §16.4.1: the bracket stands this far outside the boat's screen box (design px)
## hud.md §16.4.1 the selection marker over the masthead (design px)
const MARKER_GAP := 8.0
const MARKER_W := 12.0
const MARKER_H := 9.0
## hud.md §16.4.2 ladder lines (m): past the boats across the axis, at least each side of a boat, sample step
const LADDER_PAST := 40.0
const LADDER_MIN := 80.0
const LADDER_STEP := 4.0
## design px kept clear round every boat's hull and rig on screen
const LADDER_CLEAR := 6.0
## controls.md §3: a View press shorter than this is a tap (density), longer the ranking list
const VIEW_TAP := 0.3
const RANK_W := [70.0, 260.0, 130.0, 120.0, 120.0]
const RESULT_W := [70.0, 220.0, 200.0, 120.0, 170.0, 110.0, 90.0, 90.0]

var assist := Assist.STANDARD:
	set(a):
		if a != assist:
			assist = a
			_bump()
## the instrument density (hud.md §16.1); while `density_auto` it follows the screen (default_density)
var density := Density.RACE:
	set(d):
		var nd := clampi(d, 0, 2) as Density
		if nd != density:
			density = nd
			_bump()
var density_auto := true
var values := HudValues.new()
var race := RaceHudValues.new()
## the viewed boat is the player's own: frame() shows its commands from the local controls
var local_commands := true:
	set(on):
		local_commands = on
		if not on:
			values.commands_local = false
## key -> {text, col, value, unit}; see text_of, value_of, colour_of
var texts := {}
## the scene's camera rig (duck typed: `camera`, `mode` as CameraRig.Mode) for the world tags
var camera_rig: Object = null
## a camera without a rig (previews, tests) and its kind ("chase", "onboard", "aerial", "free")
var camera: Camera3D = null
var camera_kind := "chase"
## name tags on (the `boat_names` action, hud.md §16.4) and the boats the player selected for a tag
var show_names := true
## the all state of `boat_names`: every boat within TAG_RANGE gets a tag; off (watch): those with a rules relation
var names_all := false
## controls.md §7 world_tags: the world tags (mark tag, next-mark arrow, tack point, name tags, edge pointers) shown
var world_tags := true
## the selected boat (hud.md §16.4.1): boat -> true, at most one; see selected_boat, select, clear_selection
var selected := {}
## the pointer picks (off while the scene's pause menu is open)
var pick_enabled := true
## hud.md §16.7: the selected boat's card, refreshed with the texts; empty without one. Keys: boat, head, name,
## place, fleet, course (her standing), gap_m, rules, rules_col, rule, penalty, col (her tag colour)
var card := {}
var sim: SimSource
## the screen the HUD lays out for, when set (tests, previews); zero: its viewport's
var screen_size := Vector2.ZERO
## the boat the HUD shows (tick)
var viewed := -1

# blocks
var world: HudCanvas
var inst_page: HudCanvas
var toast_block: HudCanvas
var bug_block: HudCanvas
var feed_block: HudCanvas
## the top centre lane: start block, penalty panel, rules line, banner, prompt (visible while the sim has a race)
var race_panel: Control
var start_block: HudCanvas
var flags_view: FlagsView
var penalty_panel: HudCanvas
var turn_view: PenaltyTurnView
var alerts_block: HudCanvas
var next_panel: HudCanvas
## hud.md §16.7 the selected boat's card
var card_block: HudCanvas
var arrow_view: RoundingArrowView
## hud.md §7.1 the next-mark arrow outside the chase camera
var mark_arrow_block: HudCanvas
var radar: RadarView
var helm_block: HudCanvas
var helm_notes: HudCanvas
var rudder_bar: HudBar
var sheet_bar: HudBar
var gauge_box: Control
var gauge_views: Array[TrimGaugeView] = []
var ranking_panel: HudCanvas
var results_panel: HudCanvas
## hud.md §8.1 the course map, under the alert lane (race_panel) and over everything else that shows with it
var map_view: CourseMapView
## the course map is open (the `map` action; Esc closes it first, close_map)
var map_open := false
## the `map` key opens it (off while the scene's pause menu or the chat line has the keys)
var map_enabled := true
var results_title := ""
## hud.md §13: the HUD draws the results as its own table (off where the results screen of menus.md §5 does it)
var results_table := true
## the ranking list is held open (the `rankings` action)
var show_ranking := false
## the rankings option (controls.md §6, menus.md §3): true = Tab or a View press opens and closes the list, and
## View no longer cycles the density
var rankings_toggle := false

var _refresh_t := INF
var _flash_t := 0.0
var _message_t := 0.0
var _toast_t := 0.0
var _rounded_t := 0.0
var _last_step := -1
var _since_tick := 0.0
var _ui_fed := false
var _view_held := 0.0
var _wired: PlayerControls = null
var _map_sim: SimSource = null
var _k := 1.0
var _ladder_shapes: Array = []
## items() for the density, phase and assist of `_items_key`
var _items: Array[String] = []
var _items_key := []
var _canvases: Array[HudCanvas] = []
## the content version of the blocks that read only the tick's values, the texts and the settings (hud.md §1):
## raised by _bump whenever those may have changed; the frame keys (HudCanvas.memo_frame) come from the same
## counter, so a block that turns dynamic never meets a key it was built under
static var _versions := 0
var _version := 0
var _phase_seen := ""
var _palette_seen := ""
var _camera_seen := false
## where edge pointers run in portrait (hud.md §16.5), screen px; empty in landscape (HudPaint.edge_pointer's own box)
var edge_box := Rect2()


## HudValues.Colour -> token, in the colour-blind palette in use (hud.md §16.2.1); read only
static func colours() -> Dictionary:
	if _colours_palette != HudStyle.palette:
		_colours = {
			HudValues.Colour.NONE: HudStyle.PAPER,
			HudValues.Colour.GREEN: HudStyle.STBD,
			HudValues.Colour.YELLOW: HudStyle.MARK,
			HudValues.Colour.RED: HudStyle.PORT,
		}
		_colours_palette = HudStyle.palette
	return _colours


static var _colours := {}
static var _colours_palette := ""

func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	race.hud_event.connect(func(kd: String, d: Dictionary) -> void: hud_event.emit(kd, d))
	world = _block("World", HudPaint.world)
	world.dynamic = true
	inst_page = _block("Instruments", HudPaint.instruments)
	toast_block = _block("InstrumentsChip", HudPaint.toast)
	toast_block.visible = false
	bug_block = _block("RaceBug", HudPaint.bug)
	feed_block = _block("Feed", HudPaint.feed)
	map_view = CourseMapView.new()
	map_view.name = "CourseMap"
	map_view.values = race
	map_view.visible = false
	map_view.dynamic = true
	add_child(map_view)
	race_panel = Control.new()
	race_panel.name = "Race"
	race_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(race_panel)
	start_block = _block("Start", HudPaint.start, race_panel)
	flags_view = FlagsView.new()
	flags_view.name = "Flags"
	start_block.add_child(flags_view)
	penalty_panel = _block("Penalty", HudPaint.penalty, race_panel)
	turn_view = PenaltyTurnView.new()
	turn_view.name = "Turn"
	penalty_panel.add_child(turn_view)
	alerts_block = _block("Alerts", HudPaint.alerts, race_panel)
	next_panel = _block("NextMark", HudPaint.mark_tag)
	arrow_view = RoundingArrowView.new()
	arrow_view.name = "Rounding"
	next_panel.add_child(arrow_view)
	mark_arrow_block = _block("MarkArrow", HudPaint.mark_arrow)
	mark_arrow_block.dynamic = true
	card_block = _block("BoatCard", HudPaint.boat_card)
	card_block.visible = false
	radar = RadarView.new()
	radar.name = "Radar"
	radar.values = race
	radar.dynamic = true
	add_child(radar)
	map_view.radar = radar
	helm_block = _block("Boat", HudPaint.helm)
	helm_notes = _block("Notes", HudPaint.helm_notes)
	gauge_box = Control.new()
	gauge_box.name = "TrimGauges"
	gauge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	helm_block.add_child(gauge_box)
	sheet_bar = HudBar.new()
	sheet_bar.name = "SheetBar"
	helm_block.add_child(sheet_bar)
	rudder_bar = HudBar.new()
	rudder_bar.name = "RudderBar"
	rudder_bar.centred = true
	helm_block.add_child(rudder_bar)
	ranking_panel = _block("Ranking", _paint_ranking, self, false)
	results_panel = _block("Results", _paint_results, self, false)
	for k in ["bsp", "sog", "hdg", "cog", "heel", "tws", "twa", "twd", "aws", "awa", "sail", "sheet", "rudder",
			"message"]:
		_put(k, "")
	_show_race(false)


## a block painted by `painter(block, hud)` (HudPaint) or, with `bind_hud` off, by `painter(block)`
func _block(n: String, painter: Callable, parent: Node = self, bind_hud := true) -> HudCanvas:
	var b := HudCanvas.new()
	b.name = n
	b.painter = painter.bind(self) if bind_hud else painter
	parent.add_child(b)
	return b


# ---- texts ----

func _put(key: String, text: String, colour := HudStyle.PAPER, value := "", unit := "") -> void:
	var old: Variant = texts.get(key)
	texts[key] = {"text": text, "col": colour, "value": value, "unit": unit}
	if old == null or old["text"] != text or old["col"] != colour or old["value"] != value or old["unit"] != unit:
		_bump()


## What the blocks read may have changed (hud.md §1): the blocks that do not follow the camera or the frame time
## build again at their next refresh.
func _bump() -> void:
	_versions += 1
	_version = _versions
	HudCanvas.content_version = _version


## the full text of an item ("" when it shows nothing)
func text_of(key: String) -> String:
	return texts.get(key, {}).get("text", "")


## what a cell shows: the value, else the text
func value_of(key: String) -> String:
	var d: Dictionary = texts.get(key, {})
	var v: String = d.get("value", "")
	return v if v != "" else d.get("text", "")


func unit_of(key: String) -> String:
	return texts.get(key, {}).get("unit", "")


func colour_of(key: String) -> Color:
	return texts.get(key, {}).get("col", HudStyle.PAPER)


## whether an item has something to show now
func shown(key: String) -> bool:
	return text_of(key) != ""


# ---- density (hud.md §16.1) ----

## Race, or Glance on the Steam Deck, on screens under 900 px tall and in portrait (hud.md §16.5).
static func default_density(screen: Vector2) -> Density:
	if OS.has_environment("SteamDeck") or HudStyle.small_screen(screen) or HudStyle.portrait(screen):
		return Density.GLANCE
	return Density.RACE


## Glance, Race, Data, Glance; shows the chip and tells the settings.
func cycle_density() -> void:
	set_density((int(density) + 1) % 3)


func set_density(d: int) -> void:
	density_auto = false
	density = d as Density
	_toast_t = TOAST_TIME
	density_changed.emit(int(density))


## the phase the density table uses: "free" (no race), "pre", "beat", "run", "reach", "rounding", "penalty"
func phase() -> String:
	var r := race
	if not r.active:
		return "free"
	if not r.started:
		return "pre"
	if r.penalty_visible:
		return "penalty"
	if r.next_step > 0 and not r.finished and (r.next_dist <= 6.0 * r._loa or _rounded_t > 0.0):
		return "rounding"
	return r.leg_type if r.leg_type != "" else "beat"


## The items the density and the assist show now (hud.md §16.1, §14): instrument cells ("bsp", "twa_dial",
## "twa", "hdg", "tws", "heel_bar", "vmg_kn", "awa", "sog", "cog", "twd", "aws"; no target speed, hud.md §4), "bug",
## "bug_lap", "bug_gap" (the leader gap), "bug_gaps" (ahead and behind), "shift" (the chip in the heading cell),
## "feed" (every event, 6 lines), "feed_own" (the viewed boat's events, 3 lines), "start_min", "start_full", "hint",
## "mark_eta", "mark_brg" (the mark tag's second line), "radar", "helm". Race is the racer's list: speed, the dial,
## heading, heel, the true wind speed, the mark's distance and time, rank and gap; the rest is Data.
func items() -> Array[String]:
	var ph := phase()
	var key := [int(density), ph, int(assist)]
	if key != _items_key:
		_items = _items_of(ph)
		_items_key = key
	return _items


func _items_of(ph: String) -> Array[String]:
	var out: Array[String] = ["bsp", "twa_dial", "twa", "radar", "helm"]
	var lvl := density
	# the cluster (hud.md §16.3): Race adds heading, the true wind speed and the heel bar; Data the rest
	if lvl >= Density.RACE:
		out.append_array(["hdg", "tws", "heel_bar"])
	if lvl == Density.DATA:
		out.append_array(["vmg_kn", "awa", "sog", "cog", "twd", "aws"])
	match ph:
		"pre":
			out.append("start_min" if lvl == Density.GLANCE else "start_full")
			if lvl == Density.RACE:
				out.append("feed_own")
			if lvl == Density.DATA:
				out.append_array(["bug", "bug_lap", "feed"])
		"free":
			pass
		_:
			out.append("bug")
			if lvl == Density.GLANCE:
				out.append("feed_own")
			elif lvl == Density.RACE:
				out.append_array(["shift", "bug_gap", "mark_eta", "feed_own"])
			else:
				out.append_array(["shift", "bug_gap", "mark_eta", "bug_lap", "bug_gaps", "mark_brg", "hint", "feed"])
	if not shows("shift"):
		out.erase("shift")
	if not shows("sail_hint"):
		out.erase("hint")
	return out


## hud.md §16.1, §16.3: the shift chip shows now in the page's heading cell (the shift item, a lift or a header of
## 2 degrees or more)
func shift_chip_shown() -> bool:
	return has_item("shift") and text_of("shift") != "" and race.shift_kind != ""


func has_item(what: String) -> bool:
	return items().has(what)


## hud.md §4: the VMG angle the TWA pointer is coloured against (rad): the leg's on a beat or run, none on a reach
## (NAN), the nearer half's before the start, free sailing and after the finish
func dial_reference() -> float:
	var up := values.vmg_up_twa
	var dn := values.vmg_dn_twa
	if is_nan(up) or is_nan(dn):
		return NAN
	if race.active and race.started and race.next_step > 0 and race.leg_type != "":
		match race.leg_type:
			"beat":
				return up
			"run":
				return dn
			_:
				return NAN
	return up if absf(values.twa) < (up + dn) * 0.5 else dn


## hud.md §16.3: the true wind pointer's colour on the angle error: stbd up to 2 degrees, mark at 11, port from 20,
## linear between; paper with no reference
func pointer_colour() -> Color:
	var ref := dial_reference()
	if is_nan(ref):
		return HudStyle.PAPER
	return angle_error_colour(rad_to_deg(absf(absf(values.twa) - ref)), colours())


static func angle_error_colour(err_deg: float, palette: Dictionary) -> Color:
	var green: Color = palette[HudValues.Colour.GREEN]
	var red: Color = palette[HudValues.Colour.RED]
	if err_deg <= 2.0:
		return green
	if err_deg <= 11.0:
		return green.lerp(HudStyle.MARK, (err_deg - 2.0) / 9.0)
	if err_deg < 20.0:
		return HudStyle.MARK.lerp(red, (err_deg - 11.0) / 9.0)
	return red


## hud.md §13.1: the finish card shows now
func finish_card_shown() -> bool:
	return race.active and race.card_alpha() > 0.0


## the finish card's opacity this frame (between ticks)
func finish_card_alpha() -> float:
	return race.card_alpha(clampf(_since_tick / SimSource.DT, 0.0, 1.0))


func countdown_shown() -> bool:
	var c := text_of("clock")
	return race.active and (c.begins_with("Start in") or c.begins_with("Warning in"))


## the prep flag's rule in one line while the prep flag is up, in caps ("I FLAG: OVER IN THE LAST MINUTE MEANS ...")
func flag_rule() -> String:
	if not race.active or race.started:
		return ""
	var up := false
	for f in race.flags:
		if f in ["P", "I", "Z", "U", "black"]:
			up = true
	if not up:
		return ""
	return RaceText.PREP_MEANING[clampi(race.prep_flag, 0, 4)].to_upper()


## the feed lines the density shows: every event, 6 lines, at Data; the viewed boat's own, 3 lines, at Glance and Race
func feed_lines() -> Array:
	var out := []
	var all := has_item("feed")
	var n := 6 if all else 3
	for l in race.feed:
		if all or (has_item("feed_own") and l.own):
			out.append(l)
	return out.slice(maxi(out.size() - n, 0))


## the feed lines shown now (tests, previews)
func feed_text() -> Array[String]:
	var out: Array[String] = []
	for l in race.feed:
		out.append(l.text)
	return out


# ---- sim and input ----

## Once per simulation tick.
func tick(s: SimSource, boat: int) -> void:
	sim = s
	viewed = boat
	values.tick(s, boat)
	race.tick(s, boat)
	radar.sim = s
	_since_tick = 0.0
	_bump()


## The HUD keys of this frame (controls.md §2): rankings (Tab, or a long View press), the course map (M), radar zoom
## and orientation, hud_density (G, or a short View press), boat_select, boat_pick (click or tap), boat_names.
## Optional: without it frame() polls the input map.
func ui_input(raw: RawInput, dt := 1.0 / 60.0) -> void:
	_ui_fed = true
	if rankings_toggle:
		if raw.was_pressed(&"rankings") or raw.was_pressed(&"rankings_pad"):
			show_ranking = not show_ranking
		_view_held = 0.0
	else:
		var view := raw.is_held(&"rankings_pad")
		if view:
			_view_held += dt
		elif _view_held > 0.0:
			if _view_held < VIEW_TAP:
				cycle_density()
			_view_held = 0.0
		show_ranking = raw.is_held(&"rankings") or (view and _view_held >= VIEW_TAP)
	if raw.was_pressed(&"map") and map_enabled:
		toggle_map()
	if raw.was_pressed(&"radar_zoom_in"):
		radar.zoom(-1)
	if raw.was_pressed(&"radar_zoom_out"):
		radar.zoom(1)
	if raw.was_pressed(&"radar_orientation"):
		radar.toggle_orientation()
	if raw.was_pressed(&"hud_density"):
		cycle_density()
	if raw.was_pressed(&"boat_select"):
		select_next()
	if raw.was_pressed(&"boat_names"):
		cycle_names()
	if raw.was_pressed(&"boat_pick") and pick_enabled:
		if not is_nan(raw.pointer.x):
			pick_at(raw.pointer)
		elif is_inside_tree():
			pick_at(get_viewport().get_mouse_position())


func _poll_input() -> void:
	if _ui_fed or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var raw := RawInput.new()
	for a in [&"rankings", &"rankings_pad", &"map", &"radar_zoom_in", &"radar_zoom_out", &"radar_orientation", &"hud_density",
			&"boat_select", &"boat_names"]:  # boat_pick needs the click-or-drag of InputReader
		if InputMap.has_action(a):
			if Input.is_action_pressed(a):
				raw.hold(a)
			if Input.is_action_just_pressed(a):
				raw.pressed.append(a)
	ui_input(raw, get_process_delta_time())


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
			_put("message", controls.messages.back())
			controls.messages.clear()
			_message_t = MESSAGE_TIME
	_flash_t = maxf(_flash_t - dt, 0.0)
	_message_t = maxf(_message_t - dt, 0.0)
	_toast_t = maxf(_toast_t - dt, 0.0)
	_rounded_t = maxf(_rounded_t - dt, 0.0)
	if _message_t <= 0.0:
		_put("message", "")
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
	_check_selection()
	radar.selected = selected_boat()
	radar.advance(dt)
	_race_frame()
	_map_frame()
	# the other inputs of the blocks that build per content version (hud.md §1)
	var ph := phase()
	var cam := world_camera() != null
	if ph != _phase_seen or HudStyle.palette != _palette_seen or cam != _camera_seen:
		_phase_seen = ph
		_palette_seen = HudStyle.palette
		_camera_seen = cam
		_bump()
	start_block.dynamic = finish_card_shown()
	# from here the blocks' inputs are set for the frame: each is built once (HudCanvas.memo_frame)
	_versions += 1
	HudCanvas.memo_frame = _versions
	HudCanvas.content_version = _version
	_layout()
	_redraw()
	HudCanvas.memo_frame = -1


## PlayerControls asks the HUD whether the protest prompt shows and whether a hail can be made or answered.
func _wire(c: PlayerControls) -> void:
	if c == _wired:
		return
	_wired = c
	c.protest_prompt = func() -> bool: return race.active and race.protest_prompt()
	c.hail_available = func() -> bool: return race.active and race.hail_available
	c.hailed = func() -> bool: return race.active and race.hailed_by >= 0


# ---- course map (hud.md §8.1) ----

## Opens or closes the course map (the `map` action); it opens only with a race.
func toggle_map() -> void:
	if map_open:
		close_map()
	elif race.active and sim != null:
		map_open = true
		_map_sim = sim


## Closes the course map; whether it was open (Esc closes it before anything else, hud.md §8.1).
func close_map() -> bool:
	var was := map_open
	map_open = false
	return was


## Every frame: the map closes by itself without a race, on a new sim, or when the results or the finish card show;
## it follows the radar's pose blend, the felt wind, the assist, the name tags and the selection.
func _map_frame() -> void:
	if map_open and (not race.active or sim != _map_sim or results_panel.visible or finish_card_shown()):
		map_open = false
	map_view.sim = sim
	map_view.alpha = radar.alpha
	map_view.twd = values.twd
	map_view.tws = values.tws
	map_view.zone = shows("zone")
	map_view.names = show_names
	map_view.selected = selected_boat()


func toggle_hidden() -> void:
	visible = not visible


## hud.md §14: whether the assist preset shows a race element ("laylines", "layline_distance", "zone",
## "radar_colours", "shift", "burn_bias", "sail_hint", "shadow_view"; everything else always)
func shows(what: String) -> bool:
	match what:
		"laylines", "layline_distance", "zone", "radar_colours", "shift", "burn_bias":
			return assist != Assist.MINIMAL
		"sail_hint", "shadow_view":
			return assist == Assist.FULL
	return true


# ---- text refresh (4 Hz, hud.md §1 formats) ----

## Rewrites every number from the values of the last tick.
func refresh_text() -> void:
	_bump()
	var v := values
	for kv in [["bsp", "BSP", v.bsp], ["sog", "SOG", v.sog], ["tws", "TWS", v.tws], ["aws", "AWS", v.aws]]:
		var s := HudFormat.speed_kn(kv[2])
		_put(kv[0], "%s  %s kn" % [kv[1], s], HudStyle.PAPER, s, "KN")
	_put("hdg", "HDG  %s" % HudFormat.compass_deg(v.hdg), HudStyle.PAPER, HudFormat.compass_deg(v.hdg))
	var cog := HudFormat.compass_deg(v.cog) if v.sog / HudFormat.KNOT > 0.3 else "--"
	_put("cog", "COG  %s" % ("---" if cog == "--" else cog), HudStyle.PAPER, cog)
	var heel := HudFormat.side_angle(v.heel, "S", "P")
	_put("heel", "Heel  %s" % heel, HudStyle.PAPER, heel)
	var twa := HudFormat.side_angle(v.twa, "S", "P")
	_put("twa", "TWA  %s" % twa, HudStyle.PAPER, twa)
	_put("twd", "TWD  %s" % HudFormat.compass_deg(v.twd), HudStyle.PAPER, HudFormat.compass_deg(v.twd))
	var awa := HudFormat.side_angle(v.awa, "S", "P")
	_put("awa", "AWA  %s" % awa, HudStyle.PAPER, awa)
	var sail := _sail_name(v.sail_up) if v.sail_up != "" else "Main only"
	_put("sail", "Sail  %s" % sail, HudStyle.PAPER, sail.to_upper())
	# hud.md §5.1: the one hoist cue
	_put("hoist", "HOISTING %s" % _sail_name(v.sail_hoisting).to_upper() if v.sail_hoisting != "" else "")
	_put("rudder", "Helm  %s" % _signed_pct(v.h), HudStyle.PAPER, _signed_pct(v.h))
	var sheet := "AUTO" if v.auto_trim else "%s %%" % HudFormat.percent(100.0 * v.sheet_cmd)
	_put("sheet", "Sheet  %s%s" % [sheet, "   LET FLY" if v.let_fly else ""], HudStyle.PAPER,
		sheet + (", LET FLY" if v.let_fly else ""))
	_put("vmg_kn", "", HudStyle.PAPER, "--")
	HudText.race(self)
	HudText.card(self)


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
	sheet_bar.visible = not v.auto_trim
	sheet_bar.value = v.sheet_cmd
	sheet_bar.mark = NAN
	while gauge_views.size() < v.gauges.size():
		var gv := TrimGaugeView.new()
		gauge_box.add_child(gv)
		gauge_views.append(gv)
	var glance := density == Density.GLANCE
	for i in gauge_views.size():
		var gv := gauge_views[i]
		gv.visible = i < v.gauges.size() and not v.auto_trim
		if i >= v.gauges.size():
			continue
		var g: HudValues.Gauge = v.gauges[i]
		var title := g.name.capitalize()
		if gv.title != title:
			gv.title = title
			gv.name = "Gauge" + title.replace(" ", "")
		gv.auto = g.auto
		gv.greyed = g.greyed
		gv.needle = g.needle
		gv.show_needle = assist != Assist.MINIMAL
		gv.colour = colours()[HudValues.Colour.NONE] if (g.auto or assist == Assist.MINIMAL) else colours()[g.colour]
		gv.telltale = g.telltale
		gv.labels = not glance


# ---- race ----

func _show_race(on: bool) -> void:
	for p in [race_panel, next_panel, bug_block, feed_block]:
		p.visible = on
	if not on:
		penalty_panel.visible = false
		ranking_panel.visible = false
		results_panel.visible = false
		for k in ["vmg", "shift", "banner", "rules", "prompt"]:
			_put(k, "")


## Every frame: visibility, the parts that move, the prompt countdown, the banner and the tables.
func _race_frame() -> void:
	var r := race
	if not r.active:
		if race_panel.visible:
			_show_race(false)
		return
	if not race_panel.visible:
		_show_race(true)
		refresh_text()
	if r.started and r.next_step > _last_step and _last_step > 0:
		_rounded_t = ROUNDING_TIME
	_last_step = r.next_step
	flags_view.flags = r.flags
	flags_view.visible = not r.flags.is_empty() and has_item("start_full")
	arrow_view.sides = r.next_sides
	arrow_view.visible = r.next_step > 0
	turn_view.turn_deg = r.turn_deg
	turn_view.target_deg = r.turn_target
	turn_view.tack_done = r.turn_tack
	turn_view.gybe_done = r.turn_gybe
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
	_put("prompt", prompt, HudStyle.TINTS[RaceHudValues.Tint.YELLOW])
	if r.banner != null:
		_put("banner", r.banner.text, HudStyle.TINTS[r.banner.tint])
	else:
		_put("banner", "")
	var m := r.message
	if m != null and (assist != Assist.MINIMAL or m.breach):
		_put("rules", m.text, HudStyle.TINTS[m.tint])
	else:
		_put("rules", "")
	results_panel.visible = results_table and r.results_visible and (r.results_final or r.banner == null) \
		and not finish_card_shown()
	ranking_panel.visible = show_ranking and not results_panel.visible
	if results_panel.visible:
		results_title = "Results" if r.results_final else "Provisional results"


## the ranking list as text rows (tests, previews)
func ranking_text() -> Array[String]:
	var out: Array[String] = []
	for rw in race.ranking_rows():
		out.append("%d  %s%s  %s  %s" % [rw["rank"], rw["name"], "  [%s]" % rw["ai"] if rw["ai"] != "" else "",
			rw["gap"], rw["status"]])
	return out


func _paint_ranking(b: HudCanvas) -> void:
	var rows := []
	var own := -1
	for rw in race.ranking_rows():
		if int(rw.get("boat", -1)) == race.boat:
			own = rows.size()
		rows.append([str(rw["rank"]), rw["name"], rw["gap"], rw["ai"], rw["status"]])
	HudPaint.table(b, "Ranking", ["", "Boat", "Gap", "", "Status"], rows, RANK_W, own)


func _paint_results(b: HudCanvas) -> void:
	var own := -1
	for i in race.result_rows.size():
		if int(race.result_rows[i].get("boat", -1)) == race.boat:
			own = i
	HudPaint.table(b, results_title, ["Place", "Boat", "Skipper", "", "Time", "Gap", "Code", "Points"],
		results_text_rows(), RESULT_W, own)


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
			pts = HudFormat.points(r["points"])
		out.append([place, r["name"], r["skipper"], r["ai"], t, g, r["code"], pts])
	return out


## "+10 s", "-3 s"
static func signed_seconds(s: float) -> String:
	var t := int(HudFormat.round_half_away(absf(s)))
	return "%s%d s" % ["-" if s < 0.0 and t > 0 else "+", t]


# ---- world: camera, projection, tags (hud.md §16.4) ----

func world_camera() -> Camera3D:
	if camera != null:
		return camera
	if camera_rig != null and is_instance_valid(camera_rig):
		var c: Variant = camera_rig.get("camera")
		if c is Camera3D:
			return c
	return null


## "chase", "onboard", "aerial", "free" (the rig's mode, or `camera_kind` without a rig)
func current_camera_kind() -> String:
	if camera == null and camera_rig != null and is_instance_valid(camera_rig):
		var m: Variant = camera_rig.get("mode")
		if typeof(m) == TYPE_INT:
			return ["chase", "onboard", "aerial", "free"][clampi(m, 0, 3)]
	return camera_kind


## a world ENU point (m) on screen, null when behind the camera or without one
func project(enu: Vector3) -> Variant:
	var cam := world_camera()
	if cam == null or not cam.is_inside_tree():
		return null
	var p := Frames.enu_to_scene(enu.x, enu.y, enu.z)
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _on_screen(p: Variant, margin := 0.0) -> bool:
	if p == null:
		return false
	var s := _screen_size()
	var q: Vector2 = p
	return q.x >= margin and q.y >= margin and q.x <= s.x - margin and q.y <= s.y - margin


func own_pose() -> SimSource.RenderPose:
	if sim == null:
		return null
	if viewed < 0:
		return null
	return sim.render_pose(viewed, radar.alpha)


func own_world(z: float) -> Vector3:
	var p := own_pose()
	return Vector3(p.pos_x, p.pos_y, z) if p != null else Vector3.ZERO


## the next mark's point (the nearer buoy of a gate, the nearest point of a line)
func mark_world() -> Vector3:
	var r := race
	var pts := r.step_points(r.next_step)
	var o := own_world(0.0)
	var c := Vector2(o.x, o.y)
	var best := pts[0]
	if int(r.course()["steps"][r.next_step]["kind"]) == RaceText.Step.FINISH:
		best = Geometry2D.get_closest_point_to_segment(c, pts[0], pts[1])
	else:
		for p in pts:
			if c.distance_to(p) < c.distance_to(best):
				best = p
	return Vector3(best.x, best.y, 1.5)


## the next mark on screen, null when off screen or there is none
func mark_screen() -> Variant:
	if not race.active or race.next_step <= 0 or race.finished or world_camera() == null:
		return null
	var p: Variant = project(mark_world())
	return p if _on_screen(p, 20.0 * _k) else null


## the tack point (ENU) where the current COG meets the other tack's layline, null when not shown
func world_tack_point() -> Variant:
	var r := race
	if world_camera() == null or sim == null or not r.active or r.next_step <= 0 or is_nan(r.layline_dist) \
			or not is_nan(r.overstood):
		return null
	if not shows("layline_distance") or not (r.leg_type in ["beat", "run"]):
		return null
	var s := sim.state(viewed)
	if s == null:
		return null
	var g := Vector2(s.sog_filt_x, s.sog_filt_y)
	if g.length() < 0.1:
		return null
	var o := own_world(0.0)
	return Vector2(o.x, o.y) + g.normalized() * r.layline_dist


## `boat_names` (hud.md §16.4): watch (a rules relation or selected, the default) -> all (every boat within
## TAG_RANGE) -> off -> watch, each with its note.
func cycle_names() -> void:
	if show_names and not names_all:
		names_all = true
		note(NOTE_NAMES_ALL)
	elif show_names:
		show_names = false
		names_all = false
		note(NOTE_NAMES_OFF)
	else:
		show_names = true
		note(NOTE_NAMES_WATCH)


## A note in the helm notes for MESSAGE_TIME (the line the controls' notes use).
func note(text: String) -> void:
	_put("message", text)
	_message_t = MESSAGE_TIME


## hud.md §16.4: the boat has a rules relation to the viewed boat now (a radar colour other than white, not a ghost)
func has_relation(b: int) -> bool:
	for ct in race.contacts:
		if ct.boat == b:
			return not ct.ghost and ct.tint != RaceHudValues.Tint.WHITE
	return false


## the name tags to draw now: [{boat, p (screen), name, col, solid, outline}] (hud.md §16.4: within 50 m with a
## rules relation, every boat within 50 m with `names_all`, or selected; none with `show_names` off)
func name_tags() -> Array:
	var out := []
	if not show_names or sim == null or world_camera() == null:
		return out
	var me := own_pose()
	if me == null:
		return out
	for b in tag_boats():
		var q: Variant = project(masthead(b))
		if _on_screen(q):
			out.append(_tag(b, q))
	return out


## the boats that get a name tag now, on screen or not: within TAG_RANGE of the viewed boat with a rules relation
## (every boat within it in the all state), or selected
func tag_boats() -> Array[int]:
	var out: Array[int] = []
	if not show_names or sim == null:
		return out
	var me := own_pose()
	if me == null:
		return out
	for b in sim.boat_count():
		if b == viewed:
			continue
		var p := sim.render_pose(b, radar.alpha)
		if p == null:
			continue
		var near := Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length() <= TAG_RANGE
		if selected.has(b) or (near and (names_all or has_relation(b))):
			out.append(b)
	return out


func _tag(b: int, q: Vector2) -> Dictionary:
	var col := HudStyle.PAPER
	var solid := false
	var outline := false
	for ct in race.contacts:
		if ct.boat == b:
			col = radar.contact_colour(ct)
			solid = not ct.ghost and radar.colours and ct.tint != RaceHudValues.Tint.WHITE
			outline = radar.colours and ct.pulse == RaceHudValues.Pulse.BREACH and not ct.ghost
	return {"boat": b, "p": q, "name": race.name_of(b).to_upper(), "col": col, "solid": solid, "outline": outline}


## the selected boats that are off screen: [{w (ENU), name, d, col}]
func selected_off_screen() -> Array:
	var out := []
	if not show_names or sim == null or world_camera() == null:
		return out
	var me := own_pose()
	if me == null:
		return out
	for b in selected:
		if b >= sim.boat_count():
			continue
		var p := sim.render_pose(b, radar.alpha)
		if p == null:
			continue
		var w := masthead(b)
		if _on_screen(project(w)):
			continue
		out.append({"w": w, "name": race.name_of(b).to_upper(), "col": HudStyle.PAPER,
			"d": Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length()})
	return out


func mast_height(b: int) -> float:
	return 1.35 * sim.class_info(b).loa


## a body-frame point (x fwd, y port, z up, m) of boat `b` in the world (ENU), heel and pitch included
## (conventions.md §3 attitude)
func boat_point(b: int, body: Vector3) -> Vector3:
	var p := sim.render_pose(b, radar.alpha)
	if p == null:
		return Vector3.ZERO
	return Vector3(p.pos_x, p.pos_y, p.z) + Frames.attitude_enu(p.psi, p.theta, p.phi) * body


## hud.md §16.4: the masthead of boat `b` as she floats (ENU), so tags and the marker stay over her rig when she heels
func masthead(b: int) -> Vector3:
	return boat_point(b, Vector3(0.0, 0.0, mast_height(b)))


## the selected boat, -1 for none
func selected_boat() -> int:
	return int(selected.keys()[0]) if not selected.is_empty() else -1


## selects boat `b` alone (-1 clears)
func select(b: int) -> void:
	selected.clear()
	if b >= 0:
		selected[b] = true
	HudText.card(self)


## clears the selection; whether there was one (Esc clears it before it pauses, hud.md §16.4.1)
func clear_selection() -> bool:
	var had := not selected.is_empty()
	select(-1)
	return had


## the selection clears when she is the viewed boat, is gone, or the race is over
func _check_selection() -> void:
	var b := selected_boat()
	if b < 0:
		return
	if sim == null or b == viewed or b >= sim.boat_count() or race.race_over:
		select(-1)


## boat_select: the boats by distance from the viewed boat at the press, nearest first; the next one after the
## selected boat, after the farthest none (hud.md §16.4.1)
func select_next() -> void:
	if sim == null:
		return
	var me := own_pose()
	if me == null:
		return
	var order := []
	for b in sim.boat_count():
		if b == viewed:
			continue
		var p := sim.render_pose(b, radar.alpha)
		if p != null:
			order.append([Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length(), b])
	order.sort()
	var cur := selected_boat()
	var i := -1
	for j in order.size():
		if order[j][1] == cur:
			i = j
	select(order[i + 1][1] if i + 1 < order.size() else -1)


## a boat's hull and rig on screen: the triangle from bow and stern at the waterline to the masthead, without the
## corners behind the camera (empty when all are)
func boat_triangle(b: int) -> PackedVector2Array:
	var p := sim.render_pose(b, radar.alpha)
	if p == null:
		return PackedVector2Array()
	var half := 0.5 * sim.class_info(b).loa
	var f := Vector2(sin(p.psi), cos(p.psi)) * half
	var out := PackedVector2Array()
	for w in [Vector3(p.pos_x + f.x, p.pos_y + f.y, p.z), Vector3(p.pos_x - f.x, p.pos_y - f.y, p.z), masthead(b)]:
		var q: Variant = project(w)
		if q != null:
			out.append(q)
	return out


## the screen distance from `pos` to a triangle (0 inside), or to the segment or point left of it
static func _tri_distance(pos: Vector2, tri: PackedVector2Array) -> float:
	var n := tri.size()
	if n == 3 and Geometry2D.is_point_in_polygon(pos, tri):
		return 0.0
	if n == 1:
		return pos.distance_to(tri[0])
	var d := INF
	for i in n:
		d = minf(d, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, tri[i], tri[(i + 1) % n])))
	return d


## the boat under a screen point (hud.md §16.4.1: her hull and rig triangle grown by PICK_RADIUS; the nearest one,
## between boats covering the point the one nearest the camera); -1 for none
func boat_at(pos: Vector2) -> int:
	var cam := world_camera()
	if sim == null or cam == null:
		return -1
	var best := -1
	var best_d := PICK_RADIUS * _k
	var best_depth := INF
	for b in sim.boat_count():
		if b == viewed:
			continue
		var tri := boat_triangle(b)
		if tri.is_empty():
			continue
		var d := _tri_distance(pos, tri)
		var p := sim.render_pose(b, radar.alpha)
		var depth := cam.global_position.distance_to(Frames.enu_to_scene(p.pos_x, p.pos_y, p.z))
		if d < best_d - 1e-6 or (d <= 0.0 and best_d <= 0.0 and depth < best_depth):
			best_d = d
			best = b
			best_depth = depth
	return best


## boat_pick: a click or tap at a screen point selects the boat there; on the selected boat again or on open water
## it clears (hud.md §16.4.1). Returns the boat picked, -1 for none.
func pick_at(pos: Vector2) -> int:
	if map_open:  # hud.md §8.1: on the map's icons, never in the 3D view behind it
		var mb := map_view.boat_at(pos)
		select(mb if mb >= 0 and mb != selected_boat() else -1)
		return mb
	if sim == null or world_camera() == null:
		return -1
	var b := boat_at(pos)
	select(b if b >= 0 and b != selected_boat() else -1)
	return b


## the selected boat's marker on screen (hud.md §16.4.1): {boat, head (her masthead, px), tip (the pointer's tip, px),
## pts (its triangle), col}; empty when her masthead is off screen or none is selected
func selected_marker() -> Dictionary:
	var b := selected_boat()
	if b < 0 or sim == null or world_camera() == null or b >= sim.boat_count():
		return {}
	var q: Variant = project(masthead(b))
	if not _on_screen(q):
		return {}
	var head: Vector2 = q
	var tip := head - Vector2(0.0, MARKER_GAP * _k)
	var pts := PackedVector2Array([tip, tip + Vector2(MARKER_W * 0.5, -MARKER_H) * _k,
		tip + Vector2(-MARKER_W * 0.5, -MARKER_H) * _k])
	return {"boat": b, "head": head, "tip": tip, "pts": pts, "col": _tag(b, head)["col"]}


# ---- ladder lines (hud.md §16.4.2) ----

## the ladder axis (ENU unit vector pointing "ahead"): upwind on a beat, before the start and free sailing, downwind
## on a run, to the next mark on a reach
func ladder_axis() -> Vector2:
	var twd := race.twd10() if race.active else values.twd
	var up := Vector2(sin(twd), cos(twd))
	if race.active and race.started and race.next_step > 0 and not race.finished:
		if race.leg_type == "run":
			return -up
		if race.leg_type == "reach":
			var o := own_world(0.0)
			var m := mark_world()
			var v := Vector2(m.x - o.x, m.y - o.y)
			if v.length() > 1.0:
				return v.normalized()
	return up


## hud.md §16.4.2: the bow of boat `b` on the water (ENU, x and y): the bow point of her hull as she floats
func bow_water(b: int) -> Vector2:
	var w := boat_point(b, Vector3(0.5 * sim.class_info(b).loa, 0.0, 0.0))
	return Vector2(w.x, w.y)


## the ladder lines while a boat is selected (hud.md §16.4.2): each from its boat's bow, square to the axis, towards
## the other boat and past her line. {own: [PackedVector2Array], her: [...], gain (her lead along the axis, bow to
## bow, in the viewed boat's hull lengths), text, label (px or null), axis, own_w and her_w (each line's ends, ENU,
## the bow first)}; empty with none
func ladder_lines() -> Dictionary:
	var b := selected_boat()
	if b < 0 or sim == null or viewed < 0 or world_camera() == null or map_open or not world_tags or race.race_over:
		return {}
	var me := own_pose()
	var her := sim.render_pose(b, radar.alpha)
	if me == null or her == null:
		return {}
	var a := ladder_axis()
	var p := Vector2(a.y, -a.x)
	var o := bow_water(viewed)
	var s := bow_water(b)
	var loa := sim.class_info(viewed).loa
	var gain := (s - o).dot(a) / maxf(loa, 0.1)
	_ladder_shapes = []
	for k in sim.boat_count():
		var tri := boat_triangle(k)
		if tri.size() == 3:
			_ladder_shapes.append(tri)
	var text := "EVEN" if absf(gain) < 0.05 else "%.1f L %s" % [absf(gain), "AHEAD" if gain > 0.0 else "BEHIND"]
	# towards the other boat across the axis, past her line by LADDER_PAST, at least LADDER_MIN
	var across := (s - o).dot(p)
	var to_her := p if across >= 0.0 else -p
	var length := maxf(absf(across) + LADDER_PAST, LADDER_MIN)
	var own_end := o + to_her * length
	var her_end := s - to_her * length
	var lab := s - to_her * 2.0 * sim.class_info(b).loa
	return {"own": _ladder(o, own_end), "her": _ladder(s, her_end), "gain": gain, "text": text,
		"label": project(Vector3(lab.x, lab.y, 0.0)), "axis": a, "own_w": [o, own_end], "her_w": [s, her_end]}


## a line on the water from `from` to `to` (ENU): its runs on screen (the parts in front of the camera and not over
## a boat's hull and rig)
func _ladder(from: Vector2, to: Vector2) -> Array:
	var out := []
	var run := PackedVector2Array()
	var n := maxi(1, ceili(from.distance_to(to) / LADDER_STEP))
	for i in n + 1:
		var w := from.lerp(to, float(i) / n)
		var q: Variant = project(Vector3(w.x, w.y, 0.0))
		if q != null and _over_boat(q):
			q = null
		if q == null:
			if run.size() >= 2:
				out.append(run)
			run = PackedVector2Array()
			continue
		run.append(q)
	if run.size() >= 2:
		out.append(run)
	return out


## a ladder line's point over a boat's hull and rig on screen (the line is not drawn over boats)
func _over_boat(q: Vector2) -> bool:
	for tri in _ladder_shapes:
		if _tri_distance(q, tri) < LADDER_CLEAR * _k:
			return true
	return false


# ---- world labels keep clear of the HUD's blocks (hud.md §16.4) ----

## the screen rects the HUD's own blocks draw now (instrument page and chip, radar, helm strip and notes, the
## next-mark arrow, race bug, feed, alert lane, boat card)
func keep_clear_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for blk in [inst_page, toast_block, radar, helm_notes, mark_arrow_block, bug_block, feed_block, start_block,
			penalty_panel, alerts_block, card_block]:
		var c := blk as HudCanvas
		if not c.visible or not c.is_visible_in_tree() and c.is_inside_tree():
			continue
		if c.get_parent() == race_panel and not race_panel.visible:
			continue
		var e := c.extent()
		if e.size == Vector2.ZERO:
			continue
		var o := c.position + (race_panel.position if c.get_parent() == race_panel else Vector2.ZERO)
		out.append(Rect2(e.position + o, e.size))
	if helm_block.visible:
		out.append(Rect2(helm_block.position, helm_block.size))
	return out


## whether a world label's screen rect is clear of the HUD's blocks and on screen
func label_clear(r: Rect2, rects: Array[Rect2] = []) -> bool:
	if rects.is_empty():
		rects = keep_clear_rects()
	if not Rect2(Vector2.ZERO, _screen_size()).encloses(r):
		return false
	for k in rects:
		if r.intersects(k):
			return false
	return true


# ---- next-mark arrow (hud.md §7.1) ----

## hud.md §7.1: the next-mark arrow, in the onboard, aerial and free cameras while the mark tag would show and the
## mark is off screen
func mark_arrow_shown() -> bool:
	var r := race
	if not world_tags or map_open or not r.active or r.next_step <= 0 or r.finished or text_of("next") == "":
		return false
	if world_camera() == null or own_pose() == null:
		return false
	return current_camera_kind() != "chase" and mark_screen() == null


## hud.md §7.1: the arrow's screen angle (rad, 0 = up, clockwise): the bearing from the viewed boat to the next
## mark in the camera's frame on the water (up = its forward direction there, or its up direction looking down)
func mark_arrow_angle() -> float:
	var cam := world_camera()
	if cam == null:
		return 0.0
	var o := own_world(0.0)
	var mw := mark_world()
	var v := Vector2(mw.x - o.x, mw.y - o.y)
	var bs := cam.global_transform.basis
	var f3 := Frames.scene_to_enu(-bs.z)
	var fwd := Vector2(f3.x, f3.y)
	if fwd.length() < 0.2:
		var u3 := Frames.scene_to_enu(bs.y)
		fwd = Vector2(u3.x, u3.y)
	if fwd.length() < 1e-6 or v.length() < 1e-6:
		return 0.0
	fwd = fwd.normalized()
	var right := Vector2(fwd.y, -fwd.x)
	return atan2(v.dot(right), v.dot(fwd))


# ---- layout (hud_direction.md §5) ----

func _screen_size() -> Vector2:
	if screen_size.x > 0.0 and screen_size.y > 0.0:
		return screen_size
	if is_inside_tree():
		var s := get_viewport_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	if size.x > 0.0 and size.y > 0.0:
		return size
	return Vector2(1920, 1080)


## Lays the HUD out for the screen now: positions, sizes, the scale of every block, which blocks show.
func layout_now() -> void:
	_layout()


func _layout() -> void:
	HudLayout.blocks(self)
	HudLayout.map(self)


func _all_canvases() -> Array[HudCanvas]:
	var n := 22 + gauge_views.size()
	if _canvases.size() != n:
		_canvases = [world, inst_page, toast_block, bug_block, feed_block, start_block,
			flags_view, penalty_panel, turn_view, alerts_block, next_panel, card_block, arrow_view, mark_arrow_block, radar,
			helm_block, helm_notes,
			rudder_bar, sheet_bar, ranking_panel, results_panel, map_view]
		for g in gauge_views:
			_canvases.append(g)
	return _canvases


## hud.md §1: every visible block built again (once per frame), redrawn only when what it draws changed.
func _redraw() -> void:
	for n in _all_canvases():
		if n.is_visible_in_tree():
			n.refresh()


## Every visible HudCanvas of the HUD as laid out now (tests, previews).
func blocks() -> Array[HudCanvas]:
	var out: Array[HudCanvas] = []
	_collect(self, out)
	return out


func _collect(n: Node, out: Array[HudCanvas]) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is HudCanvas:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
