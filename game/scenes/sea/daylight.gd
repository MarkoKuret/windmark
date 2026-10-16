class_name Daylight
extends RefCounted
## The daylight model (water_render.md §4.5, WM-124): two inputs, the time of day (a local clock hour) and the
## conditions (clear, fair, hazy, overcast), give every value of the sky rig and its colour grade. The sun's place
## comes from the hour, the venue's latitude, longitude, UTC offset and date (the short NOAA formulas); the colours
## follow the sun's elevation through a morning and an afternoon keyframe table, blended around solar noon, and the
## conditions multiply them. Pure functions: SkyRig applies the result, the tests and previews call them directly.

## The lowest sun the light goes to (deg): the hour is clamped to the hours with the sun at least this high.
const MIN_SUN := 6.0
## The venues' race windows end with the sun at least this high (deg; water_render.md §4.6, low sun limit).
const MIN_RACE_SUN := 10.0
## Hours either side of solar noon over which the morning and afternoon tables blend.
const NOON_BLEND_H := 1.5
## At most this much distance haze at the horizon, whatever the conditions and the hour.
const HAZE_MAX_CAP := 0.9

const CONDITION_NAMES := ["clear", "fair", "hazy", "overcast"]

## The site of the sun formula: latitude and longitude (deg, the venue file's origin), the local clock's offset from
## UTC (h, summer time included) and the day of the year (1 to 365).
const DEFAULT_SITE := {"lat": 45.5, "lon": 13.6, "utc_offset_h": 2.0, "day": 237}

## water_render.md §4.5 hour keys over the sun's elevation (deg), per branch: sun colour and energy, sky horizon and
## zenith (linear), exposure, factors on the conditions' haze max and cloud cover, and the grade (contrast, warm and
## cool tints, saturation, white keep). Linear between keys, held beyond the first and last.
const MIDDAY := {
	"sun_color": Color(1.0, 0.92, 0.80), "sun_energy": 3.6, "horizon": Color(0.50, 0.74, 1.10),
	"zenith": Color(0.05, 0.18, 0.62), "exposure": 0.50, "haze_k": 1.0, "cloud_k": 1.0,
	"contrast": 0.30, "warm": Vector3(0.040, 0.014, -0.036), "cool": Vector3(-0.030, 0.004, 0.044),
	"saturation": 1.07, "white_keep": 1.0,
}
const AFTERNOON := [
	[6.0, {"sun_color": Color(1.0, 0.54, 0.24), "sun_energy": 3.3, "horizon": Color(0.86, 0.72, 0.58),
		"zenith": Color(0.09, 0.19, 0.50), "exposure": 0.78, "haze_k": 1.25, "cloud_k": 0.70,
		"contrast": 0.26, "warm": Vector3(0.084, 0.030, -0.060), "cool": Vector3(-0.036, 0.0, 0.052),
		"saturation": 1.10, "white_keep": 0.3}],
	[12.0, {"sun_color": Color(1.0, 0.64, 0.34), "sun_energy": 3.7, "horizon": Color(0.74, 0.72, 0.76),
		"zenith": Color(0.07, 0.18, 0.54), "exposure": 0.66, "haze_k": 1.13, "cloud_k": 0.72,
		"contrast": 0.27, "warm": Vector3(0.076, 0.028, -0.056), "cool": Vector3(-0.034, 0.0, 0.050),
		"saturation": 1.10, "white_keep": 0.4}],
	# the former late-afternoon preset
	[17.0, {"sun_color": Color(1.0, 0.72, 0.44), "sun_energy": 3.8, "horizon": Color(0.60, 0.70, 0.94),
		"zenith": Color(0.05, 0.17, 0.58), "exposure": 0.60, "haze_k": 0.65 / 0.60, "cloud_k": 0.75,
		"contrast": 0.28, "warm": Vector3(0.066, 0.024, -0.052), "cool": Vector3(-0.032, 0.0, 0.048),
		"saturation": 1.09, "white_keep": 0.6}],
	[26.0, {"sun_color": Color(1.0, 0.86, 0.68), "sun_energy": 3.7, "horizon": Color(0.55, 0.72, 1.02),
		"zenith": Color(0.05, 0.175, 0.60), "exposure": 0.55, "haze_k": 1.04, "cloud_k": 0.88,
		"contrast": 0.30, "warm": Vector3(0.052, 0.018, -0.044), "cool": Vector3(-0.030, 0.002, 0.046),
		"saturation": 1.08, "white_keep": 0.9}],
	[38.0, MIDDAY],
]
const MORNING := [
	[6.0, {"sun_color": Color(1.0, 0.70, 0.46), "sun_energy": 3.2, "horizon": Color(0.72, 0.72, 0.86),
		"zenith": Color(0.06, 0.155, 0.50), "exposure": 0.76, "haze_k": 1.40, "cloud_k": 0.40,
		"contrast": 0.26, "warm": Vector3(0.044, 0.018, -0.012), "cool": Vector3(-0.040, 0.008, 0.058),
		"saturation": 1.04, "white_keep": 0.6}],
	[12.0, {"sun_color": Color(1.0, 0.80, 0.58), "sun_energy": 3.5, "horizon": Color(0.62, 0.72, 0.95),
		"zenith": Color(0.055, 0.17, 0.57), "exposure": 0.65, "haze_k": 1.28, "cloud_k": 0.45,
		"contrast": 0.27, "warm": Vector3(0.036, 0.016, -0.014), "cool": Vector3(-0.038, 0.008, 0.056),
		"saturation": 1.04, "white_keep": 0.8}],
	[17.0, {"sun_color": Color(1.0, 0.84, 0.66), "sun_energy": 3.6, "horizon": Color(0.56, 0.70, 1.00),
		"zenith": Color(0.055, 0.175, 0.60), "exposure": 0.60, "haze_k": 1.20, "cloud_k": 0.50,
		"contrast": 0.27, "warm": Vector3(0.030, 0.014, -0.016), "cool": Vector3(-0.036, 0.008, 0.054),
		"saturation": 1.04, "white_keep": 1.0}],
	[26.0, {"sun_color": Color(1.0, 0.90, 0.78), "sun_energy": 3.6, "horizon": Color(0.50, 0.72, 1.08),
		"zenith": Color(0.05, 0.18, 0.63), "exposure": 0.54, "haze_k": 1.10, "cloud_k": 0.70,
		"contrast": 0.28, "warm": Vector3(0.026, 0.012, -0.020), "cool": Vector3(-0.034, 0.006, 0.050),
		"saturation": 1.05, "white_keep": 1.0}],
	[38.0, MIDDAY],
]

