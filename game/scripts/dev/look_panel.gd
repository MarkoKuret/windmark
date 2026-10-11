class_name LookPanel
extends CanvasLayer
## The developer look panel (hud.md §18, controls.md §3 notes): F9 in the sail scene opens a side column that
## changes the look live through DevLook (the functions the startup flags call), with an fps and frame time
## readout. A development tool: not in the player's settings, nothing saved.
##
## Keys while it has the focus: Up and Down pick a row, Left and Right change it, Enter or Space toggles a row or
## runs an action, Esc gives the keys back to the boat (the panel stays up), F9 closes it. F9 on an open panel
## without the focus takes the focus again; so does a click on it. Mouse: click a row to step it forward (or run
## it), right click to step back, the wheel either way, click outside the panel to give the keys back. While it
## has the focus the scene hands the boat, the cameras and the scene keys no buttons (`blocks_input`); the
## simulation keeps running.

const TOGGLE_KEY := KEY_F9
## between the HUD (layer 1) and the pause menu (60); the frame-time overlay (128) stays on top
const LAYER := 50
## design px at 1920 x 1080 (HudStyle.ui_k scales them)
const WIDTH := 330.0
const ROW_H := 24.0
const TEXT := 15.0
const SMALL := 13.0
const READOUT_EVERY := 0.25

## the sail scene (duck typed: the DevLook members, `perf`, `controls`, `wind_speed_kn`, `scenario_run`,
## `restart_with_wind`)
var scene: Node
var is_open := false
var focused := false
var selected := 0
## the rows: {id, label, kind ("choice", "slider", "action"), values (a slider: [min, max, step, snap to the
## step]), fmt (value -> text), get, set, note (how it applies), look (where to look, hud.md §18)}
var rows: Array[Dictionary] = []
## the wind the restart row uses, kn
var restart_wind_kn := 12.0
## the readout's last values
var fps := 0.0
var frame_ms := 0.0

var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _readout: Label
var _hint: Label
var _row_nodes: Array[Dictionary] = []
## the frame whose keys stay blocked after the focus is given back (the Esc or click that gave it back)
var _block_frame := -1
var _since_readout := 0.0
var _ms_sum := 0.0
var _ms_n := 0


func _ready() -> void:
	name = "LookPanel"
	layer = LAYER
	if scene != null and "wind_speed_kn" in scene:
		restart_wind_kn = roundf(float(scene.get("wind_speed_kn")))
	_build_rows()
	_build_ui()
	_panel.visible = false


# ---- rows -------------------------------------------------------------------------------------------------------

