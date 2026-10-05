class_name Hud
extends Control
## The in-race HUD (hud.md). The boat instruments (§2, §3.1, §5: speed, heading, heel, true and apparent wind, helm
## and sheet, sail status, trim gauges) and, while the sim has a race, the race HUD: start countdown and flags
## (§9.1), signal banners, the start numbers with time to burn and bias, OVER and OCS (§9.2), the next mark tag
## with its rounding side, distance, bearing and ETA (§7), VMG / VMC and targets (§4), the tack point (§6), the
## shift meter (§3.2), the sail hint, rank, gaps and splits (§10), the rules line (§11), the protest and hail
## prompts, the penalty panel and the turn on the water (§12), the radar (§8), the event feed and the ranking
## list and results (§13), each shown per the assist preset (§14) and the instrument density (§16.1).
##
## The look is hud.md §16 and docs/design/hud_direction.md: glass instrument pages, Barlow Semi Condensed with
## tabular figures, the colour tokens of HudStyle; every block is a HudCanvas painted by HudPaint. World tags
## (mark tag, tack point, name tags, edge pointers, penalty turn) need the scene's camera (`camera_rig`, or
## `camera`); without one the mark tag is docked under the race bug and the rest is left out.
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
const TOAST_TIME := 1.5
const ROUNDING_TIME := 6.0
## hud.md §16.4: name tags within this range of the viewed boat, m
const TAG_RANGE := 50.0
## a click or tap within this many px of a boat picks it (design px)
const PICK_RADIUS := 40.0
## controls.md §3: a View press shorter than this is a tap (density), longer the ranking list
const VIEW_TAP := 0.3
const RANK_W := [70.0, 260.0, 130.0, 120.0, 120.0]
const RESULT_W := [70.0, 220.0, 200.0, 120.0, 170.0, 110.0, 90.0, 90.0]

var assist := Assist.STANDARD
## the instrument density (hud.md §16.1); while `density_auto` it follows the screen (default_density)
var density := Density.RACE:
	set(d):
		density = clampi(d, 0, 2) as Density
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
## name tags on (the `boat_names` action) and the boats the player selected for a tag
var show_names := true
## controls.md §7 world_tags: the world tags (mark tag, tack point, name tags, edge pointers, penalty turn) shown
var world_tags := true
var selected := {}
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
var wind_page: HudCanvas
var feed_block: HudCanvas
## the top centre lane: start block, penalty panel, rules line, banner, prompt (visible while the sim has a race)
var race_panel: Control
var start_block: HudCanvas
var flags_view: FlagsView
var penalty_panel: HudCanvas
var ring_view: PenaltyRingView
var alerts_block: HudCanvas
var next_panel: HudCanvas
var arrow_view: RoundingArrowView
var radar: RadarView
var helm_block: HudCanvas
var helm_notes: HudCanvas
var rudder_bar: HudBar
var sheet_bar: HudBar
var gauge_box: Control
var gauge_views: Array[TrimGaugeView] = []
var ranking_panel: HudCanvas
var results_panel: HudCanvas
var results_title := ""
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
var _k := 1.0
## where edge pointers run in portrait (hud.md §16.5), screen px; empty in landscape (HudPaint.edge_pointer's own box)
var edge_box := Rect2()



## HudValues.Colour -> token, in the colour-blind palette in use (hud.md §16.2.1)
static func colours() -> Dictionary:
	return {
		HudValues.Colour.NONE: HudStyle.PAPER,
		HudValues.Colour.GREEN: HudStyle.STBD,
		HudValues.Colour.YELLOW: HudStyle.MARK,
		HudValues.Colour.RED: HudStyle.PORT,
	}

