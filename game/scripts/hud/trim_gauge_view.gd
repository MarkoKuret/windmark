class_name TrimGaugeView
extends Control
## One trim gauge (hud.md §5): a needle over -2..+2 of the normalised trim error (+ = eased beyond the optimum),
## coloured by |e|; AUTO shows a neutral needle at 0; greyed while the sail is being hoisted or dropped.

var title := ""
var needle := 0.0
var colour := Color.WHITE
var auto := false
var greyed := false
var show_needle := true
var telltale := ""


func _init() -> void:
	custom_minimum_size = Vector2(150, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 15
	var a := 0.4 if greyed else 1.0
	var head := title + ("  AUTO" if auto else "")
	draw_string(font, Vector2(0, 14), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	if show_needle:
		var y := 24.0
		var w := size.x
		draw_rect(Rect2(0, y, w, 12), Color(1, 1, 1, 0.12 * a))
		# tolerance band |e| <= 1
		draw_rect(Rect2(w * 0.25, y, w * 0.5, 12), Color(1, 1, 1, 0.12 * a))
		draw_line(Vector2(w * 0.5, y - 2), Vector2(w * 0.5, y + 14), Color(1, 1, 1, 0.5 * a), 1.0)
		var e := 0.0 if auto else clampf(needle, -2.0, 2.0)
		var x := (e + 2.0) / 4.0 * w
		var c := colour
		c.a = a
		draw_line(Vector2(x, y - 3), Vector2(x, y + 15), c, 3.0)
	draw_string(font, Vector2(0, 54), telltale, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
