extends Node3D
## The kite tuner (sail_visuals.md §4.1, WM-173): a windowed development tool that shapes a class's flying kite
## live. Pick the class, the kite, the true wind angle, the gybe and the wind; move the sliders of the kite's set
## parameters (and its `camber` and `twist_top` look keys); the kite is bent by the same SailShape the game uses, on
## the generated boat with the main set at its optimum. Save writes the class file's `visual.sails.<kite>.look` and
## `.set` blocks (only the values away from their defaults, the rest of the file left as it was); the game reads them
## at the next race, the generator's previews after a rebuild (game/README.md).
##
##   godot --path game res://scenes/tools/kite_tuner.tscn -- --class=wm9 [--kite=kite] [--twa=150] [--tws=12]
##       [--gybe=port|starboard]
##
## Mouse: drag on the boat to orbit (left or right button), the wheel to zoom. Presentation only: nothing here
## touches the core or the performance tables.

const KNOT := 1852.0 / 3600.0
const PANEL_W := 420.0
const TEXT := 15
const SMALL := 13
const ROW_H := 26.0
const UP := 3

## one-line help per key, shown as the slider's tooltip
const HELP := {
	"camber": "Largest camber over chord of the deepest row, when full.",
	"twist_top": "Head turned further to leeward than the foot (asym: grows with the AWA).",
	"depth_peak_h": "Height of the deepest row, share of the luff.",
	"depth_foot": "Camber of the foot row over the deepest.",
	"depth_head": "Camber at the head over the deepest.",
	"draft_low": "Draft position from the luff, share of the chord, lower sail.",
	"draft_head": "Draft position at the head.",
	"draft_from_h": "Height where the draft starts moving to its head position.",
	"belly_aft": "How far the wind blows the belly aft along the chord.",
	"belly_up": "How far the wind lifts the belly up the luff.",
	"twist_exp": "Twist profile up the sail (asym: larger twists lower down; sym: larger keeps it to the top).",
	"twist_awa_lo": "Asym: the twist starts at this apparent wind angle.",
	"twist_awa_hi": "Asym: full twist from this apparent wind angle.",
	"twist_run": "Asym: the twist fades out over this much before a dead run.",
	"foot_sag": "The low panels' belly sags down by this share of its depth.",
	"foot_sag_h": "The sag fades out at this share of the height.",
	"girth_foot": "Flying chord of the foot row, times the computed one.",
	"girth_mid": "Flying chord at mid height, times the computed one.",
	"girth_head": "Flying chord at the head, times the computed one.",
	"luff_curl": "Extra belly along the luff (negative: the luff stands up to windward).",
	"leech_curl": "Extra belly along the leech (negative: the leech stands up to windward).",
	"head_drop": "Head eased down the luff (halyard eased), share of the luff.",
	"clew_lift": "Clew raised up the luff (negative: lowered), share of the foot.",
	"clew_out": "Clew let out along the chord (negative: drawn in), share of the foot.",
	"clew_h": "The clew moves fade out at this share of the height.",
	"tack_rise": "Tack raised, share of the luff (pole end up, or tack line eased).",
	"forward": "Cloth projected forward of the sheeted position, share of the luff; corners held.",
	"stay_clear": "On a pole: margin ahead of the forestay, share of the foretriangle base.",
	"stay_width": "On a pole: half width of the forestay's wall, share of the foretriangle base.",
	"stay_head": "On a pole: the forestay push fades out over this top share of the height.",
	"stay_luff": "On a pole: chord share from which the forestay push is taken in full.",
	"stay_leech": "On a pole: share of the forestay push lost toward the leech.",
}

## where the class files are read and saved (tests point it at a copy); "" = the repository's data/classes
var class_dir := ""
## read the command line in _ready (tests turn it off)
var read_args := true

var class_id := ""
var kite_id := ""
var kite_type := ""
var twa_deg := 140.0
var tws_kn := 12.0
## +1: wind from starboard (starboard gybe), -1: from port
var gybe := 1.0
var kite_trim := 1.0
var main_trim := 1.0
## the current values of every shown key (set keys and the look keys), their defaults, and the class file's
var values := {}
var defaults := {}
var saved := {}
## key -> {"slider", "readout", "row", "label"}
var rows := {}

