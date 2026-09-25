class_name SeaEnvSource
extends Node
## Placeholder environment source for the sea renderer, with the fields the core binding (WM-016.01) will
## provide:
##   sea_components() -> Array of [a, kx, ky, c, T]      (sea.md §7.1, SeaField::components())
##   sea_exposure()   -> Dictionary grid or {}           (sea.md §6)
##   wind_state(t_ms) -> Dictionary {base_speed, base_from, global_from, puff_tile, cap_up, cap_down,
##                                   patches: Array of [px, py, R, s, e]}   (wind.md §9 puff_patches)
##   current_at(x, y, t_ms) -> Vector2                    (wind.md §7)
##   venue_wind_field() -> Dictionary {grid, sectors} or {}  (data_format.md §6.2, the venue's land effect)
## Two modes: PLACEHOLDER builds a sea with the formulas of sea.md §2 and §3 and puffs with the slot model of
## wind.md §6 but Godot's random numbers (so the look is right, the exact waves are not the core's);
## CORE_SAMPLES reads a scenario written by the core (core/tools/gen_sea_render_samples.cpp): the core's
## own components and exposure, and its puff patches at the sampled time nearest before t.

enum Mode { PLACEHOLDER, CORE_SAMPLES }

const G := 9.81
const KNOT := 0.51444447
const SEA_R := [0.75, 0.85, 0.95, 1.05, 1.18, 1.35, 1.6, 1.95, 2.4, 3.0]
const SEA_W := [0.1621, 0.2738, 0.4766, 0.5384, 0.3616, 0.3225, 0.2765, 0.2051, 0.1433, 0.0887]
const SEA_O := [0.0, -25.0, 20.0, -10.0, 35.0, -40.0, 12.0, 45.0, -30.0, 5.0]

@export var mode: Mode = Mode.PLACEHOLDER
@export var race_seed: int = 1
@export var wind_kn: float = 14.0
@export var wind_from_deg: float = 225.0
@export var fetch_m: float = 12000.0
@export var sea_scale: float = 1.0
@export var puffs_enabled: bool = true
@export var samples_path: String = "res://generated/sea/sea_render_samples.json"
@export var scenario: String = "example_bay_20kn"
## The venue of the core samples (CORE_SAMPLES), for its land-effect wind field: a name under data/venues or a
## path; "" for none.
@export var venue: String = "example_bay"

var _components: Array = []
var _exposure: Dictionary = {}
var _core: Dictionary = {}
var _built := false


func _ready() -> void:
	_build()


## Builds again after a change of mode, scenario or placeholder parameters (for owners that set them after
## the node is ready).
func rebuild() -> void:
	_built = false
	_core = {}
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	if mode == Mode.CORE_SAMPLES and _load_core():
		return
	if mode == Mode.CORE_SAMPLES:
		push_warning("SeaEnvSource: %s has no scenario %s, using the placeholder sea" % [samples_path, scenario])
		mode = Mode.PLACEHOLDER
	_components = _placeholder_components()
	_exposure = {}


func sea_components() -> Array:
	_build()
	return _components


func sea_exposure() -> Dictionary:
	_build()
	return _exposure


func current_at(_x: float, _y: float, _t_ms: float) -> Vector2:
	return Vector2.ZERO


func venue_wind_field() -> Dictionary:
	_build()
	if mode != Mode.CORE_SAMPLES or venue == "":
		return {}
	var path := venue
	if not venue.contains("/"):
		path = BoatClassData.repo_path("data/venues/%s.venue.json" % venue)
	return read_wind_field(path)


