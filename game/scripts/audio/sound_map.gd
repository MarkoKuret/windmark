class_name SoundMap
extends RefCounted
## The sound map of audio.md §9: the only place that names sound files. load_file() reads a map, expands the
## per-slot entries (`slots`), and resolves the files lazily: pick(id) returns a random variant (never the same
## twice in a row). A missing file warns once (`warn_hook`, push_warning by default) and drops out of its sound;
## a sound with no file left plays its synthesised fallback (`synth`, SoundSynth) or is disabled. Paths under
## res:// load as imported resources, others (a sound set in user:// or on disk) as .ogg or .wav at run time.
## Unknown keys are ignored.

const SCHEMA := "windmark.soundmap/1"
const DEFAULT_PATH := "res://data/sound_map.json"

## receives every warning (tests collect them); unset: push_warning
static var warn_hook: Callable

var path := ""
## the folder the relative file names are under
var root := ""
## id -> the entry with its defaults (files, loop, bus, volume, space, anchor, d_min, gate, trigger, volume_terms,
## pitch_terms, synth)
var sounds := {}
## signal kind name -> [sound id, count]
var signals := {}
## rule code name -> sound id
var hails := {}
## {buoy, committee} -> sound id
var course := {}
## beds (file names), bounds_kn, crossfade_kn, volume, one_shots (sound ids)
var ambience := {}

var _variants := {}  # id -> Array of {file, stream, synth}
var _last := {}  # id -> index of the last variant played
var _files := {}  # full path -> AudioStream or null (missing)
static var _warned := {}


## The map at `p` (default: the game's own), null when it cannot be read.
static func load_file(p := DEFAULT_PATH) -> SoundMap:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		_warn("sound map %s not found" % p)
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or String(d.get("schema", "")) != SCHEMA:
		_warn("sound map %s: not a %s file" % [p, SCHEMA])
		return null
	var m := SoundMap.new()
	m.path = p
	m._read(d)
	return m


static func _warn(msg: String) -> void:
	if warn_hook.is_valid():
		warn_hook.call(msg)
	else:
		push_warning(msg)


## Forget which files already warned (tests).
static func reset_warnings() -> void:
	_warned.clear()


func _read(d: Dictionary) -> void:
	root = String(d.get("root", path.get_base_dir()))
	if not (root.begins_with("res://") or root.begins_with("user://") or root.begins_with("/")):
		root = path.get_base_dir().path_join(root).simplify_path()
	var src: Dictionary = d.get("sounds", {})
	for id in src:
		var e: Variant = src[id]
		if not e is Dictionary:
			continue
		var slots: Variant = e.get("slots", [])
		if slots is Array and not slots.is_empty():
			for k in slots:
				var one: Dictionary = _substitute(e, String(k))
				one.erase("slots")
				one["slot"] = String(k)
				sounds["%s:%s" % [id, k]] = _defaults(String(id), one)
		else:
			sounds[String(id)] = _defaults(String(id), e)
	signals = d.get("signals", {})
	hails = d.get("hails", {})
	course = d.get("course", {})
	ambience = d.get("ambience", {})


## `<k>` replaced by the slot in every string of the entry
static func _substitute(v: Variant, k: String) -> Variant:
	if v is String:
		return v.replace("<k>", k)
	if v is Array:
		var a := []
		for x in v:
			a.append(_substitute(x, k))
		return a
	if v is Dictionary:
		var o := {}
		for key in v:
			o[key] = _substitute(v[key], k)
		return o
	return v


static func _defaults(id: String, e: Dictionary) -> Dictionary:
	var o := e.duplicate(true)
	o["id"] = id
	o["files"] = e.get("files", [])
	o["loop"] = bool(e.get("loop", false))
	o["bus"] = String(e.get("bus", "own_boat"))
	o["volume"] = float(e.get("volume", 1.0))
	o["space"] = String(e.get("space", "3d"))
	o["anchor"] = e.get("anchor", "mid")
	o["d_min"] = float(e.get("d_min", 10.0))
	for key in ["volume_terms", "pitch_terms"]:
		var terms := []
		for t in e.get(key, []):
			if t is Dictionary:
				terms.append(SoundFormula.norm_term(t))
		o[key] = terms
	return o


func has(id: String) -> bool:
	return sounds.has(id)


func entry(id: String) -> Dictionary:
	return sounds.get(id, {})


## The ids of the sounds whose id starts with `prefix`.
func ids(prefix := "") -> Array:
	var out := []
	for id in sounds:
		if String(id).begins_with(prefix):
			out.append(id)
	return out


## full path of a file name of the map
func resolve(file: String) -> String:
	if file.begins_with("res://") or file.begins_with("user://") or file.begins_with("/"):
		return file
	return root.path_join(file)


## The variants of a sound that load: [{file, stream, synth}] ([] when disabled). Resolved on first use.
func variants(id: String) -> Array:
	if _variants.has(id):
		return _variants[id]
	var out := []
	var e := entry(id)
	for f in e.get("files", []):
		var p := resolve(String(f))
		var s := stream_at(p, bool(e.get("loop", false)))
		if s != null:
			out.append({"file": p, "stream": s, "synth": ""})
	if out.is_empty() and SoundSynth.has_kind(String(e.get("synth", ""))):
		var kind := String(e["synth"])
		out.append({"file": "synth:" + kind, "stream": SoundSynth.stream(kind), "synth": kind})
	_variants[id] = out
	return out


## A random variant, never the same one twice in a row: {file, stream, synth}, {} when the sound is disabled.
func pick(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var v := variants(id)
	if v.is_empty():
		return {}
	if v.size() == 1:
		return v[0]
	var last := int(_last.get(id, -1))
	var i := rng.randi_range(0, v.size() - 2)
	if i >= last and last >= 0:
		i += 1
	_last[id] = i
	return v[i]


## The stream of a file (cached), null (and one warning) when it is missing or not audio.
func stream_at(p: String, loop: bool) -> AudioStream:
	if _files.has(p):
		return _files[p]
	var s: AudioStream = null
	if p.begins_with("res://"):
		if ResourceLoader.exists(p):
			s = load(p) as AudioStream
	elif FileAccess.file_exists(p):
		match p.get_extension().to_lower():
			"ogg":
				s = AudioStreamOggVorbis.load_from_file(p)
			"wav":
				s = AudioStreamWAV.load_from_file(p)
	if s == null:
		if not _warned.has(p):
			_warned[p] = true
			_warn("sound file %s missing: sound disabled" % p)
	else:
		_set_loop(s, loop)
	_files[p] = s
	return s


static func _set_loop(s: AudioStream, loop: bool) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = loop
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if loop and w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif not loop:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED


## The ambience bed streams in order (null for a missing one).
func bed_streams() -> Array:
	var out := []
	for f in ambience.get("beds", []):
		out.append(stream_at(resolve(String(f)), true))
	return out