func _build_rows() -> void:
	var s := scene
	var on_off := func(v: Variant) -> String: return "On" if v else "Off"
	var k_text := func(v: Variant) -> String: return "x%.1f" % float(v) if float(v) > 0.0 else "Off"
	_add("aa", "Anti-aliasing", "choice", DevLook.AA_MODES,
		func(v: Variant) -> String: return {"off": "Off", "fxaa": "FXAA", "smaa": "SMAA"}.get(v, str(v)),
		func() -> Variant: return DevLook.aa(s), func(v: Variant) -> void: DevLook.set_aa(s, v),
		"Live. Screen-space AA of the 3D view (--aa)",
		"masts, stays and sheets against the sky; subtle on Retina")
	_add("look", "Grade", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.look(), func(v: Variant) -> void: DevLook.set_look(s, v),
		"Live. Off also drops SSAO and depth of field (--look)",
		"the whole picture: compare the sea's blues")
	_add("grade", "Grade strength", "slider", [DevLook.STRENGTH_MIN, DevLook.STRENGTH_MAX, DevLook.STRENGTH_STEP],
		k_text,
		func() -> Variant: return DevLook.grade_strength(),
		func(v: Variant) -> void: DevLook.set_grade_strength(s, v),
		"Live. The film grade, 0 off to 1.5 (--grade)",
		"sky and sea colour, warm sunlit water, cool shadow sides; whites stay white")
	_add("ssao", "SSAO", "choice", [-1, 0, 1],
		_ssao_text,
		func() -> Variant: return DevLook.ssao_choice(), func(v: Variant) -> void: DevLook.set_ssao(s, v),
		"Live. Contact shading; the tier has it on H only (--ssao)",
		"high tier only: deck at the foot of the mast, cockpit corners")
	_add("dof", "Clip camera DOF", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.dof(), func(v: Variant) -> void: DevLook.set_dof(s, v),
		"Live. Long lens and mark shots, tiers M and H (--dof)",
		"clip cameras only: press X for the long lens")
	var tr := DevLook.time_range(s)
	_add("time", "Time of day", "slider", [tr.x, tr.y, DevLook.TIME_STEP, true],
		func(v: Variant) -> String: return "%s  sun %d°" % [Daylight.hour_text(float(v)),
			roundi(DevLook.sun_elevation(s))],
		func() -> Variant: return DevLook.time(s), func(v: Variant) -> void: DevLook.set_time(s, v),
		"Live. Local clock on the venue's date, sun 6° or more (--time)",
		"the sun's height and colour, shadow length on the water, the sky toward the sun")
	_add("conditions", "Conditions", "choice", DevLook.CONDITIONS,
		func(v: Variant) -> String: return str(v).capitalize(),
		func() -> Variant: return DevLook.conditions(s), func(v: Variant) -> void: DevLook.set_conditions(s, v),
		"Live. Sky, sun, haze and grade (--conditions)",
		"clouds, how far land and boats fade, shadow strength")
	_add("quality", "Quality tier", "choice", [0, 1, 2],
		func(v: Variant) -> String: return "LMH"[clampi(int(v), 0, 2)] if int(v) >= 0 else "Setting",
		func() -> Variant: return DevLook.quality(s), func(v: Variant) -> void: DevLook.set_quality(s, v),
		"Live: sea grid and shader, wakes, shadows, glow, SSAO. Short hitch while shaders compile (--quality)",
		"water detail near the boat, wakes, shadows on the water")
	_add("haze", "Haze", "slider", [DevLook.HAZE_MIN, DevLook.HAZE_MAX, 0.1],
		func(v: Variant) -> String: return "x%.1f (%.2f)" % [float(v), _haze_max() * float(v)],
		func() -> Variant: return DevLook.haze(s), func(v: Variant) -> void: DevLook.set_haze(s, v),
		"Live. Factor on the light's haze, 0 to 1.5 (--haze)",
		"far boats, marks and the land at 1 to 10 km")
	_add("haze_reset", "Reset haze", "action", [], func(_v: Variant) -> String: return "x1.0",
		func() -> Variant: return null, func(_v: Variant) -> void: DevLook.set_haze(s, 1.0),
		"Haze back to the light's", "")
	_add("caps", "Whitecaps", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.whitecaps(s), func(v: Variant) -> void: DevLook.set_whitecaps(s, v),
		"Live (--caps)",
		"set the drawn wind to 20 kn or more")
	var winds: Array = [0.0]
	for kn in range(8, 26):
		winds.append(float(kn))
	_add("drawn_wind", "Drawn wind (sea)", "choice", winds,
		func(v: Variant) -> String: return "Sim" if float(v) <= 0.0 else "%d kn" % int(v),
		func() -> Variant: return DevLook.drawn_wind(s), func(v: Variant) -> void: DevLook.set_drawn_wind(s, v),
		"Live: the wind the water draws (caps, puffs); waves and boats keep the race's (--drawn-wind)",
		"puff patches and whitecaps on the water")
	var restart: Array = []
	for kn in range(4, 31):
		restart.append(float(kn))
	_add("wind", "Wind for restart", "choice", restart,
		func(v: Variant) -> String: return "%d kn" % int(v),
		func() -> Variant: return restart_wind_kn, func(v: Variant) -> void: restart_wind_kn = float(v),
		"Restart only: the core takes its wind when the world is made. Enter on the next row", "")
	_add("restart", "Restart with wind", "action", [],
		func(_v: Variant) -> String: return "%d kn" % int(restart_wind_kn),
		func() -> Variant: return null, func(_v: Variant) -> void: restart(),
		"Restarts this race or free sail with that wind, other settings kept (--wind)",
		"the waves and the boat speed after the restart")
	_add("breathing", "Chase breathing", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.breathing(s), func(v: Variant) -> void: DevLook.set_breathing(s, v),
		"Live. Off: the plain heading follow, no bank, trail or lean (--breathing)",
		"chase camera in a tack or a gybe")
	_add("drawn_shadows", "Drawn boat shadows", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.drawn_shadows(s), func(v: Variant) -> void: DevLook.set_drawn_shadows(s, v),
		"Live. Shadows drawn on the water, tiers L and M (--no-drawn-shadows)",
		"tiers L and M: the boat's shadow on the water")
	_add("boat_shadows", "Boat sun shadows", "choice", [true, false], on_off,
		func() -> Variant: return DevLook.boat_shadows(s), func(v: Variant) -> void: DevLook.set_boat_shadows(s, v),
		"Live. The boats cast the sun's shadows (--no-boat-shadows)",
		"the sails' and boom's shadows on the deck")
	_add("render_scale", "Render scale", "choice", DevLook.RENDER_SCALES,
		_scale_text,
		func() -> Variant: return DevLook.render_scale_choice(),
		func(v: Variant) -> void: DevLook.set_render_scale(s, v),
		"Live. The 3D view's resolution, FSR above it (--render-scale)",
		"fine detail: rigging, sail numbers, the far fleet")
	_add("perf", "Frame-time overlay", "choice", [true, false], on_off,
		func() -> Variant: return _perf() != null and _perf().overlay, _set_perf,
		"Live. The measuring overlay top left; also Shift+F9 (--perf)", "top left")


