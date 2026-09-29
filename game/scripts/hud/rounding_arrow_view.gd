class_name RoundingArrowView
extends HudCanvas
## hud.md §7 rounding side on the mark tag: a circular arrow in `mark` per buoy, turning anticlockwise to leave the
## mark to port and clockwise to leave it to starboard; a gate shows one per buoy.

var sides: Array[int] = []  # RaceText.Side per buoy


func _init() -> void:
	super()


func _build() -> void:
	var r := 9.0 * k
	var x := r + 2.0 * k
	for sd in sides:
		var port: bool = sd == RaceText.Side.PORT
		var c := Vector2(x, size.y * 0.5)
		# a 300 degree arc from the top; the head at its end shows the direction of the rounding
		var a0 := -PI * 0.5
		var sweep := -TAU * 0.8 if port else TAU * 0.8
		_a(c, r, a0, a0 + sweep, 24, HudStyle.MARK, 2.5 * k)
		var e := a0 + sweep
		var tip := c + r * Vector2(cos(e), sin(e))
		var tangent := Vector2(-sin(e), cos(e)) * (1.0 if not port else -1.0)
		var nrm := Vector2(cos(e), sin(e))
		_p(PackedVector2Array([tip + tangent * 5.0 * k, tip + nrm * 4.5 * k, tip - nrm * 4.5 * k]), HudStyle.MARK)
		x += 2.0 * r + 8.0 * k
