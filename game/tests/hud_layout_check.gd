class_name HudLayoutCheck
extends RefCounted
## Layout checks of the HUD as laid out now (hud.md §15, §16.5), for the tests and the offline previews: the screen
## area each block draws (HudCanvas.extent), and the overlaps between blocks. A block's children (the flags in the
## start block, the ring in the penalty panel, the bars and gauges in the helm strip) belong to it. World tags (the
## world layer, the mark tag) and the centred tables (ranking, results), which sit over everything by design, are
## left out.


## The HudCanvas's offset on the screen (its position plus its Control parents' up to the Hud).
static func offset(h: Hud, b: HudCanvas) -> Vector2:
	var o := b.position
	var n: Node = b.get_parent()
	while n != null and n != h:
		if n is Control:
			o += (n as Control).position
		n = n.get_parent()
	return o


## The block a HudCanvas belongs to: itself under the Hud or the alert lane, else its ancestor there.
static func group(h: Hud, b: Node) -> Node:
	var n := b
	while n.get_parent() != null and n.get_parent() != h and n.get_parent() != h.race_panel:
		n = n.get_parent()
	return n


## block name -> its drawn screen rect (merged with its children's), for the visible blocks that draw something.
static func areas(h: Hud) -> Dictionary:
	var skip: Array[Node] = [h.world, h.next_panel, h.ranking_panel, h.results_panel]
	var out := {}
	for b in h.blocks():
		var g := group(h, b)
		if skip.has(g):
			continue
		var e := b.extent()
		if e.size == Vector2.ZERO:
			continue
		var r := Rect2(e.position + offset(h, b), e.size)
		var key := String(g.name)
		out[key] = (out[key] as Rect2).merge(r) if out.has(key) else r
	return out


## Every problem: two blocks whose drawn areas overlap (by more than `tolerance` px), or a block off the screen;
## in portrait (hud.md §16.5) also a world tag's text (mark tag, edge pointers, name tags) over the alert lane.
static func problems(h: Hud, screen: Vector2, tolerance := 1.0) -> Array[String]:
	var out: Array[String] = []
	var a := areas(h)
	if HudStyle.portrait(screen):
		for b in [h.world, h.next_panel]:
			if not (b as HudCanvas).visible:
				continue
			var o := offset(h, b)
			for q in (b as HudCanvas).primitives():
				if q["k"] != "text" or q["text"] == "":
					continue
				var r := HudCanvas.prim_rect(q)
				r.position += o
				for lane in ["Start", "Penalty", "Alerts"]:
					if a.has(lane) and r.grow(-tolerance).intersects((a[lane] as Rect2).grow(-tolerance)):
						out.append("world text '%s' over the alert lane (%s)" % [q["text"], lane])
	var names := a.keys()
	var scr := Rect2(Vector2.ZERO, screen).grow(tolerance)
	for i in names.size():
		var ri: Rect2 = a[names[i]]
		if not scr.encloses(ri):
			out.append("%s off screen %s" % [names[i], ri])
		for j in range(i + 1, names.size()):
			var rj: Rect2 = a[names[j]]
			if ri.grow(-tolerance).intersects(rj.grow(-tolerance)):
				out.append("%s %s overlaps %s %s" % [names[i], ri, names[j], rj])
	return out