func _add(id: String, label: String, kind: String, values: Array, fmt: Callable, getter: Callable, setter: Callable,
		note: String, look := "") -> void:
	rows.append({"id": id, "label": label, "kind": kind, "values": values, "fmt": fmt, "get": getter,
		"set": setter, "note": note, "look": look})


func _ssao_text(v: Variant) -> String:
	var t: String = ["Tier", "Off", "On"][clampi(int(v), -1, 1) + 1]
	if int(v) < 0:
		t += " (on)" if DevLook.ssao_on(scene) else " (off)"
	return t


func _scale_text(v: Variant) -> String:
	if float(v) <= 0.0:
		return "Setting (%d %%)" % _effective_scale_pct()
	return "%d %%" % roundi(float(v) * 100.0)


func _set_perf(on: Variant) -> void:
	var p := _perf()
	if p != null and p.overlay != bool(on):
		p.toggle()


func _perf() -> PerfMonitor:
	var p: Variant = scene.get("perf") if scene != null else null
	return p if p is PerfMonitor else null


func _haze_max() -> float:
	var sky: Variant = scene.get("sky") if scene != null else null
	return (sky as SkyRig).haze_max if sky is SkyRig else 0.0


func _effective_scale_pct() -> int:
	return roundi((get_tree().root.scaling_3d_scale if is_inside_tree() else 1.0) * 100.0)


func row_index(id: String) -> int:
	for i in rows.size():
		if rows[i]["id"] == id:
			return i
	return -1


## The row's current value (null for an action).
func value(id: String) -> Variant:
	var i := row_index(id)
	return (rows[i]["get"] as Callable).call() if i >= 0 else null


## The row's value as the panel shows it.
func value_text(id: String) -> String:
	var i := row_index(id)
	if i < 0:
		return ""
	var r := rows[i]
	return (r["fmt"] as Callable).call((r["get"] as Callable).call())