var data: BoatClassData
var bv: BoatView
var kite_part: BoatView.SailPart
var sv: SimSource.SailsView
var awa := 0.0
var aws := 0.0
var camera: Camera3D
var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.2
var dist := 30.0

var _class_pick: OptionButton
var _kite_pick: OptionButton
var _gybe_pick: OptionButton
var _wind_rows := {}
var _list: VBoxContainer
var _status: Label
var _wind_info: Label
var _title: Label
var _classes: Array[String] = []
var _dragging := false
var _ui: Control


func _ready() -> void:
	_build_world()
	_build_ui()
	_classes = list_classes()
	for id in _classes:
		_class_pick.add_item(id)
	var want := _classes[0] if not _classes.is_empty() else ""
	var want_kite := ""
	if read_args:
		for a in OS.get_cmdline_user_args():
			var kv := a.trim_prefix("--").split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"class": want = kv[1]
				"kite": want_kite = kv[1]
				"twa": twa_deg = clampf(float(kv[1]), 60.0, 180.0)
				"tws": tws_kn = clampf(float(kv[1]), 4.0, 30.0)
				"gybe": gybe = -1.0 if kv[1] == "port" else 1.0
	_sync_wind_rows()
	if want != "":
		select_class(want, want_kite)


func _process(delta: float) -> void:
	if bv != null and sv != null:
		bv.apply_sails(sv, sv, 1.0, delta)


# ---- data -------------------------------------------------------------------------------------------------------

func _class_path(id: String) -> String:
	var dir := class_dir if class_dir != "" else BoatClassData.repo_path("data/classes")
	return dir.path_join("%s.boat.json" % id)


## The classes with a spinnaker, a performance file and a generated boat.
func list_classes() -> Array[String]:
	var out: Array[String] = []
	var dir := class_dir if class_dir != "" else BoatClassData.repo_path("data/classes")
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".boat.json"):
			continue
		var id := f.trim_suffix(".boat.json")
		var cls: Variant = BoatClassData._read_json(dir.path_join(f))
		if not cls is Dictionary or not ResourceLoader.exists("res://generated/boats/%s.glb" % id) \
				or not FileAccess.file_exists(BoatClassData.repo_path("data/perf/%s.perf.json" % id)):
			continue
		for s in cls.get("sails", []):
			if KiteSet.is_kite(String(s.get("type", ""))):
				out.append(id)
				break
	return out


## Loads class `id` and its kite `kite` (the first spinnaker when "" or not found); false when it does not load.
func select_class(id: String, kite := "") -> bool:
	var cls: Variant = BoatClassData._read_json(_class_path(id))
	if not cls is Dictionary:
		_set_status("No class file for %s" % id, true)
		return false
	var d := BoatClassData.load_class(id)
	if d == null:
		_set_status("Class %s does not load (performance file missing?)" % id, true)
		return false
	class_id = id
	data = d
	var idx := _classes.find(id)
	if idx >= 0:
		_class_pick.select(idx)
	_kite_pick.clear()
	var kites: Array[String] = []
	for s in cls.get("sails", []):
		if KiteSet.is_kite(String(s.get("type", ""))):
			kites.append(String(s["id"]))
			_kite_pick.add_item(String(s["id"]))
	if kites.is_empty():
		_set_status("%s has no spinnaker" % id, true)
		return false
	if bv != null:
		bv.queue_free()
		bv = null
	bv = BoatView.create(data.info, data.info.rudder_max)
	bv.full_rate = true
	add_child(bv)
	return select_kite(kite if kite in kites else kites[0])


func select_kite(id: String) -> bool:
	kite_part = null
	for sp in bv.sail_parts:
		if sp.id == id and sp.shape != null:
			kite_part = sp
	if kite_part == null:
		_set_status("%s: kite %s is not drawn (generated boat missing?)" % [class_id, id], true)
		return false
	kite_id = id
	kite_type = kite_part.type
	for i in _kite_pick.item_count:
		if _kite_pick.get_item_text(i) == id:
			_kite_pick.select(i)
	_load_values()
	_build_rows()
	_title.text = "%s  %s" % [data.info.name, kite_id]
	target = kite_part.centre + Vector3(0, 0, 0.1 * kite_part.sl)
	dist = 1.6 * kite_part.sl + 6.0
	_refresh_wind()
	_reshape()
	set_view("leeward")
	_set_status("Loaded %s" % _class_path(class_id).get_file(), false)
	return true


