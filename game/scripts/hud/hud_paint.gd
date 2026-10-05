class_name HudPaint
extends RefCounted
## The painters of the HUD blocks (hud.md §16, docs/design/hud_direction.md): each takes the block (a HudCanvas,
## coordinates in its own px) and the Hud, and adds the primitives. Positions and sizes are the 1920 x 1080
## design's, times the block's `k`. What shows follows Hud.has_item (density and assist) and the Hud's texts.

const LAB := 14  # cell labels
const LAB_S := 13
const TINY := 11
const TRACK := 0.14  # label tracking, em

# ---- instrument page geometry (design px): the page sizes and the cell grid per level ----

const PAGE := {Hud.Density.GLANCE: Vector2(486, 200), Hud.Density.RACE: Vector2(650, 246),
	Hud.Density.DATA: Vector2(720, 298)}
const PAGE_GLANCE_NO_CUE := 150.0


## The instrument page size of the level (design px); Glance is shorter without its cue strip.
static func page_size(h: Hud) -> Vector2:
	var s: Vector2 = PAGE[h.density]
	if h.density == Hud.Density.GLANCE and not h.has_item("cue"):
		s.y = PAGE_GLANCE_NO_CUE
	return s


static func _hw(b: HudCanvas) -> float:
	return maxf(1.0, 1.5 * b.k)


## glass page: ink 14 % to 44 %, a hairline along the top edge (no blur, no corner ticks)
static func glass(b: HudCanvas, r: Rect2) -> void:
	var k := b.k
	var rr := Rect2(r.position * k, r.size * k)
	b._grad(rr, Color(HudStyle.INK, 0.14), Color(HudStyle.INK, 0.44))
	b._l(rr.position, Vector2(rr.end.x, rr.position.y), HudStyle.HAIR, _hw(b))


static func divider(b: HudCanvas, a: Vector2, c: Vector2) -> void:
	b._l(a * b.k, c * b.k, Color(HudStyle.HAIR, HudStyle.HAIR.a * 0.45), _hw(b))


## caption top left at (x, y), unit top right at x_right (design px)
static func caption(b: HudCanvas, x: float, y: float, text: String, x_right := -1.0, unit := "", size := LAB) -> void:
	var k := b.k
	b._s(Vector2(x, y) * k, text, int(roundf(size * k)), HudStyle.MIST, 600, TRACK)
	if unit != "" and x_right >= 0.0:
		b._s(Vector2(x_right, y) * k, unit, int(roundf(size * k)), HudStyle.MIST, 600, TRACK, HORIZONTAL_ALIGNMENT_RIGHT)


## a number right-aligned at (x_right, baseline) with an optional side letter after it in its tack colour
static func number(b: HudCanvas, x_right: float, y: float, text: String, size: float, col := HudStyle.PAPER,
		side := "") -> void:
	var k := b.k
	var sz := int(roundf(size * k))
	var x := x_right * k
	if side != "":
		var ssz := int(roundf(size * 0.5 * k))
		b._s(Vector2(x, y * k), side, ssz, HudStyle.PORT if side == "P" else HudStyle.STBD, 600, 0.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
		x -= HudCanvas.text_width(side, ssz) + 3.0 * k
	b._s(Vector2(x, y * k), HudStyle.minus(text), sz, col, 600, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)


## a number with its unit after it at 45 % size (world tags, start numbers): left, centre or right aligned
static func number_unit(b: HudCanvas, x: float, y: float, value: String, unit: String, size: float,
		col := HudStyle.PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var k := b.k
	var sz := int(roundf(size * k))
	var usz := int(roundf(maxf(size * 0.45, 13.0) * k))
	var v := HudStyle.minus(value)
	var w := HudCanvas.text_width(v, sz)
	var uw := HudCanvas.text_width(unit, usz, 600, 0.06) + 4.0 * k if unit != "" else 0.0
	var x0 := x * k
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x0 -= (w + uw) * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 -= w + uw
	b._s(Vector2(x0, y * k), v, sz, col)
	if unit != "":
		b._s(Vector2(x0 + w + 4.0 * k, y * k), unit, usz, HudStyle.MIST, 600, 0.06)
	return (w + uw) / k


## "44° P" -> ["44°", "P"]
static func side_split(t: String) -> Array[String]:
	if t.ends_with(" P") or t.ends_with(" S"):
		return [t.substr(0, t.length() - 2), t.right(1)]
	return [t, ""]


# ---- instrument page ----

static func instruments(b: HudCanvas, h: Hud) -> void:
	var sz := page_size(h)
	glass(b, Rect2(Vector2.ZERO, sz))
	_pips(b, h, sz.x)
	match h.density:
		Hud.Density.GLANCE:
			_page_glance(b, h, sz)
		Hud.Density.RACE:
			_page_race(b, h, false)
		Hud.Density.DATA:
			_page_race(b, h, true)


static func _pips(b: HudCanvas, h: Hud, w: float) -> void:
	var k := b.k
	for i in 3:
		var r := Rect2(Vector2(w - 40.0 + 11.0 * i, 9.0) * k, Vector2(7, 7) * k)
		if i <= int(h.density):
			b._rect(r, HudStyle.PAPER)
		else:
			b._pl(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
				r.position]), HudStyle.HAIR, maxf(1.0, k))


static func _bsp(b: HudCanvas, h: Hud) -> void:
	caption(b, 14, 24, "BOAT SPEED", 236, "KN")
	number(b, 236, 134, h.value_of("bsp"), 112)


