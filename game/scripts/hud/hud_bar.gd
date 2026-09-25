class_name HudBar
extends Control
## A horizontal bar: the rudder (centred, -1..1, hud.md §2: the helm h with a second mark at h_cmd) or the
## sheet (0..1, 0 = sheeted hard in).

var centred := false
var value := 0.0
## second mark (h_cmd), NAN for none
var mark := NAN
var fill := Color(0.9, 0.9, 0.9)
var mark_colour := Color(1.0, 0.75, 0.2)


func _init() -> void:
	custom_minimum_size = Vector2(190, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _x(v: float) -> float:
	var t := (v + 1.0) * 0.5 if centred else v
	return clampf(t, 0.0, 1.0) * size.x


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15))
	var x0 := _x(0.0)
	var x1 := _x(value)
	draw_rect(Rect2(Vector2(minf(x0, x1), 1), Vector2(absf(x1 - x0), size.y - 2)), fill)
	if centred:
		draw_line(Vector2(x0, 0), Vector2(x0, size.y), Color(1, 1, 1, 0.6), 1.0)
	if not is_nan(mark):
		var xm := _x(mark)
		draw_line(Vector2(xm, -2), Vector2(xm, size.y + 2), mark_colour, 2.0)