## The defaults and the class file's values of every key of this kite.
func _load_values() -> void:
	defaults = KiteSet.defaults(kite_type)
	for row in KiteSet.LOOK_PARAMS:
		defaults[row[0]] = _look_default(row[0])
	var cls: Variant = BoatClassData._read_json(_class_path(class_id))
	var entry := KiteSet.class_entry(cls, kite_id)
	saved = defaults.duplicate()
	var st: Variant = entry.get("set", {})
	if st is Dictionary:
		for k in st:
			if saved.has(k):
				saved[k] = float(st[k])
	var lk: Variant = entry.get("look", {})
	if lk is Dictionary:
		for row in KiteSet.LOOK_PARAMS:
			if (lk as Dictionary).has(row[0]):
				saved[row[0]] = float(lk[row[0]])
	values = saved.duplicate()


## A look key's default for this kite type (sail_visuals.md §4, the generator's LOOK_DEFAULTS).
func _look_default(key: String) -> float:
	var asym := kite_type == "spinnaker_asym"
	if key == "camber":
		return 0.27 if asym else 0.30
	return 0.45 if asym else 0.0


func _shown(row: Array) -> bool:
	var only: String = row[7] if row.size() > 7 else ""
	if only == "asym":
		return kite_type == "spinnaker_asym"
	if only == "pole":
		return kite_part != null and kite_part.mode == BoatView.Mode.POLE
	return true


func _row_def(key: String) -> Array:
	for row in KiteSet.LOOK_PARAMS:
		if row[0] == key:
			return row
	for row in KiteSet.PARAMS:
		if row[0] == key:
			return row
	return []


# ---- shape and wind ---------------------------------------------------------------------------------------------

## The values the kite is drawn with: a value within half a slider step of its default is the default.
func effective() -> Dictionary:
	var out := {}
	for k in values:
		var row := _row_def(k)
		var step: float = row[6] if not row.is_empty() else 0.0
		out[k] = defaults[k] if absf(values[k] - defaults[k]) <= 0.5 * step + 1e-9 else values[k]
	return out


func _reshape() -> void:
	if bv == null or kite_part == null:
		return
	var e := effective()
	var look := {}
	var kset := {}
	for k in e:
		if k == "camber" or k == "twist_top":
			look[k] = e[k]
		else:
			kset[k] = e[k]
	bv.reshape_kite(kite_id, look, kset)
	step()
	_update_status()


## Places the sails now (the tests; the frames do it as well).
func step() -> void:
	if bv != null and sv != null:
		for k in 3:  # the main's stop (sail_visuals.md §7.6) reads the kite's clew as last placed
			bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)


## The apparent wind from the kite configuration's polar and the sails at their optimum (times the trims): the main
## and the kite up, the other sails down.
func _refresh_wind() -> void:
	if data == null or kite_part == null:
		return
	var fi := kite_part.index
	var cfg: Dictionary = data.configs.get(fi, {})
	if cfg.is_empty():
		return
	var tws := tws_kn * KNOT
	var twa := deg_to_rad(twa_deg)
	var v: float = cfg["polar"].at(tws, twa)
	var aw := Vector2(tws * cos(twa) + v, tws * sin(twa))
	awa = gybe * aw.angle()
	aws = aw.length()
	sv = SimSource.SailsView.new()
	sv.awa = awa
	sv.aws = aws
	sv.tws = tws
	var kite_beta := 0.0
	for i in data.info.sails.size():
		var st := SimSource.SailState.new()
		var si: SimSource.SailInfo = data.info.sails[i]
		if i == data.info.main_sail or i == fi:
			st.phase = UP
			var opt: PerfTable = cfg["optimal"].get(i)
			var m: float = opt.at(tws, absf(awa)) if opt != null else si.sheet_min
			var f := main_trim if i == data.info.main_sail else kite_trim
			st.beta = -Frames.sgn(awa) * clampf(m * f, si.sheet_min, si.sheet_max)
			if i == fi:
				kite_beta = st.beta
				var pa: PerfTable = data.sail_data[i]["pole_angle"]
				st.pole = -Frames.sgn(awa) * (pa.at(tws, absf(awa)) if pa != null else 0.0)
		sv.sails.append(st)
		sv.out.append(SimSource.SailOutput.new())
	_wind_info.text = "AWA %d°  AWS %.1f kn  boat %.1f kn  kite sheet %d°" % [
		roundi(rad_to_deg(absf(awa))), aws / KNOT, v / KNOT, roundi(rad_to_deg(absf(kite_beta)))]
	step()