## the cue cell: VMG % on a beat or run, polar % otherwise, with its meter
static func _cue(b: HudCanvas, h: Hud, x: float, y_cap: float, x_right: float, y_num: float, size: float,
		meter: Rect2, compact := false) -> void:
	var vmg := h.cue_is_vmg()
	var name := "VMG TARGET" if vmg else "POLAR"
	if compact:
		caption(b, x, y_cap, name)
	else:
		caption(b, x, y_cap, name, x_right, "%")
	var pct := h.cue_pct()
	number(b, x_right, y_num, "--" if is_nan(pct) else HudFormat.percent(pct), size)
	_meter(b, meter, pct)


## hairline 80 % to 110 % with a tall paper tick at 100 % and a yellow bar and pointer at the value
static func _meter(b: HudCanvas, r: Rect2, pct: float) -> void:
	var k := b.k
	var y := r.position.y * k
	var x0 := r.position.x * k
	var x1 := r.end.x * k
	var hw := _hw(b)
	b._l(Vector2(x0, y), Vector2(x1, y), HudStyle.HAIR, hw)
	for i in 4:
		var tx := lerpf(x0, x1, i / 3.0)
		b._l(Vector2(tx, y - 4.0 * k), Vector2(tx, y), HudStyle.HAIR, hw)
	var xt := lerpf(x0, x1, 20.0 / 30.0)
	b._l(Vector2(xt, y - 10.0 * k), Vector2(xt, y + 6.0 * k), HudStyle.PAPER, hw)
	if is_nan(pct):
		return
	var xv := lerpf(x0, x1, clampf((pct - 80.0) / 30.0, 0.0, 1.0))
	b._rect(Rect2(minf(xv, xt), y - 2.0 * k, maxf(absf(xt - xv), hw), 5.0 * k), HudStyle.MARK)
	b._p(PackedVector2Array([Vector2(xv, y - 4.0 * k), Vector2(xv - 6.0 * k, y - 14.0 * k),
		Vector2(xv + 6.0 * k, y - 14.0 * k)]), HudStyle.MARK)


static func _twa_value(b: HudCanvas, h: Hud, x_right: float, y: float, size: float) -> void:
	var t := side_split(h.value_of("twa"))
	number(b, x_right, y, t[0], size, HudStyle.PAPER, t[1])


static func _page_glance(b: HudCanvas, h: Hud, sz: Vector2) -> void:
	_bsp(b, h)
	divider(b, Vector2(250, 10), Vector2(250, 140))
	caption(b, 264, 24, "TWA")
	dial(b, h, Vector2(328, 88), 52.0, false)
	_twa_value(b, h, 472, 134, 44)
	if h.has_item("cue"):
		divider(b, Vector2(10, 150), Vector2(sz.x - 10, 150))
		_cue(b, h, 14, 182, 472, 188, 30, Rect2(170, 178, 200, 0), true)


static func _page_race(b: HudCanvas, h: Hud, data: bool) -> void:
	var w: float = PAGE[h.density].x
	_bsp(b, h)
	divider(b, Vector2(250, 10), Vector2(250, 236))
	if h.has_item("cue"):
		_cue(b, h, 264, 24, 446, 98, 64, Rect2(274, 124, 162, 0))
	divider(b, Vector2(460, 10), Vector2(460, 236))
	caption(b, 474, 24, "TWA")
	var dc := Vector2(474 + (w - 474) * 0.5 - 6.0, 104)
	dial(b, h, dc, 62.0, data)
	_twa_value(b, h, w - 14, 232, 44)
	divider(b, Vector2(10, 150), Vector2(450, 150))
	var target: Dictionary = h.texts.get("target_cell", {})
	if data:
		caption(b, 474, 214, "AWA", -1, "", LAB_S)
		var aw := side_split(h.value_of("awa"))
		b._s(Vector2(474, 234) * b.k, aw[0] + aw[1], int(roundf(18 * b.k)), HudStyle.MIST, 600)
		caption(b, 14, 174, "HDG")
		number(b, 111, 230, h.value_of("hdg"), 44)
		divider(b, Vector2(125, 160), Vector2(125, 236))
		var reach := h.race.active and h.race.leg_type == "reach"
		caption(b, 139, 174, "VMC" if reach else "VMG", 236, "KN")
		number(b, 236, 230, h.value_of("vmg_kn"), 44)
	else:
		caption(b, 14, 174, "HEADING")
		number(b, 236, 230, h.value_of("hdg"), 52)
	if h.has_item("target"):
		caption(b, 264, 174, "TARGET", 446, target.get("unit", ""))
		number(b, 446, 230, target.get("value", "--"), 44)
	if not data:
		return
	divider(b, Vector2(10, 246), Vector2(w - 10, 246))
	# row 3: small cells, the label over the value (room for the 11 px floor of small screens)
	var cells := [["SOG", "sog", 86.0], ["COG", "cog", 186.0], ["AWS", "aws", 294.0]]
	if h.has_item("polar"):
		cells.append(["POLAR %", "polar", 418.0])
	var x := 14.0
	for c in cells:
		caption(b, x, 268, c[0], -1, "", LAB_S)
		number(b, c[2], 292, h.value_of(c[1]), 26)
		divider(b, Vector2(c[2] + 14.0, 256), Vector2(c[2] + 14.0, 290))
		x = c[2] + 28.0
	caption(b, 446, 268, "HEEL", -1, "", LAB_S)
	_heel_bar(b, h, Rect2(446, 284, 170, 0))
	var hs := side_split(h.value_of("heel"))
	number(b, w - 14, 292, hs[0], 26)