## water_render.md §4.5 conditions: distance haze (WM-084), cloud cover (cumulus: times the hour's cloud factor),
## a factor on the sun's energy, the midday sun and sky colours (the per-channel ratio to fair's is applied to the
## hour's colours; a grey sky instead takes its own colours, dimmed and tinted by the hour), a factor on the exposure,
## on the drawn boat shadows (§4.7) and on the sun shadows' blur (§4.6), the cloud deck's diffuse lighting, the sea
## body colour's saturation and value (§4.2), the puffs' darkening (§4.3), and the grade's change.
const FAIR_SUN := Color(1.0, 0.92, 0.80)
const FAIR_HORIZON := Color(0.50, 0.74, 1.10)
const FAIR_ZENITH := Color(0.05, 0.18, 0.62)
const CONDITIONS := {
	"clear": {"haze_begin": 300.0, "haze_end": 16000.0, "haze_max": 0.45, "haze_curve": 0.42,
		"cloud_cover": 0.0, "cumulus": true, "sun_k": 1.0, "sun_color": FAIR_SUN, "horizon": FAIR_HORIZON,
		"zenith": FAIR_ZENITH, "exposure_k": 1.0, "shadow": 1.0,
		"grey_sky": false, "diffuse": 0.0, "shadow_blur_k": 1.0, "sea_saturation": 1.0, "sea_value": 1.0, "puff_k": 1.0,
		"contrast_add": 0.02, "warm_k": 1.0, "cool_k": 1.0, "saturation_k": 1.02},
	"fair": {"haze_begin": 200.0, "haze_end": 14000.0, "haze_max": 0.60, "haze_curve": 0.40,
		"cloud_cover": 0.40, "cumulus": true, "sun_k": 1.0, "sun_color": FAIR_SUN, "horizon": FAIR_HORIZON,
		"zenith": FAIR_ZENITH, "exposure_k": 1.0, "shadow": 1.0,
		"grey_sky": false, "diffuse": 0.0, "shadow_blur_k": 1.0, "sea_saturation": 1.0, "sea_value": 1.0, "puff_k": 1.0,
		"contrast_add": 0.0, "warm_k": 1.0, "cool_k": 1.0, "saturation_k": 1.0},
	"hazy": {"haze_begin": 150.0, "haze_end": 10000.0, "haze_max": 0.80, "haze_curve": 0.40,
		"cloud_cover": 0.25, "cumulus": true, "sun_k": 2.8 / 3.6, "sun_color": Color(1.0, 0.95, 0.88),
		"horizon": Color(0.80, 0.88, 1.00), "zenith": Color(0.24, 0.40, 0.74), "exposure_k": 1.10, "shadow": 0.85,
		"grey_sky": false, "diffuse": 0.0, "shadow_blur_k": 1.0, "sea_saturation": 1.0, "sea_value": 1.0, "puff_k": 1.0,
		"contrast_add": 0.06, "warm_k": 0.9, "cool_k": 0.9, "saturation_k": 1.0},
	# a diffuse day: the deck gives the light (the sky's grey ramp, brighter overhead), the sun behind it about a
	# tenth; the exposure brings the dimmer whole back up, the sea body greyer and darker
	"overcast": {"haze_begin": 120.0, "haze_end": 9000.0, "haze_max": 0.75, "haze_curve": 0.40,
		"cloud_cover": 0.88, "cumulus": false, "sun_k": 0.04, "sun_color": Color(1.0, 0.98, 0.96),
		"horizon": Color(0.60, 0.63, 0.67), "zenith": Color(0.68, 0.71, 0.75), "exposure_k": 1.6, "shadow": 0.10,
		"grey_sky": true, "diffuse": 1.0, "shadow_blur_k": 4.0, "sea_saturation": 0.5, "sea_value": 0.85, "puff_k": 2.4,
		"contrast_add": -0.06, "warm_k": 0.3, "cool_k": 0.5, "saturation_k": 0.9},
}

