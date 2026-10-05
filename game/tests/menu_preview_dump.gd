extends SceneTree
## Dumps the menus for the offline previews (tests/menu_preview.py draws them). No window opens. Each shot is the
## main menu at 1280 x 800 (100 % UI scale) in one state; the dump lists what the menu draws: the boxes (StyleBoxFlat
## of panels, buttons and rows), the texts (with their font file, size, tracking and colour), the colour rects and
## the course map's geometry, each with the clip rect of the scroll container it sits in.
##   godot --headless --path game -s res://tests/menu_preview_dump.gd
## Writes generated/menu_preview/<shot>.json.

const OUT := "res://generated/menu_preview"
const SIZE := Vector2i(1280, 800)

var m: MainMenu


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Settings.path = "user://menu_preview_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_current()
	var s := Settings.current()
	s.welcomed = true
	s.last_setup = {"mode": "race", "class_id": "wm7", "venue": "example_bay", "course": "example_bay/example_wl",
		"fleet_size": 10, "ai_level": "expert", "wind_kn": 14.0, "wind_from_deg": 30.0}
	root.size = SIZE
	m = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	root.add_child(m)
	await _frames(1)
	root.size = SIZE
	await _frames(3)
	m.buttons["continue"].grab_focus()
	await _frames(2)
	_dump("main")
	m.open_page("quick")
	await _frames(3)
	m.quick.rows["fleet_size"].grab_focus()
	await _frames(2)
	_dump("race_card")
	m.close_page()
	m.open_page("settings")
	await _frames(2)
	m.settings_panel.show_section("hud")
	await _frames(2)
	m.settings_panel.rows["palette"].grab_focus()
	await _frames(3)
	_dump("settings")
	m.settings_panel.show_section("controls")
	await _frames(2)
	var r: BindingRow = m.settings_panel.binding_rows["let_fly"]
	r.grab_focus()
	await _frames(2)
	m.settings_panel._scroll.ensure_control_visible(r)
	await _frames(3)
	_dump("bindings")
	m.settings_panel.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _col(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


func _rect(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _box(sb: StyleBox, r: Rect2, clip: Rect2) -> Dictionary:
	var f := sb as StyleBoxFlat
	if f == null:
		return {}
	return {"k": "box", "r": _rect(r), "clip": _rect(clip), "bg": _col(f.bg_color), "draw_center": f.draw_center,
		"bl": f.border_width_left, "bb": f.border_width_bottom, "bc": _col(f.border_color),
		"radius": f.corner_radius_top_left, "shadow": f.shadow_size, "shadow_col": _col(f.shadow_color),
		"shadow_off": [f.shadow_offset.x, f.shadow_offset.y]}


func _font_info(c: Control, font_name := "font", size_name := "font_size") -> Dictionary:
	var f := c.get_theme_font(font_name)
	var path := ""
	var spacing := 0
	if f is FontVariation:
		path = (f as FontVariation).base_font.resource_path
		spacing = (f as FontVariation).spacing_glyph
	elif f is FontFile:
		path = f.resource_path
	return {"font": path.get_file(), "size": c.get_theme_font_size(size_name), "spacing": spacing}


func _text(c: Control, text: String, col: Color, r: Rect2, clip: Rect2, align: int, valign: int, wrap: bool) -> Dictionary:
	var d := _font_info(c)
	d.merge({"k": "text", "t": text, "col": _col(col), "r": _rect(r), "clip": _rect(clip), "align": align,
		"valign": valign, "wrap": wrap})
	return d


func _dump(shot: String) -> void:
	root.size = SIZE
	var items: Array = []
	var full := Rect2(Vector2.ZERO, Vector2(SIZE))
	_walk(m, full, items)
	var f := FileAccess.open(OUT.path_join(shot + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [SIZE.x, SIZE.y], "shot": shot, "items": items}))
	f.close()
	print("menu preview: %s, %d items (menu %s, root %s, page %s, version %s)" % [shot, items.size(), m.size, root.size,
		m._panel.get_global_rect(), m.version_label.get_global_rect()])


func _walk(n: Node, clip: Rect2, items: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Node3D or n is CanvasLayer:
		return
	var c := n as Control
	if c != null:
		var r := c.get_global_rect()
		if c is MenuBackdrop:
			items.append({"k": "haze", "r": _rect(r)})
		elif c is CourseMap:
			items.append(_map(c as CourseMap, r))
		elif c is ColorRect:
			items.append({"k": "rect", "r": _rect(r), "clip": _rect(clip), "col": _col((c as ColorRect).color)})
		elif c is Button:
			var b := c as Button
			var st := "disabled" if b.disabled else "normal"
			var sb := b.get_theme_stylebox(st)
			var d := _box(sb, r, clip)
			if not d.is_empty():
				items.append(d)
			var focused := b.has_focus()
			if focused:
				var fd := _box(b.get_theme_stylebox("focus"), r, clip)
				if not fd.is_empty():
					items.append(fd)
			var col := b.get_theme_color("font_disabled_color" if b.disabled else
				("font_focus_color" if focused else "font_color"))
			var cm := sb.content_margin_left if sb != null else 0.0
			var tr := Rect2(r.position + Vector2(cm, 0), Vector2(r.size.x - 2 * cm, r.size.y))
			items.append(_text(b, b.text, col, tr, clip, b.alignment, 1, false))
		elif c is PanelContainer:
			var d := _box(c.get_theme_stylebox("panel"), r, clip)
			if not d.is_empty():
				items.append(d)
		elif c is Label:
			var l := c as Label
			var sb := l.get_theme_stylebox("normal")
			var d := _box(sb, r, clip)
			if not d.is_empty():
				items.append(d)
			var txt := l.text
			if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
				var font := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				var w := r.size.x - (sb.content_margin_left + sb.content_margin_right if sb != null else 0.0)
				while txt.length() > 1 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
					txt = txt.substr(0, txt.length() - 2) + "…"
			items.append(_text(l, txt, l.get_theme_color("font_color"), r, clip, l.horizontal_alignment,
				l.vertical_alignment, l.autowrap_mode != TextServer.AUTOWRAP_OFF))
		if c is ScrollContainer or c.clip_contents:
			clip = clip.intersection(r)
	for ch in n.get_children():
		_walk(ch, clip, items)


func _map(cm: CourseMap, r: Rect2) -> Dictionary:
	var to_px := cm._fit()
	var marks := []
	var rounding := CourseMap.rounding_ids(cm.course)
	for mk in cm.course.get("marks", []):
		var id := str(mk.get("id", ""))
		if cm.points.has(id):
			var p: Vector2 = to_px.call(cm.points[id])
			marks.append({"type": str(mk.get("type", "buoy")), "rounding": id in rounding, "p": [p.x, p.y]})
	var path := []
	for p in cm.path():
		var q: Vector2 = to_px.call(p)
		path.append([q.x, q.y])
	var lines := {}
	for key in ["start", "finish"]:
		var ends: Array = cm.course.get(key, {}).get("ends", [])
		if ends.size() == 2:
			var a: Vector2 = to_px.call(cm.points[str(ends[0])])
			var b: Vector2 = to_px.call(cm.points[str(ends[1])])
			lines[key] = [a.x, a.y, b.x, b.y]
	return {"k": "map", "r": _rect(r), "marks": marks, "path": path, "lines": lines,
		"wind_from": cm.wind_from_deg, "wind_kn": cm.wind_kn}