## centre zero, +-30 degrees, the bar in the tack colour to the side that is down
static func _heel_bar(b: HudCanvas, h: Hud, r: Rect2) -> void:
	var k := b.k
	var y := r.position.y * k
	var x0 := r.position.x * k
	var x1 := r.end.x * k
	var hw := _hw(b)
	b._l(Vector2(x0, y), Vector2(x1, y), HudStyle.HAIR, hw)
	for i in 7:
		var tx := lerpf(x0, x1, i / 6.0)
		b._l(Vector2(tx, y - (6.0 if i == 3 else 3.0) * k), Vector2(tx, y + 3.0 * k), HudStyle.HAIR, hw)
	var phi := h.values.heel  # + = starboard down
	var xc := (x0 + x1) * 0.5
	var xv := xc + clampf(rad_to_deg(phi) / 30.0, -1.0, 1.0) * (x1 - x0) * 0.5
	b._rect(Rect2(minf(xc, xv), y - 2.5 * k, absf(xv - xc), 5.0 * k), HudStyle.STBD if phi > 0.0 else HudStyle.PORT)


## TWA dial (hud.md §16.3): bow up, close-hauled sectors, the target ticks, the true wind pointer from the rim and
## (with `apparent`) the apparent wind as a hollow pointer; a hull outline in the centre. Every frame.
static func dial(b: HudCanvas, h: Hud, c_design: Vector2, r_design: float, apparent: bool) -> void:
	var k := b.k
	var c := c_design * k
	var r := r_design * k
	var hw := _hw(b)
	b._c(c, r, Color(HudStyle.INK, 0.30))
	b._a(c, r, 0.0, TAU, 72, HudStyle.HAIR, hw)
	var dir := func(a: float) -> Vector2: return Vector2(sin(a), -cos(a))
	for i in 12:
		var a := TAU * i / 12.0
		b._l(c + dir.call(a) * r, c + dir.call(a) * (r - 8.0 * k), HudStyle.HAIR, hw)
	# close-hauled sectors 20..60 degrees, port on the left
	var s0 := deg_to_rad(20.0)
	var s1 := deg_to_rad(60.0)
	b._a(c, r - 4.0 * k, -PI * 0.5 + s0, -PI * 0.5 + s1, 12, Color(HudStyle.STBD, 0.85), 3.0 * k)
	b._a(c, r - 4.0 * k, -PI * 0.5 - s1, -PI * 0.5 - s0, 12, Color(HudStyle.PORT, 0.85), 3.0 * k)
	var tt := h.dial_target()
	if not is_nan(tt):
		for sgn in [1.0, -1.0]:
			var a: float = sgn * tt
			b._l(c + dir.call(a) * (r - 2.0 * k), c + dir.call(a) * (r - 16.0 * k), HudStyle.MARK, 2.0 * k)
	# hull
	var hl := r * 0.42
	var hb := r * 0.14
	b._pl(PackedVector2Array([c + Vector2(0, -hl), c + Vector2(hb, -hl * 0.2), c + Vector2(hb * 0.8, hl),
		c + Vector2(-hb * 0.8, hl), c + Vector2(-hb, -hl * 0.2), c + Vector2(0, -hl)]), HudStyle.PAPER, hw)
	_pointer(b, c, r, h.values.twa, true)
	if apparent:
		_pointer(b, c, r, h.values.awa, false)


static func _pointer(b: HudCanvas, c: Vector2, r: float, a: float, solid: bool) -> void:
	var k := b.k
	var d := Vector2(sin(a), -cos(a))
	var s := Vector2(-d.y, d.x)
	var tip := c + d * (r - 14.0 * k)
	var base := c + d * (r + 2.0 * k)
	var pts := PackedVector2Array([tip, base + s * 6.0 * k, base - s * 6.0 * k])
	if solid:
		b._p(pts, HudStyle.PAPER)
		b._l(tip, c + d * r * 0.5, HudStyle.PAPER, 2.0 * k)
	else:
		pts.append(pts[0])
		b._pl(pts, HudStyle.PAPER, 1.5 * k)


# ---- toast ----