func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	race.hud_event.connect(func(kd: String, d: Dictionary) -> void: hud_event.emit(kd, d))
	world = _block("World", HudPaint.world)
	inst_page = _block("Instruments", HudPaint.instruments)
	toast_block = _block("InstrumentsChip", HudPaint.toast)
	toast_block.visible = false
	bug_block = _block("RaceBug", HudPaint.bug)
	wind_page = _block("Wind", HudPaint.wind)
	feed_block = _block("Feed", HudPaint.feed)
	race_panel = Control.new()
	race_panel.name = "Race"
	race_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(race_panel)
	start_block = _block("Start", HudPaint.start, race_panel)
	flags_view = FlagsView.new()
	flags_view.name = "Flags"
	start_block.add_child(flags_view)
	penalty_panel = _block("Penalty", HudPaint.penalty, race_panel)
	ring_view = PenaltyRingView.new()
	ring_view.name = "Ring"
	penalty_panel.add_child(ring_view)
	alerts_block = _block("Alerts", HudPaint.alerts, race_panel)
	next_panel = _block("NextMark", HudPaint.mark_tag)
	arrow_view = RoundingArrowView.new()
	arrow_view.name = "Rounding"
	next_panel.add_child(arrow_view)
	radar = RadarView.new()
	radar.name = "Radar"
	radar.values = race
	add_child(radar)
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
	for k in ["bsp", "sog", "hdg", "cog", "heel", "polar", "tws", "twa", "twd", "aws", "awa", "sail", "sheet", "rudder",
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
	texts[key] = {"text": text, "col": colour, "value": value, "unit": unit}


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
## "twa", "cue", "hdg", "target", "vmg_kn", "awa", "sog", "cog", "aws", "polar", "heel_bar"), "bug", "bug_lap",
## "bug_gaps", "wind_page", "shift", "feed", "feed_own", "start_min", "start_full", "hint", "radar", "helm".
func items() -> Array[String]:
	var out: Array[String] = ["bsp", "twa_dial", "twa", "radar", "helm"]
	var ph := phase()
	var lvl := density
	var data := ["vmg_kn", "awa", "sog", "cog", "aws", "heel_bar"]
	match ph:
		"free":
			out.append("cue")
			if lvl >= Density.RACE:
				out.append_array(["hdg", "wind_page"])
			if lvl == Density.DATA:
				out.append_array(["awa", "sog", "cog", "aws", "heel_bar"])
		"pre":
			out.append("start_min" if lvl == Density.GLANCE else "start_full")
			if lvl >= Density.RACE:
				out.append_array(["cue", "hdg", "target", "wind_page", "bug", "feed"])
			if lvl == Density.DATA:
				out.append_array(data)
				out.append("bug_lap")
		_:
			out.append("bug")
			var leg := ph in ["beat", "run", "reach"]
			if lvl == Density.GLANCE:
				if leg:
					out.append("cue")
				out.append("feed_own")
			else:
				out.append_array(["cue", "hdg", "target", "wind_page", "shift", "bug_lap", "feed"])
				if lvl == Density.DATA:
					out.append_array(data)
					out.append_array(["bug_gaps", "hint"])
					if race.leg_type != "reach":
						out.append("polar")
	if not shows("shift"):
		out.erase("shift")
	if not shows("sail_hint"):
		out.erase("hint")
	return out


func has_item(what: String) -> bool:
	return items().has(what)


## the cue cell shows VMG % (beat or run, racing) rather than polar %
func cue_is_vmg() -> bool:
	return race.active and race.started and race.next_step > 0 and race.leg_type in ["beat", "run"]


func cue_pct() -> float:
	return race.vmg_pct if cue_is_vmg() else values.polar_pct


## the target angle ticks on the TWA dial: the leg's target TWA on a beat or run, NAN otherwise
func dial_target() -> float:
	if race.active and race.leg_type in ["beat", "run"] and not is_nan(race.target_twa):
		return race.target_twa
	return NAN


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


## the feed lines the density shows: 6 at Data, 3 at Race, the own ones at Glance
func feed_lines() -> Array:
	var out := []
	var n := 6 if has_item("feed") and density == Density.DATA else 3
	for l in race.feed:
		if has_item("feed") or (has_item("feed_own") and l.own):
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


## The HUD keys of this frame (controls.md §2): rankings (Tab, or a long View press), radar zoom and orientation,
## hud_density (G, or a short View press), boat_select, boat_pick (click or tap), boat_names. Optional: without it
## frame() polls the input map.
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
		show_names = not show_names
	if raw.was_pressed(&"boat_pick") and is_inside_tree():
		pick_at(get_viewport().get_mouse_position())


func _poll_input() -> void:
	if _ui_fed or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var raw := RawInput.new()
	for a in [&"rankings", &"rankings_pad", &"radar_zoom_in", &"radar_zoom_out", &"radar_orientation", &"hud_density",
			&"boat_select", &"boat_names", &"boat_pick"]:
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
	radar.advance(dt)
	_race_frame()
	_layout()
	_redraw()


## PlayerControls asks the HUD whether the protest prompt shows and whether a hail can be made or answered.
func _wire(c: PlayerControls) -> void:
	if c == _wired:
		return
	_wired = c
	c.protest_prompt = func() -> bool: return race.active and race.protest_prompt()
	c.hail_available = func() -> bool: return race.active and race.hail_available
	c.hailed = func() -> bool: return race.active and race.hailed_by >= 0


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
	var v := values
	for kv in [["bsp", "BSP", v.bsp], ["sog", "SOG", v.sog], ["tws", "TWS", v.tws], ["aws", "AWS", v.aws]]:
		var s := HudFormat.speed_kn(kv[2])
		_put(kv[0], "%s  %s kn" % [kv[1], s], HudStyle.PAPER, s, "KN")
	_put("hdg", "HDG  %s" % HudFormat.compass_deg(v.hdg), HudStyle.PAPER, HudFormat.compass_deg(v.hdg))
	var cog := HudFormat.compass_deg(v.cog) if v.sog / HudFormat.KNOT > 0.3 else "--"
	_put("cog", "COG  %s" % ("---" if cog == "--" else cog), HudStyle.PAPER, cog)
	var heel := HudFormat.side_angle(v.heel, "S", "P")
	_put("heel", "Heel  %s" % heel, HudStyle.PAPER, heel)
	var pol := "--" if is_nan(v.polar_pct) else HudFormat.percent(v.polar_pct)
	_put("polar", "Polar  --" if pol == "--" else "Polar  %s %%" % pol, HudStyle.PAPER, pol)
	var twa := HudFormat.side_angle(v.twa, "S", "P")
	_put("twa", "TWA  %s" % twa, HudStyle.PAPER, twa)
	_put("twd", "TWD  %s" % HudFormat.compass_deg(v.twd), HudStyle.PAPER, HudFormat.compass_deg(v.twd))
	var awa := HudFormat.side_angle(v.awa, "S", "P")
	_put("awa", "AWA  %s" % awa, HudStyle.PAPER, awa)
	var sail := _sail_name(v.sail_up) if v.sail_up != "" else "Main only"
	if v.sail_hoisting != "":
		sail += ", hoisting %s %s %%" % [_sail_name(v.sail_hoisting), HudFormat.percent(100.0 * v.hoist_progress)]
	_put("sail", "Sail  %s" % sail, HudStyle.PAPER, sail.to_upper())
	_put("rudder", "Helm  %s" % _signed_pct(v.h), HudStyle.PAPER, _signed_pct(v.h))
	var sheet := "AUTO" if v.auto_trim else "%s %%" % HudFormat.percent(100.0 * v.sheet_cmd)
	_put("sheet", "Sheet  %s%s" % [sheet, "   LET FLY" if v.let_fly else ""], HudStyle.PAPER,
		sheet + (", LET FLY" if v.let_fly else ""))
	_put("vmg_kn", "", HudStyle.PAPER, "--")
	_put("target_cell", "", HudStyle.PAPER, "--", "KN")
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
		gv.name = "Gauge" + g.name.capitalize().replace(" ", "")
		gv.title = g.name.capitalize()
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
		for k in ["vmg", "target", "shift", "banner", "rules", "prompt"]:
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
	ring_view.turn_deg = r.turn_deg
	ring_view.target_deg = r.turn_target
	ring_view.tack_done = r.turn_tack
	ring_view.gybe_done = r.turn_gybe
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
	results_panel.visible = r.results_visible and (r.results_final or r.banner == null)
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
			pts = "%d" % int(r["points"]) if fmod(r["points"], 1.0) == 0.0 else "%.1f" % r["points"]
		out.append([place, r["name"], r["skipper"], r["ai"], t, g, r["code"], pts])
	return out


## The race numbers at 4 Hz (hud.md §1 formats, §14 assists).
func _race_text() -> void:
	var r := race
	if not r.active:
		return
	var red: Color = HudStyle.PORT
	var white: Color = HudStyle.PAPER
	# clock (§9.1)
	var clock := ""
	var clock_v := ""
	if r.state <= RaceText.RaceState.FREE_SAILING or (r.state == RaceText.RaceState.SEQUENCE
			and r.race_time < -r.warning_time):
		clock_v = HudFormat.countdown(-r.race_time - r.warning_time)
		clock = "Warning in %s" % clock_v
	elif r.state == RaceText.RaceState.SEQUENCE:
		clock_v = HudFormat.countdown(-r.race_time)
		clock = "Start in %s" % clock_v
	elif r.finished:
		clock_v = HudFormat.finish_time(r.t_finish)
		clock = "Finished  %s" % clock_v
	elif r.state == RaceText.RaceState.ABANDONED:
		clock = "Abandoned"
	else:
		clock_v = HudFormat.clock(r.race_time)
		clock = "Race  %s" % clock_v
	_put("clock", clock, white, clock_v)
	# start line panel (§9.2)
	if r.start_panel:
		var dv := HudStyle.split_unit(HudFormat.signed_distance(r.line_dist) if not r.line_end
			else HudFormat.distance(r.line_dist))
		var d := "Line  %s" % HudFormat.signed_distance(r.line_dist) if not r.line_end \
			else "Line  %s (end)" % HudFormat.distance(r.line_dist)
		_put("line", d, white, dv[0], dv[1] + (" END" if r.line_end else ""))
		var full := shows("burn_bias")
		var tl := "--" if is_nan(r.t_line) else HudFormat.clock(r.t_line)
		_put("tline", ("To line  %s" % tl) if full else "", white, tl)
		var burn := ""
		var burn_v := "--"
		if full and r.race_time < 0.0:
			burn = "Burn  --" if is_nan(r.burn) else "Burn  %s" % signed_seconds(r.burn)
			if not is_nan(r.burn):
				burn_v = signed_seconds(r.burn).trim_suffix(" s")
		_put("burn", burn, white if is_nan(r.burn) or r.burn >= 0.0 else HudStyle.OWE, burn_v,
			"" if burn_v == "--" else "S")
		var bias := ""
		if full and r.bias_end != "":
			bias = "Bias  %s +%d° · %s" % [r.bias_end, int(HudFormat.round_half_away(rad_to_deg(r.bias))),
				HudFormat.distance(r.bias_m)]
		_put("bias", bias, white, r.bias_end)
		if bias != "":
			texts["bias"]["sub"] = ("+%d° · %s" % [int(HudFormat.round_half_away(rad_to_deg(r.bias))),
				HudFormat.distance(r.bias_m)]).to_upper()
	else:
		for k in ["line", "tline", "burn", "bias"]:
			_put(k, "")
	_put("over", "OVER  %s" % r.over_text if r.over else "", red)
	# next mark (§7) and performance (§4, §6, §3.2)
	if r.next_step > 0:
		_put("next", r.next_name, HudStyle.MARK)
		_put("lap", "Lap %d/%d · Leg %d/%d" % [r.lap, r.laps, r.leg, r.legs])
		var md := HudStyle.split_unit(HudFormat.distance(r.next_dist))
		_put("mark_dist", HudFormat.distance(r.next_dist), white, md[0], md[1])
		_put("bearing", "Bearing  %s  (%s)" % [HudFormat.compass_deg(r.next_bearing),
			HudFormat.relative_bearing(r.next_rel)])
		var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
		_put("leg", "%s  ·  ETA %s" % [r.leg_type.capitalize(), eta])
		if r.leg_type == "reach":
			_put("vmg", "VMC  %s kn" % HudFormat.speed_kn(r.vmc), white, HudFormat.speed_kn(r.vmc), "KN")
			_put("target", "Target  %s kn" % HudFormat.speed_kn(r.target_speed))
			_put("target_cell", "", white, HudFormat.speed_kn(r.target_speed), "KN")
			_put("vmg_kn", "", white, HudFormat.speed_kn(r.vmc), "KN")
		else:
			_put("vmg", "VMG  %s kn  %s %%" % [HudFormat.speed_kn(r.vmg), HudFormat.percent(r.vmg_pct)], white,
				HudFormat.percent(r.vmg_pct), "%")
			var tdeg := "" if is_nan(r.target_twa) else "%d°" % int(HudFormat.round_half_away(rad_to_deg(r.target_twa)))
			var tt := "" if tdeg == "" else "  " + tdeg
			_put("target", "Target  %s kn%s" % [HudFormat.speed_kn(r.target_speed), tt])
			if tdeg != "":
				_put("target_cell", "", white, tdeg, "%s KN" % HudFormat.speed_kn(r.target_speed))
			else:
				_put("target_cell", "", white, HudFormat.speed_kn(r.target_speed), "KN")
			_put("vmg_kn", "", white, HudFormat.speed_kn(r.vmg), "KN")
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
			sh_col = HudStyle.STBD
		elif r.shift_kind == "header":
			sh_col = red
		_put("shift", sh, sh_col)
		_put("hint", r.sail_hint if shows("sail_hint") else "", HudStyle.HAVE)
	else:
		for k in ["next", "lap", "mark_dist", "bearing", "leg", "layline", "hint", "vmg", "target", "shift"]:
			_put(k, "")
		if not r.started and r.target_speed > 0.0:
			_put("target_cell", "", white, HudFormat.speed_kn(r.target_speed), "KN")
	# position (§10)
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
	_put("pen_deadline", dl, red if r.deadline < 10.0 else white, HudFormat.clock(maxf(r.deadline, 0.0)))
	_put("pen_dsq", "One more penalty = disqualification" if r.dsq_warning and r.pending > 0 else "", red)


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


## the name tags to draw now: [{boat, p (screen), name, col, solid, outline}] (hud.md §16.4: within 50 m or
## selected, off with `boat_names`)
func name_tags() -> Array:
	var out := []
	if not show_names or sim == null or world_camera() == null:
		return out
	var me := own_pose()
	if me == null:
		return out
	for b in tag_boats():
		var p := sim.render_pose(b, radar.alpha)
		var q: Variant = project(Vector3(p.pos_x, p.pos_y, p.z + mast_height(b)))
		if _on_screen(q):
			out.append(_tag(b, q))
	return out


## the boats that get a name tag now, on screen or not: within TAG_RANGE of the viewed boat, or selected
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
		if selected.has(b) or Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length() <= TAG_RANGE:
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
		var w := Vector3(p.pos_x, p.pos_y, p.z + mast_height(b))
		if _on_screen(project(w)):
			continue
		out.append({"w": w, "name": race.name_of(b).to_upper(), "col": HudStyle.PAPER,
			"d": Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length()})
	return out


func mast_height(b: int) -> float:
	return 1.35 * sim.class_info(b).loa


## boat_select: the next boat by distance after the one selected (nearest first), then none
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
	var cur := -1
	if selected.size() == 1:
		cur = selected.keys()[0]
	selected.clear()
	var i := -1
	for j in order.size():
		if order[j][1] == cur:
			i = j
	if i + 1 < order.size():
		selected[order[i + 1][1]] = true


## boat_pick: selects or clears the boat under a screen point (hull to mast top within PICK_RADIUS); -1 for none
func pick_at(pos: Vector2) -> int:
	if sim == null or world_camera() == null:
		return -1
	var best := -1
	var best_d := PICK_RADIUS * _k
	for b in sim.boat_count():
		if b == viewed:
			continue
		var p := sim.render_pose(b, radar.alpha)
		if p == null:
			continue
		var a: Variant = project(Vector3(p.pos_x, p.pos_y, p.z + 1.0))
		var t: Variant = project(Vector3(p.pos_x, p.pos_y, p.z + mast_height(b)))
		if a == null or t == null:
			continue
		var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, t))
		if d < best_d:
			best_d = d
			best = b
	if best >= 0:
		if selected.has(best):
			selected.erase(best)
		else:
			selected[best] = true
	return best