## The old light preset names (`--sky=`): conditions and the afternoon sun elevation of their hour.
const ALIASES := {
	"clear": {"conditions": "clear", "sun": 38.0}, "fair": {"conditions": "fair", "sun": 38.0},
	"hazy": {"conditions": "hazy", "sun": 38.0}, "late": {"conditions": "fair", "sun": 17.0},
}


# ---- the sun ----------------------------------------------------------------------------------------------------

## The sun at a local clock hour: Vector3(elevation deg, azimuth deg clockwise from north, solar time - 12 h).
## NOAA's short formulas (fractional year, declination and equation of time series), no refraction.
static func sun_position(site: Dictionary, hour: float) -> Vector3:
	var lat := deg_to_rad(float(site.get("lat", DEFAULT_SITE["lat"])))
	var lon := float(site.get("lon", DEFAULT_SITE["lon"]))
	var tz := float(site.get("utc_offset_h", DEFAULT_SITE["utc_offset_h"]))
	var day := float(site.get("day", DEFAULT_SITE["day"]))
	var g := TAU / 365.0 * (day - 1.0 + (hour - tz - 12.0) / 24.0)
	var dec := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) \
			+ 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var eqt := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g)
			- 0.040849 * sin(2.0 * g))
	var tst := hour * 60.0 + eqt + 4.0 * lon - 60.0 * tz
	var ha := deg_to_rad(tst / 4.0 - 180.0)
	var sz := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
	var el := rad_to_deg(asin(clampf(sz, -1.0, 1.0)))
	var az := rad_to_deg(atan2(sin(ha), cos(ha) * sin(lat) - tan(dec) * cos(lat))) + 180.0
	return Vector3(el, fposmod(az, 360.0), tst / 60.0 - 12.0)


## The local clock hour of solar noon on the site's date.
static func solar_noon(site: Dictionary) -> float:
	var h := 12.0
	for i in 3:
		h -= sun_position(site, h).z
	return h