## The wind_field of a venue file (data_format.md §6.2), {} when the file or the field is missing.
static func read_wind_field(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("wind_field") is Dictionary:
		return data["wind_field"]
	return {}


func wind_state(t_ms: float) -> Dictionary:
	_build()
	if mode == Mode.CORE_SAMPLES:
		return _core_wind(t_ms)
	var base := wind_kn * KNOT
	var from := deg_to_rad(wind_from_deg)
	return {
		"base_speed": base, "base_from": from, "global_from": from, "puff_tile": 1000.0,
		"cap_up": 0.25, "cap_down": 0.4, "patches": _placeholder_puffs(t_ms, base, from) if puffs_enabled else [],
	}


## sea.md §2 growth law and §3 components, with Godot random numbers in place of the core's streams.
func _placeholder_components() -> Array:
	var U := wind_kn * KNOT
	if U < 1.0:
		return []
	var chi := minf(G * fetch_m / (U * U), 2.2e4)
	var hs := 0.0016 * sqrt(chi) * U * U / G
	var tp := 0.286 * pow(chi, 1.0 / 3.0) * U / G
	var from := deg_to_rad(wind_from_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([race_seed, 5])
	var out := []
	for i in 10:
		var T := maxi(200, int(tp * 1000.0 / SEA_R[i] + 0.5))
		var w := TAU * 1000.0 / T
		var kap := (w * w / G) / TAU
		var dir := fposmod(from + PI + deg_to_rad(SEA_O[i]) + (rng.randf() - 0.5) * deg_to_rad(10.0), TAU)
		var a := minf(hs * 0.353553391 * SEA_W[i] * sea_scale, 0.1 / (kap * TAU))
		if a > 0.0:
			out.append([a, kap * sin(dir), kap * cos(dir), rng.randf(), T])
	return out


## wind.md §6.2 and §6.3 slot model (default parameters) with Godot random numbers.
func _placeholder_puffs(t_ms: float, base: float, from: float) -> Array:
	var out := []
	var n_puff := 5
	var n := 10
	var tile := 1000.0
	for j in n:
		var r := RandomNumberGenerator.new()
		r.seed = hash([race_seed, 3, j])
		var life := 60000 + int(r.randf() * 60001.0)
		var off := int(r.randf() * life)
		var q := int(t_ms) + off
		var g := q / life
		var age := q % life
		var u := RandomNumberGenerator.new()
		u.seed = hash([race_seed, 4, j, g])
		var cx := u.randf() * tile
		var cy := u.randf() * tile
		var R := 0.5 * (200.0 + u.randf() * 100.0)
		var s := (0.3 + u.randf() * 0.2) if j < n_puff else -(0.5 + u.randf() * 0.2)
		var sb := base * (1.0 + s)
		var age_s := age * 0.001
		var px := cx - sb * sin(from) * age_s
		var py := cy - sb * cos(from) * age_s
		var fl := float(life)
		var fa := float(age)
		var e := fa / (0.1 * fl) if fa < 0.1 * fl else (1.0 if fa < 0.9 * fl else (fl - fa) / (0.1 * fl))
		if e >= 1e-4:
			out.append([px, py, R, s, e])
	return out


func _load_core() -> bool:
	if not FileAccess.file_exists(samples_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(samples_path))
	if not (data is Dictionary):
		return false
	for sc in data.get("scenarios", []):
		if sc["name"] == scenario:
			_core = sc
			_components = sc["components"]
			_exposure = sc["exposure"] if sc["exposure"] is Dictionary else {}
			return true
	return false


## The core's puff patches at the last sampled time at or before t, drifted on to t with the current direction
## (a placeholder: the binding will return puff_patches(t) directly).
func _core_wind(t_ms: float) -> Dictionary:
	var w: Dictionary = _core.get("wind", {})
	var base: float = w.get("base_speed", wind_kn * KNOT)
	var out := {
		"base_speed": base, "base_from": w.get("base_from", deg_to_rad(wind_from_deg)),
		"puff_tile": w.get("puff_tile", 1000.0), "cap_up": w.get("cap_up", 0.25),
		"cap_down": w.get("cap_down", 0.4), "patches": [],
	}
	out["global_from"] = out["base_from"]
	var best = null
	for p in _core.get("puffs", []):
		if p["t"] <= t_ms and (best == null or p["t"] > best["t"]):
			best = p
	if best == null or not puffs_enabled:
		return out
	out["global_from"] = best["global_from"]
	var dt_s: float = (t_ms - best["t"]) * 0.001
	var f: float = best["global_from"]
	for p in best["patches"]:
		var sb: float = base * (1.0 + p[3])
		out["patches"].append([p[0] - sb * sin(f) * dt_s, p[1] - sb * cos(f) * dt_s, p[2], p[3], p[4]])
	return out


## Sample times of the core puff data (CORE_SAMPLES), for fixed renders.
func core_puff_times() -> Array:
	_build()
	var out := []
	for p in _core.get("puffs", []):
		out.append(p["t"])
	return out
