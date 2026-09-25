class_name RoundingArrowView
extends Control
## hud.md §7 rounding side: a left arrow = leave to port (red), a right arrow = leave to starboard (green); a gate
## shows one per buoy.

var sides: Array[int] = []  # RaceText.Side per buoy


func _init() -> void:
	custom_minimum_size = Vector2(64, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var x := 0.0
	for sd in sides:
		var port: bool = sd == RaceText.Side.PORT
		var col := Color(0.95, 0.3, 0.25) if port else Color(0.3, 0.85, 0.35)
		var y := size.y * 0.5
		var tip := Vector2(x + (2.0 if port else 26.0), y)
		var tail := Vector2(x + (26.0 if port else 2.0), y)
		draw_line(tail, tip + Vector2(6.0 if port else -6.0, 0), col, 4.0)
		var back := 10.0 if port else -10.0
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(back, -8), tip + Vector2(back, 8)]), col)
		x += 32.0
