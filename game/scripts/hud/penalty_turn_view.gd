class_name PenaltyTurnView
extends HudCanvas
## hud.md §12.1 turn progress inside the penalty panel: a small ring gauge (a hair track, the progress arc in paper
## from the top clockwise over |turn| / 360) with |turn| in degrees in its middle, and right of it the words TACK
## over GYBE, in paper once done and faint before. Nothing of it is drawn on the water.

const R := 22.0  # ring radius, design px
const W := 3.0  # ring width

var turn_deg := 0.0
var target_deg := 360.0
var tack_done := false
var gybe_done := false


func _init() -> void:
	super()


## the share of the turn done, 0..1
func fraction() -> float:
	return clampf(absf(turn_deg) / maxf(target_deg, 1.0), 0.0, 1.0)


func _build() -> void:
	var c := Vector2(R + 2.0, 38.0) * k
	var r := R * k
	_a(c, r, 0.0, TAU, 48, HudStyle.HAIR, W * k)
	var f := fraction()
	if f > 0.0:
		_a(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(4, int(ceil(48.0 * f))), HudStyle.PAPER, W * k)
	_s(c + Vector2(1.0 * k, 5.0 * k), "%d°" % int(HudFormat.round_half_away(absf(turn_deg))), int(roundf(14.0 * k)),
		HudStyle.PAPER, 600, 0.0, HORIZONTAL_ALIGNMENT_CENTER)
	var x := (2.0 * R + 14.0) * k
	var fs := int(roundf(HudPaint.TINY * k))
	_s(Vector2(x, 36.0 * k), "TACK", fs, _done_col(tack_done), 700, HudPaint.TRACK)
	_s(Vector2(x, 52.0 * k), "GYBE", fs, _done_col(gybe_done), 700, HudPaint.TRACK)


static func _done_col(done: bool) -> Color:
	return HudStyle.PAPER if done else Color(HudStyle.MIST, 0.45)
