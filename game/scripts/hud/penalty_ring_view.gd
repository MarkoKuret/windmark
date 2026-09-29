class_name PenaltyRingView
extends HudCanvas
## hud.md §12.1 turn progress: a ring filling in `port` with |turn| up to 360 (or 720) degrees, the degrees in
## its middle, and the tack and gybe chips beside it that fill when done.

var turn_deg := 0.0
var target_deg := 360.0
var tack_done := false
var gybe_done := false


func _init() -> void:
	super()


func _build() -> void:
	var r := 38.0 * k
	var c := Vector2(r + 4.0 * k, size.y * 0.5)
	var w := 7.0 * k
	_a(c, r, 0.0, TAU, 64, Color(HudStyle.PAPER, 0.18), w)
	var f := clampf(turn_deg / maxf(target_deg, 1.0), 0.0, 1.0)
	if f > 0.0:
		_a(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(4, int(64 * f)), HudStyle.PORT, w)
	_s(c + Vector2(0, 8.0 * k), "%d°" % int(HudFormat.round_half_away(turn_deg)), int(roundf(24.0 * k)), HudStyle.PAPER,
		600, 0.0, HORIZONTAL_ALIGNMENT_CENTER)
	var x := c.x + r + 16.0 * k
	_chip(Vector2(x, c.y - 26.0 * k), "TACK", tack_done)
	_chip(Vector2(x, c.y + 4.0 * k), "GYBE", gybe_done)


func _chip(p: Vector2, text: String, done: bool) -> void:
	var sz := Vector2(46.0, 22.0) * k
	if done:
		_rect(Rect2(p, sz), HudStyle.PAPER)
	else:
		_pl(PackedVector2Array([p, p + Vector2(sz.x, 0), p + sz, p + Vector2(0, sz.y), p]), HudStyle.HAIR,
			maxf(1.0, 1.5 * k))
	_s(p + Vector2(sz.x * 0.5, 16.0 * k), text, int(roundf(12.0 * k)), HudStyle.INK if done else HudStyle.MIST, 700,
		0.1, HORIZONTAL_ALIGNMENT_CENTER)
