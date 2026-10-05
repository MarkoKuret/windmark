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
var venue := "example_bay"
## course as "<venue>/<course id>" (game/data/courses/<venue>/<id>.course.json), used in race mode
var course := "example_bay/example_wl"
## boats in the race including the player, 1 to 40
var fleet_size := 10
## AI level of the AI boats: easy, intermediate, expert or pro (ai.md)
var ai_level := "intermediate"
## base true wind speed in knots and the direction it blows from in degrees (0 = north)
var wind_kn := 12.0
var wind_from_deg := 0.0
## seed of the world (wind shifts, puffs, AI randomness); 0 picks one from the clock
var seed := 0
## scenario mode: the scenario id (game/data/scenarios/<id>.scenario.json) or a path to a .scenario.json file
var scenario := ""

## the setup the next scene reads; set by the menus, cleared by nobody (a new session overwrites it)
static var next: GameSetup = null


static func current() -> GameSetup:
	if next == null:
		next = GameSetup.new()
	return next


## The fields the menus remember (menus.md §1, Settings.last_setup): mode, class, sail number, venue, course, fleet,
## AI level and wind.
func to_dict() -> Dictionary:
	return {"mode": mode, "class_id": class_id, "livery": livery, "venue": venue, "course": course,
		"fleet_size": fleet_size, "ai_level": ai_level, "wind_kn": wind_kn, "wind_from_deg": wind_from_deg}


## A copy with a new seed (0: from the clock), as Race again starts it (menus.md §5).
func again() -> GameSetup:
	var g := GameSetup.new()
	for k in to_dict():
		g.set(k, get(k))
	g.scenario = scenario
	g.seed = 0
	return g