## The kite's placed mid-surface (model axes), for the tests.
func kite_mid() -> PackedVector3Array:
	return kite_part.shape.mid() if kite_part != null else PackedVector3Array()


# ---- save, revert, reset, copy ------------------------------------------------------------------------------------

## The non-default values as the class file writes them: {"look": {...}, "set": {...}} (keys in tuner order).
func changed_blocks() -> Dictionary:
	var e := effective()
	var look := {}
	var kset := {}
	for row in KiteSet.LOOK_PARAMS:
		if e.has(row[0]) and e[row[0]] != defaults[row[0]]:
			look[row[0]] = snappedf(e[row[0]], 0.0001)
	for row in KiteSet.PARAMS:
		if e.has(row[0]) and e[row[0]] != defaults[row[0]]:
			kset[row[0]] = snappedf(e[row[0]], 0.0001)
	return {"look": look, "set": kset}


## Writes the kite's blocks into the class file: every key at its default removed, every other one set in place;
## the rest of the file as it was. True when written (or nothing to change).
func save() -> bool:
	var path := _class_path(class_id)
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		_set_status("Cannot read %s" % path, true)
		return false
	var e := effective()
	var out := text
	var base := PackedStringArray(["visual", "sails", kite_id])
	for row in KiteSet.LOOK_PARAMS + KiteSet.PARAMS:
		var k: String = row[0]
		if not e.has(k):
			continue
		var block := "look" if KiteSet.LOOK_PARAMS.has(row) else "set"
		var p := base + PackedStringArray([block, k])
		if e[k] == defaults[k]:
			out = JsonEdit.drop(out, p, 2)
		else:
			out = JsonEdit.put(out, p, JsonEdit.num(e[k]))
		if out == "":
			_set_status("Could not edit %s at visual.sails.%s.%s.%s" % [path.get_file(), kite_id, block, k], true)
			return false
	if JSON.parse_string(out) == null:
		_set_status("Edit gave invalid JSON; %s not written" % path.get_file(), true)
		return false
	if out != text:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_set_status("Cannot write %s" % path, true)
			return false
		f.store_string(out)
		f.close()
	_load_values()
	_sync_sliders()
	_reshape()
	_set_status("Saved to %s" % path.get_file() if out != text else "Nothing to save", false)
	return true


## Back to the class file's values.
func revert() -> void:
	_load_values()
	_sync_sliders()
	_reshape()
	_set_status("Reverted to %s" % _class_path(class_id).get_file(), false)


## Every value to its default (not saved until Save).
func reset_defaults() -> void:
	values = defaults.duplicate()
	_sync_sliders()
	_reshape()
	_set_status("Defaults (not saved)", false)


## The non-default values as JSON, also on the clipboard.
func copy_values() -> String:
	var b := changed_blocks()
	var out := {}
	if not (b["look"] as Dictionary).is_empty():
		out["look"] = b["look"]
	if not (b["set"] as Dictionary).is_empty():
		out["set"] = b["set"]
	var text := JSON.stringify({kite_id: out})
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	_set_status("Copied: %s" % text, false)
	return text


## Sets one value as a slider move does (tests).
func set_value(key: String, v: float) -> void:
	if not values.has(key):
		return
	values[key] = v
	if rows.has(key):
		var sl: HSlider = rows[key]["slider"]
		sl.set_value_no_signal(_to_slider(key, v))
		_update_row(key)
	_reshape()


