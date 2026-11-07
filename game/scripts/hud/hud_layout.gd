class_name HudLayout
extends RefCounted
## The HUD's layout (hud_direction.md §5; hud.md §16.5 portrait): where every block of a Hud sits and how big it is
## for the screen now, in landscape and in portrait; the alert lane, the helm strip, the mark tag kept clear of the
## other blocks, the tables. Static functions on the Hud `hud`, called from Hud._layout.

## hud.md §8.1: the band the alert lane keeps on top of the course map in portrait (design px)
const MAP_LANE_BAND := 440.0
## the alert lane's scale over the rest in portrait, at most (hud.md §16.5)
const PORTRAIT_LANE_MAX := 1.15


## hud.md §8.1: the map over the whole screen; while it shows only the alert lane stays over it, the other blocks
## and the world tags are hidden.
static func map(hud: Hud) -> void:
	hud.map_view.visible = hud.map_open
	hud.map_view.position = Vector2.ZERO
	hud.map_view.size = hud._screen_size()
	hud.map_view.k = hud._k
	hud.map_view.lane_rect = Rect2()
	hud.map_view.lane_top = 0.0
	if hud.map_open:
		# the alert lane clear of the course, at the HUD's scale: a column on the left under the map's header
		# (landscape), or a band under the header (portrait)
		var sc := hud.map_view.size
		var m := HudStyle.margins(sc)
		var top := m.y + (CourseMapView.HEADER + 8.0) * hud._k
		place_lane(hud, hud._k)
		if HudStyle.portrait(sc):
			hud.race_panel.position = Vector2(sc.x * 0.5 - HudPaint.LANE_W * hud._k * 0.5, top)
			hud.map_view.lane_top = MAP_LANE_BAND * hud._k
		else:
			# the lane's drawn area left under the header; the frame moves right of it only when needed
			hud.race_panel.position = Vector2(m.x, top)
			var lr := Rect2()
			for blk in [hud.start_block, hud.penalty_panel, hud.alerts_block]:
				var c := blk as HudCanvas
				if not c.visible:
					continue
				var e := c.extent()
				if e.size == Vector2.ZERO:
					continue
				var r := Rect2(e.position + c.position + hud.race_panel.position, e.size)
				lr = r if not lr.has_area() else lr.merge(r)
			hud.map_view.lane_rect = lr
	var on := not hud.map_open
	if on:
		hud.world.visible = hud.world_tags
	for b in [hud.inst_page, hud.helm_block, hud.helm_notes]:
		(b as CanvasItem).visible = on
	if hud.map_open:
		for b in [hud.world, hud.toast_block, hud.bug_block, hud.feed_block, hud.next_panel, hud.card_block,
				hud.radar, hud.ranking_panel, hud.mark_arrow_block]:
			(b as CanvasItem).visible = false


