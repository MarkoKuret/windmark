class_name PenaltyRingView
extends Control
## hud.md §12.1 turn progress: a ring filling with |turn| up to 360 (or 720) degrees, with a tack tick and a gybe
## tick that light when done.

var turn_deg := 0.0
var target_deg := 360.0
var tack_done := false
var gybe_done := false


func _init() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := Vector2(28, 30)
	var r := 22.0
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.2), 6.0)
	var f := clampf(turn_deg / maxf(target_deg, 1.0), 0.0, 1.0)
	if f > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(4, int(48 * f)), Color(1.0, 0.75, 0.2), 6.0)
	var font := get_theme_default_font()
	var on := Color(0.3, 0.85, 0.35)
	var off := Color(1, 1, 1, 0.3)
	draw_string(font, Vector2(52, 20), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, on if tack_done else off)
	draw_string(font, Vector2(52, 48), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, on if gybe_done else off)