## The hours [first, last] with the sun at least `min_sun` high (bisection either side of solar noon); both the
## noon when it never gets so high.
static func hour_range(site: Dictionary, min_sun := MIN_SUN) -> Vector2:
	var noon := solar_noon(site)
	if sun_position(site, noon).x < min_sun:
		return Vector2(noon, noon)
	return Vector2(_cross(site, noon, noon - 12.0, min_sun), _cross(site, noon, noon + 12.0, min_sun))


static func _cross(site: Dictionary, above: float, below: float, el: float) -> float:
	for i in 40:
		var m := 0.5 * (above + below)
		if sun_position(site, m).x >= el:
			above = m
		else:
			below = m
	return above


## The hour clamped to the hours with the sun at least MIN_SUN high.
static func clamp_hour(site: Dictionary, hour: float) -> float:
	var r := hour_range(site)
	return clampf(hour, r.x, r.y)


## The hour of the afternoon (or morning) sun at `el` deg; solar noon when the sun never gets so high.
static func hour_for_sun(site: Dictionary, el: float, afternoon := true) -> float:
	var r := hour_range(site, el)
	return r.y if afternoon else r.x


# ---- the light --------------------------------------------------------------------------------------------------

static func is_condition(name: String) -> bool:
	return CONDITIONS.has(name)


## Every value of the sky rig and the grade for a site, an hour (clamped) and conditions (unknown: fair):
## sun_elevation_deg, sun_azimuth_deg, sun_color, sun_energy, horizon, zenith, cloud_cover, exposure, haze_begin,
## haze_end, haze_max, haze_curve, shadow, diffuse, shadow_blur_k, sea_saturation, sea_value, puff_k, hour (the
## clamped hour), grade {contrast, warm, cool, saturation, white_keep}.
static func light(site: Dictionary, hour: float, conditions: String) -> Dictionary:
	var h := clamp_hour(site, hour)
	var sp := sun_position(site, h)
	var k := hour_keys(sp.x, sp.z)
	var c: Dictionary = CONDITIONS.get(conditions, CONDITIONS["fair"])
	var out := {"hour": h, "sun_elevation_deg": maxf(sp.x, MIN_SUN), "sun_azimuth_deg": sp.y}
	out["sun_color"] = _ratio(k["sun_color"], c["sun_color"], FAIR_SUN, true)
	out["sun_energy"] = float(k["sun_energy"]) * float(c["sun_k"])
	if c["grey_sky"]:
		var g := grey_sky_k(sp.x, k["sun_color"])
		out["horizon"] = (c["horizon"] as Color) * g
		out["zenith"] = (c["zenith"] as Color) * g
	else:
		out["horizon"] = _ratio(k["horizon"], c["horizon"], FAIR_HORIZON)
		out["zenith"] = _ratio(k["zenith"], c["zenith"], FAIR_ZENITH)
	out["cloud_cover"] = float(c["cloud_cover"]) * (float(k["cloud_k"]) if c["cumulus"] else 1.0)
	out["exposure"] = float(k["exposure"]) * float(c["exposure_k"])
	out["haze_begin"] = c["haze_begin"]
	out["haze_end"] = c["haze_end"]
	out["haze_curve"] = c["haze_curve"]
	out["haze_max"] = minf(float(c["haze_max"]) * float(k["haze_k"]), HAZE_MAX_CAP)
	out["shadow"] = c["shadow"]
	for key in ["diffuse", "shadow_blur_k", "sea_saturation", "sea_value", "puff_k"]:
		out[key] = c[key]
	out["grade"] = {
		"contrast": float(k["contrast"]) + float(c["contrast_add"]),
		"warm": (k["warm"] as Vector3) * float(c["warm_k"]),
		"cool": (k["cool"] as Vector3) * float(c["cool_k"]),
		"saturation": float(k["saturation"]) * float(c["saturation_k"]),
		"white_keep": k["white_keep"],
	}
	return out