static func blocks(hud: Hud) -> void:
	var sc := hud._screen_size()
	var k := HudStyle.ui_k(sc)
	var m := HudStyle.margins(sc)
	hud._k = k
	if hud.density_auto:
		hud.density = Hud.default_density(sc)
	for b in hud._all_canvases():
		b.k = k
	var its := hud.items()
	hud.world.position = Vector2.ZERO
	hud.world.size = sc
	hud.edge_box = Rect2()
	if HudStyle.portrait(sc):
		portrait(hud, sc, k, m, its)
		return
	# instrument page, bottom left
	var ps := HudPaint.page_size(hud) * k
	hud.inst_page.position = Vector2(m.x, sc.y - m.y - ps.y)
	hud.inst_page.size = ps
	hud.toast_block.visible = hud._toast_t > 0.0
	hud.toast_block.position = hud.inst_page.position - Vector2(0, 40.0 * k)
	hud.toast_block.size = Vector2(300, 32) * k
	hud.toast_block.modulate.a = clampf(hud._toast_t / 0.24, 0.0, 1.0)
	# race bug, top left
	hud.bug_block.visible = hud.race.active and its.has("bug")
	hud.bug_block.position = m
	hud.bug_block.size = Vector2(520, 200) * k
	# the feed, top right (the only block there: the wind is on the instrument page, hud.md §16.3)
	hud.feed_block.visible = hud.race.active and (its.has("feed") or its.has("feed_own"))
	hud.feed_block.size = Vector2(620, 170) * k
	hud.feed_block.position = Vector2(sc.x - m.x - hud.feed_block.size.x, m.y)
	# radar, bottom right
	hud.radar.visible = hud.race.active
	hud.radar.compact = hud.density == Hud.Density.GLANCE
	var d := 300.0 * k * (0.72 if hud.radar.compact else 1.0)
	hud.radar.size = Vector2(d, d + (0.0 if hud.radar.compact else 30.0 * k))
	hud.radar.position = Vector2(sc.x - m.x - d, sc.y - m.y - hud.radar.size.y)
	# helm strip between the page and the radar
	var left := hud.inst_page.position.x + ps.x + 24.0 * k
	var right := (hud.radar.position.x if hud.radar.visible else sc.x - m.x) - 24.0 * k
	var hw := minf(HudPaint.HELM.x * k, maxf(right - left, 160.0 * k))
	place_helm(hud, Vector2((left + right) * 0.5 - hw * 0.5, sc.y - m.y - HudPaint.HELM.y * k), hw, k)
	# top centre lane: start block, penalty panel, alerts
	hud.race_panel.position = Vector2(sc.x * 0.5 - HudPaint.LANE_W * k * 0.5, m.y)
	place_lane(hud, k)
	# the next mark tag: on the mark, or docked under the race bug without a camera
	hud.next_panel.size = Vector2(330, 120) * k
	hud.next_panel.visible = hud.race.active and hud.race.next_step > 0 and not hud.race.finished \
		and hud.text_of("next") != ""
	hud.world.visible = hud.world_tags
	if not hud.world_tags and hud.world_camera() != null:
		hud.next_panel.visible = false
	if hud.next_panel.visible and hud.world_camera() != null:
		var mp: Variant = hud.mark_screen()
		if mp == null:
			hud.next_panel.visible = false
		else:
			var p: Vector2 = mp
			hud.next_panel.position = Vector2(clampf(p.x - 30.0 * k, m.x, sc.x - m.x - hud.next_panel.size.x),
				clampf(p.y - 150.0 * k, m.y, sc.y - m.y - hud.next_panel.size.y))
	else:
		hud.next_panel.position = Vector2(m.x, m.y + 230.0 * k)
	hud.arrow_view.position = Vector2.ZERO
	hud.arrow_view.size = Vector2(26, 22) * k
	# the next-mark arrow (hud.md §7.1): centred over the helm notes
	hud.mark_arrow_block.visible = hud.mark_arrow_shown()
	hud.mark_arrow_block.size = HudPaint.MARK_ARROW * k
	hud.mark_arrow_block.position = Vector2(
		hud.helm_block.position.x + hud.helm_block.size.x * 0.5 - hud.mark_arrow_block.size.x * 0.5,
		hud.helm_notes.position.y - 8.0 * k - hud.mark_arrow_block.size.y)
	# the selected boat's card (hud.md §16.7): left, 48 px over the page, never above 16 px under the race bug
	if card_shown(hud):
		var ch := HudPaint.card_height(hud) * k
		var y_min := m.y
		if hud.bug_block.visible:
			y_min = hud.bug_block.position.y + hud.bug_block.extent().end.y + 16.0 * k
		var x := m.x
		if hud.next_panel.visible and hud.world_camera() == null:
			x = hud.next_panel.position.x + hud.next_panel.size.x + 16.0 * k  # beside the docked mark tag (no camera)
		hud.card_block.position = Vector2(x, maxf(y_min, hud.inst_page.position.y - 48.0 * k - ch))
		hud.card_block.size = Vector2(HudPaint.CARD_W * k, ch)
	place_mark_tag(hud, sc, k, m)
	# tables, centred
	var rs := HudPaint.table_size(Hud.RANK_W, hud.race.ranking_rows().size() if hud.ranking_panel.visible else 0) * k
	hud.ranking_panel.size = rs
	hud.ranking_panel.position = (sc - rs) * 0.5
	var qs := HudPaint.table_size(Hud.RESULT_W, hud.race.result_rows.size()) * k
	hud.results_panel.size = qs
	hud.results_panel.position = (sc - qs) * 0.5


