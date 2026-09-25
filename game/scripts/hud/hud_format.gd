class_name HudFormat
extends RefCounted
## hud.md §1 formats. Rounding is to nearest, half away from zero, after smoothing.

const KNOT := 0.514444  # m/s per knot


static func round_half_away(x: float) -> float:
	return signf(x) * floorf(absf(x) + 0.5)


## knots, 1 decimal ("7.4"); below 0.05 shows "0.0"
static func speed_kn(ms: float) -> String:
	var kn := ms / KNOT
	if absf(kn) < 0.05:
		return "0.0"
	return "%.1f" % (round_half_away(kn * 10.0) / 10.0)


## compass 000-359
static func compass_deg(rad: float) -> String:
	var d := int(round_half_away(rad_to_deg(Frames.wrap_2pi(rad)))) % 360
	return "%03d" % d


## integer degrees of |a| with a side letter: `pos_letter` for a > 0, `neg_letter` otherwise ("42° S")
static func side_angle(rad: float, pos_letter: String, neg_letter: String) -> String:
	var d := int(round_half_away(rad_to_deg(absf(rad))))
	return "%d° %s" % [d, pos_letter if rad > 0.0 else neg_letter]


static func percent(x: float) -> String:
	return "%d" % int(round_half_away(x))


const NM := 1852.0


## distance: < 200 m integer metres ("85 m"), to 0.2 nm metres rounded to 5 m, beyond nautical miles ("0.43 nm")
static func distance(m: float) -> String:
	if m < 200.0:
		return "%d m" % int(round_half_away(m))
	if m < 0.2 * NM:
		return "%d m" % int(round_half_away(m / 5.0) * 5.0)
	return "%.2f nm" % (round_half_away(m / NM * 100.0) / 100.0)


## race clock and gaps m:ss
static func clock(s: float) -> String:
	var t := int(round_half_away(absf(s)))
	return "%s%d:%02d" % ["-" if s < 0.0 and t > 0 else "", floori(t / 60.0), t % 60]


## countdown m:ss, with tenths in the last 10 s ("0:07.4"); `s` = seconds to go
static func countdown(s: float) -> String:
	if s < 10.0:
		var tenths := int(round_half_away(maxf(s, 0.0) * 10.0))
		return "0:%02d.%d" % [floori(tenths / 10.0), tenths % 10]
	var t := int(round_half_away(s))
	return "%d:%02d" % [floori(t / 60.0), t % 60]


## finish times h:mm:ss.ss ("0:42:17.35"), from seconds
static func finish_time(s: float) -> String:
	var cs := int(round_half_away(maxf(s, 0.0) * 100.0))
	var h := floori(cs / 360000.0)
	var m := floori((cs % 360000) / 6000.0)
	var sec := (cs % 6000) / 100.0
	return "%d:%02d:%05.2f" % [h, m, sec]


## a gap m:ss with its sign ("+0:23", "-0:05"; "+0:00" for zero)
static func gap(s: float) -> String:
	var t := int(round_half_away(absf(s)))
	return "%s%d:%02d" % ["-" if s < 0.0 and t > 0 else "+", floori(t / 60.0), t % 60]


## a signed distance ("+45 m", "-30 m")
static func signed_distance(m: float) -> String:
	return ("-" if m < 0.0 and round_half_away(absf(m)) > 0.0 else "+") + distance(absf(m))


## relative bearing to the bow, integer degrees with L or R ("35° L"); `rel` > 0 is to starboard
static func relative_bearing(rel: float) -> String:
	var d := int(round_half_away(rad_to_deg(absf(rel))))
	if d == 0:
		return "0°"
	return "%d° %s" % [d, "R" if rel > 0.0 else "L"]
