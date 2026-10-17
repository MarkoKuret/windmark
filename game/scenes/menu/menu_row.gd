class_name MenuRow
extends PanelContainer
## One setting on a menu (menus.md §4): its name on the left in caps, its value on the right between ‹ and ›
## (tabular figures, as the HUD numerals); focused, a yellow bar with a navy edge.
## Left and right (keys, D-pad, stick) step the value; Enter or A steps it forward; the mouse clicks the left or
## right half of the value. INFO rows only show a value (the bindings).

signal changed(value: Variant)

enum Kind { CHOICE, RANGE, BOOL, INFO }

var kind := Kind.CHOICE
var key := ""
var value: Variant
## the settings screen's help line for this row (menus.md §3)
var help := ""
## CHOICE: the values and their shown names
var choices: Array = []
var names: Array = []
## RANGE
var min_value := 0.0
var max_value := 1.0
var step := 0.1
var format: Callable = func(v: float) -> String: return "%.2f" % v

var _name: Label
var _value: Label
var _focused := false


static func choice(text: String, k: String, vals: Array, shown: Array, v: Variant) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.CHOICE
	r.key = k
	r.choices = vals
	r.names = shown
	r._init_row(text, v)
	return r


static func range_row(text: String, k: String, lo: float, hi: float, st: float, v: float, fmt: Callable) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.RANGE
	r.key = k
	r.min_value = lo
	r.max_value = hi
	r.step = st
	r.format = fmt
	r._init_row(text, v)
	return r


static func toggle(text: String, k: String, v: bool) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.BOOL
	r.key = k
	r._init_row(text, v)
	return r


static func info(text: String, v: String) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.INFO
	r._init_row(text, v)
	return r


func _init_row(text: String, v: Variant) -> void:
	name = "Row_" + (key if key != "" else text.validate_node_name())
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, MenuTheme.ROW_H)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_name = MenuTheme.caps(text, MenuTheme.ROW_SIZE - 2, MenuTheme.INK)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_name)
	_value = MenuTheme.label("", MenuTheme.ROW_SIZE, MenuTheme.NAVY, 600)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.custom_minimum_size = Vector2(170 if kind != Kind.INFO else 0, 0)
	h.add_child(_value)
	focus_entered.connect(func() -> void: _focused = true; _style())
	focus_exited.connect(func() -> void: _focused = false; _style())
	mouse_entered.connect(grab_focus)
	value = v
	_show()
	_style()


func _style() -> void:
	var pad := MenuTheme.ROW_PAD
	add_theme_stylebox_override("panel", MenuTheme.focus_box(pad) if _focused
		else MenuTheme.box(Color(0, 0, 0, 0), 0, 2, pad))
	_name.add_theme_color_override("font_color", MenuTheme.NAVY if _focused else MenuTheme.INK)
	if kind == Kind.INFO:
		_value.add_theme_color_override("font_color", MenuTheme.NAVY if _focused else MenuTheme.MUTED)


func value_text() -> String:
	match kind:
		Kind.CHOICE:
			var i := choices.find(value)
			return str(names[i]) if i >= 0 else str(value)
		Kind.RANGE:
			return format.call(float(value))
		Kind.BOOL:
			return "On" if value else "Off"
	return str(value)


func _show() -> void:
	if kind == Kind.INFO:
		_value.text = str(value)
	else:
		_value.text = "‹   %s   ›" % value_text()


## Replace the choices (a list that depends on another row); keeps the value when it is still there.
func set_choices(vals: Array, shown: Array) -> void:
	choices = vals
	names = shown
	if not choices.has(value):
		value = choices[0] if not choices.is_empty() else null
	_show()


func set_value(v: Variant, notify := false) -> void:
	value = v
	_show()
	if notify:
		changed.emit(value)


## One step: +1 forward, -1 back. Choices and switches wrap; ranges stop at their ends.
func step_value(dir: int) -> void:
	match kind:
		Kind.CHOICE:
			if choices.is_empty():
				return
			var i := maxi(choices.find(value), 0)
			value = choices[posmod(i + dir, choices.size())]
		Kind.RANGE:
			var n := roundi((float(value) - min_value) / step) + dir
			value = clampf(min_value + n * step, min_value, max_value)
		Kind.BOOL:
			value = not value
		_:
			return
	_show()
	changed.emit(value)


func _gui_input(e: InputEvent) -> void:
	if kind == Kind.INFO:
		return
	if e.is_action_pressed("ui_left", true):
		step_value(-1)
		accept_event()
	elif e.is_action_pressed("ui_right", true):
		step_value(1)
		accept_event()
	elif e.is_action_pressed("ui_accept"):
		step_value(1)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var x: float = (e as InputEventMouseButton).position.x
		var mid := _value.position.x + _value.size.x * 0.5 + (get_theme_stylebox("panel").content_margin_left)
		step_value(-1 if kind != Kind.BOOL and x < mid else 1)
		accept_event()