## A grey sky's factor at a sun elevation (deg) and the hour's sun colour: the deck dims as the sun drops (the
## square root of sin(el) over sin 38 deg, at least 0.45) and takes a quarter of the sun's tint (water_render.md §4.5).
static func grey_sky_k(el: float, sun_col: Color) -> Color:
	var dim := sqrt(clampf(sin(deg_to_rad(maxf(el, MIN_SUN))) / sin(deg_to_rad(38.0)), 0.2025, 1.0))
	return Color.WHITE.lerp(sun_col, 0.25) * dim


## The hour's keys at a sun elevation (deg) and a solar time from noon (h): the morning and afternoon tables at
## that elevation, blended over NOON_BLEND_H either side of solar noon.
static func hour_keys(el: float, from_noon: float) -> Dictionary:
	var w := smoothstep(-NOON_BLEND_H, NOON_BLEND_H, from_noon)
	return _mix(_table(MORNING, el), _table(AFTERNOON, el), w)


static func _table(tab: Array, el: float) -> Dictionary:
	if el <= tab[0][0]:
		return tab[0][1]
	for i in range(1, tab.size()):
		if el <= tab[i][0]:
			var a: float = tab[i - 1][0]
			var b: float = tab[i][0]
			return _mix(tab[i - 1][1], tab[i][1], (el - a) / (b - a))
	return tab[-1][1]


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var out := {}
	for key in a:
		var va: Variant = a[key]
		var vb: Variant = b[key]
		match typeof(va):
			TYPE_COLOR:
				out[key] = (va as Color).lerp(vb, t)
			TYPE_VECTOR3:
				out[key] = (va as Vector3).lerp(vb, t)
			_:
				out[key] = lerpf(float(va), float(vb), t)
	return out


## The hour's colour times the conditions' midday colour over fair's, per channel; a sun colour is kept with red 1.
static func _ratio(col: Color, cond: Color, fair: Color, normalise := false) -> Color:
	var o := Color(col.r * cond.r / fair.r, col.g * cond.g / fair.g, col.b * cond.b / fair.b)
	if normalise:
		var m := maxf(o.r, maxf(o.g, o.b))
		o = Color(o.r / m, o.g / m, o.b / m)
	return o


## water_render.md §4.2 sea body colours (linear) at full saturation and value: deep, shallow (crests), light
## through the crests.
const SEA_DEEP := Vector3(0.006, 0.042, 0.115)
const SEA_SHALLOW := Vector3(0.012, 0.100, 0.155)
const SEA_SSS := Vector3(0.03, 0.33, 0.40)
const LUMA := Vector3(0.2126, 0.7152, 0.0722)


## The sea body colours with their saturation and value scaled about their luminance:
## value · mix(luma, colour, saturation). {col_deep, col_shallow, col_sss}.
static func sea_colors(saturation: float, value: float) -> Dictionary:
	var out := {}
	for k in [["col_deep", SEA_DEEP], ["col_shallow", SEA_SHALLOW], ["col_sss", SEA_SSS]]:
		var c: Vector3 = k[1]
		var l := c.dot(LUMA)
		out[k[0]] = (Vector3(l, l, l).lerp(c, saturation)) * value
	return out


# ---- clock text -------------------------------------------------------------------------------------------------

## "HH:MM" -> hours; -1 when it does not parse.
static func parse_hour(s: String) -> float:
	var p := s.strip_edges().split(":")
	if p.size() < 1 or p.size() > 2 or not p[0].is_valid_int():
		return -1.0
	var m := 0
	if p.size() == 2:
		if not p[1].is_valid_int():
			return -1.0
		m = p[1].to_int()
	var h := p[0].to_int()
	if h < 0 or h > 24 or m < 0 or m > 59:
		return -1.0
	return h + m / 60.0


static func hour_text(h: float) -> String:
	var m := roundi(h * 60.0)
	return "%02d:%02d" % [posmod(m / 60, 24), posmod(m, 60)]


## Day of the year (1 to 365, no leap day) of a "MM-DD" date; -1 when it does not parse.
static func day_of_year(md: String) -> int:
	var p := md.split("-")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return -1
	var mo := p[0].to_int()
	var d := p[1].to_int()
	var lens := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if mo < 1 or mo > 12 or d < 1 or d > lens[mo - 1]:
		return -1
	var n := d
	for i in mo - 1:
		n += lens[i]
	return n
