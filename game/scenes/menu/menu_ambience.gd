class_name MenuAmbience
extends Node
## The main menu's quiet ambience (menus.md §4, audio.md §6.1): the sound map's sea bed for the backdrop's wind
## (12 kn: the moderate bed) and its wind bed, both low, with a halyard or a gull now and then, all on the
## `ambience` bus, so the ambience and master volumes act on it live (Settings.apply_audio). It fades in when the
## menu opens and out before a scene change (fade_out). No music, and nothing from the live backdrop, which stays
## silent (MenuStage). Headless runs log the sounds without starting players (as MenuSounds and GameAudio do).

const BUS := "ambience"
## the backdrop's wind (MenuStage.WIND_KN): picks the sea bed by the map's bounds
const WIND_KN := 12.0
## the sea bed at this share of the map's bed volume (audio.md §6: 0.4), and the wind bed's gain: quiet, under the
## menu's own sounds
const BED_SHARE := 0.6
const WIND_GAIN := 0.12
## the one-shots (map ids; the ones the map lacks are skipped), how often (s, uniform) and how loud
const ONE_SHOTS := ["amb.halyard", "amb.gull"]
const EVERY := Vector2(25.0, 70.0)
const SHOT_GAIN := Vector2(0.12, 0.25)
const FADE_IN_S := 2.0

var audible := DisplayServer.get_name() != "headless"
## the beds playing: [{id, file, gain}]
var beds: Array = []
## one-shots played, by map id (tests)
var played: Array[String] = []
## seconds since start
var time := 0.0
## 0 silent to 1 full
var fade := 0.0
var rng := RandomNumberGenerator.new()

var _map: SoundMap
var _players: Array[AudioStreamPlayer] = []
var _shot: AudioStreamPlayer
var _fade_rate := 1.0 / FADE_IN_S
var _next := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	AudioBuses.set_duck(BUS, 0.0)  # a race's signal duck does not follow into the menu
	rng.randomize()
	_map = SoundMap.load_file()
	if _map == null:
		return
	var files: Array = _map.ambience.get("beds", [])
	if not files.is_empty():
		var w := SoundFormula.bed_weights(WIND_KN, _map.ambience.get("bounds_kn", [6, 14, 22]),
			float(_map.ambience.get("crossfade_kn", 2.0)))
		var best := 0
		for i in mini(w.size(), files.size()):
			if w[i] > w[best]:
				best = i
		_add_bed("amb.bed", _map.resolve(String(files[best])), float(_map.ambience.get("volume", 0.4)) * BED_SHARE)
	for v in _map.variants("wind.bed"):
		if String(v["synth"]) == "":
			_add_bed("wind.bed", String(v["file"]), WIND_GAIN)
			break
	_shot = AudioStreamPlayer.new()
	_shot.name = "OneShot"
	_shot.bus = BUS
	add_child(_shot)
	_next = rng.randf_range(EVERY.x, EVERY.y)
	_volumes()


func _add_bed(id: String, file: String, gain: float) -> void:
	var s := _map.stream_at(file, true)
	if s == null:
		return
	beds.append({"id": id, "file": file, "gain": gain})
	var p := AudioStreamPlayer.new()
	p.name = id.capitalize().replace(" ", "")
	p.bus = BUS
	p.stream = s
	add_child(p)
	_players.append(p)
	if audible:
		p.play(rng.randf() * maxf(s.get_length() - 0.1, 0.0))  # a random point in the loop


## Fades the ambience out over `s` seconds (before a scene change).
func fade_out(s: float) -> void:
	_fade_rate = -1.0 / maxf(s, 0.01)


func _process(dt: float) -> void:
	step(dt)


## One frame: the fade, the one-shots.
func step(dt: float) -> void:
	time += dt
	fade = clampf(fade + _fade_rate * dt, 0.0, 1.0)
	_volumes()
	if _map == null or time < _next:
		return
	_next = time + rng.randf_range(EVERY.x, EVERY.y)
	var ids := ONE_SHOTS.filter(func(id: String) -> bool: return _map.has(id) and not _map.variants(id).is_empty())
	if ids.is_empty() or fade <= 0.0:
		return
	var id: String = ids[rng.randi_range(0, ids.size() - 1)]
	var v := _map.pick(id, rng)
	played.append(id)
	if audible and not v.is_empty():
		_shot.stream = v["stream"]
		_shot.volume_db = linear_to_db(rng.randf_range(SHOT_GAIN.x, SHOT_GAIN.y) * fade)
		_shot.play()


func _volumes() -> void:
	for i in _players.size():
		var g := float(beds[i]["gain"]) * fade
		_players[i].volume_db = linear_to_db(g) if g > 0.0 else -80.0


## The bed players (tests).
func players() -> Array[AudioStreamPlayer]:
	return _players