# ---- camera -----------------------------------------------------------------------------------------------------

## Fixed views: "windward", "leeward" (abeam), "ahead", "above", "chase". Model axes: bow +Z, port +X, up +Y.
func set_view(name: String) -> void:
	var ws := -1.0 if awa > 0.0 else 1.0  # the windward side's X: wind from starboard puts it at -X
	match name:
		"windward":
			yaw = ws * PI / 2.0
			pitch = 0.12
		"leeward":
			yaw = -ws * PI / 2.0
			pitch = 0.12
		"ahead":
			yaw = 0.0
			pitch = 0.1
		"above":
			yaw = PI
			pitch = 1.45
		"chase":
			yaw = PI
			pitch = 0.3
	_place_camera()


func _place_camera() -> void:
	if camera == null:
		return
	pitch = clampf(pitch, -0.2, 1.5)
	dist = clampf(dist, 3.0, 400.0)
	var d := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = target + d * dist
	camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist *= 0.9
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist *= 1.1
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch += mm.relative.y * 0.006
		_place_camera()


# ---- world ------------------------------------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = MenuTheme.SKY_TOP
	sm.sky_horizon_color = MenuTheme.SKY_HORIZON
	sm.ground_horizon_color = MenuTheme.SEA_HORIZON
	sm.ground_bottom_color = MenuTheme.SEA_DEEP
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	sea.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2f5d75")
	mat.roughness = 0.35
	sea.material_override = mat
	add_child(sea)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()


# ---- interface --------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = MenuTheme.theme()
	layer.add_child(_ui)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.CLOTH, 0, 3, Vector2(14, 12)))
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_bottom = -10
	panel.offset_right = 10 + PANEL_W
	_ui.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := MenuTheme.label("KITE TUNER", 22, MenuTheme.NAVY, 700, MenuTheme.ITEM_TRACKING)
	col.add_child(head)
	_title = MenuTheme.label("", TEXT, MenuTheme.MUTED)
	col.add_child(_title)
	# class, kite, gybe
	var picks := GridContainer.new()
	picks.columns = 2
	picks.add_theme_constant_override("h_separation", 10)
	col.add_child(picks)
	_class_pick = _option(picks, "Class")
	_class_pick.item_selected.connect(func(i: int) -> void: select_class(_class_pick.get_item_text(i)))
	_kite_pick = _option(picks, "Kite")
	_kite_pick.item_selected.connect(func(i: int) -> void: select_kite(_kite_pick.get_item_text(i)))
	_gybe_pick = _option(picks, "Wind from")
	_gybe_pick.add_item("Starboard")
	_gybe_pick.add_item("Port")
	_gybe_pick.item_selected.connect(func(i: int) -> void:
		gybe = 1.0 if i == 0 else -1.0
		_refresh_wind())
	# wind and trims
	_wind_slider(col, "twa", "True wind angle", 60.0, 180.0, 1.0, "%d°")
	_wind_slider(col, "tws", "True wind speed", 4.0, 30.0, 0.5, "%.1f kn")
	_wind_slider(col, "kite_trim", "Kite sheet, of optimum", 60.0, 130.0, 1.0, "%d %%")
	_wind_slider(col, "main_trim", "Main sheet, of optimum", 60.0, 130.0, 1.0, "%d %%")
	_wind_info = MenuTheme.label("", SMALL, MenuTheme.MUTED)
	col.add_child(_wind_info)
	col.add_child(HSeparator.new())
	# the parameters
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	col.add_child(HSeparator.new())
	# actions
	var acts := GridContainer.new()
	acts.columns = 2
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 6)
	col.add_child(acts)
	var save_b := _button(acts, "Save", func() -> void: save())
	MenuTheme.set_primary(save_b, Vector2(12, 4))
	_button(acts, "Revert", func() -> void: revert())
	_button(acts, "Reset to defaults", func() -> void: reset_defaults())
	_button(acts, "Copy values", func() -> void: copy_values())
	_status = MenuTheme.label("", SMALL, MenuTheme.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	col.add_child(_status)
	# the camera views, top right over the boat
	var views := HBoxContainer.new()
	views.anchor_left = 1.0
	views.anchor_right = 1.0
	views.offset_left = -560
	views.offset_right = -10
	views.offset_top = 10
	views.alignment = BoxContainer.ALIGNMENT_END
	views.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	views.add_theme_constant_override("separation", 6)
	_ui.add_child(views)
	for v in [["windward", "Abeam windward"], ["leeward", "Abeam leeward"], ["ahead", "Ahead"],
			["above", "Above"], ["chase", "Chase"]]:
		var b := _button(views, v[1], func() -> void: set_view(v[0]))
		b.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.CLOTH, 0, 3, Vector2(10, 4)))
	var hint := MenuTheme.label("Drag to orbit, wheel to zoom", SMALL, MenuTheme.CLOTH_SOLID)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -260
	hint.offset_top = -30
	hint.offset_right = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(hint)


