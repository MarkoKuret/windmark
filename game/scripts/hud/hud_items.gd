class_name HudItems
extends RefCounted
## The density table of the HUD (hud.md §16.1, §14): the items a Hud shows at its density and assist in each race
## phase, listed by Hud.items.


static func of(hud: Hud, ph: String) -> Array[String]:
	var out: Array[String] = ["bsp", "twa_dial", "twa", "radar", "helm"]
	var lvl := hud.density
	# the cluster (hud.md §16.3): Race adds heading, the true wind speed and the heel bar; Data the rest
	if lvl >= Hud.Density.RACE:
		out.append_array(["hdg", "tws", "heel_bar"])
	if lvl == Hud.Density.DATA:
		out.append_array(["vmg_kn", "awa", "sog", "cog", "twd", "aws"])
	match ph:
		"pre":
			out.append("start_min" if lvl == Hud.Density.GLANCE else "start_full")
			if lvl == Hud.Density.RACE:
				out.append("feed_own")
			if lvl == Hud.Density.DATA:
				out.append_array(["bug", "bug_lap", "feed"])
		"free":
			pass
		_:
			out.append("bug")
			if lvl == Hud.Density.GLANCE:
				out.append("feed_own")
			elif lvl == Hud.Density.RACE:
				out.append_array(["shift", "bug_gap", "bug_ahead", "mark_eta", "feed_own"])
			else:
				out.append_array(["shift", "bug_gap", "bug_ahead", "mark_eta", "bug_lap", "bug_gaps", "mark_brg", "hint",
					"feed"])
	if not hud.shows("shift"):
		out.erase("shift")
	if not hud.shows("sail_hint"):
		out.erase("hint")
	return out
