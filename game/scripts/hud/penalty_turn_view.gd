class_name PenaltyTurnView
extends HudCanvas
## hud.md §12.1 turn progress as plain text, no ring: TURN over |turn| in degrees (every penalty is one turn of
## 360), and the words TACK and GYBE under it, in paper once done and faint before.

var turn_deg := 0.0
var target_deg := 360.0
var tack_done := false
var gybe_done := false


func _init() -> void:
	super()


func _build() -> void:
	var x := 8.0 * k
	_s(Vector2(x, 20.0 * k), "TURN", int(roundf(HudPaint.LAB * k)), HudStyle.MIST, 600, HudPaint.TRACK)
	_s(Vector2(x, 64.0 * k), "%d°" % int(HudFormat.round_half_away(turn_deg)), int(roundf(40.0 * k)), HudStyle.PAPER,
		600)
	var fs := int(roundf(HudPaint.LAB_S * k))
	var tw := HudCanvas.text_width("TACK", fs, 700, HudPaint.TRACK)
	_s(Vector2(x, 90.0 * k), "TACK", fs, _done_col(tack_done), 700, HudPaint.TRACK)
	_s(Vector2(x + tw + 14.0 * k, 90.0 * k), "GYBE", fs, _done_col(gybe_done), 700, HudPaint.TRACK)


static func _done_col(done: bool) -> Color:
	return HudStyle.PAPER if done else Color(HudStyle.MIST, 0.45)
