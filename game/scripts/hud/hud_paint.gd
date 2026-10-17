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

const PAGE := {Hud.Density.GLANCE: Vector2(486, 150), Hud.Density.RACE: Vector2(486, 246),
	Hud.Density.DATA: Vector2(720, 298)}


## The instrument page size of the level (design px).
static func page_size(h: Hud) -> Vector2:
	return PAGE[h.density]


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


static func _twa_value(b: HudCanvas, h: Hud, x_right: float, y: float, size: float) -> void:
	var t := side_split(h.value_of("twa"))
	number(b, x_right, y, t[0], size, HudStyle.PAPER, t[1])


static func _page_glance(b: HudCanvas, h: Hud, sz: Vector2) -> void:
	_bsp(b, h)
	divider(b, Vector2(250, 10), Vector2(250, 140))
	caption(b, 264, 24, "TWA")
	dial(b, h, Vector2(328, 88), 52.0, false)
	_twa_value(b, h, 472, 134, 44)


## Race: boat speed over heading, the TWA dial beside them; Data adds VMG (VMC on a reach) over SOG between them and
## a row of COG, AWS and the heel bar. No target speed (hud.md §4, §16.3).
static func _page_race(b: HudCanvas, h: Hud, data: bool) -> void:
	var w: float = PAGE[h.density].x
	_bsp(b, h)
	divider(b, Vector2(250, 10), Vector2(250, 236))
	var tx := 264.0
	if data:
		var reach := h.race.active and h.race.leg_type == "reach"
		caption(b, 264, 24, "VMC" if reach else "VMG", 446, "KN")
		number(b, 446, 112, h.value_of("vmg_kn"), 64)
		caption(b, 264, 174, "SOG", 446, "KN")
		number(b, 446, 230, h.value_of("sog"), 44)
		divider(b, Vector2(460, 10), Vector2(460, 236))
		divider(b, Vector2(264, 150), Vector2(450, 150))
		tx = 474.0
	caption(b, tx, 24, "TWA")
	var dc := Vector2(tx + (w - tx) * 0.5 - 6.0, 104)
	dial(b, h, dc, 62.0, data)
	_twa_value(b, h, w - 14, 232, 44)
	divider(b, Vector2(10, 150), Vector2(240, 150))
	caption(b, 14, 174, "HEADING")
	number(b, 236, 230, h.value_of("hdg"), 52)
	if not data:
		return
	caption(b, 474, 214, "AWA", -1, "", LAB_S)
	var aw := side_split(h.value_of("awa"))
	b._s(Vector2(474, 234) * b.k, aw[0] + aw[1], int(roundf(18 * b.k)), HudStyle.MIST, 600)
	divider(b, Vector2(10, 246), Vector2(w - 10, 246))
	# row 3: small cells, the label over the value (room for the 11 px floor of small screens)
	var cells := [["COG", "cog", 120.0], ["AWS", "aws", 270.0]]
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


## TWA dial (hud.md §16.3): bow up, close-hauled sectors, the VMG angle notches (the reference pair strong), the
## true wind pointer from the rim coloured by the angle error and (with `apparent`) the apparent wind as a hollow
## pointer; a hull outline in the centre. Every frame.
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
	var ref := h.dial_reference()
	for opt in [h.values.vmg_up_twa, h.values.vmg_dn_twa]:
		if is_nan(opt):
			continue
		var strong: bool = is_nan(ref) or is_equal_approx(opt, ref)
		var col := Color(HudStyle.MARK, 1.0 if strong else 0.45)
		for sgn in [1.0, -1.0]:
			var a: float = sgn * opt
			var u: Vector2 = dir.call(a)
			var sd := Vector2(-u.y, u.x)
			var tip := c + u * (r - 11.0 * k)
			b._p(PackedVector2Array([tip, c + u * r + sd * 6.0 * k, c + u * r - sd * 6.0 * k]), col)
			b._l(tip, c + u * (r - 18.0 * k), col, 2.0 * k)
	# hull
	var hl := r * 0.42
	var hb := r * 0.14
	b._pl(PackedVector2Array([c + Vector2(0, -hl), c + Vector2(hb, -hl * 0.2), c + Vector2(hb * 0.8, hl),
		c + Vector2(-hb * 0.8, hl), c + Vector2(-hb, -hl * 0.2), c + Vector2(0, -hl)]), HudStyle.PAPER, hw)
	_pointer(b, c, r, h.values.twa, true, h.pointer_colour())
	if apparent:
		_pointer(b, c, r, h.values.awa, false)


