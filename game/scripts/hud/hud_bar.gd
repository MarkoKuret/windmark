class_name HudBar
extends HudCanvas
## A hairline bar of the helm strip: the rudder (centred, -1..1, hud.md §2: the helm h as a short bar from the
## centre with the command h_cmd as a yellow pointer) or the sheet (0..1, 0 = sheeted hard in).

var centred := false
var value := 0.0
## second mark (h_cmd), NAN for none
var mark := NAN
var fill := HudStyle.PAPER
var mark_colour := HudStyle.MARK


func _init() -> void:
	super()


func _x(v: float) -> float:
	var t := (v + 1.0) * 0.5 if centred else v
	return clampf(t, 0.0, 1.0) * size.x


func _build() -> void:
	var y := size.y - 1.0
	var w := maxf(1.0, 1.5 * k)
	_l(Vector2(0, y), Vector2(size.x, y), HudStyle.HAIR, w)
	for i in 5:
		var tx := size.x * i / 4.0
		_l(Vector2(tx, y - (8.0 if i == 2 and centred else 5.0) * k), Vector2(tx, y), HudStyle.HAIR, w)
	var x0 := _x(0.0)
	var x1 := _x(value)
	_rect(Rect2(Vector2(minf(x0, x1), y - 3.0 * k), Vector2(maxf(absf(x1 - x0), w), 4.0 * k)), fill)
	if not is_nan(mark):
		var xm := _x(mark)
		_p(PackedVector2Array([Vector2(xm, y - 4.0 * k), Vector2(xm - 6.0 * k, y - 14.0 * k),
			Vector2(xm + 6.0 * k, y - 14.0 * k)]), mark_colour)