## hud.md §16.4: the mark tag on the mark keeps clear of the HUD's blocks: above-right of it, else under it, else
## left of it; hidden when none is clear (the mark's diamond stays)
static func place_mark_tag(hud: Hud, sc: Vector2, k: float, m: Vector2) -> void:
	if not hud.next_panel.visible or hud.world_camera() == null or HudStyle.portrait(sc):
		return
	var mp: Variant = hud.mark_screen()
	if mp == null:
		return
	var p: Vector2 = mp
	var sz := hud.next_panel.size
	var rects := hud.keep_clear_rects()
	for at in [Vector2(p.x - 30.0 * k, p.y - 150.0 * k), Vector2(p.x - 30.0 * k, p.y + 24.0 * k),
			Vector2(p.x - sz.x - 24.0 * k, p.y - 150.0 * k)]:
		var pos := Vector2(clampf(at.x, m.x, sc.x - m.x - sz.x), clampf(at.y, m.y, sc.y - m.y - sz.y))
		var e := hud.next_panel.extent()
		var r := Rect2(pos + e.position, e.size) if e.size != Vector2.ZERO else Rect2(pos, sz)
		if hud.label_clear(r, rects):
			hud.next_panel.position = pos
			return
	hud.next_panel.visible = false


## hud.md §16.7: the card shows while a boat is selected, not with the results
static func card_shown(hud: Hud) -> bool:
	hud.card_block.visible = not hud.card.is_empty() and not hud.race.race_over and not hud.results_panel.visible \
		and not (hud.race.active and hud.race.results_visible and hud.race.results_final)
	return hud.card_block.visible


## The helm strip at `pos`, `hw` wide: its bars and trim gauges inside it, the notes over it.
static func place_helm(hud: Hud, pos: Vector2, hw: float, k: float) -> void:
	hud.helm_block.size = Vector2(hw, HudPaint.HELM.y * k)
	hud.helm_block.position = pos
	hud.rudder_bar.position = Vector2(0, 116.0 * k)
	hud.rudder_bar.size = Vector2(hw, 12.0 * k)
	hud.sheet_bar.position = Vector2(hw * 0.3, 72.0 * k)
	hud.sheet_bar.size = Vector2(hw * 0.4, 10.0 * k)
	var gw := (hw - 20.0 * k) * 0.5
	for i in hud.gauge_views.size():
		hud.gauge_views[i].position = Vector2(i * (gw + 20.0 * k), 0)
		hud.gauge_views[i].size = Vector2(gw, 56.0 * k)
	hud.helm_notes.size = Vector2(hw + 240.0 * k, 56.0 * k)
	hud.helm_notes.position = hud.helm_block.position + Vector2(-120.0 * k, -60.0 * k)


