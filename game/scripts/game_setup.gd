class_name GameSetup
extends RefCounted
## What the next session on the water should be: written by the menus (quick race, free sail), read by the sail
## scene when it starts. Command-line flags of the scene override these fields; the defaults are free sailing.

## free: one boat sailing freely on the venue; race: a race on `course` with `fleet_size` boats (the player and AI);
## scenario: the rules scenario `scenario` (race.md §14), whose file gives the class, course, wind, seed and boats
var mode := "free"
## class id of the player's boat and of the AI boats (data/classes/<id>.boat.json)
var class_id := "wm7"
## the player's boat (a `boats` id of data/liveries/<class>.liveries.json: sail number and name, the menus' Sail
## number row); "": the first boat of the file
var livery := ""
## venue id (data/venues/<id>.venue.json)
var venue := "practice_waters"
## course as "<venue>/<course id>" (game/data/courses/<venue>/<id>.course.json), used in race mode
var course := "practice_waters/example_wl"
## boats in the race including the player, 1 to 40
var fleet_size := 10
## AI level of the AI boats: easy, intermediate, expert or pro (ai.md); Easy until the player picks another (menus.md §1:
## the first race is against boats she can beat while she learns the keys)
var ai_level := "easy"
## weather mode (race.md §2.1): local (the venue's own weather), random (a surprise day) or custom (wind_kn,
## wind_from_deg, shift and gusts below); "" sets the wind of the fields below directly (tests, tools)
var weather := "local"
## Custom: base true wind speed in knots and the direction it blows from in degrees (0 = north), the shift preset
## (steady, stable, oscillating, shifty, unstable) and the puff preset (none, light, standard, gusty)
var wind_kn := 12.0
var wind_from_deg := 0.0
var shift := "shifty"
var gusts := "standard"
## seed of the world (wind shifts, puffs, AI randomness); 0 picks one from the clock
var seed := 0
## the light (water_render.md §4.5): the time of day as a local clock hour (-1: the venue's, by the weather mode),
## the conditions ("": the venue's; clear, fair, hazy, overcast) and the clock's run during the race (game hours per
## real hour, 0 fixed)
var light_time := -1.0
var light_conditions := ""
var light_advance := 0.0
## scenario mode: the scenario id (game/data/scenarios/<id>.scenario.json) or a path to a .scenario.json file
var scenario := ""

## the setup the next scene reads; set by the menus, cleared by nobody (a new session overwrites it)
static var next: GameSetup = null


static func current() -> GameSetup:
	if next == null:
		next = GameSetup.new()
	return next


## The fields the menus remember (menus.md §1, Settings.last_setup): mode, class, sail number, venue, course, fleet,
## AI level and weather.
func to_dict() -> Dictionary:
	return {"mode": mode, "class_id": class_id, "livery": livery, "venue": venue, "course": course,
		"fleet_size": fleet_size, "ai_level": ai_level, "weather": weather, "wind_kn": wind_kn,
		"wind_from_deg": wind_from_deg, "shift": shift, "gusts": gusts}


## A copy with a new seed (0: from the clock), as Race again starts it (menus.md §5).
func again() -> GameSetup:
	var g := GameSetup.new()
	for k in to_dict():
		g.set(k, get(k))
	g.scenario = scenario
	g.light_time = light_time
	g.light_conditions = light_conditions
	g.light_advance = light_advance
	g.seed = 0
	return g