## hud.md §12.1: the turn on the water while a penalty is pending or being sailed, chase and aerial cameras only
func penalty_turn_shown() -> bool:
	var r := race
	if not r.active or world_camera() == null or not (r.pending > 0 or r.turn_deg >= 1.0):
		return false
	return current_camera_kind() in ["chase", "aerial"]


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
	var sc := _screen_size()
	var k := HudStyle.ui_k(sc)
	var m := HudStyle.margins(sc)
	_k = k
	if density_auto:
		density = default_density(sc)
	for b in _all_canvases():
		b.k = k
	var its := items()
	world.position = Vector2.ZERO
	world.size = sc
	edge_box = Rect2()
	if HudStyle.portrait(sc):
		_layout_portrait(sc, k, m, its)
		return
	# instrument page, bottom left
	var ps := HudPaint.page_size(self) * k
	inst_page.position = Vector2(m.x, sc.y - m.y - ps.y)
	inst_page.size = ps
	toast_block.visible = _toast_t > 0.0
	toast_block.position = inst_page.position - Vector2(0, 40.0 * k)
	toast_block.size = Vector2(300, 32) * k
	toast_block.modulate.a = clampf(_toast_t / 0.24, 0.0, 1.0)
	# race bug, top left
	bug_block.visible = race.active and its.has("bug")
	bug_block.position = m
	bug_block.size = Vector2(520, 200) * k
	# wind page and feed, top right
	wind_page.visible = its.has("wind_page")
	wind_page.size = Vector2(HudPaint.WIND.x, 160) * k
	wind_page.position = Vector2(sc.x - m.x - HudPaint.WIND.x * k, m.y)
	feed_block.visible = race.active and (its.has("feed") or its.has("feed_own"))
	feed_block.size = Vector2(620, 170) * k
	feed_block.position = Vector2(sc.x - m.x - feed_block.size.x, m.y + (172.0 * k if wind_page.visible else 0.0))
	# radar, bottom right
	radar.visible = race.active
	radar.compact = density == Density.GLANCE
	var d := 300.0 * k * (0.72 if radar.compact else 1.0)
	radar.size = Vector2(d, d + (0.0 if radar.compact else 30.0 * k))
	radar.position = Vector2(sc.x - m.x - d, sc.y - m.y - radar.size.y)
	# helm strip between the page and the radar
	var left := inst_page.position.x + ps.x + 24.0 * k
	var right := (radar.position.x if radar.visible else sc.x - m.x) - 24.0 * k
	var hw := minf(HudPaint.HELM.x * k, maxf(right - left, 160.0 * k))
	_place_helm(Vector2((left + right) * 0.5 - hw * 0.5, sc.y - m.y - HudPaint.HELM.y * k), hw, k)
	# top centre lane: start block, penalty panel, alerts
	race_panel.position = Vector2(sc.x * 0.5 - HudPaint.LANE_W * k * 0.5, m.y)
	_place_lane(k)
	# the next mark tag: on the mark, or docked under the race bug without a camera
	next_panel.size = Vector2(330, 120) * k
	next_panel.visible = race.active and race.next_step > 0 and not race.finished and text_of("next") != ""
	world.visible = world_tags
	if not world_tags and world_camera() != null:
		next_panel.visible = false
	if next_panel.visible and world_camera() != null:
		var mp: Variant = mark_screen()
		if mp == null:
			next_panel.visible = false
		else:
			var p: Vector2 = mp
			next_panel.position = Vector2(clampf(p.x - 30.0 * k, m.x, sc.x - m.x - next_panel.size.x),
				clampf(p.y - 150.0 * k, m.y, sc.y - m.y - next_panel.size.y))
	else:
		next_panel.position = Vector2(m.x, m.y + 230.0 * k)
	arrow_view.position = Vector2.ZERO
	arrow_view.size = Vector2(26, 22) * k
	# tables, centred
	var rs := HudPaint.table_size(RANK_W, race.ranking_rows().size() if ranking_panel.visible else 0) * k
	ranking_panel.size = rs
	ranking_panel.position = (sc - rs) * 0.5
	var qs := HudPaint.table_size(RESULT_W, race.result_rows.size()) * k
	results_panel.size = qs
	results_panel.position = (sc - qs) * 0.5


