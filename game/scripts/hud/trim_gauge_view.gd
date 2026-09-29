class_name TrimGaugeView
extends HudCanvas
## One trim gauge (hud.md §5) of the helm strip: the sail's name and tell-tale over a hairline scale of -2..+2 of
## the normalised trim error (+ = eased beyond the optimum, to the right: EASE), the tolerance band |e| <= 1 and the
## needle coloured by |e|; AUTO shows a neutral needle at 0; greyed while the sail is being hoisted or dropped.

var title := ""
var needle := 0.0
var colour := HudStyle.PAPER
var auto := false
var greyed := false
var show_needle := true
var telltale := ""
## the helm strip at Glance has no labels
var labels := true


func _init() -> void:
	super()


func _build() -> void:
	var a := 0.4 if greyed else 1.0
	var fs := int(roundf(13.0 * k))
	if labels:
		_s(Vector2(0, 14.0 * k), (title + ("  AUTO" if auto else "")).to_upper(), fs, _al(HudStyle.MIST, a), 600, 0.14)
		_s(Vector2(size.x, 14.0 * k), telltale.to_upper(), fs, _al(HudStyle.PAPER, a), 600, 0.14,
			HORIZONTAL_ALIGNMENT_RIGHT)
	var y := 28.0 * k
	var w := maxf(1.0, 1.5 * k)
	_l(Vector2(0, y), Vector2(size.x, y), _al(HudStyle.HAIR, a), w)
	if show_needle:
		_rect(Rect2(size.x * 0.25, y - 2.0 * k, size.x * 0.5, 4.0 * k), Color(HudStyle.PAPER, 0.35 * a))
		var e := 0.0 if auto else clampf(needle, -2.0, 2.0)
		var x := (e + 2.0) / 4.0 * size.x
		_rect(Rect2(x - 2.0 * k, y - 8.0 * k, 4.0 * k, 16.0 * k), _al(colour, a))
	if labels:
		var ts := int(roundf(11.0 * k))
		_s(Vector2(0, y + 18.0 * k), "IN", ts, _al(HudStyle.MIST, a), 600, 0.14)
		_s(Vector2(size.x, y + 18.0 * k), "EASE", ts, _al(HudStyle.MIST, a), 600, 0.14, HORIZONTAL_ALIGNMENT_RIGHT)


static func _al(c: Color, a: float) -> Color:
	return Color(c, c.a * a)