static func _pointer(b: HudCanvas, c: Vector2, r: float, a: float, solid: bool, col := HudStyle.PAPER) -> void:
	var k := b.k
	var d := Vector2(sin(a), -cos(a))
	var s := Vector2(-d.y, d.x)
	var tip := c + d * (r - 14.0 * k)
	var base := c + d * (r + 2.0 * k)
	var pts := PackedVector2Array([tip, base + s * 6.0 * k, base - s * 6.0 * k])
	if solid:  # an ink edge so the coloured pointer reads over the dial's sectors
		var edge := pts.duplicate()
		edge.append(pts[0])
		b._l(tip, c + d * r * 0.5, Color(HudStyle.INK, 0.6), 4.0 * k)
		b._pl(edge, Color(HudStyle.INK, 0.6), 3.0 * k)
		b._p(pts, col)
		b._l(tip, c + d * r * 0.5, col, 2.0 * k)
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

## hud.md §12.1: a compact chip; the ring on the left, three lines from PEN_X, the deadline on the right
const PEN := Vector2(540, 76)
const PEN_X := 124.0
## the deadline's column (design px): caption, number and bar, right-aligned at the panel's edge
const PEN_DEADLINE_W := 116.0


## the panel's height (design px): a line more for the disqualification warning
static func pen_height(h: Hud) -> float:
	return PEN.y + (20.0 if h.text_of("pen_dsq") != "" else 0.0)