## The helm strip at `pos`, `hw` wide: its bars and trim gauges inside it, the notes over it.
func _place_helm(pos: Vector2, hw: float, k: float) -> void:
	helm_block.size = Vector2(hw, HudPaint.HELM.y * k)
	helm_block.position = pos
	rudder_bar.position = Vector2(0, 116.0 * k)
	rudder_bar.size = Vector2(hw, 12.0 * k)
	sheet_bar.position = Vector2(hw * 0.3, 72.0 * k)
	sheet_bar.size = Vector2(hw * 0.4, 10.0 * k)
	var gw := (hw - 20.0 * k) * 0.5
	for i in gauge_views.size():
		gauge_views[i].position = Vector2(i * (gw + 20.0 * k), 0)
		gauge_views[i].size = Vector2(gw, 56.0 * k)
	helm_notes.size = Vector2(hw + 240.0 * k, 56.0 * k)
	helm_notes.position = helm_block.position + Vector2(-120.0 * k, -60.0 * k)


## The alert lane's blocks inside `race_panel` (placed by the caller) at the lane's scale `k`: the start block with
## its flags, the penalty panel with its ring, the alert lines; returns the lane's height (px).
func _place_lane(k: float) -> float:
	race_panel.size = Vector2(HudPaint.LANE_W, 600) * k
	for b in [start_block, flags_view, penalty_panel, ring_view, alerts_block]:
		(b as HudCanvas).k = k
	var y := 0.0
	var sh := HudPaint.start_height(self)
	start_block.visible = sh > 0.0
	start_block.position = Vector2.ZERO
	start_block.size = Vector2(HudPaint.LANE_W, maxf(sh, 1.0)) * k
	var cw := 240.0
	if countdown_shown():
		var ct := text_of("clock")
		cw = HudCanvas.text_width(ct.substr(ct.rfind(" ") + 1), int(roundf(128.0 * k))) / k
	flags_view.position = Vector2(HudPaint.LANE_W * 0.5 + cw * 0.5 + 28.0, 44.0) * k
	flags_view.size = Vector2(flags_view.width() + 2.0, 50.0 * k)
	y += sh + (8.0 if sh > 0.0 else 0.0)
	if penalty_panel.visible:
		penalty_panel.position = Vector2((HudPaint.LANE_W - HudPaint.PEN.x) * 0.5, y) * k
		penalty_panel.size = HudPaint.PEN * k
		ring_view.position = Vector2(12, 10) * k
		ring_view.size = Vector2(150, 96) * k
		y += HudPaint.PEN.y + 12.0
	var ah := HudPaint.alerts_height(self)
	alerts_block.visible = ah > 0.0
	alerts_block.position = Vector2(0, y) * k
	alerts_block.size = Vector2(HudPaint.LANE_W, maxf(ah, 1.0)) * k
	return (y + ah) * k