## One step of a row: the next (dir 1) or previous (-1) choice, wrapping; a slider moves by its step within its
## range; an action runs.
func step(id: String, dir: int) -> void:
	var i := row_index(id)
	if i < 0:
		return
	var r := rows[i]
	var vals: Array = r["values"]
	match r["kind"]:
		"action":
			(r["set"] as Callable).call(null)
		"slider":
			var v := float((r["get"] as Callable).call())
			var snap := float(vals[2]) if vals.size() > 3 and vals[3] else 0.01
			(r["set"] as Callable).call(clampf(snappedf(v + dir * float(vals[2]), snap), float(vals[0]), float(vals[1])))
		_:
			var k := _index_of(vals, (r["get"] as Callable).call())
			(r["set"] as Callable).call(vals[posmod((k if k >= 0 else 0) + dir, vals.size())])
	refresh()


## Enter or Space on a row: an action runs, a choice steps forward.
func activate(id: String) -> void:
	step(id, 1)


func _index_of(vals: Array, v: Variant) -> int:
	for k in vals.size():
		if typeof(vals[k]) in [TYPE_FLOAT, TYPE_INT] and typeof(v) in [TYPE_FLOAT, TYPE_INT]:
			if absf(float(vals[k]) - float(v)) < 1e-3:
				return k
		elif vals[k] == v:
			return k
	return -1


## The look restarted with `restart_wind_kn` (the scene's restart_with_wind).
func restart() -> void:
	if scene != null and scene.has_method("restart_with_wind"):
		scene.restart_with_wind(restart_wind_kn)


# ---- open, close, focus -----------------------------------------------------------------------------------------

func toggle() -> void:
	if is_open and not focused:
		set_focused(true)
	elif is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	_panel.visible = true
	set_focused(true)
	refresh()


func close() -> void:
	is_open = false
	_panel.visible = false
	set_focused(false)


func set_focused(on: bool) -> void:
	if focused and not on:
		_block_frame = Engine.get_process_frames()
	focused = on and is_open
	refresh()


## Whether the scene should hand the boat, cameras and scene keys no buttons this frame: while the panel has the
## focus, and in the frame that gave it back (so that Esc does not also open the pause menu).
func blocks_input() -> bool:
	return focused or Engine.get_process_frames() == _block_frame


## The scene's pause menu or chat has the keys.
func _host_busy() -> bool:
	var pc: Variant = scene.get("controls") if scene != null else null
	return pc is PlayerControls and ((pc as PlayerControls).menu_open or (pc as PlayerControls).text_focus)


func _input(e: InputEvent) -> void:
	if _host_busy():
		return
	if e is InputEventKey and e.pressed:
		var k := e as InputEventKey
		if k.keycode == TOGGLE_KEY and not k.echo:
			if not k.shift_pressed:
				toggle()
				get_viewport().set_input_as_handled()
			return
		if not focused:
			return
		_key(k)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and is_open:
		var inside := _panel.get_global_rect().has_point((e as InputEventMouseButton).position)
		if focused and not inside:
			set_focused(false)


func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_UP:
			select(selected - 1)
		KEY_DOWN:
			select(selected + 1)
		KEY_LEFT:
			step(rows[selected]["id"], -1)
		KEY_RIGHT:
			step(rows[selected]["id"], 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not k.echo:
				activate(rows[selected]["id"])
		KEY_ESCAPE:
			if not k.echo:
				set_focused(false)


func select(i: int) -> void:
	selected = posmod(i, rows.size())
	refresh()


# ---- drawing ----------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudStyle.INK, 0.86)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.gui_input.connect(_panel_input)
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(_list)
	_title = _label(700, HudStyle.PAPER)
	_title.text = "Look panel (developer)   F9"
	_list.add_child(_title)
	_readout = _label(600, HudStyle.HAVE)
	_readout.name = "Readout"
	_list.add_child(_readout)
	for i in rows.size():
		var h := HBoxContainer.new()
		h.name = "Row_" + rows[i]["id"]
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		var name_l := _label(500, HudStyle.MIST)
		name_l.text = rows[i]["label"]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val_l := _label(600, HudStyle.PAPER)
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(name_l)
		h.add_child(val_l)
		var idx := i
		h.gui_input.connect(func(ev: InputEvent) -> void: _row_input(idx, ev, h))
		_list.add_child(h)
		_row_nodes.append({"box": h, "name": name_l, "value": val_l})
	_hint = _label(500, HudStyle.MIST)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_hint)


