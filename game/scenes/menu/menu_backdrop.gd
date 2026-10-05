class_name MenuBackdrop
extends Control
## The menus' painted backdrop: a hazy sky over a calm sea, a few long swells and one distant sail on the
## horizon, drawn without image files (the main menu's fallback when the live backdrop does not load, menus.md §4).
## `dim` darkens it for the pause menu over the race; `haze` lays a soft light haze in the top-left corner (under
## the wordmark) over either backdrop.

@export var horizon := 0.58
@export var dim := 0.0
@export var draw_scene := true
@export var haze := false

var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if draw_scene:
		_t += dt
		queue_redraw()


func _band(y0: float, y1: float, c0: Color, c1: Color) -> void:
	var w := size.x
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([c0, c0, c1, c1]))


func _draw() -> void:
	var w := size.x
	var h := size.y
	if draw_scene:
		var hy := h * horizon
		_band(0, hy * 0.55, MenuTheme.SKY_TOP, MenuTheme.SKY_TOP.lerp(MenuTheme.SKY_HORIZON, 0.55))
		_band(hy * 0.55, hy, MenuTheme.SKY_TOP.lerp(MenuTheme.SKY_HORIZON, 0.55), MenuTheme.SKY_HORIZON)
		_band(hy, hy + (h - hy) * 0.35, MenuTheme.SEA_HORIZON, MenuTheme.SEA_HORIZON.lerp(MenuTheme.SEA_DEEP, 0.6))
		_band(hy + (h - hy) * 0.35, h, MenuTheme.SEA_HORIZON.lerp(MenuTheme.SEA_DEEP, 0.6), MenuTheme.SEA_DEEP)
		draw_line(Vector2(0, hy), Vector2(w, hy), Color(1, 1, 1, 0.35), 1.0)
		# long swells: thin light strokes, wider apart towards the viewer
		for i in 9:
			var f := float(i + 1) / 10.0
			var y := hy + (h - hy) * f * f
			var pts := PackedVector2Array()
			var amp := 1.0 + 5.0 * f * f
			var ph := _t * (0.25 + 0.15 * f) + i * 1.7
			for k in 33:
				var x := w * k / 32.0
				pts.append(Vector2(x, y + amp * sin(x / (60.0 + 240.0 * f) + ph)))
			draw_polyline(pts, Color(1, 1, 1, 0.05 + 0.05 * (1.0 - f)), 1.0 + 1.5 * f, true)
		# a distant boat: hull and two sails, gently rising and falling
		var bx := w * 0.80
		var by := hy + 3.0 + 1.2 * sin(_t * 0.7)
		var s := clampf(h / 800.0, 0.6, 1.6)
		var sail := Color(0.98, 0.97, 0.94)
		draw_colored_polygon(PackedVector2Array([Vector2(bx, by - 2 * s), Vector2(bx, by - 70 * s),
			Vector2(bx + 30 * s, by - 5 * s)]), sail)
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 3 * s, by - 5 * s), Vector2(bx - 3 * s, by - 58 * s),
			Vector2(bx - 26 * s, by - 5 * s)]), Color(sail, 0.92))
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 30 * s, by - 3 * s), Vector2(bx + 36 * s, by - 3 * s),
			Vector2(bx + 30 * s, by + 2 * s), Vector2(bx - 26 * s, by + 2 * s)]), MenuTheme.NAVY)
		draw_line(Vector2(bx - 20 * s, by + 5 * s), Vector2(bx + 26 * s, by + 5 * s), Color(1, 1, 1, 0.25), 1.0)
	if haze:
		var c0 := Color(MenuTheme.SKY_HORIZON, 0.55)
		var c1 := Color(MenuTheme.SKY_HORIZON, 0.0)
		var hw := w * 0.6
		var hh := h * 0.45
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(hw, 0), Vector2(hw * 0.5, hh * 0.5), Vector2(0, hh)]),
			PackedColorArray([c0, c1, Color(MenuTheme.SKY_HORIZON, 0.2), c1]))
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(MenuTheme.SEA_DEEP, dim))
