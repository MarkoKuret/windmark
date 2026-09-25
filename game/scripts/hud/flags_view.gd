class_name FlagsView
extends Control
## hud.md §9.1 flags row: the flags shown now as small drawn flags (class, P, I, Z, U, black, X, first
## substitute), each with its name under it.

var flags: Array[String] = []

const W := 34.0
const H := 22.0
const GAP := 10.0


func _init() -> void:
	custom_minimum_size = Vector2(4 * (W + GAP), H + 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	var x := 0.0
	for f in flags:
		var r := Rect2(x, 0, W, H)
		_flag(f, r)
		draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
		var label: String = {"class": "Class", "1st substitute": "1st sub", "black": "Black"}.get(f, f)
		draw_string(font, Vector2(x, H + 14), label, HORIZONTAL_ALIGNMENT_CENTER, W, 12, Color(1, 1, 1, 0.9))
		x += W + GAP


func _flag(f: String, r: Rect2) -> void:
	var blue := Color(0.1, 0.25, 0.7)
	var yellow := Color(0.98, 0.82, 0.1)
	var red := Color(0.85, 0.12, 0.12)
	var white := Color(0.97, 0.97, 0.97)
	var black := Color(0.05, 0.05, 0.05)
	var c := r.get_center()
	match f:
		"class":  # the class flag: a plain pennant-style mark on white
			draw_rect(r, white)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.35), Vector2(r.size.x, r.size.y * 0.3)), blue)
		"P":
			draw_rect(r, blue)
			draw_rect(Rect2(c - r.size * 0.2, r.size * 0.4), white)
		"I":
			draw_rect(r, yellow)
			draw_circle(c, r.size.y * 0.3, black)
		"Z":
			var p := r.position
			var s := r.size
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(s.x, 0), c]), yellow)
			draw_colored_polygon(PackedVector2Array([p + Vector2(s.x, 0), p + s, c]), black)
			draw_colored_polygon(PackedVector2Array([p + s, p + Vector2(0, s.y), c]), red)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, s.y), p, c]), blue)
		"U":
			var h := r.size * 0.5
			draw_rect(Rect2(r.position, h), red)
			draw_rect(Rect2(r.position + Vector2(h.x, 0), h), white)
			draw_rect(Rect2(r.position + Vector2(0, h.y), h), white)
			draw_rect(Rect2(r.position + h, h), red)
		"black":
			draw_rect(r, black)
		"X":
			draw_rect(r, white)
			draw_rect(Rect2(Vector2(c.x - 3, r.position.y), Vector2(6, r.size.y)), blue)
			draw_rect(Rect2(Vector2(r.position.x, c.y - 3), Vector2(r.size.x, 6)), blue)
		"1st substitute":
			var p := r.position
			var s := r.size
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(s.x, s.y * 0.5), p + Vector2(0, s.y)]), blue)
			draw_colored_polygon(PackedVector2Array([p + Vector2(s.x * 0.2, s.y * 0.25),
				p + Vector2(s.x * 0.6, s.y * 0.5), p + Vector2(s.x * 0.2, s.y * 0.75)]), yellow)
		_:
			draw_rect(r, Color(0.5, 0.5, 0.5))