func _label(weight: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", HudStyle.font(weight))
	l.add_theme_color_override("font_color", color)
	return l


func _panel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and not _host_busy():
		set_focused(true)


## A click on a row: left steps forward (an action runs), right steps back, the wheel steps either way.
func _row_input(i: int, ev: InputEvent, box: Control) -> void:
	if not (ev is InputEventMouseButton and ev.pressed) or _host_busy():
		return
	var mb := ev as InputEventMouseButton
	set_focused(true)
	select(i)
	var id: String = rows[i]["id"]
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			step(id, 1)
		MOUSE_BUTTON_RIGHT:
			step(id, -1)
		MOUSE_BUTTON_WHEEL_UP:
			step(id, 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			step(id, -1)
	box.accept_event()


## Every row's text, the selection and the hint.
func refresh() -> void:
	if _panel == null or not is_open:
		return
	for i in rows.size():
		var n: Dictionary = _row_nodes[i]
		var sel := i == selected and focused
		var arrows: bool = rows[i]["kind"] != "action"
		var txt := value_text(rows[i]["id"])
		(n["value"] as Label).text = ("‹ %s ›" % txt) if arrows else ("[ %s ]" % txt)
		(n["value"] as Label).add_theme_color_override("font_color", HudStyle.MARK if sel else HudStyle.PAPER)
		(n["name"] as Label).add_theme_color_override("font_color", HudStyle.PAPER if sel else HudStyle.MIST)
		(n["name"] as Label).text = ("› " if sel else "  ") + rows[i]["label"]
	var note: String = rows[selected]["note"]
	if rows[selected]["id"] in ["wind", "restart"] and scene != null and scene.get("scenario_run") != null:
		note = "A rules scenario sets its own wind: the restart keeps it"
	if rows[selected]["look"] != "":
		note += "\nLook at: " + rows[selected]["look"]
	_hint.text = note + ("\nUp, Down  Left, Right  Enter   Esc: keys back to the boat" if focused
		else "\nF9 or click: keys to the panel")
	_title.text = "Look panel (developer)   F9" + ("" if focused else "   (boat has the keys)")


func _process(dt: float) -> void:
	_ms_sum += dt * 1000.0
	_ms_n += 1
	_since_readout += dt
	if not is_open:
		return
	_layout()
	if _since_readout >= READOUT_EVERY:
		fps = Engine.get_frames_per_second()
		frame_ms = _ms_sum / maxi(_ms_n, 1)
		_ms_sum = 0.0
		_ms_n = 0
		_since_readout = 0.0
		_readout.text = "%.0f fps   %.1f ms   tier %s   3D %d %%" % [fps, frame_ms,
			"LMH"[clampi(DevLook.quality(scene), 0, 2)], _effective_scale_pct()]
		refresh()


## A side column on the right under the top margin, scaled like the HUD.
func _layout() -> void:
	var sc := get_viewport().get_visible_rect().size
	var k := HudStyle.ui_k(sc)
	var fs := maxi(HudStyle.MIN_TEXT, roundi(TEXT * k))
	var fsm := maxi(HudStyle.MIN_TEXT, roundi(SMALL * k))
	var sb := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	sb.set_content_margin_all(10.0 * k)
	for n in _row_nodes:
		(n["name"] as Label).add_theme_font_size_override("font_size", fs)
		(n["value"] as Label).add_theme_font_size_override("font_size", fs)
		(n["box"] as Control).custom_minimum_size = Vector2(0, ROW_H * k)
	_title.add_theme_font_size_override("font_size", fs)
	_readout.add_theme_font_size_override("font_size", fs)
	_hint.add_theme_font_size_override("font_size", fsm)
	var w := minf(WIDTH * k, sc.x * 0.45)
	_panel.custom_minimum_size = Vector2(w, 0)
	_hint.custom_minimum_size = Vector2(w - 20.0 * k, 0)
	_panel.size = Vector2(w, 0)
	var m := HudStyle.margins(sc)
	_panel.position = Vector2(sc.x - m.x - w, m.y)