## The alert lane's blocks inside `race_panel` (placed by the caller) at the lane's scale `k`: the start block with
## its flags, the penalty panel with its ring, the alert lines; returns the lane's height (px).
static func place_lane(hud: Hud, k: float) -> float:
	hud.race_panel.size = Vector2(HudPaint.LANE_W, 600) * k
	for b in [hud.start_block, hud.flags_view, hud.penalty_panel, hud.turn_view, hud.alerts_block]:
		(b as HudCanvas).k = k
	var y := 0.0
	var sh := HudPaint.start_height(hud)
	hud.start_block.visible = sh > 0.0
	hud.start_block.position = Vector2.ZERO
	hud.start_block.size = Vector2(HudPaint.LANE_W, maxf(sh, 1.0)) * k
	var cw := 240.0
	if hud.countdown_shown():
		var ct := hud.text_of("clock")
		cw = HudCanvas.text_width(ct.substr(ct.rfind(" ") + 1), int(roundf(128.0 * k))) / k
	hud.flags_view.position = Vector2(HudPaint.LANE_W * 0.5 + cw * 0.5 + 28.0, 44.0) * k
	hud.flags_view.size = Vector2(hud.flags_view.width() + 2.0, 50.0 * k)
	y += sh + (8.0 if sh > 0.0 else 0.0)
	if hud.penalty_panel.visible:
		var ph := HudPaint.pen_height(hud)
		hud.penalty_panel.position = Vector2((HudPaint.LANE_W - HudPaint.PEN.x) * 0.5, y) * k
		hud.penalty_panel.size = Vector2(HudPaint.PEN.x, ph) * k
		hud.turn_view.position = Vector2(10, 0) * k
		hud.turn_view.size = Vector2(HudPaint.PEN_X - 10.0, HudPaint.PEN.y) * k
		y += ph + 12.0
	var ah := HudPaint.alerts_height(hud)
	hud.alerts_block.visible = ah > 0.0
	hud.alerts_block.position = Vector2(0, y) * k
	hud.alerts_block.size = Vector2(HudPaint.LANE_W, maxf(ah, 1.0)) * k
	return (y + ah) * k