# ---- portrait layout (hud.md §16.5) ----

## the alert lane's scale over the rest in portrait, at most (hud.md §16.5)
const PORTRAIT_LANE_MAX := 1.15


## Portrait: the race bug and wind page on top, the alert lane large under them, the instruments compact at the
## bottom (page left, compact radar right, helm strip, notes, chip and feed over them), tables fitted to the width.
func _layout_portrait(sc: Vector2, k: float, m: Vector2, its: Array[String]) -> void:
	var mb := HudStyle.bottom_margin(sc)
	var inner := sc.x - 2.0 * m.x
	# top row: race bug left, wind page right
	bug_block.visible = race.active and its.has("bug")
	bug_block.position = m
	bug_block.size = Vector2(520, 200) * k
	wind_page.visible = its.has("wind_page")
	wind_page.size = Vector2(HudPaint.WIND.x, 160) * k
	wind_page.position = Vector2(sc.x - m.x - HudPaint.WIND.x * k, m.y)
	var top := 0.0
	if bug_block.visible:
		top = maxf(top, bug_block.extent().end.y)
	if wind_page.visible:
		top = maxf(top, wind_page.extent().end.y)
	# the alert lane under them, as large as fits
	var kl := minf(k * PORTRAIT_LANE_MAX, inner / HudPaint.LANE_W)
	race_panel.position = Vector2(sc.x * 0.5 - HudPaint.LANE_W * kl * 0.5, m.y + top + (16.0 * k if top > 0.0 else 0.0))
	var lane_h := _place_lane(kl)
	# bottom row: instrument page left, compact radar right
	var ps := HudPaint.page_size(self) * k
	radar.visible = race.active
	radar.compact = true
	var d := 300.0 * k * 0.72
	radar.size = Vector2(d, d)
	radar.position = Vector2(sc.x - m.x - d, sc.y - mb - d)
	inst_page.position = Vector2(m.x, sc.y - mb - ps.y)
	inst_page.size = ps
	var row_top := minf(inst_page.position.y, radar.position.y if radar.visible else INF)
	# helm strip centred over the row, notes over it, the density chip over the page
	var hw := minf(HudPaint.HELM.x * k, inner)
	_place_helm(Vector2(sc.x * 0.5 - hw * 0.5, row_top - 12.0 * k - HudPaint.HELM.y * k), hw, k)
	toast_block.visible = _toast_t > 0.0
	toast_block.position = inst_page.position - Vector2(0, 40.0 * k)
	toast_block.size = Vector2(300, 32) * k
	toast_block.modulate.a = clampf(_toast_t / 0.24, 0.0, 1.0)
	# the feed right-aligned over the helm notes, its last line nearest them
	feed_block.visible = race.active and (its.has("feed") or its.has("feed_own"))
	var lines := feed_lines().size() if feed_block.visible else 0
	feed_block.size = Vector2(minf(620.0 * k, inner), (lines * 26.0 + 2.0) * k)
	feed_block.position = Vector2(sc.x - m.x - feed_block.size.x, helm_notes.position.y - 8.0 * k - feed_block.size.y)
	# the next mark tag: on the mark, or docked under the alert lane without a camera
	next_panel.size = Vector2(330, 120) * k
	next_panel.visible = race.active and race.next_step > 0 and not race.finished and text_of("next") != ""
	if next_panel.visible and world_camera() != null:
		var mp: Variant = mark_screen()
		if mp == null:
			next_panel.visible = false
		else:
			var p: Vector2 = mp
			# kept under the alert lane, so it never covers the rule text
			var y_min := race_panel.position.y + lane_h + 12.0 * k if lane_h > 0.0 else m.y + top
			next_panel.position = Vector2(clampf(p.x - 30.0 * k, m.x, sc.x - m.x - next_panel.size.x),
				clampf(p.y - 150.0 * k, y_min, maxf(y_min, sc.y - mb - next_panel.size.y)))
	else:
		next_panel.position = Vector2(m.x, race_panel.position.y + lane_h + 12.0 * k)
	arrow_view.position = Vector2.ZERO
	arrow_view.size = Vector2(26, 22) * k
	# edge pointers between the alert lane and the feed and helm notes
	var e_top := race_panel.position.y + lane_h + 24.0 * k
	var e_bottom := minf(helm_notes.position.y, feed_block.position.y if lines > 0 else INF) - 56.0 * k
	edge_box = Rect2(70.0 * k, e_top, sc.x - 140.0 * k, maxf(e_bottom - e_top, 1.0))
	# tables centred, scaled down to the width
	_place_table(ranking_panel, RANK_W, race.ranking_rows().size() if ranking_panel.visible else 0, k, inner, sc)
	_place_table(results_panel, RESULT_W, race.result_rows.size(), k, inner, sc)


func _place_table(b: HudCanvas, widths: Array, rows: int, k: float, inner: float, sc: Vector2) -> void:
	var ds := HudPaint.table_size(widths, rows)
	b.k = minf(k, inner / ds.x)
	b.size = ds * b.k
	b.position = (sc - b.size) * 0.5


func _all_canvases() -> Array[HudCanvas]:
	var out: Array[HudCanvas] = [world, inst_page, toast_block, bug_block, wind_page, feed_block, start_block,
		flags_view, penalty_panel, ring_view, alerts_block, next_panel, arrow_view, radar, helm_block, helm_notes,
		rudder_bar, sheet_bar, ranking_panel, results_panel]
	for g in gauge_views:
		out.append(g)
	return out


func _redraw() -> void:
	for n in _all_canvases():
		if n.is_visible_in_tree():
			n.queue_redraw()


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