static func toast(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var lvl: String = Hud.DENSITY_NAMES[h.density]
	var w := 124.0 + HudCanvas.text_width(lvl, int(roundf(13 * k)), 700, 0.1) / k + 16.0
	b._rect(Rect2(Vector2.ZERO, Vector2(w, 32) * k), Color(HudStyle.INK, 0.86))
	b._rect(Rect2(Vector2.ZERO, Vector2(4, 32) * k), HudStyle.MARK)
	b._s(Vector2(16, 21) * k, "INSTRUMENTS", int(roundf(13 * k)), HudStyle.MIST, 600, TRACK)
	b._s(Vector2(124, 21) * k, lvl, int(roundf(13 * k)), HudStyle.PAPER, 700, 0.1)


# ---- race bug (top left) ----

const BUG_W := 340.0


static func bug(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	b._rect(Rect2(Vector2.ZERO, Vector2(BUG_W, 72) * k), Color(HudStyle.INK, 0.86))
	b._rect(Rect2(Vector2.ZERO, Vector2(6, 72) * k), HudStyle.MARK)
	var clock := h.text_of("clock")
	var cap := "RACE"
	var val := h.value_of("clock")
	if not r.started or clock.begins_with("Start in") or clock.begins_with("Warning in"):
		cap = "FLEET"
		val = str(r.fleet)
	elif clock.begins_with("Finished"):
		cap = "FINISHED"
	elif clock == "Abandoned":
		cap = "RACE"
		val = "ABANDONED"
	b._s(Vector2(24, 22) * k, cap, int(roundf(15 * k)), HudStyle.MIST, 600, TRACK)
	var vs := 40.0 if val.length() <= 5 else 30.0
	if cap == "FLEET":
		number_unit(b, 24, 62, val, "BOATS", vs)
	else:
		b._s(Vector2(24, 62) * k, val, int(roundf(vs * k)), HudStyle.PAPER)
	if r.started and r.rank > 0:
		b._l(Vector2(190, 14) * k, Vector2(190, 58) * k, HudStyle.HAIR, _hw(b))
		b._s(Vector2(210, 22) * k, "RANK", int(roundf(15 * k)), HudStyle.MIST, 600, TRACK)
		number_unit(b, 210, 62, str(r.rank), "/ %d" % r.fleet, 40)
	var y := 102.0
	if h.has_item("bug_lap"):
		var line := ""
		if r.started and r.next_step > 0:
			line = h.text_of("lap").to_upper() + " · " + r.leg_type.to_upper()
		elif not r.started and r.laps > 0:
			line = "%d %s · %d LEGS" % [r.laps, "LAP" if r.laps == 1 else "LAPS", maxi(r.legs, 1)]
		if line != "":
			b._s(Vector2(0, y) * k, line, int(roundf(15 * k)), HudStyle.PAPER, 600, TRACK)
			y += 32.0
	if h.has_item("bug_gaps"):
		for key in ["gap", "ahead", "behind"]:
			var t := h.text_of(key)
			if t != "":
				b._s(Vector2(0, y) * k, t, int(roundf(20 * k)), HudStyle.PAPER, 500)
				y += 28.0


# ---- wind page (top right) ----

const WIND := Vector2(312, 112)


static func wind(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	glass(b, Rect2(Vector2.ZERO, WIND))
	caption(b, 14, 24, "TRUE WIND", 182, "KN")
	number(b, 182, 96, h.value_of("tws"), 56)
	divider(b, Vector2(196, 10), Vector2(196, 102))
	caption(b, 208, 24, "TWD", 300, h.value_of("twd"))
	var c := Vector2(254, 70) * k
	var rr := 30.0 * k
	var hw := _hw(b)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector2(sin(a), -cos(a))
		b._l(c + d * rr, c + d * (rr - 6.0 * k), HudStyle.HAIR, hw)
	b._s(c + Vector2(0, -rr + 16.0 * k), "N", int(roundf(TINY * k)), HudStyle.MIST, 600, 0.0,
		HORIZONTAL_ALIGNMENT_CENTER)
	# the true wind blowing across the dial from where it comes (north up)
	var d := Vector2(sin(h.values.twd), -cos(h.values.twd))
	var from := c + d * rr
	var to := c - d * rr
	b._l(from, to - d * -6.0 * k, HudStyle.PAPER, 2.0 * k)
	var s := Vector2(-d.y, d.x)
	b._p(PackedVector2Array([to, to + d * 10.0 * k + s * 5.0 * k, to + d * 10.0 * k - s * 5.0 * k]), HudStyle.PAPER)
	if h.has_item("shift") and h.text_of("shift") != "" and h.race.shift_kind != "":
		var col := HudStyle.STBD if h.race.shift_kind == "lift" else HudStyle.PORT
		var t := h.text_of("shift")
		var tw := HudCanvas.text_width(t, int(roundf(15 * k)), 700, 0.1) / k + 28.0
		var r := Rect2(Vector2(WIND.x - tw, 124) * k, Vector2(tw, 30) * k)
		b._rect(r, col)
		var sv := b.text_shadow
		b.text_shadow = false
		b._s(Vector2(r.position.x + r.size.x * 0.5, r.position.y + 21.0 * k), t, int(roundf(15 * k)), HudStyle.INK, 700,
			0.1, HORIZONTAL_ALIGNMENT_CENTER)
		b.text_shadow = sv


# ---- feed (under the wind page, right-aligned) ----

static func feed(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var y := 20.0
	for l in h.feed_lines():
		b._s(Vector2(b.size.x, y * k), l.text, int(roundf(18 * k)), Color(HudStyle.PAPER, clampf(l.ticks / 20.0, 0.0, 1.0)
			* 0.9), 500, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 26.0


# ---- start block (top centre, before the start) ----

const LANE_W := 900.0


static func start_height(h: Hud) -> float:
	if not h.race.active:
		return 0.0
	var y := 150.0 if h.countdown_shown() else 0.0
	if h.finish_card_shown():
		y += CARD_H
	if h.race.start_panel:
		y += 96.0 if h.has_item("start_full") else 76.0
	if h.flag_rule() != "":
		y += 30.0
	if h.text_of("over") != "":
		y += 48.0
	return y


static func start(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	var cx := LANE_W * 0.5
	var clock := h.text_of("clock")
	var y := 0.0
	if h.countdown_shown():
		var cap := "START IN" if clock.begins_with("Start") else "WARNING IN"
		b._s(Vector2(cx, 22) * k, cap, int(roundf(15 * k)), HudStyle.MIST, 600, TRACK, HORIZONTAL_ALIGNMENT_CENTER)
		var t := clock.substr(clock.rfind(" ") + 1)
		var last10 := cap == "START IN" and r.race_time > -10.0
		b._s(Vector2(cx, 134) * k, t, int(roundf(128 * k)), HudStyle.MARK if last10 else HudStyle.PAPER, 600, 0.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		y = 150.0
	if h.finish_card_shown():
		finish_card(b, h, y)
		y += CARD_H
	if r.start_panel:
		if h.has_item("start_full"):
			var cells := [["LINE", "line"], ["TO LINE", "tline"], ["BURN", "burn"], ["BIAS", "bias"]]
			var shown := []
			for c in cells:
				if h.text_of(c[1]) != "":
					shown.append(c)
			var x := cx - 100.0 * (shown.size() - 1)
			for c in shown:
				b._s(Vector2(x, y + 20.0) * k, c[0], int(roundf(15 * k)), HudStyle.MIST, 600, TRACK,
					HORIZONTAL_ALIGNMENT_CENTER)
				number_unit(b, x, y + 62.0, h.value_of(c[1]), h.unit_of(c[1]), 40, h.colour_of(c[1]),
					HORIZONTAL_ALIGNMENT_CENTER)
				if c[1] == "bias":
					b._s(Vector2(x, y + 86.0) * k, h.texts["bias"].get("sub", ""), int(roundf(13 * k)), HudStyle.MIST,
						600, 0.06, HORIZONTAL_ALIGNMENT_CENTER)
				if c[1] == "burn":
					_burn_bar(b, h, Vector2(x, y + 80.0))
				x += 200.0
			y += 96.0
		else:
			if h.text_of("burn") != "":
				b._s(Vector2(cx, y + 20.0) * k, "BURN", int(roundf(15 * k)), HudStyle.MIST, 600, TRACK,
					HORIZONTAL_ALIGNMENT_CENTER)
				number_unit(b, cx, y + 56.0, h.value_of("burn"), h.unit_of("burn"), 36, h.colour_of("burn"),
					HORIZONTAL_ALIGNMENT_CENTER)
				_burn_bar(b, h, Vector2(cx, y + 68.0))
			y += 76.0
	var rule := h.flag_rule()
	if rule != "":
		b._s(Vector2(cx, y + 18.0) * k, rule, int(roundf(13 * k)), HudStyle.PAPER, 600, 0.1, HORIZONTAL_ALIGNMENT_CENTER)
		y += 30.0
	var over := h.text_of("over")
	if over != "":
		var t := over.to_upper().replace("  ", ": ")
		var tw := HudCanvas.text_width(t, int(roundf(22 * k)), 700, 0.06) / k + 36.0
		var rr := Rect2(Vector2(cx - tw * 0.5, y + 6.0) * k, Vector2(tw, 36) * k)
		b._rect(rr, HudStyle.PORT)
		var sv := b.text_shadow
		b.text_shadow = false
		b._s(Vector2(cx, y + 32.0) * k, t, int(roundf(22 * k)), HudStyle.PAPER, 700, 0.06, HORIZONTAL_ALIGNMENT_CENTER)
		b.text_shadow = sv


const CARD_H := 186.0


## hud.md §13.1 the finish card at `y` (design px) in the lane: caption, the place (or code) at the countdown's size
## with the gap beside it, the finish time under them; faded by the card's opacity
static func finish_card(b: HudCanvas, h: Hud, y: float) -> void:
	var k := b.k
	var c: Dictionary = h.race.card
	var a := h.finish_card_alpha()
	var cx := LANE_W * 0.5
	b._s(Vector2(cx, y + 22) * k, c.get("caption", ""), int(roundf(15 * k)), Color(HudStyle.MIST, HudStyle.MIST.a * a),
		600, TRACK, HORIZONTAL_ALIGNMENT_CENTER)
	var big: String = c.get("big", "")
	var gap: String = c.get("gap", "")
	var big_px := int(roundf(128 * k))
	var gap_px := int(roundf(48 * k))
	var wb := HudCanvas.text_width(big, big_px)
	var wg := HudCanvas.text_width(gap, gap_px) + 22.0 * k if gap != "" else 0.0
	var x := cx * k - (wb + wg) * 0.5
	var col: Color = HudStyle.MARK if bool(c.get("win", false)) else HudStyle.PAPER
	if c.get("kind", "") != "finish":
		col = HudStyle.PORT
	b._s(Vector2(x, (y + 134) * k), big, big_px, Color(col, a), 600)
	if gap != "":
		b._s(Vector2(x + wb + 22.0 * k, (y + 134) * k), gap, gap_px, Color(HudStyle.MIST, HudStyle.MIST.a * a), 600)
	var t: String = c.get("time", "")
	if t != "":
		b._s(Vector2(cx, y + 170) * k, t, int(roundf(20 * k)), Color(HudStyle.PAPER, a), 600, 0.04,
			HORIZONTAL_ALIGNMENT_CENTER)


## late/early bar: +-30 s from the centre, yellow to the value
static func _burn_bar(b: HudCanvas, h: Hud, c_design: Vector2) -> void:
	var k := b.k
	var c := c_design * k
	var half := 50.0 * k
	var hw := _hw(b)
	b._l(c - Vector2(half, 0), c + Vector2(half, 0), HudStyle.HAIR, hw)
	b._l(c - Vector2(0, 5.0 * k), c + Vector2(0, 5.0 * k), HudStyle.PAPER, hw)
	b._s(c + Vector2(-half - 6.0 * k, 4.0 * k), "LATE", int(roundf(TINY * k)), HudStyle.MIST, 600, TRACK,
		HORIZONTAL_ALIGNMENT_RIGHT)
	b._s(c + Vector2(half + 6.0 * k, 4.0 * k), "EARLY", int(roundf(TINY * k)), HudStyle.MIST, 600, TRACK)
	var burn := h.race.burn
	if is_nan(burn):
		return
	var xv := clampf(burn / 30.0, -1.0, 1.0) * half
	b._rect(Rect2(c.x + minf(0.0, xv), c.y - 2.5 * k, absf(xv), 5.0 * k), HudStyle.MARK if burn >= 0.0 else HudStyle.OWE)


# ---- penalty panel (top centre, while racing) ----

const PEN := Vector2(620, 118)


static func penalty(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	b._rect(Rect2(Vector2.ZERO, PEN * k), Color(HudStyle.INK, 0.86))
	b._rect(Rect2(Vector2.ZERO, Vector2(PEN.x, 4) * k), HudStyle.PORT)
	var x := 176.0
	var head := "PENALTY"
	if r.pending > 0:
		head += " · %d PENDING · RULE %s" % [r.pending, RaceText.code(r.penalty_rule)]
	b._s(Vector2(x, 30) * k, head, int(roundf(14 * k)), HudStyle.PORT, 700, 0.1)
	var main := RaceText.rule_text(r.penalty_rule) if r.pending > 0 else h.text_of("pen_head")
	b._s(Vector2(x, 62) * k, main, int(roundf(24 * k)), HudStyle.PAPER, 600)
	var sub := h.text_of("pen_turn")
	if r.pending > 0 and r.penalty_other >= 0:
		sub = "With %s · %s" % [r.name_of(r.penalty_other).to_upper(), sub]
	b._s(Vector2(x, 88) * k, sub, int(roundf(16 * k)), HudStyle.MIST, 500)
	if h.text_of("pen_dsq") != "":
		b._s(Vector2(x, 110) * k, h.text_of("pen_dsq"), int(roundf(14 * k)), HudStyle.PORT, 700, 0.06)
	if h.text_of("pen_deadline") != "":
		b._s(Vector2(PEN.x - 16, 30) * k, "DEADLINE", int(roundf(14 * k)), HudStyle.MIST, 600, TRACK,
			HORIZONTAL_ALIGNMENT_RIGHT)
		b._s(Vector2(PEN.x - 16, 88) * k, h.value_of("pen_deadline"), int(roundf(52 * k)), h.colour_of("pen_deadline"),
			600, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)


# ---- alert lines (rules line, banner, prompt) ----

static func alert_lines(h: Hud) -> Array:
	var out := []
	for key in ["rules", "banner", "prompt"]:
		if h.text_of(key) != "":
			out.append(key)
	return out


static func alerts_height(h: Hud) -> float:
	var y := 0.0
	for key in alert_lines(h):
		y += 64.0 if key == "banner" and h.race.banner != null and h.race.banner.full else 52.0
	return y


static func alerts(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var cx := LANE_W * 0.5
	var y := 0.0
	for key in alert_lines(h):
		var full: bool = key == "banner" and h.race.banner != null and h.race.banner.full
		var size := 34.0 if full else (24.0 if key != "prompt" else 20.0)
		var t := h.text_of(key)
		if key == "rules":
			t = t.to_upper()
		var col := h.colour_of(key)
		var tw := HudCanvas.text_width(t, int(roundf(size * k)), 700, 0.04) / k + 40.0
		var hgt := size + 18.0
		var rr := Rect2(Vector2(cx - tw * 0.5, y), Vector2(tw, hgt))
		b._rect(Rect2(rr.position * k, rr.size * k), Color(HudStyle.INK, 0.86))
		b._rect(Rect2(rr.position * k, Vector2(6, hgt) * k), col)
		b._s(Vector2(cx + 3.0, y + hgt * 0.5 + size * 0.36) * k, t, int(roundf(size * k)), col, 700, 0.04,
			HORIZONTAL_ALIGNMENT_CENTER)
		y += 64.0 if full else 52.0


# ---- helm strip (bottom centre) ----

const HELM := Vector2(360, 128)


static func helm(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	if h.density == Hud.Density.GLANCE:
		return
	var fs := int(roundf(LAB_S * k))
	var y := 108.0
	var left := "HELM"
	if h.density == Hud.Density.DATA:
		left += "  " + h.value_of("rudder")
	b._s(Vector2(0, y) * k, left, fs, HudStyle.MIST, 600, TRACK)
	var sail := h.value_of("sail")
	b._s(Vector2(HELM.x, y) * k, sail, fs, HudStyle.PAPER, 600, TRACK, HORIZONTAL_ALIGNMENT_RIGHT)
	var sh := "SHEETS AUTO" if h.values.auto_trim else "SHEET " + h.value_of("sheet")
	b._s(Vector2(HELM.x * 0.5, y) * k, sh, fs, HudStyle.PORT if h.values.let_fly else HudStyle.PAPER, 600, TRACK,
		HORIZONTAL_ALIGNMENT_CENTER)


## the sail hint and the controls' messages, one line each over the helm strip
static func helm_notes(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var y := 16.0
	for key in ["message", "hint"]:
		var t := h.text_of(key)
		if t != "" and (key != "hint" or h.has_item("hint")):
			b._s(Vector2(b.size.x * 0.5, y * k), t, int(roundf(16 * k)), HudStyle.HAVE if key == "hint" else HudStyle.PAPER,
				600, 0.04, HORIZONTAL_ALIGNMENT_CENTER)
			y += 24.0


# ---- mark tag ----

static func mark_tag(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	var x := 30.0
	b._s(Vector2(x, 16) * k, h.text_of("next").to_upper(), int(roundf(15 * k)), HudStyle.MARK, 600, TRACK)
	number_unit(b, x, 60, h.value_of("mark_dist"), h.unit_of("mark_dist"), 44)
	var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
	var sub := "ETA %s · BRG %s · %s" % [eta, HudFormat.compass_deg(r.next_bearing),
		HudFormat.relative_bearing(r.next_rel)]
	b._s(Vector2(x, 86) * k, sub, int(roundf(13 * k)), HudStyle.PAPER, 600, 0.1)
	if h.world_tack_point() == null and h.text_of("layline") != "":
		var t := h.text_of("layline")
		b._s(Vector2(x, 112) * k, t.to_upper().replace("LAYLINE", turn_in_label(r.leg_type)), int(roundf(13 * k)),
			HudStyle.PORT if t.begins_with("OVER") else HudStyle.PAPER, 600, 0.1)


## hud.md §16.4: the turn onto the other tack's layline is a tack on a beat and a gybe on a run
static func turn_in_label(leg_type: String) -> String:
	return "GYBE IN" if leg_type == "run" else "TACK IN"


# ---- ranking list and results ----

static func table(b: HudCanvas, title: String, header: Array, rows: Array, widths: Array, own_row := -1) -> void:
	var k := b.k
	var w := 0.0
	for x in widths:
		w += x
	w += 48.0
	var hgt := 96.0 + 38.0 * rows.size() + 16.0
	b._rect(Rect2(Vector2.ZERO, Vector2(w, hgt) * k), Color(HudStyle.INK, 0.86))
	b._l(Vector2.ZERO, Vector2(w, 0) * k, HudStyle.HAIR, _hw(b))
	b._rect(Rect2(Vector2.ZERO, Vector2(6, hgt) * k), HudStyle.MARK)
	b._s(Vector2(24, 40) * k, title.to_upper(), int(roundf(22 * k)), HudStyle.PAPER, 700, 0.08)
	var x := 24.0
	for i in header.size():
		b._s(Vector2(x, 78) * k, str(header[i]).to_upper(), int(roundf(LAB * k)), HudStyle.MIST, 600, TRACK)
		x += widths[i]
	var y := 116.0
	for ri in rows.size():
		x = 24.0
		var row: Array = rows[ri]
		var col := HudStyle.MARK if ri == own_row else HudStyle.PAPER
		for i in row.size():
			var t := str(row[i])
			b._s(Vector2(x, y) * k, t.to_upper() if i == 1 else t, int(roundf(20 * k)),
				HudStyle.MIST if i == 3 else col, 600, 0.04 if i == 1 else 0.0)
			x += widths[i]
		y += 38.0


static func table_size(widths: Array, rows: int) -> Vector2:
	var w := 48.0
	for x in widths:
		w += x
	return Vector2(w, 96.0 + 38.0 * rows + 16.0)


# ---- world: tags and marks on the scene (needs the camera) ----

static func world(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var hw := _hw(b)
	var r := h.race
	# the mark tag's leader and the mark point
	var mp: Variant = h.mark_screen()
	if mp != null and h.next_panel.visible:
		var p: Vector2 = mp
		var tag_foot := h.next_panel.position + Vector2(30.0, 96.0) * k
		b._l(tag_foot, p, Color(HudStyle.MARK, 0.9), hw)
		var d := 6.0 * k
		b._pl(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0),
			p + Vector2(0, -d)]), HudStyle.MARK, hw)
	elif r.active and r.next_step > 0 and h.world_camera() != null and h.text_of("next") != "":
		var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
		edge_pointer(b, h, h.mark_world(), h.text_of("next").to_upper(), "%s · ETA %s" % [
			HudFormat.distance(r.next_dist), eta], HudStyle.MARK)
	# tack point
	var tp: Variant = h.world_tack_point()
	if tp != null:
		var bs: Variant = h.project(h.own_world(0.0))
		var ts: Variant = h.project(Vector3(tp.x, tp.y, 0.0))
		if bs != null and ts != null:
			var a: Vector2 = bs
			var c: Vector2 = ts
			var n := int(a.distance_to(c) / (11.0 * k))
			for i in n:
				var t0 := float(i) / n
				b._l(a.lerp(c, t0), a.lerp(c, t0 + 0.35 / n), Color(HudStyle.PAPER, 0.9), 2.0 * k)
			var col := HudStyle.PORT if h.values.twa > 0.0 else HudStyle.STBD
			b._a(c, 7.0 * k, 0.0, TAU, 24, col, 2.0 * k)
			var t := h.text_of("layline")
			if t.begins_with("Layline"):
				b._s(c + Vector2(0, -44.0 * k), turn_in_label(r.leg_type), int(roundf(LAB * k)), HudStyle.PAPER, 600, TRACK,
					HORIZONTAL_ALIGNMENT_CENTER)
				number_unit(b, c.x / k, c.y / k - 14.0, HudStyle.split_unit(HudFormat.distance(r.layline_dist))[0],
					HudStyle.split_unit(HudFormat.distance(r.layline_dist))[1] + "  " + HudFormat.clock(r.layline_time), 36,
					HudStyle.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	# name tags
	for tag in h.name_tags():
		var q: Vector2 = tag["p"]
		var name: String = tag["name"]
		var col: Color = tag["col"]
		var solid: bool = tag["solid"]
		var fs := int(roundf(13 * k))
		var tw := HudCanvas.text_width(name, fs, 700, 0.1) + 16.0 * k
		var rr := Rect2(q + Vector2(-tw * 0.5, -34.0 * k), Vector2(tw, 22.0 * k))
		b._l(q + Vector2(0, -12.0 * k), q, Color(col, col.a * 0.8), hw)
		b._rect(rr, Color(col, col.a) if solid else Color(HudStyle.INK, 0.8 * col.a))
		if tag["outline"]:
			var o := rr.grow(3.0 * k)
			b._pl(PackedVector2Array([o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y),
				o.position]), col, hw)
		var sv := b.text_shadow
		b.text_shadow = false
		b._s(Vector2(q.x, rr.position.y + 16.0 * k), name, fs, Color(HudStyle.INK, col.a) if solid else col, 700, 0.1,
			HORIZONTAL_ALIGNMENT_CENTER)
		b.text_shadow = sv
	for e in h.selected_off_screen():
		edge_pointer(b, h, e["w"], e["name"], HudFormat.distance(e["d"]), e["col"])
	# penalty turn on the water (chase and aerial cameras)
	if h.penalty_turn_shown():
		_penalty_turn(b, h)


## an arrow at the screen edge towards a world point off screen, with a name and a line under it
static func edge_pointer(b: HudCanvas, h: Hud, w: Vector3, name: String, sub: String, col: Color) -> void:
	var k := b.k
	var cam := h.world_camera()
	if cam == null:
		return
	var sz := b.size
	var c := sz * 0.5
	var scene := Frames.enu_to_scene(w.x, w.y, w.z)
	var p := cam.unproject_position(scene)
	var dir := p - c
	if cam.is_position_behind(scene):
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2(0, -1)
	# keep clear of the corners' blocks: the top lane and bug, the instrument page and radar at the bottom
	var box := Rect2(Vector2(70.0, 250.0) * k, sz - Vector2(140.0, 250.0 + 330.0) * k)
	if h.edge_box.has_area():
		box = h.edge_box  # portrait (hud.md §16.5): under the alert lane, over the bottom stack
	c = box.get_center()
	var half := box.size * 0.5
	var t := minf(absf(half.x / dir.x) if absf(dir.x) > 1e-6 else INF, absf(half.y / dir.y) if absf(dir.y) > 1e-6 else INF)
	var q := c + dir * t
	var u := dir.normalized()
	var s := Vector2(-u.y, u.x)
	b._p(PackedVector2Array([q + u * 16.0 * k, q + s * 8.0 * k, q - s * 8.0 * k]), col)
	var right := u.x > 0.3
	var left := u.x < -0.3
	var al := HORIZONTAL_ALIGNMENT_RIGHT if right else (HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER)
	var tx := q.x + (-14.0 * k if right else (14.0 * k if left else 0.0))
	var ty := q.y + (-6.0 * k if absf(u.y) < 0.7 else (-40.0 * k if u.y > 0.0 else 30.0 * k))
	b._s(Vector2(tx, ty), name, int(roundf(LAB_S * k)), col, 700, 0.1, al)
	b._s(Vector2(tx, ty + 20.0 * k), sub, int(roundf(18 * k)), HudStyle.PAPER, 500, 0.0, al)


## a ring of 1.5 L round the boat on the water: faint in full, the turn so far thick in `port`, a head at the bow
static func _penalty_turn(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	var pose := h.own_pose()
	if pose == null:
		return
	var rad := 1.5 * r._loa
	var o := Vector2(pose.pos_x, pose.pos_y)
	var dirn := float(r.turn_sign if r.turn_sign != 0 else 1)
	var f := clampf(r.turn_deg / maxf(r.turn_target, 1.0), 0.0, 1.0)
	# the circle the bow sails round: centre abeam on the turning side; a point at compass angle a from it
	var centre := o + rad * Vector2(sin(pose.psi + dirn * PI * 0.5), cos(pose.psi + dirn * PI * 0.5))
	var a_bow := pose.psi - dirn * PI * 0.5  # the boat's position seen from the centre
	var ring := PackedVector2Array()
	var done := PackedVector2Array()
	var n := 64
	for i in n + 1:
		var a := a_bow + TAU * i / n
		var q: Variant = h.project(Vector3(centre.x + rad * sin(a), centre.y + rad * cos(a), 0.0))
		if q == null:
			return
		ring.append(q)
	var m := maxi(2, int(n * f) + 1)
	for i in m:
		var a := a_bow - dirn * TAU * f * (1.0 - float(i) / (m - 1))
		var q: Variant = h.project(Vector3(centre.x + rad * sin(a), centre.y + rad * cos(a), 0.0))
		if q == null:
			return
		done.append(q)
	b._pl(ring, Color(HudStyle.PORT, 0.35), 2.0 * k)
	if f > 0.0:
		b._pl(done, HudStyle.PORT, 7.0 * k)
	var tip: Vector2 = done[done.size() - 1]
	var prev: Vector2 = done[maxi(done.size() - 2, 0)] if done.size() > 1 else ring[1]
	var u := (tip - prev).normalized() if tip.distance_to(prev) > 0.1 else Vector2.RIGHT
	var s := Vector2(-u.y, u.x)
	b._p(PackedVector2Array([tip + u * 22.0 * k, tip + s * 13.0 * k, tip - s * 13.0 * k]), HudStyle.PORT)
	var lab: Vector2 = ring[n / 2]
	b._s(lab + Vector2(0, 30.0 * k), "TURN %d°" % int(HudFormat.round_half_away(r.turn_deg)), int(roundf(LAB * k)),
		HudStyle.PAPER, 600, TRACK, HORIZONTAL_ALIGNMENT_CENTER)
