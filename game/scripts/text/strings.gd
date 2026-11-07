class_name Strings
extends RefCounted
## The front end's string table (menus.md §1.3 "Strings"): fixed player-facing texts by key, English as the source.
## A language adds its own table later; a key it lacks falls back to the English. Templates take named parts,
## `{name}`, so a language can reorder them. No em dashes in any text.

const EN := {
	# weather modes and the Custom rows (menus.md §1)
	"weather.label": "Weather",
	"weather.mode.local": "Local",
	"weather.mode.random": "Random",
	"weather.mode.custom": "Custom",
	"weather.wind_speed": "Wind speed",
	"weather.wind_from": "Wind from",
	"weather.shifts": "Shifts",
	"weather.gusts": "Gusts",
	"weather.shifts.steady": "Steady",
	"weather.shifts.stable": "Stable",
	"weather.shifts.oscillating": "Oscillating",
	"weather.shifts.shifty": "Shifty",
	"weather.shifts.unstable": "Unstable",
	"weather.gusts.none": "None",
	"weather.gusts.light": "Light",
	"weather.gusts.moderate": "Moderate",
	"weather.gusts.very_strong": "Very strong",
	# the light rows (menus.md §1)
	"light.time": "Time",
	"light.sky": "Sky",
	"light.venue_default": "Venue default",
	"light.surprise": "Surprise",
	"light.sky.clear": "Clear",
	"light.sky.fair": "Fair",
	"light.sky.hazy": "Hazy",
	"light.sky.overcast": "Overcast",
	# the venue briefing (menus.md §1.3)
	"briefing.header": "{name} · {tag}",
	"briefing.label.wind": "Wind",
	"briefing.label.shifts": "Shifts",
	"briefing.label.gusts": "Gusts",
	"briefing.label.current": "Current",
	"briefing.label.sea": "Sea",
	"briefing.label.tip": "Tip",
	"briefing.label.weather": "Weather",
	"briefing.unknown": "Unknown: read it on the water",
	"briefing.line.wind": "{lo}-{hi} kn from the {point}",
	"briefing.line.wind_one": "{v} kn from the {point}",
	"briefing.line.shifts": "{word}: {size}, {pace} ({a}°)",
	"briefing.line.trend": "{line}, {dir} {n}°",
	"briefing.trend.veers": "veers",
	"briefing.trend.backs": "backs",
	"briefing.line.gusts": "{word}: to +{g} %, {spread}",
	"briefing.line.current": "{word}, {c} kn",
	"briefing.line.current_tide": "{line}, {state} (sets {point})",
	"briefing.line.current_tide_noset": "{line}, {state}",
	"briefing.line.current_slack": "Slack, turning",
	"briefing.line.current_sets": "{line}, sets {point}",
	"briefing.line.sea_range": "{a} to {b}",
	"briefing.line.swell": "{line}, swell {hs} m from the {point}",
	"briefing.label.light": "Light",
	"briefing.line.light": "{time}, {sky}",
	"briefing.sky.clear": "clear",
	"briefing.sky.fair": "fair",
	"briefing.sky.hazy": "hazy",
	"briefing.sky.overcast": "overcast",
	"briefing.word.shifts.steady": "Steady",
	"briefing.word.shifts.stable": "Stable",
	"briefing.word.shifts.oscillating": "Oscillating",
	"briefing.word.shifts.shifty": "Shifty",
	"briefing.word.shifts.unstable": "Unstable",
	"briefing.size.small": "small",
	"briefing.size.medium": "medium",
	"briefing.size.large": "large",
	"briefing.size.very_large": "very large",
	"briefing.pace.slow": "slow",
	"briefing.pace.regular": "regular",
	"briefing.pace.fast": "fast",
	"briefing.word.gusts.none": "None",
	"briefing.word.gusts.light": "Light",
	"briefing.word.gusts.moderate": "Moderate",
	"briefing.word.gusts.strong": "Strong",
	"briefing.word.gusts.very_strong": "Very strong",
	"briefing.spread.scattered": "scattered",
	"briefing.spread.frequent": "frequent",
	"briefing.spread.everywhere": "everywhere",
	"briefing.word.current.none": "None",
	"briefing.word.current.light": "Light",
	"briefing.word.current.moderate": "Moderate",
	"briefing.word.current.strong": "Strong",
	"briefing.word.current.very_strong": "Very strong",
	"briefing.tide.flooding": "flooding",
	"briefing.tide.ebbing": "ebbing",
	"briefing.word.sea.flat": "Flat",
	"briefing.word.sea.chop": "Chop",
	"briefing.word.sea.moderate": "Moderate",
	"briefing.word.sea.rough": "Rough",
	"compass.n": "N",
	"compass.ne": "NE",
	"compass.e": "E",
	"compass.se": "SE",
	"compass.s": "S",
	"compass.sw": "SW",
	"compass.w": "W",
	"compass.nw": "NW",
	# the results screen after a Random race (menus.md §5)
	"results.today": "Today: {wind} · {shifts} · {gusts}",
	"results.today.gusts": "{word} gusts",
	"results.today.no_gusts": "No gusts",
	# the results screen's best line from the race history (menus.md §5, §6)
	"results.best": "Your best here: {time}",
	"results.new_best": "New best: {time}, was {old}",
	"results.first_race": "First race here",
	"results.first_finish": "First finish here",
}

## the language in use ("" or "en": English); a later language table goes in TABLES
static var language := ""
const TABLES := {}


## The text of `key` with its `{name}` parts filled from `parts`; the key itself when no table has it.
static func t(key: String, parts := {}) -> String:
	var table: Dictionary = TABLES.get(language, {})
	var s: String = table.get(key, EN.get(key, key))
	for k in parts:
		s = s.replace("{%s}" % k, str(parts[k]))
	return s