static func penalty(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var r := h.race
	var hgt := pen_height(h)
	b._rect(Rect2(Vector2.ZERO, Vector2(PEN.x, hgt) * k), Color(HudStyle.INK, 0.86))
	b._rect(Rect2(Vector2.ZERO, Vector2(PEN.x, 3) * k), HudStyle.PORT)
	var x := PEN_X
	var dl := h.text_of("pen_deadline") != ""
	var w := PEN.x - 16.0 - x - (PEN_DEADLINE_W if dl else 0.0)
	var cap := "PENALTY"
	if r.pending > 1:
		cap += " 1 OF %d" % r.pending
	if r.pending > 0:
		cap += " · RULE %s" % RaceText.code(r.penalty_rule)
	b._s(Vector2(x, 22) * k, cap, int(roundf(LAB * k)), HudStyle.PORT, 700, 0.1)
	var main := RaceText.rule_text(r.penalty_rule) if r.pending > 0 else h.text_of("pen_head")
	var mf := _fit_cut(b, main, 20, w, 600)
	b._s(Vector2(x, 46) * k, mf[0], mf[1], HudStyle.PAPER, 600)
	var state: Array[String] = []
	if r.pending > 0 and r.penalty_other >= 0:
		state.append("WITH " + r.name_of(r.penalty_other).to_upper())
	if h.text_of("pen_turn") != "":
		state.append(h.text_of("pen_turn").to_upper())
	if not state.is_empty():
		var sf := _fit_cut(b, " · ".join(state), LAB, w, 600, 0.06)
		b._s(Vector2(x, 66) * k, sf[0], sf[1], HudStyle.MIST, 600, 0.06)
	if h.text_of("pen_dsq") != "":
		b._s(Vector2(x, 88) * k, h.text_of("pen_dsq").to_upper(), int(roundf(LAB * k)), HudStyle.PORT, 700, 0.06)
	if dl:
		b._s(Vector2(PEN.x - 16, 20) * k, "DEADLINE", int(roundf(TINY * k)), HudStyle.LABEL, 600, TRACK,
			HORIZONTAL_ALIGNMENT_RIGHT)
		b._s(Vector2(PEN.x - 16, 58) * k, h.value_of("pen_deadline"), int(roundf(40 * k)), h.colour_of("pen_deadline"),
			600, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
		# hud.md §12.1: a thin bar under the number shrinking towards 0:00
		var bar := deadline_bar(h)
		b._rect(Rect2(bar[0].position * k, bar[0].size * k), Color(HudStyle.HAIR, HudStyle.HAIR.a * 0.45))
		if bar[1].size.x > 0.0:
			b._rect(Rect2(bar[1].position * k, bar[1].size * k), h.colour_of("pen_deadline"))


const DEADLINE_BAR := Vector2(100, 3)
const DEADLINE_FULL := 120.0


## the deadline bar's track and fill (design px, in the panel): the fill over time left / 120 s from the left
static func deadline_bar(h: Hud) -> Array[Rect2]:
	var track := Rect2(Vector2(PEN.x - 16 - DEADLINE_BAR.x, 65), DEADLINE_BAR)
	var f := clampf(h.race.deadline / DEADLINE_FULL, 0.0, 1.0)
	return [track, Rect2(track.position, Vector2(track.size.x * f, track.size.y))]


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
		y += 56.0 if key == "banner" and h.race.banner != null and h.race.banner.full else 44.0
	return y


static func alerts(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var cx := LANE_W * 0.5
	var y := 0.0
	for key in alert_lines(h):
		var full: bool = key == "banner" and h.race.banner != null and h.race.banner.full
		var size := 28.0 if full else 20.0
		var t := h.text_of(key)
		if key == "rules":
			t = t.to_upper()
		var col := h.colour_of(key)
		var tw := HudCanvas.text_width(t, int(roundf(size * k)), 700, 0.04) / k + 40.0
		var hgt := size + 16.0
		var rr := Rect2(Vector2(cx - tw * 0.5, y), Vector2(tw, hgt))
		b._rect(Rect2(rr.position * k, rr.size * k), Color(HudStyle.INK, 0.86))
		b._rect(Rect2(rr.position * k, Vector2(6, hgt) * k), col)
		b._s(Vector2(cx + 3.0, y + hgt * 0.5 + size * 0.36) * k, t, int(roundf(size * k)), col, 700, 0.04,
			HORIZONTAL_ALIGNMENT_CENTER)
		y += 56.0 if full else 44.0


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


## the hoist cue (hud.md §5.1), the sail hint and the controls' messages, one line each over the helm strip
static func helm_notes(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var y := 16.0
	var hoist := h.text_of("hoist")
	if hoist != "":
		var fs := int(roundf(16 * k))
		var tw := HudCanvas.text_width(hoist, fs, 600, 0.1)
		var cx := b.size.x * 0.5
		b._s(Vector2(cx, y * k), hoist, fs, HudStyle.PAPER, 600, 0.1, HORIZONTAL_ALIGNMENT_CENTER)
		var bar := Rect2(Vector2(cx - tw * 0.5, (y + 6.0) * k), Vector2(tw, 3.0 * k))
		b._rect(bar, HudStyle.HAIR)
		b._rect(Rect2(bar.position, Vector2(tw * clampf(h.values.hoist_progress, 0.0, 1.0), bar.size.y)), HudStyle.MARK)
		y += 30.0
	for key in ["message", "hint"]:
		var t := h.text_of(key)
		if t != "" and (key != "hint" or (h.has_item("hint") and hoist == "")) and y < 56.0:
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


# ---- next-mark arrow (hud.md §7.1: onboard, aerial and free cameras) ----

const MARK_ARROW := Vector2(360, 64)


## A solid arrow head in `mark` pointing at the next mark in the camera's frame, the mark's name and distance on a
## small ink chip beside it; the group centred in the block.
static func mark_arrow(b: HudCanvas, h: Hud) -> void:
	if not h.mark_arrow_shown():
		return
	var k := b.k
	var name := h.text_of("next").to_upper()
	var nfs := int(roundf(LAB_S * k))
	var nw := HudCanvas.text_width(name, nfs, 700, TRACK) / k
	var val := h.value_of("mark_dist")
	var unit := h.unit_of("mark_dist")
	var dw := HudCanvas.text_width(val, int(roundf(24 * k))) / k + HudCanvas.text_width(unit, int(roundf(13 * k)), 600,
		0.06) / k + 4.0
	var tw := maxf(nw, dw)
	var cell := 44.0
	var pad := 10.0
	var x0 := (MARK_ARROW.x - (cell + 8.0 + tw + 2.0 * pad)) * 0.5
	var cy := MARK_ARROW.y * 0.5
	# the arrow head, notched at the back, with a thin ink edge so it reads over bright water
	var a := h.mark_arrow_angle()
	var c := Vector2(x0 + cell * 0.5, cy) * k
	var u := Vector2(sin(a), -cos(a))
	var s := Vector2(-u.y, u.x)
	var l := 15.0 * k
	var pts := PackedVector2Array([c + u * l, c - u * l + s * l * 0.75, c - u * l * 0.4, c - u * l - s * l * 0.75])
	var edge := pts.duplicate()
	edge.append(pts[0])
	b._pl(edge, Color(HudStyle.INK, 0.7), 3.0 * k)
	b._p(pts, HudStyle.MARK)
	# the chip: name over distance
	var tx := x0 + cell + 8.0
	b._rect(Rect2(Vector2(tx, cy - 26.0) * k, Vector2(tw + 2.0 * pad, 52.0) * k), Color(HudStyle.INK, 0.7))
	b._s(Vector2(tx + pad, cy - 8.0) * k, name, nfs, HudStyle.MARK, 700, TRACK)
	number_unit(b, tx + pad, cy + 18.0, val, unit, 24)


# ---- world: tags and marks on the scene (needs the camera) ----

static func world(b: HudCanvas, h: Hud) -> void:
	var k := b.k
	var hw := _hw(b)
	var r := h.race
	# the mark tag's leader and the mark point
	var mp: Variant = h.mark_screen()
	if mp != null and (h.next_panel.visible or h.world_camera() != null):
		var p: Vector2 = mp
		if h.next_panel.visible:
			var tag_foot := h.next_panel.position + Vector2(30.0, 96.0) * k
			if tag_foot.y < p.y:
				b._l(tag_foot, p, Color(HudStyle.MARK, 0.9), hw)
			else:  # the tag under the mark: the leader from its top
				b._l(h.next_panel.position + Vector2(30.0, 0.0) * k, p, Color(HudStyle.MARK, 0.9), hw)
		var d := 6.0 * k
		b._pl(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0),
			p + Vector2(0, -d)]), HudStyle.MARK, hw)
	elif r.active and r.next_step > 0 and h.world_camera() != null and h.text_of("next") != "" \
			and h.current_camera_kind() == "chase":  # elsewhere the next-mark arrow points at it (hud.md §7.1)
		var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
		edge_pointer(b, h, h.mark_world(), h.text_of("next").to_upper(), "%s · ETA %s" % [
			HudFormat.distance(r.next_dist), eta], HudStyle.MARK)
	var rects := h.keep_clear_rects()
	# the ladder lines of the viewed and the selected boat (hud.md §16.4.2), under the tags
	var lad := h.ladder_lines()
	if not lad.is_empty():
		for run in lad["own"]:
			b._pl(run, Color(HudStyle.MARK, 0.9), hw)
		for run in lad["her"]:
			b._pl(run, Color(HudStyle.PAPER, 0.75), hw)
		if lad["label"] != null:
			var lq: Vector2 = lad["label"]
			var fs := int(roundf(13 * k))
			var tw := HudCanvas.text_width(lad["text"], fs, 700, 0.1) + 14.0 * k
			var lr := Rect2(lq - Vector2(tw * 0.5, 11.0 * k), Vector2(tw, 22.0 * k))
			if h.label_clear(lr, rects):
				b._rect(lr, Color(HudStyle.INK, 0.7))
				b._s(Vector2(lq.x, lq.y + 5.0 * k), lad["text"], fs, HudStyle.PAPER, 700, 0.1, HORIZONTAL_ALIGNMENT_CENTER)
	# tack point: the ring and its label only, no line from the boat (hud.md §16.4); the label above the ring, else
	# under it, else none, clear of the HUD's blocks
	var tp: Variant = h.world_tack_point()
	if tp != null:
		var ts: Variant = h.project(Vector3(tp.x, tp.y, 0.0))
		if ts != null:
			var c: Vector2 = ts
			var col := HudStyle.PORT if h.values.twa > 0.0 else HudStyle.STBD
			b._a(c, 7.0 * k, 0.0, TAU, 24, col, 2.0 * k)
			var t := h.text_of("layline")
			if t.begins_with("Layline"):
				var du := HudStyle.split_unit(HudFormat.distance(r.layline_dist))
				var unit: String = du[1] + "  " + HudFormat.clock(r.layline_time)
				var w := maxf(HudCanvas.text_width(turn_in_label(r.leg_type), int(roundf(LAB * k)), 600, TRACK),
					HudCanvas.text_width(du[0], int(roundf(36 * k))) + HudCanvas.text_width(unit, int(roundf(16.2 * k)), 600,
					0.06) + 4.0 * k)
				for below in [false, true]:
					var top := c.y + (14.0 * k if below else -58.0 * k)
					if not h.label_clear(Rect2(c.x - w * 0.5, top, w, 50.0 * k), rects):
						continue
					b._s(Vector2(c.x, top + 14.0 * k), turn_in_label(r.leg_type), int(roundf(LAB * k)), HudStyle.PAPER, 600,
						TRACK, HORIZONTAL_ALIGNMENT_CENTER)
					number_unit(b, c.x / k, (top / k) + 44.0, du[0], unit, 36, HudStyle.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
					break
	# the selected boat's pointer over her masthead (hud.md §16.4.1); her tag stands on it
	var mk := h.selected_marker()
	if not mk.is_empty():
		var edge: PackedVector2Array = mk["pts"].duplicate()
		edge.append(edge[0])
		b._pl(edge, Color(HudStyle.INK, 0.7), 1.5 * k)
		b._p(mk["pts"], mk["col"])
	# name tags, clear of the HUD's blocks
	for tag in h.name_tags():
		var q: Vector2 = tag["p"]
		var name: String = tag["name"]
		var col: Color = tag["col"]
		var solid: bool = tag["solid"]
		var on_marker: bool = not mk.is_empty() and int(mk["boat"]) == int(tag["boat"])
		var foot := q + Vector2(0, -12.0 * k)
		if on_marker:
			foot = (mk["tip"] as Vector2) - Vector2(0, (Hud.MARKER_H + 4.0) * k)
		var fs := int(roundf(13 * k))
		var tw := HudCanvas.text_width(name, fs, 700, 0.1) + 16.0 * k
		if not h.label_clear(Rect2(foot + Vector2(-tw * 0.5, -22.0 * k), Vector2(tw, 22.0 * k)), rects):
			continue
		if not on_marker:
			b._l(foot, q, Color(col, col.a * 0.8), hw)
		name_chip(b, foot, name, col, solid, tag["outline"])
	for e in h.selected_off_screen():
		edge_pointer(b, h, e["w"], e["name"], HudFormat.distance(e["d"]), e["col"])


## A boat icon (hud.md §8): a triangle `l` px long at `q`, bow along `psi_screen` (0 = up, clockwise), with a paper
## outline when `outline` (Breach). The radar and the course map.
static func boat_icon(b: HudCanvas, q: Vector2, psi_screen: float, l: float, col: Color, outline: bool) -> void:
	var f := Vector2(sin(psi_screen), -cos(psi_screen))
	var s := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([q + f * 0.5 * l, q - f * 0.5 * l + s * 0.22 * l, q - f * 0.5 * l - s * 0.22 * l])
	b._p(pts, col)
	if outline:
		pts.append(pts[0])
		b._pl(pts, HudStyle.PAPER, 1.5 * b.k)


## A mark's rounding arrow (hud.md §8, §8.1): an arc of radius `r` px from the top of the mark at `q`, 0.6 pi
## anticlockwise on the screen to leave it to port, clockwise to starboard, with a dot at its head.
static func rounding_arc(b: HudCanvas, q: Vector2, r: float, port: bool, col: Color, w: float) -> void:
	var a0 := -PI * 0.5
	var sweep := -PI * 0.6 if port else PI * 0.6
	b._a(q, r, a0, a0 + sweep, 10, col, w)
	b._c(q + r * Vector2(cos(a0 + sweep), sin(a0 + sweep)), 2.5 * b.k, col)


## A name chip (hud.md §16.4) with its bottom centre at `bottom`: solid in `col` with ink text when `solid`, else
## `col` text on ink; a hairline frame in `col` when `outline` (Breach). World name tags and the course map.
static func name_chip(b: HudCanvas, bottom: Vector2, name: String, col: Color, solid: bool, outline: bool) -> void:
	var k := b.k
	var fs := int(roundf(13 * k))
	var tw := HudCanvas.text_width(name, fs, 700, 0.1) + 16.0 * k
	var rr := Rect2(bottom + Vector2(-tw * 0.5, -22.0 * k), Vector2(tw, 22.0 * k))
	b._rect(rr, Color(col, col.a) if solid else Color(HudStyle.INK, 0.8 * col.a))
	if outline:
		var o := rr.grow(3.0 * k)
		b._pl(PackedVector2Array([o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y),
			o.position]), col, _hw(b))
	var sv := b.text_shadow
	b.text_shadow = false
	b._s(Vector2(bottom.x, rr.position.y + 16.0 * k), name, fs, Color(HudStyle.INK, col.a) if solid else col, 700, 0.1,
		HORIZONTAL_ALIGNMENT_CENTER)
	b.text_shadow = sv


## four hairline corners round `r` (screen px), each a quarter of the side and at most 14 design px
static func bracket(b: HudCanvas, r: Rect2, col: Color, max_len := 14.0) -> void:
	var hw := _hw(b)
	var lx := minf(r.size.x * 0.25, max_len * b.k)
	var ly := minf(r.size.y * 0.25, max_len * b.k)
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	b._pl(PackedVector2Array([p0 + Vector2(0, ly), p0, p0 + Vector2(lx, 0)]), col, hw)
	b._pl(PackedVector2Array([p1 - Vector2(lx, 0), p1, p1 + Vector2(0, ly)]), col, hw)
	b._pl(PackedVector2Array([p2 - Vector2(0, ly), p2, p2 - Vector2(lx, 0)]), col, hw)
	b._pl(PackedVector2Array([p3 + Vector2(lx, 0), p3, p3 - Vector2(0, ly)]), col, hw)


# ---- selected boat card (hud.md §16.7) ----

const CARD_W := 340.0


## the font size (px, already scaled) at which `text` fits `max_w` design px, from `size` down to the 11 px floor
static func _fit(b: HudCanvas, text: String, size: float, max_w: float, weight := 600, tracking := 0.0) -> int:
	var sz := int(roundf(size * b.k))
	while sz > HudStyle.MIN_TEXT and HudCanvas.text_width(text, sz, weight, tracking) > max_w * b.k:
		sz -= 1
	return sz


## `text` at the size _fit gives, cut with an ellipsis when it is still too wide at the floor
static func _fit_cut(b: HudCanvas, text: String, size: float, max_w: float, weight := 600, tracking := 0.0) -> Array:
	var sz := _fit(b, text, size, max_w, weight, tracking)
	var t := text
	while t.length() > 1 and HudCanvas.text_width(t, sz, weight, tracking) > max_w * b.k:
		t = t.substr(0, t.length() - 2).strip_edges() + "…"
	return [t, sz]


## the card's rows' baselines (design px) and its height, from what the card has: the header (caption and name) over
## a divider, then her standing, the rules line and the penalty line, each only with a value
static func card_rows(h: Hud) -> Dictionary:
	var c := h.card
	var y := 70.0
	var out := {}
	if c.get("course", "") != "":
		y += 26.0
		out["course"] = y
	if c.get("rules", "") != "":
		y += 28.0
		out["rules"] = y
	if c.get("penalty", "") != "":
		y += 26.0
		out["penalty"] = y
	out["height"] = y + 14.0 if y > 70.0 else 70.0
	return out


static func card_height(h: Hud) -> float:
	return card_rows(h)["height"] if not h.card.is_empty() else 0.0


static func boat_card(b: HudCanvas, h: Hud) -> void:
	var c := h.card
	if c.is_empty():
		return
	var k := b.k
	var rows := card_rows(h)
	var hgt: float = rows["height"]
	var col: Color = c.get("col", HudStyle.PAPER)
	var bar := HudStyle.HAIR if col.is_equal_approx(HudStyle.PAPER) else col
	b._rect(Rect2(Vector2.ZERO, Vector2(CARD_W, hgt) * k), Color(HudStyle.INK, 0.86))
	b._l(Vector2.ZERO, Vector2(CARD_W, 0) * k, HudStyle.HAIR, _hw(b))
	b._rect(Rect2(Vector2.ZERO, Vector2(4, hgt) * k), bar)
	var x := 20.0
	var xr := CARD_W - 16.0
	# header: sail number and skipper, the name; the place on the right
	var place: String = c.get("place", "")
	var head: String = c.get("head", "")
	var right_w := 0.0
	var cap_w := 0.0
	if place != "":
		var csz := int(roundf(LAB * k))
		b._s(Vector2(xr, 22) * k, "PLACE", csz, HudStyle.LABEL, 600, TRACK, HORIZONTAL_ALIGNMENT_RIGHT)
		cap_w = HudCanvas.text_width("PLACE", csz, 600, TRACK) / k + 12.0
		right_w = number_unit(b, xr, 54, place, "/ %d" % int(c.get("fleet", 0)), 26, HudStyle.PAPER,
			HORIZONTAL_ALIGNMENT_RIGHT)
	if head != "":
		var hf := _fit_cut(b, head, LAB, xr - x - cap_w, 600, TRACK)
		b._s(Vector2(x, 22) * k, hf[0], hf[1], HudStyle.LABEL, 600, TRACK)
	var name: String = c.get("name", "")
	var nf := _fit_cut(b, name, 26, xr - x - right_w - 16.0, 700, 0.04)
	b._s(Vector2(x, 54) * k, nf[0], nf[1], HudStyle.PAPER, 700, 0.04)
	if hgt > 70.0:
		divider(b, Vector2(x, 70), Vector2(xr, 70))
	if rows.has("course"):
		var cf := _fit_cut(b, c["course"], 16, xr - x, 600)
		b._s(Vector2(x, rows["course"]) * k, cf[0], cf[1], HudStyle.PAPER, 600)
	if rows.has("rules"):
		var t: String = c["rules"]
		b._s(Vector2(x, rows["rules"]) * k, t, _fit(b, t, 15, xr - x, 700, 0.06), c.get("rules_col", HudStyle.PAPER),
			700, 0.06)
	if rows.has("penalty"):
		var t: String = c["penalty"]
		b._s(Vector2(x, rows["penalty"]) * k, t, _fit(b, t, 15, xr - x, 700, 0.06), HudStyle.PORT, 700, 0.06)


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
