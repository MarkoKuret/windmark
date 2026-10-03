class_name HudCanvas
extends Control
## A HUD block drawn from primitives: a subclass builds its drawing in _build() with the helpers below, _draw()
## renders it, and primitives() returns the same list for the offline previews (tests/race_hud_preview.py) and the
## tests. Coordinates are the control's own; texts are drawn at their baseline in the HUD font (HudStyle).
##   {k: "rect", r: Rect2, col} {k: "grad", r: Rect2, top, bottom} {k: "line", a, b, col, w}
##   {k: "polyline", pts, col, w} {k: "poly", pts, col} {k: "circle", p, r, col}
##   {k: "arc", p, r, a0, a1, n, col, w} {k: "text", p, text, size, col, weight, tracking, align, width}

## the scale of the design (HudStyle.ui_k), set by the layout
var k := 1.0
## a block painted by someone else: painter.call(self) adds the primitives (HudPaint)
var painter := Callable()
## texts get a soft drop shadow (hud_direction.md: data over the scene)
var text_shadow := true

var _prims: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Override: add the primitives of this frame.
func _build() -> void:
	if painter.is_valid():
		painter.call(self)


func primitives() -> Array:
	_prims = []
	_build()
	return _prims


func _rect(r: Rect2, col: Color) -> void:
	_prims.append({"k": "rect", "r": r, "col": col})


func _grad(r: Rect2, top: Color, bottom: Color) -> void:
	_prims.append({"k": "grad", "r": r, "top": top, "bottom": bottom})


func _l(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_prims.append({"k": "line", "a": a, "b": b, "col": col, "w": w})


func _pl(pts: PackedVector2Array, col: Color, w: float) -> void:
	_prims.append({"k": "polyline", "pts": pts, "col": col, "w": w})


func _p(pts: PackedVector2Array, col: Color) -> void:
	_prims.append({"k": "poly", "pts": pts, "col": col})


func _c(p: Vector2, r: float, col: Color) -> void:
	_prims.append({"k": "circle", "p": p, "r": r, "col": col})


func _a(p: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
	_prims.append({"k": "arc", "p": p, "r": r, "a0": a0, "a1": a1, "n": n, "col": col, "w": w})


## Text at baseline `p`; with `align` centre or right, `p.x` is the centre or the right end.
func _s(p: Vector2, text: String, size_px: int, col: Color, weight := 600, tracking := 0.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_prims.append({"k": "text", "p": p, "text": text, "size": maxi(size_px, HudStyle.MIN_TEXT), "col": col,
		"weight": weight, "tracking": tracking, "align": align, "shadow": text_shadow})


## The area this block draws now, in its own coordinates (the union of its primitives' bounds; texts from the
## baseline up the font's ascent and down its descent). Rect2() when it draws nothing. The layout and the tests.
func extent() -> Rect2:
	var out := Rect2()
	var any := false
	for q in primitives():
		var r := prim_rect(q)
		if r.size == Vector2.ZERO and r.position == Vector2.ZERO:
			continue
		out = r if not any else out.merge(r)
		any = true
	return out


## The bounds of one primitive (see the list at the top).
static func prim_rect(q: Dictionary) -> Rect2:
	match q["k"]:
		"rect", "grad":
			return q["r"]
		"line":
			var w: float = q["w"] * 0.5
			return Rect2(q["a"], Vector2.ZERO).expand(q["b"]).grow(w)
		"polyline", "poly":
			var pts: PackedVector2Array = q["pts"]
			if pts.is_empty():
				return Rect2()
			var r := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				r = r.expand(p)
			return r.grow(q.get("w", 0.0) * 0.5)
		"circle", "arc":
			var rr: float = q["r"] + q.get("w", 0.0) * 0.5
			return Rect2(q["p"] - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
		"text":
			if q["text"] == "":
				return Rect2()
			var sz: int = q["size"]
			var f := HudStyle.font(q["weight"], q["tracking"], sz)
			var w := f.get_string_size(q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			var p: Vector2 = q["p"]
			var al: int = q["align"]
			var x := p.x - (w if al == HORIZONTAL_ALIGNMENT_RIGHT else (w * 0.5 if al == HORIZONTAL_ALIGNMENT_CENTER else 0.0))
			return Rect2(x, p.y - f.get_ascent(sz), w, f.get_ascent(sz) + f.get_descent(sz))
	return Rect2()


## The width of a text as _s draws it.
static func text_width(text: String, size_px: int, weight := 600, tracking := 0.0) -> float:
	var sz := maxi(size_px, HudStyle.MIN_TEXT)
	return HudStyle.font(weight, tracking, sz).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


func _draw() -> void:
	for q in primitives():
		match q["k"]:
			"rect":
				draw_rect(q["r"], q["col"])
			"grad":
				var r: Rect2 = q["r"]
				draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
					Vector2(r.position.x, r.end.y)]), PackedColorArray([q["top"], q["top"], q["bottom"], q["bottom"]]))
			"line":
				draw_line(q["a"], q["b"], q["col"], q["w"], true)
			"polyline":
				if (q["pts"] as PackedVector2Array).size() >= 2:
					draw_polyline(q["pts"], q["col"], q["w"], true)
			"poly":
				if (q["pts"] as PackedVector2Array).size() >= 3:
					draw_colored_polygon(q["pts"], q["col"])
			"circle":
				draw_circle(q["p"], q["r"], q["col"])
			"arc":
				draw_arc(q["p"], q["r"], q["a0"], q["a1"], q["n"], q["col"], q["w"], true)
			"text":
				var sz: int = q["size"]
				var f := HudStyle.font(q["weight"], q["tracking"], sz)
				var p: Vector2 = q["p"]
				var al: int = q["align"]
				if al != HORIZONTAL_ALIGNMENT_LEFT:
					var w := f.get_string_size(q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
					p.x -= w if al == HORIZONTAL_ALIGNMENT_RIGHT else w * 0.5
				if q["shadow"]:
					var sh := Color(0, 0, 0, 0.45 * (q["col"] as Color).a)
					draw_string(f, p + Vector2(0, maxf(1.0, k)), q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, sh)
				draw_string(f, p, q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, q["col"])
