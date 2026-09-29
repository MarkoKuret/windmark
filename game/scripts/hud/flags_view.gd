class_name FlagsView
extends HudCanvas
## hud.md §9.1 flags row: the flags shown now as small drawn flags (class, P, I, Z, U, black, X, first
## substitute), each with its name under it in caps.

var flags: Array[String] = []

const W := 44.0
const H := 28.0
const GAP := 16.0


func _init() -> void:
	super()


func width() -> float:
	return maxf(flags.size() * (W + GAP) - GAP, 0.0) * k


func _build() -> void:
	var x := 0.0
	for f in flags:
		var r := Rect2(x, 0, W * k, H * k)
		_flag(f, r)
		var o := r.grow(0.5)
		_pl(PackedVector2Array([o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y),
			o.position]), Color(0, 0, 0, 0.5), 1.0)
		var label: String = {"class": "CLASS", "1st substitute": "1ST SUB", "black": "BLACK"}.get(f, f + " FLAG")
		_s(Vector2(x + W * k * 0.5, (H + 18.0) * k), label, int(roundf(11.0 * k)), HudStyle.MIST, 600, 0.14,
			HORIZONTAL_ALIGNMENT_CENTER)
		x += (W + GAP) * k


func _flag(f: String, r: Rect2) -> void:
	var blue := Color(0.1, 0.25, 0.7)
	var yellow := Color(0.98, 0.82, 0.1)
	var red := Color(0.85, 0.12, 0.12)
	var white := Color(0.97, 0.97, 0.97)
	var black := Color(0.05, 0.05, 0.05)
	var c := r.get_center()
	var p := r.position
	var s := r.size
	match f:
		"class":  # the class flag: a plain band on white
			_rect(r, white)
			_rect(Rect2(p + Vector2(0, s.y * 0.35), Vector2(s.x, s.y * 0.3)), blue)
		"P":
			_rect(r, blue)
			_rect(Rect2(c - s * 0.2, s * 0.4), white)
		"I":
			_rect(r, yellow)
			_c(c, s.y * 0.3, black)
		"Z":
			_p(PackedVector2Array([p, p + Vector2(s.x, 0), c]), yellow)
			_p(PackedVector2Array([p + Vector2(s.x, 0), p + s, c]), black)
			_p(PackedVector2Array([p + s, p + Vector2(0, s.y), c]), red)
			_p(PackedVector2Array([p + Vector2(0, s.y), p, c]), blue)
		"U":
			var h := s * 0.5
			_rect(Rect2(p, h), red)
			_rect(Rect2(p + Vector2(h.x, 0), h), white)
			_rect(Rect2(p + Vector2(0, h.y), h), white)
			_rect(Rect2(p + h, h), red)
		"black":
			_rect(r, black)
		"X":
			_rect(r, white)
			_rect(Rect2(Vector2(c.x - s.x * 0.09, p.y), Vector2(s.x * 0.18, s.y)), blue)
			_rect(Rect2(Vector2(p.x, c.y - s.y * 0.14), Vector2(s.x, s.y * 0.28)), blue)
		"1st substitute":
			_p(PackedVector2Array([p, p + Vector2(s.x, s.y * 0.5), p + Vector2(0, s.y)]), blue)
			_p(PackedVector2Array([p + Vector2(s.x * 0.2, s.y * 0.25), p + Vector2(s.x * 0.6, s.y * 0.5),
				p + Vector2(s.x * 0.2, s.y * 0.75)]), yellow)
		_:
			_rect(r, Color(0.5, 0.5, 0.5))