func _option(parent: Control, text: String) -> OptionButton:
	parent.add_child(MenuTheme.caps(text, SMALL, MenuTheme.MUTED))
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_override("font", MenuTheme.font(600, 0.0, TEXT))
	o.add_theme_font_size_override("font_size", TEXT)
	o.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.NAVY, 0.06), 0, 2, Vector2(8, 3)))
	parent.add_child(o)
	return o


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := MenuTheme.button(text, TEXT, false, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider_style(sl: HSlider) -> void:
	var track := MenuTheme.box(Color(MenuTheme.NAVY, 0.18), 0, 2, Vector2(0, 2))
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", MenuTheme.box(MenuTheme.ACCENT, 0, 2, Vector2(0, 2)))
	sl.add_theme_stylebox_override("grabber_area_highlight", MenuTheme.box(MenuTheme.ACCENT, 0, 2, Vector2(0, 2)))


## One wind or trim slider (no class data: the tuner's own state).
func _wind_slider(parent: Control, key: String, text: String, lo: float, hi: float, st: float, fmt: String) -> void:
	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(0, ROW_H)
	parent.add_child(r)
	var l := MenuTheme.label(text, TEXT, MenuTheme.INK)
	l.custom_minimum_size = Vector2(170, 0)
	r.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = st
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider_style(sl)
	r.add_child(sl)
	var ro := MenuTheme.label("", TEXT, MenuTheme.NAVY, 600)
	ro.custom_minimum_size = Vector2(70, 0)
	ro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(ro)
	_wind_rows[key] = {"slider": sl, "readout": ro, "fmt": fmt}
	sl.value_changed.connect(func(v: float) -> void:
		match key:
			"twa": twa_deg = v
			"tws": tws_kn = v
			"kite_trim": kite_trim = v / 100.0
			"main_trim": main_trim = v / 100.0
		ro.text = fmt % v
		_refresh_wind())


func _sync_wind_rows() -> void:
	var vals := {"twa": twa_deg, "tws": tws_kn, "kite_trim": kite_trim * 100.0, "main_trim": main_trim * 100.0}
	for k in _wind_rows:
		var w: Dictionary = _wind_rows[k]
		(w["slider"] as HSlider).set_value_no_signal(vals[k])
		(w["readout"] as Label).text = String(w["fmt"]) % vals[k]
	_gybe_pick.select(0 if gybe > 0.0 else 1)


func _to_slider(key: String, v: float) -> float:
	var row := _row_def(key)
	return rad_to_deg(v) if row[3] == "deg" else v


func _from_slider(key: String, v: float) -> float:
	var row := _row_def(key)
	return deg_to_rad(v) if row[3] == "deg" else v


## The parameter sliders of this kite, grouped.
func _build_rows() -> void:
	for c in _list.get_children():
		c.queue_free()
	rows.clear()
	var group := ""
	var all: Array = []
	for row in KiteSet.PARAMS:
		all.append(row)
	for lrow in KiteSet.LOOK_PARAMS:  # the look keys go first in their group
		var at := 0
		for i in all.size():
			if all[i][1] == lrow[1]:
				at = i
				break
		all.insert(at, lrow)
	for row in all:
		if not _shown(row):
			continue
		if row[1] != group:
			group = row[1]
			var g := MenuTheme.caps(group, SMALL, MenuTheme.NAVY)
			g.add_theme_font_override("font", MenuTheme.font(700, MenuTheme.LABEL_TRACKING, SMALL))
			g.custom_minimum_size = Vector2(0, 22)
			g.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_list.add_child(g)
		_add_row(row)
	for k in rows:
		_update_row(k)


func _add_row(row: Array) -> void:
	var key: String = row[0]
	var deg: bool = row[3] == "deg"
	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(0, ROW_H)
	r.tooltip_text = HELP.get(key, "")
	_list.add_child(r)
	var l := MenuTheme.label(row[2], TEXT, MenuTheme.INK)
	l.custom_minimum_size = Vector2(178, 0)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = HELP.get(key, "")
	r.add_child(l)
	var sl := HSlider.new()
	sl.min_value = rad_to_deg(row[4]) if deg else row[4]
	sl.max_value = rad_to_deg(row[5]) if deg else row[5]
	sl.step = rad_to_deg(row[6]) if deg else row[6]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = HELP.get(key, "")
	_slider_style(sl)
	sl.set_value_no_signal(_to_slider(key, values[key]))
	r.add_child(sl)
	var ro := MenuTheme.label("", TEXT, MenuTheme.NAVY, 600)
	ro.custom_minimum_size = Vector2(62, 0)
	ro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(ro)
	var rb := Button.new()
	rb.text = "D"
	rb.tooltip_text = "Back to the default"
	rb.custom_minimum_size = Vector2(24, 22)
	rb.add_theme_font_override("font", MenuTheme.font(700, 0.0, SMALL))
	rb.add_theme_font_size_override("font_size", SMALL)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		rb.add_theme_stylebox_override(st, MenuTheme.box(MenuTheme.ACCENT if st != "normal" else Color(MenuTheme.NAVY, 0.06),
			0, 2, Vector2(4, 1)))
	rb.add_theme_color_override("font_color", MenuTheme.NAVY)
	rb.pressed.connect(func() -> void: set_value(key, defaults[key]))
	r.add_child(rb)
	rows[key] = {"slider": sl, "readout": ro, "label": l, "row": r}
	sl.value_changed.connect(func(v: float) -> void:
		values[key] = _from_slider(key, v)
		_update_row(key)
		_reshape())


func _sync_sliders() -> void:
	for k in rows:
		(rows[k]["slider"] as HSlider).set_value_no_signal(_to_slider(k, values[k]))
		_update_row(k)


## The readout (the value, and metres for a share of the luff), in the accent weight when away from the default
## and marked when not saved.
func _update_row(key: String) -> void:
	if not rows.has(key):
		return
	var row := _row_def(key)
	var e := effective()
	var v: float = e[key]
	var text := ""
	if row[3] == "deg":
		text = "%d°" % roundi(rad_to_deg(v))
	elif absf(row[6]) < 0.005:
		text = "%.3f" % v
	else:
		text = "%.2f" % v
	if key in ["head_drop", "tack_rise", "forward"] and kite_part != null and kite_part.shape != null:
		text = "%.2f m" % (v * float(kite_part.shape.frame()["sl"]))
	var ro: Label = rows[key]["readout"]
	ro.text = text
	var changed: bool = e[key] != defaults[key]
	var unsaved: bool = absf(e[key] - saved[key]) > 1e-9
	ro.add_theme_color_override("font_color", MenuTheme.SIGNAL if unsaved else MenuTheme.NAVY)
	(rows[key]["label"] as Label).add_theme_font_override("font", MenuTheme.font(700 if changed else 500, 0.0, TEXT))


func _update_status() -> void:
	var n := 0
	for k in values:
		if absf(effective()[k] - saved[k]) > 1e-9:
			n += 1
	if n > 0 and _status != null and not _status.text.begins_with("Could") and not _status.text.begins_with("Cannot"):
		_status.text = "%d unsaved change%s (red). Bold: away from the default." % [n, "" if n == 1 else "s"]
		_status.add_theme_color_override("font_color", MenuTheme.INK)


func _set_status(text: String, error: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", MenuTheme.SIGNAL if error else MenuTheme.INK)
	if error:
		push_warning("kite tuner: " + text)