## Portrait: the race bug on top, the alert lane large under it, the instruments compact at the bottom (page left,
## compact radar right, helm strip, notes, chip and feed over them), tables fitted to the width.
static func portrait(hud: Hud, sc: Vector2, k: float, m: Vector2, its: Array[String]) -> void:
	var mb := HudStyle.bottom_margin(sc)
	var inner := sc.x - 2.0 * m.x
	# top row: the race bug, left
	hud.bug_block.visible = hud.race.active and its.has("bug")
	hud.bug_block.position = m
	hud.bug_block.size = Vector2(520, 200) * k
	var top := 0.0
	if hud.bug_block.visible:
		top = maxf(top, hud.bug_block.extent().end.y)
	# the alert lane under them, as large as fits
	var kl := minf(k * PORTRAIT_LANE_MAX, inner / HudPaint.LANE_W)
	hud.race_panel.position = Vector2(sc.x * 0.5 - HudPaint.LANE_W * kl * 0.5,
		m.y + top + (16.0 * k if top > 0.0 else 0.0))
	var lane_h := place_lane(hud, kl)
	# bottom row: instrument page left, compact radar right
	var ps := HudPaint.page_size(hud) * k
	hud.radar.visible = hud.race.active
	hud.radar.compact = true
	var d := 300.0 * k * 0.72
	hud.radar.size = Vector2(d, d)
	hud.radar.position = Vector2(sc.x - m.x - d, sc.y - mb - d)
	hud.inst_page.position = Vector2(m.x, sc.y - mb - ps.y)
	hud.inst_page.size = ps
	var row_top := minf(hud.inst_page.position.y, hud.radar.position.y if hud.radar.visible else INF)
	# helm strip centred over the row, notes over it, the density chip over the page
	var hw := minf(HudPaint.HELM.x * k, inner)
	place_helm(hud, Vector2(sc.x * 0.5 - hw * 0.5, row_top - 12.0 * k - HudPaint.HELM.y * k), hw, k)
	hud.toast_block.visible = hud._toast_t > 0.0
	hud.toast_block.position = hud.inst_page.position - Vector2(0, 40.0 * k)
	hud.toast_block.size = Vector2(300, 32) * k
	hud.toast_block.modulate.a = clampf(hud._toast_t / 0.24, 0.0, 1.0)
	# the feed right-aligned over the helm notes, its last line nearest them
	hud.feed_block.visible = hud.race.active and (its.has("feed") or its.has("feed_own"))
	var lines := hud.feed_lines().size() if hud.feed_block.visible else 0
	hud.feed_block.size = Vector2(minf(620.0 * k, inner), (lines * 26.0 + 2.0) * k)
	hud.feed_block.position = Vector2(sc.x - m.x - hud.feed_block.size.x,
		hud.helm_notes.position.y - 8.0 * k - hud.feed_block.size.y)
	# the next mark tag: on the mark, or docked under the alert lane without a camera
	hud.next_panel.size = Vector2(330, 120) * k
	hud.next_panel.visible = hud.race.active and hud.race.next_step > 0 and not hud.race.finished \
		and hud.text_of("next") != ""
	if hud.next_panel.visible and hud.world_camera() != null:
		var mp: Variant = hud.mark_screen()
		if mp == null:
			hud.next_panel.visible = false
		else:
			var p: Vector2 = mp
			# kept under the alert lane, so it never covers the rule text
			var y_min := hud.race_panel.position.y + lane_h + 12.0 * k if lane_h > 0.0 else m.y + top
			if hud.mark_arrow_shown():  # and under the next-mark arrow (hud.md §7.1)
				y_min = hud.race_panel.position.y + lane_h + (24.0 + HudPaint.MARK_ARROW.y + 12.0) * k
			hud.next_panel.position = Vector2(clampf(p.x - 30.0 * k, m.x, sc.x - m.x - hud.next_panel.size.x),
				clampf(p.y - 150.0 * k, y_min, maxf(y_min, sc.y - mb - hud.next_panel.size.y)))
	else:
		hud.next_panel.position = Vector2(m.x, hud.race_panel.position.y + lane_h + 12.0 * k)
	hud.arrow_view.position = Vector2.ZERO
	hud.arrow_view.size = Vector2(26, 22) * k
	# the selected boat's card (hud.md §16.7): left, over the helm notes, beside the feed
	var card_top := INF
	if card_shown(hud):
		var ch := HudPaint.card_height(hud) * k
		hud.card_block.size = Vector2(HudPaint.CARD_W * k, ch)
		hud.card_block.position = Vector2(m.x, hud.helm_notes.position.y - 8.0 * k - ch)
		card_top = hud.card_block.position.y
	# edge pointers between the alert lane and the feed, helm notes and card
	var e_top := hud.race_panel.position.y + lane_h + 24.0 * k
	var e_bottom := minf(minf(hud.helm_notes.position.y, hud.feed_block.position.y if lines > 0 else INF), card_top) \
		- 56.0 * k
	# the next-mark arrow (hud.md §7.1) centred at the top of that box, the edge pointers under it
	hud.mark_arrow_block.visible = hud.mark_arrow_shown()
	hud.mark_arrow_block.size = HudPaint.MARK_ARROW * k
	hud.mark_arrow_block.position = Vector2(sc.x * 0.5 - hud.mark_arrow_block.size.x * 0.5, e_top)
	if hud.mark_arrow_block.visible:
		e_top += hud.mark_arrow_block.size.y + 12.0 * k
	hud.edge_box = Rect2(70.0 * k, e_top, sc.x - 140.0 * k, maxf(e_bottom - e_top, 1.0))
	# tables centred, scaled down to the width
	place_table(hud, hud.ranking_panel, Hud.RANK_W, hud.race.ranking_rows().size() if hud.ranking_panel.visible else 0,
		k, inner, sc)
	place_table(hud, hud.results_panel, Hud.RESULT_W, hud.race.result_rows.size(), k, inner, sc)


static func place_table(_hud: Hud, b: HudCanvas, widths: Array, rows: int, k: float, inner: float, sc: Vector2) -> void:
	var ds := HudPaint.table_size(widths, rows)
	b.k = minf(k, inner / ds.x)
	b.size = ds * b.k
	b.position = (sc - b.size) * 0.5
