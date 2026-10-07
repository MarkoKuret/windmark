class_name GameAudio
extends Node3D
## The race's sound (audio.md): boat sounds from the sound map on every boat (§3), the wind at the listener (§4),
## the race signals and events (§5), the ambience beds and one-shots (§6) and the course objects (§7), on the
## buses of §1.1 (AudioBuses). Presentation only: it reads the sim and never writes to it.
##
## A scene calls setup(sim, boat_nodes, viewed) once (boat_nodes: the BoatView of each boat, drawn at the render
## pose; the boat sounds hang under them at their boat-frame anchors), tick() after every sim step (the boat
## inputs, triggers, contacts, other boats' finishes, countdown beeps), frame(dt, camera, onboard) every frame (gates,
## formulas, smoothing, voices, wind pan, ambience, ducking), and connects Hud.hud_event to on_hud_event (signals,
## own penalty and penalty done, rule warnings, the own finish). `viewed` is the boat on own_boat, `paused` ducks
## for the pause menu, `countdown_beeps` is the Full assist's countdown.
##
## Voices (§1): at most `max_voices` players at once, by priority: the viewed boat and the listener's sounds, then
## the race sounds, then other boats and course objects by distance. Other boats get their full set within
## FULL_RANGE and only the wake and collisions beyond; only the MAX_OTHER nearest are voiced. `played` logs every
## one-shot (id, file, boat, space, t) for the tests. Headless the players are not started (`audible`).
##
## Rates (audio.md §1): the formulas, gates, voice choice, ducking and the players' positions and buses at
## PARAM_HZ; every frame only the smoothing toward those targets and the players' volume and pitch when they moved.

const MAX_VOICES := 48
const MAX_OTHER := 6
const FULL_RANGE := 150.0
const FAR_SOUNDS := ["boat.wake"]
const TAU := 0.1
const SILENT := 0.01
const SIGNAL_GAP := 0.8
const SIGNAL_D_MIN := 150.0
const SIGNAL_DUCK_DB := -6.0
const SIGNAL_DUCK_S := 1.5
const PAUSE_DUCK_DB := -12.0
const HAIL_COOLDOWN := 4.0
const BED_TAU := 10.0
const AMB_EVERY := Vector2(20.0, 60.0)
const AMB_DIST := 30.0
const BEEPS := [30.0, 20.0, 10.0, 5.0, 4.0, 3.0, 2.0, 1.0]
const WIND_PAN := 0.6
const PLAYED_MAX := 2000
## the formulas' rate (audio.md §1 updates), Hz
const PARAM_HZ := 30.0
## a player's volume and pitch are set again when they move more than this (dB, ratio)
const SET_DB := 0.05
const SET_PITCH := 0.001
const SIGNAL_NAMES := {
	RaceText.SignalKind.WARNING: "warning",
	RaceText.SignalKind.PREP_UP: "prep_up",
	RaceText.SignalKind.PREP_DOWN: "prep_down",
	RaceText.SignalKind.START: "start",
	RaceText.SignalKind.GENERAL_RECALL: "general_recall",
	RaceText.SignalKind.X_UP: "x_up",
}
## WM_CONTACT_* -> the map's event name
const CONTACT_EVENTS := ["contact_boat", "contact_mark", "contact_mark", "contact_hard", "contact_hard"]
const MARK_BUOY := 0
const MARK_COMMITTEE := 1

var map: SoundMap
var sim: SimSource
var viewed := 0
var paused := false
var countdown_beeps := false
var max_voices := MAX_VOICES
## players really play; headless (no sound out) they are set up and tracked but not started, so a test run never
## leaves playbacks behind in the audio server at exit
var audible := DisplayServer.get_name() != "headless"
var rng := RandomNumberGenerator.new()
## seconds of audio time (the sum of the frames' dt)
var time := 0.0
var played: Array = []

var _boats: Array = []  # BoatSlot per boat
var _listener_loops: Array = []  # Voice: wind
var _beds: Array = []  # Voice per ambience bed
var _course_loops: Array = []  # Voice per course object
var _one_shots: Array = []  # {player, end, priority}
var _queue: Array = []  # {t, id, opts}
var _boat_loop_ids: Array = []
var _boat_trigger_ids: Array = []
var _listener_pos := Vector3.ZERO
var _cam := {"cam_height": 2.0, "cam_onboard": 0.0, "cam_wind": 0.8}
var _bed_kn := NAN
var _committee := Vector3.ZERO
var _has_committee := false
var _duck_until := -INF
var _duck_amb := 0.0
var _duck_pause := 0.0
var _pan := 0.0
var _next_amb := 0.0
var _last_race_time := NAN
var _hail_t := {}
var _furling := {}  # class id -> {sail id: furling}
var _k := 1.0  # the frame's smoothing weight (TAU)
var _cands: Array = []  # the boat loops that want to sound or still play, this frame
## time since the last formula update (s), INF: due at the next frame
var _param_t := INF
## the loops driven between formula updates: the candidates of the last one
var _driven: Array = []


## A looping sound of a boat, the listener or a course object.
class Voice:
	var id := ""
	var e := {}
	var boat := -1
	var gate: SoundFormula.Gate = null
	var player: Node = null
	var active := false
	var want := false
	var disabled := false
	var vol := 0.0
	var pitch := 1.0
	var synth := ""
	var file := ""
	var priority := 0.0
	var bus := ""
	## world position (scene) for sources not on a boat
	var pos := Vector3.ZERO
	## the targets of the last formula update (volume, pitch)
	var tv := 0.0
	var tp := 1.0
	## what the player was last given
	var set_db := INF
	var set_pitch := -1.0

	func _init(sound_id: String, entry: Dictionary, b := -1) -> void:
		id = sound_id
		e = entry
		boat = b
		bus = String(entry.get("bus", "own_boat"))
		if entry.has("gate") and entry["gate"] is Dictionary:
			gate = SoundFormula.Gate.new(entry["gate"])


## One boat: its inputs, loops, triggers and anchors.
class BoatSlot:
	var node: Node3D = null
	var own_node := false
	var audio: Node3D = null
	var inputs: BoatSoundInputs
	var loops := {}  # id -> Voice
	var triggers := {}  # id -> SoundFormula.Trigger
	var anchors := {}  # anchor name -> model-space point
	var sail_names := []
	var main_name := ""
	var kite_winch := Vector3.ZERO
	var contact_pos := Vector3.ZERO
	var rub_tick := -100
	var rub_v := 0.0
	## 0 own, 1 full set, 2 wake and collisions only, 3 silent
	var mode := 3
	var dist := 0.0
	## mode 3 and every loop already silenced
	var quiet := false


func setup(s: SimSource, nodes: Array = [], view := 0, m: SoundMap = null) -> void:
	AudioBuses.ensure()
	sim = s
	viewed = view
	map = m if m != null else SoundMap.load_file()
	if map == null:
		return
	_boat_loop_ids.clear()
	_boat_trigger_ids.clear()
	for id in map.ids("boat."):
		var e := map.entry(id)
		if e.has("trigger"):
			_boat_trigger_ids.append(id)
		elif bool(e["loop"]):
			_boat_loop_ids.append(id)
	set_boats(nodes)
	_build_listener()
	_build_course()
	_next_amb = time + rng.randf_range(AMB_EVERY.x, AMB_EVERY.y)


## A new sim (a restarted race) and its boat nodes; the map stays.
func restart(s: SimSource, nodes: Array = []) -> void:
	sim = s
	_last_race_time = NAN
	_queue.clear()
	if map == null:
		return
	set_boats(nodes)
	_build_course()


## The boat nodes (after the scene rebuilt its boat views); a missing node gets one of its own at the render pose.
func set_boats(nodes: Array) -> void:
	for slot in _boats:
		for v in slot.loops.values():
			_free_voice(v)
		if slot.own_node and is_instance_valid(slot.node):
			slot.node.queue_free()
		elif is_instance_valid(slot.audio):
			slot.audio.queue_free()
	_boats.clear()
	_driven.clear()
	_param_t = INF
	if sim == null or map == null:
		return
	for b in sim.boat_count():
		var slot := BoatSlot.new()
		var info := sim.class_info(b)
		if b < nodes.size() and nodes[b] is Node3D and is_instance_valid(nodes[b]):
			slot.node = nodes[b]
		else:
			slot.node = Node3D.new()
			slot.node.name = "BoatSound%d" % b
			slot.own_node = true
			add_child(slot.node)
		slot.audio = Node3D.new()
		slot.audio.name = "Audio"
		slot.node.add_child(slot.audio)
		_set_anchors(slot, info)
		var bow: float = slot.anchors.get("_bow_x", 3.0)
		slot.inputs = BoatSoundInputs.new(bow, _class_furling(info))
		for id in _boat_loop_ids:
			slot.loops[id] = Voice.new(id, map.entry(id), b)
		for id in _boat_trigger_ids:
			slot.triggers[id] = SoundFormula.Trigger.new(map.entry(id)["trigger"])
		_boats.append(slot)


func _class_furling(info: SimSource.ClassInfo) -> Dictionary:
	if info == null:
		return {}
	if not _furling.has(info.id):
		var f := {}
		var p := BoatClassData.repo_path("data/classes/%s.boat.json" % info.id)
		if FileAccess.file_exists(p):
			var cls: Variant = BoatClassData._read_json(p)
			if cls is Dictionary:
				for cs in cls.get("sails", []):
					f[String(cs.get("id", ""))] = bool(cs.get("furling", false))
		_furling[info.id] = f
	return _furling[info.id]


static func _v3(a: Variant, fallback: Vector3) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## audio.md §9 anchors from the physics sidecar (boat frame), stored in model space.
func _set_anchors(slot: BoatSlot, info: SimSource.ClassInfo) -> void:
	var loa := info.loa if info != null and info.loa > 0.0 else 7.0
	var lwl := info.lwl if info != null and info.lwl > 0.0 else 0.9 * loa
	var ph: Dictionary = info.physics if info != null else {}
	var rig: Dictionary = ph.get("rig", {})
	var sails: Dictionary = ph.get("sails", {})
	var body := {
		"bow": Vector3(0.5 * lwl, 0.0, 0.2),
		"stern": Vector3(-0.5 * lwl, 0.0, 0.2),
		"mid": Vector3(0.0, 0.0, 0.1),
		"masthead": _v3(rig.get("masthead"), Vector3(0.0, 0.0, 1.4 * loa)),
		"mast_foot": _v3(rig.get("mast_step"), Vector3(0.0, 0.0, 1.0)),
		"boom_pivot": _v3(rig.get("boom_pivot"), Vector3(0.0, 0.0, 1.5)),
		"forestay_tack": _v3(rig.get("forestay_tack"), Vector3(0.45 * loa, 0.0, 0.8)),
	}
	var leads: Dictionary = rig.get("sheet_leads", {})
	body["winch:front"] = _v3(leads.get("headsail", {}).get("winch"), Vector3(-0.25 * loa, -0.8, 0.6))
	var kite: Vector3 = _v3(leads.get("flying", {}).get("winch"), body["winch:front"])
	var boom_len := float(rig.get("boom_length", 0.4 * loa))
	body["winch:main"] = body["boom_pivot"] + Vector3(-0.7 * boom_len, 0.0, -0.8)
	if info != null:
		for si in info.sails:
			slot.sail_names.append(si.name)
			var sd: Dictionary = sails.get(si.name, {})
			body["sail:" + si.name] = _v3(sd.get("centroid"), body["boom_pivot"] + Vector3(0.0, 0.0, 0.3 * loa))
		if info.main_sail >= 0 and info.main_sail < info.sails.size():
			slot.main_name = info.sails[info.main_sail].name
	for k in body:
		slot.anchors[k] = Frames.body_to_model(body[k])
	slot.kite_winch = Frames.body_to_model(kite)
	slot.anchors["_bow_x"] = 0.5 * lwl


## model-space position of an anchor on a boat (Vector3.INF: the contact point, in the world)
func _anchor(slot: BoatSlot, a: Variant) -> Vector3:
	if a is Array:
		return Frames.body_to_model(_v3(a, Vector3.ZERO))
	var s := String(a)
	var inp: Dictionary = slot.inputs.inputs
	match s:
		"contact":
			return Vector3.INF
		"sail:main":
			return slot.anchors.get("sail:" + slot.main_name, slot.anchors["mid"])
		"sail:front", "sail:change":
			var i := int(inp.get("front_index" if s == "sail:front" else "change_index", -1))
			if i >= 0 and i < slot.sail_names.size():
				return slot.anchors.get("sail:" + String(slot.sail_names[i]), slot.anchors["mid"])
			return slot.anchors["forestay_tack"]
		"winch:front":
			return slot.kite_winch if float(inp.get("sail.front.kite", 0.0)) > 0.5 else slot.anchors["winch:front"]
	return slot.anchors.get(s, slot.anchors["mid"])


func _build_listener() -> void:
	for v in _listener_loops + _beds:
		_free_voice(v)
	_listener_loops.clear()
	_beds.clear()
	for id in map.ids("wind."):
		var e := map.entry(id)
		if bool(e["loop"]):
			var v := Voice.new(id, e)
			v.priority = 0.5
			_listener_loops.append(v)
	var files: Array = map.ambience.get("beds", [])
	for i in files.size():
		var e := {"files": [files[i]], "loop": true, "bus": "ambience", "space": "2d",
			"volume": float(map.ambience.get("volume", 0.4))}
		var v := Voice.new("amb.bed%d" % i, e)
		v.priority = 0.5
		_beds.append(v)


## audio.md §7 course objects: a buoy sound on every buoy, the committee sound on the committee boat.
func _build_course() -> void:
	for v in _course_loops:
		_free_voice(v)
	_course_loops.clear()
	_has_committee = false
	if sim == null or not sim.has_race():
		return
	var c := sim.course()
	for m in c.get("marks", []):
		var t := int(m.get("type", -1))
		var pos := Frames.enu_to_scene(float(m.get("x", 0.0)), float(m.get("y", 0.0)), 0.5)
		if t == MARK_COMMITTEE and not _has_committee:
			_has_committee = true
			_committee = pos + Vector3(0.0, 2.5, 0.0)
		var id := String(map.course.get("buoy" if t == MARK_BUOY else "committee" if t == MARK_COMMITTEE else "", ""))
		if id != "" and map.has(id):
			var v := Voice.new(id, map.entry(id))
			v.pos = pos
			_course_loops.append(v)


## After every sim step.
func tick() -> void:
	if map == null or sim == null:
		return
	if _boats.size() != sim.boat_count():
		set_boats([])
	for b in _boats.size():
		var slot: BoatSlot = _boats[b]
		if slot.mode == 3 and b != viewed:
			if not slot.inputs.is_reset():  # unvoiced: no inputs; the rates and crossings start over when voiced
				slot.inputs.reset()
				for tr in slot.triggers.values():
					tr.reset()
			continue
		slot.inputs.update(sim, b)
	_contacts()
	for b in _boats.size():
		var slot: BoatSlot = _boats[b]
		if slot.mode == 3 and b != viewed:
			continue
		for id in _boat_trigger_ids:
			var tr: SoundFormula.Trigger = slot.triggers[id]
			if tr.kind == "event":
				continue
			if tr.update(slot.inputs.inputs, time) and slot.mode <= 1:
				_trigger_play(id, b, slot.inputs.inputs)
	_race_tick()


func _trigger_play(id: String, b: int, inputs: Dictionary, at: Variant = null) -> void:
	var e := map.entry(id)
	var gain := float(e["volume"]) * SoundFormula.value(e["volume_terms"], inputs)
	play(id, {"boat": b, "gain": gain, "at": at if at != null else e.get("anchor", "mid"),
		"priority": 0.0 if b == viewed else 2.0 + _boats[b].dist / 1000.0})


## collisions.md §5 contact events: a begin fires the contact triggers, a continued contact drives boat.rub.
func _contacts() -> void:
	var n := sim.tick()
	for ev in sim.contact_events():
		var b := int(ev.get("boat", -1))
		if b < 0 or b >= _boats.size():
			continue
		var slot: BoatSlot = _boats[b]
		var kind := int(ev.get("other_kind", 0))
		var other := int(ev.get("other", -1)) if kind == 0 else -1
		var p: Vector2 = ev.get("point", Vector2.ZERO)
		var pos := Frames.enu_to_scene(p.x, p.y, sim.sea_height(p.x, p.y) + 0.5)
		slot.contact_pos = pos
		if other >= 0 and other < _boats.size():
			_boats[other].contact_pos = pos
		if bool(ev.get("begin", false)):
			var inp: Dictionary = slot.inputs.inputs.duplicate()
			inp["closing_speed"] = float(ev.get("closing_speed", 0.0))
			var name: String = CONTACT_EVENTS[clampi(kind, 0, CONTACT_EVENTS.size() - 1)]
			for id in _boat_trigger_ids:
				var tr: SoundFormula.Trigger = slot.triggers[id]
				if tr.event == name and tr.on_event(inp, time):
					var own := b == viewed or other == viewed
					if own or slot.mode <= 2 or (other >= 0 and _boats[other].mode <= 2):
						var e := map.entry(id)
						var gain := float(e["volume"]) * SoundFormula.value(e["volume_terms"], inp)
						play(id, {"boat": viewed if own and b != viewed else b, "gain": gain, "at": pos,
							"priority": 0.0 if own else 2.0 + slot.dist / 1000.0})
		else:
			var s := sim.state(b)
			var v_rel := absf(s.v) if s != null else 0.0
			if other >= 0 and s != null:
				var so := sim.state(other)
				if so != null:
					v_rel = (Vector2(sin(s.psi), cos(s.psi)) * s.v - Vector2(sin(so.psi), cos(so.psi)) * so.v).length()
			slot.rub_tick = n
			slot.rub_v = v_rel
	for slot in _boats:
		slot.inputs.inputs["rub_v"] = slot.rub_v if n - slot.rub_tick <= 2 else 0.0


## Other boats' finishes (3-D at the committee boat) and the countdown beeps.
func _race_tick() -> void:
	if not sim.has_race():
		return
	for ev in sim.race_events():
		if int(ev.get("kind", -1)) == RaceText.Ev.FINISHED and int(ev.get("boat", -1)) != viewed and _has_committee:
			play("race.horn_finish", {"space": "3d", "at": _committee, "d_min": SIGNAL_D_MIN, "priority": 1.0})
	var r := sim.race()
	var rt := float(r.get("race_time", NAN))
	if countdown_beeps and int(r.get("state", -1)) == RaceText.RaceState.SEQUENCE and not is_nan(_last_race_time):
		for m in BEEPS:
			if _last_race_time < -m and rt >= -m:
				play("race.beep", {"priority": 1.0})
	_last_race_time = rt


## Hud.hud_event: signals, the own penalty and penalty done, rule warnings, the own finish.
func on_hud_event(kind: String, d: Dictionary) -> void:
	if map == null:
		return
	match kind:
		"signal":
			race_signal(int(d.get("kind", -1)))
		"penalty":
			if int(d.get("boat", -1)) == viewed:
				play("race.penalty", {"priority": 1.0})
		"penalty_served":
			if int(d.get("boat", viewed)) == viewed:
				play("race.penalty_done", {"priority": 1.0})
		"finished":
			play("race.horn_finish", {"priority": 1.0})
			if _has_committee:
				play("race.horn_finish", {"space": "3d", "at": _committee, "d_min": SIGNAL_D_MIN, "priority": 1.0})
		"rule_warning":
			if int(d.get("holder", -1)) == viewed:
				_hail(int(d.get("rule", 0)))


## audio.md §5: a signal's sounds (count of them, SIGNAL_GAP apart), 2-D and at the committee boat; ducks the
## ambience.
func race_signal(kind: int) -> void:
	var nm: String = SIGNAL_NAMES.get(kind, "")
	var sig: Variant = map.signals.get(nm, null)
	if nm == "" or not sig is Array or sig.is_empty():
		return
	var id := String(sig[0])
	var count := int(sig[1]) if sig.size() > 1 else 1
	for i in count:
		if i == 0:
			_signal_sound(id)
		else:
			_queue.append({"t": time + i * SIGNAL_GAP, "id": id})
	_duck_until = time + SIGNAL_DUCK_S + (count - 1) * SIGNAL_GAP


func _signal_sound(id: String) -> void:
	play(id, {"priority": 1.0})
	if _has_committee:
		play(id, {"space": "3d", "at": _committee, "d_min": SIGNAL_D_MIN, "priority": 1.0})


func _hail(rule: int) -> void:
	var code: String = RaceText.RULE_CODES[rule] if rule >= 0 and rule < RaceText.RULE_CODES.size() else ""
	var id := String(map.hails.get(code, ""))
	if id == "" or not map.has(id):
		return
	if time - float(_hail_t.get(code, -INF)) < HAIL_COOLDOWN:
		return
	_hail_t[code] = time
	play(id, {"boat": viewed, "at": map.entry(id).get("anchor", "mid"), "bus": "voice", "priority": 0.0})


## Plays a one-shot. opts: boat (-1: none), at (an anchor of the boat, or a scene position), gain (default the
## entry's volume), space ("2d"/"3d", default the entry's), d_min, bus, priority (lower wins). Returns whether it
## plays: not when the sound is disabled, silent, or every voice is taken by a higher priority.
func play(id: String, opts := {}) -> bool:
	if map == null or not map.has(id):
		return false
	var e := map.entry(id)
	var gain := float(opts.get("gain", e["volume"]))
	if gain <= SILENT:
		return false
	var prio := float(opts.get("priority", 1.0))
	if active_voices() >= max_voices and not _make_room(prio):
		return false
	var pick := map.pick(id, rng)
	if pick.is_empty():
		return false
	var b := int(opts.get("boat", -1))
	var space := String(opts.get("space", e["space"]))
	var at: Variant = opts.get("at", e.get("anchor", "mid"))
	var player: Node
	if space == "3d" and (b >= 0 or at is Vector3):
		var p3 := _player3d(float(opts.get("d_min", e["d_min"])))
		if at is Vector3 or b < 0 or b >= _boats.size():
			add_child(p3)
			p3.top_level = true
			p3.global_position = at if at is Vector3 else _listener_pos
		else:
			var slot: BoatSlot = _boats[b]
			var local := _anchor(slot, at)
			if local == Vector3.INF:
				add_child(p3)
				p3.top_level = true
				p3.global_position = slot.contact_pos
			else:
				slot.audio.add_child(p3)
				p3.position = local
		p3.volume_db = linear_to_db(gain)
		player = p3
	else:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		p2.volume_db = linear_to_db(gain)
		player = p2
		space = "2d"
	var bus := String(opts.get("bus", ""))
	if bus == "":
		bus = (("own_boat" if b == viewed else "fleet") if b >= 0 and String(e["bus"]) in ["own_boat", "fleet"]
			else String(e["bus"]))
	player.set("bus", bus)
	player.set("stream", pick["stream"])
	if audible:
		player.call("play")
	var length: float = pick["stream"].get_length()
	_one_shots.append({"player": player, "end": time + (length if length > 0.0 else 1.0) + 0.05, "priority": prio})
	played.append({"id": id, "file": String(pick["file"]), "boat": b, "space": space, "t": time, "bus": bus})
	if played.size() > PLAYED_MAX:
		played.remove_at(0)
	return true


## Stops the active loop of lowest priority when it is lower than prio (a larger number).
func _make_room(prio: float) -> bool:
	var worst: Voice = null
	for v in _all_loops():
		if v.active and v.priority > prio and (worst == null or v.priority > worst.priority):
			worst = v
	if worst == null:
		return false
	_stop(worst)
	return true


## Every frame after the ticks and the camera: the formula update at PARAM_HZ, the smoothing every frame.
func frame(dt: float, cam: Camera3D = null, onboard := false) -> void:
	if map == null or sim == null:
		return
	time += dt
	_k = Frames.smooth_k(dt, TAU)
	while not _queue.is_empty() and float(_queue[0]["t"]) <= time + 1e-6:
		_signal_sound(String(_queue.pop_front()["id"]))
	_param_t += dt
	if _param_t + 1e-6 < 1.0 / PARAM_HZ:
		for v in _driven:
			_drive(v, v.tv, v.tp)
			if v.active:
				_set_level(v)
		return
	var pdt := dt if is_inf(_param_t) else _param_t
	_param_t = 0.0
	_update(pdt, cam, onboard)


## The formula update: listener, gates, formulas, targets, voices, ducking; `dt` the time since the last one.
func _update(dt: float, cam: Camera3D, onboard: bool) -> void:
	_cands.clear()
	_listener_pos = cam.global_position if cam != null else (
		_boats[viewed].node.global_position if viewed < _boats.size() else Vector3.ZERO)
	var enu := Frames.scene_to_enu(_listener_pos)
	var cam_h := enu.z - sim.sea_height(enu.x, enu.y)
	_cam["cam_height"] = cam_h
	_cam["cam_onboard"] = 1.0 if onboard else 0.0
	_cam["cam_wind"] = 1.0 if onboard else clampf(1.0 - (cam_h - 5.0) / 200.0, 0.4, 0.8)
	_boat_voices(dt)
	_listener_voices(dt, cam, onboard)
	for v in _course_loops:
		var d: float = v.pos.distance_to(_listener_pos)
		_drive(v, float(v.e["volume"]) if d < 50.0 * float(v.e["d_min"]) else 0.0, 1.0)
		v.priority = 2.0 + d / 1000.0
	_ambience_one_shot()
	_expire_one_shots()
	_allocate()
	_ducking(dt)
	_driven = _cands + _listener_loops + _beds + _course_loops


func _boat_voices(dt: float) -> void:
	var others := []
	for b in _boats.size():
		var slot: BoatSlot = _boats[b]
		if slot.own_node:
			var p := sim.render_pose(b, 1.0)
			if p != null:
				slot.node.transform = Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
		slot.dist = slot.node.global_position.distance_to(_listener_pos)
		if b != viewed:
			others.append(b)
	var dist := PackedFloat32Array()
	for b in others:
		_boats[b].mode = 3
		dist.append(_boats[b].dist)
	for i in SeaWakes.nearest(dist, MAX_OTHER, INF):
		var slot: BoatSlot = _boats[others[i]]
		slot.mode = 1 if slot.dist <= FULL_RANGE else 2
	if viewed >= 0 and viewed < _boats.size():
		_boats[viewed].mode = 0
	for b in _boats.size():
		var slot: BoatSlot = _boats[b]
		if slot.mode == 3:
			if not slot.quiet:
				for v in slot.loops.values():
					v.vol = 0.0
					v.want = false
					if v.active:
						_stop(v)
				slot.quiet = true
			continue
		slot.quiet = false
		var inp: Dictionary = slot.inputs.inputs
		for k in _cam:
			inp[k] = _cam[k]
		var own := b == viewed
		var bus := "own_boat" if own else "fleet"
		var prio := 0.0 if own else 2.0 + slot.dist / 1000.0
		for id in _boat_loop_ids:
			var v: Voice = slot.loops[id]
			v.bus = bus
			v.priority = prio
			if slot.mode == 2 and not id in FAR_SOUNDS:
				v.vol = 0.0
				v.tv = 0.0
				v.want = false
				if v.active:
					_cands.append(v)
				continue
			var open := v.gate.update(inp, dt) if v.gate != null else true
			if not open and not v.active and v.vol <= SILENT:
				v.want = false  # closed and silent: nothing to evaluate
				continue
			var tv := float(v.e["volume"]) * SoundFormula.value(v.e["volume_terms"], inp) if open else 0.0
			var tp := 1.0
			if not v.e["pitch_terms"].is_empty():
				tp = SoundFormula.value(v.e["pitch_terms"], inp)
			if v.synth != "":
				tp *= SoundSynth.pitch_factor(v.synth, inp)
			_drive(v, tv, tp)
			_cands.append(v)


## smooth toward the target volume and pitch (the frame's weight _k); wants a player while audible. The targets
## stay for the frames until the next formula update.
func _drive(v: Voice, tv: float, tp: float) -> void:
	v.tv = tv
	v.tp = tp
	if not v.active and v.vol <= SILENT:
		v.pitch = tp  # a loop starting from silence fades in at its current pitch
	v.vol += (tv - v.vol) * _k
	v.pitch += (tp - v.pitch) * _k
	v.want = v.vol > SILENT and not v.disabled


func _listener_voices(dt: float, cam: Camera3D, onboard: bool) -> void:
	var inp: Dictionary = _boats[viewed].inputs.inputs if viewed >= 0 and viewed < _boats.size() else _cam
	for k in _cam:
		inp[k] = _cam[k]
	for v in _listener_loops:
		var tv := float(v.e["volume"]) * SoundFormula.value(v.e["volume_terms"], inp)
		var tp := SoundFormula.value(v.e["pitch_terms"], inp) * SoundSynth.pitch_factor(v.synth, inp)
		_drive(v, tv, tp)
	# audio.md §4 pan: onboard, the ear facing the apparent wind
	var pan := 0.0
	if onboard and cam != null and viewed < sim.boat_count():
		var s := sim.state(viewed)
		if s != null:
			var right := cam.global_basis.x
			right.y = 0.0
			if right.length() > 1e-3:
				pan = WIND_PAN * Frames.compass_dir(s.awd_from).dot(right.normalized())
	_pan = SoundFormula.smooth(_pan, pan, dt, TAU)
	AudioBuses.set_wind_pan(_pan)
	# audio.md §6 beds by the smoothed true wind
	var tws := float(inp.get("tws_kn", 0.0))
	_bed_kn = tws if is_nan(_bed_kn) else SoundFormula.smooth(_bed_kn, tws, dt, BED_TAU)
	var w := SoundFormula.bed_weights(_bed_kn, map.ambience.get("bounds_kn", [6, 14, 22]),
		float(map.ambience.get("crossfade_kn", 2.0)))
	for i in _beds.size():
		var v: Voice = _beds[i]
		_drive(v, float(v.e["volume"]) * (w[i] if i < w.size() else 0.0), 1.0)


func _ambience_one_shot() -> void:
	if time < _next_amb:
		return
	_next_amb = time + rng.randf_range(AMB_EVERY.x, AMB_EVERY.y)
	var ids: Array = map.ambience.get("one_shots", [])
	if ids.is_empty():
		return
	var id := String(ids[rng.randi_range(0, ids.size() - 1)])
	var a := rng.randf_range(0.0, TAU)
	var pos := _listener_pos + Vector3(cos(a), 0.0, sin(a)) * AMB_DIST
	var e := map.entry(id)
	play(id, {"space": "3d", "at": pos, "d_min": AMB_DIST, "priority": 1.5,
		"gain": float(e.get("volume", 1.0)) * rng.randf_range(0.3, 0.6)})


func _expire_one_shots() -> void:
	var keep := []
	for o in _one_shots:
		if time >= float(o["end"]) or not is_instance_valid(o["player"]):
			if is_instance_valid(o["player"]):
				o["player"].queue_free()
		else:
			keep.append(o)
	_one_shots = keep


func _all_loops() -> Array:
	var out := _listener_loops + _beds + _course_loops
	for slot in _boats:
		out.append_array(slot.loops.values())
	return out


## audio.md §1 voices: the loops that want to sound, by priority, within what the one-shots leave.
func _allocate() -> void:
	var want := []
	for v in _cands + _listener_loops + _beds + _course_loops:
		if v.want:
			want.append(v)
		elif v.active:
			_stop(v)
	want.sort_custom(func(x: Voice, y: Voice) -> bool: return x.priority < y.priority)
	var budget := max_voices - _one_shots.size()
	for i in want.size():
		var v: Voice = want[i]
		if i >= budget:
			if v.active:
				_stop(v)
			continue
		if not v.active:
			_start(v)
		if v.active:
			_update_player(v)


func _start(v: Voice) -> void:
	var pick := map.pick(v.id, rng) if map.has(v.id) else _pick_entry(v)
	if pick.is_empty():
		v.disabled = true
		v.want = false
		return
	v.synth = String(pick["synth"])
	v.file = String(pick["file"])
	if v.player == null:
		if String(v.e["space"]) == "3d":
			var p3 := _player3d(float(v.e["d_min"]))
			if v.boat >= 0 and v.boat < _boats.size() and String(v.e.get("anchor", "")) != "contact":
				_boats[v.boat].audio.add_child(p3)
			else:
				add_child(p3)
				p3.top_level = true
			v.player = p3
		else:
			var p2 := AudioStreamPlayer.new()
			add_child(p2)
			v.player = p2
	v.player.set("stream", pick["stream"])
	v.active = true
	v.set_db = INF
	v.set_pitch = -1.0
	_update_player(v)
	var length: float = pick["stream"].get_length()
	if audible:
		v.player.call("play", rng.randf_range(0.0, length) if length > 0.0 else 0.0)


## ambience beds are not map sounds: their files come from the map's ambience block
func _pick_entry(v: Voice) -> Dictionary:
	var files: Array = v.e.get("files", [])
	if files.is_empty():
		return {}
	var s := map.stream_at(map.resolve(String(files[0])), true)
	return {} if s == null else {"file": map.resolve(String(files[0])), "stream": s, "synth": ""}


## the player's volume and pitch, set only when they moved (between formula updates)
func _set_level(v: Voice) -> void:
	var db := linear_to_db(maxf(v.vol, 1e-4))
	if absf(db - v.set_db) > SET_DB:
		v.set_db = db
		v.player.set("volume_db", db)
	var pitch := clampf(v.pitch, 0.5, 2.0)
	if absf(pitch - v.set_pitch) > SET_PITCH:
		v.set_pitch = pitch
		v.player.set("pitch_scale", pitch)


func _update_player(v: Voice) -> void:
	var p := v.player
	_set_level(v)
	p.set("bus", v.bus)
	if p is AudioStreamPlayer3D:
		var p3 := p as AudioStreamPlayer3D
		if v.boat >= 0 and v.boat < _boats.size():
			var slot: BoatSlot = _boats[v.boat]
			var local := _anchor(slot, v.e.get("anchor", "mid"))
			if local == Vector3.INF:
				p3.global_position = slot.contact_pos
			else:
				p3.position = local
		else:
			p3.global_position = v.pos


func _stop(v: Voice) -> void:
	if audible and v.player != null and is_instance_valid(v.player):
		v.player.call("stop")
	v.active = false


func _free_voice(v: Voice) -> void:
	if v.player != null and is_instance_valid(v.player):
		v.player.queue_free()
	v.player = null
	v.active = false


static func _player3d(d_min: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = d_min
	p.max_distance = 50.0 * d_min
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_db = 0.0
	p.attenuation_filter_db = 0.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	return p


## audio.md §1.1: a signal ducks ambience and venue by 6 dB for 1.5 s; the pause ducks all but ambience and ui.
func _ducking(dt: float) -> void:
	_duck_amb = SoundFormula.smooth(_duck_amb, SIGNAL_DUCK_DB if time < _duck_until else 0.0, dt, TAU)
	_duck_pause = SoundFormula.smooth(_duck_pause, PAUSE_DUCK_DB if paused else 0.0, dt, TAU)
	for bus in AudioBuses.NAMES:
		var db := 0.0
		if not bus in ["ambience", "ui"]:
			db += _duck_pause
		if bus in ["ambience", "venue"]:
			db += _duck_amb
		AudioBuses.set_duck(bus, db)


func _exit_tree() -> void:
	for bus in AudioBuses.NAMES:
		AudioBuses.set_duck(bus, 0.0)
	AudioBuses.set_wind_pan(0.0)


# ---- test readers ----

## players sounding now: active loops and one-shots
func active_voices() -> int:
	var n := _one_shots.size()
	for v in _all_loops():
		if v.active:
			n += 1
	return n


## the ids of a boat's active loops
func active_loops(b: int) -> Array:
	var out := []
	if b >= 0 and b < _boats.size():
		for v in _boats[b].loops.values():
			if v.active:
				out.append(v.id)
	return out


## the ids of a boat's loops that want to sound
func wanted_loops(b: int) -> Array:
	var out := []
	if b >= 0 and b < _boats.size():
		for v in _boats[b].loops.values():
			if v.want:
				out.append(v.id)
	return out


## a listener loop, bed ("amb.bed<i>") or course voice by id: {active, vol, pitch, file}
func voice_state(id: String, b := -1) -> Dictionary:
	var src: Array = _all_loops() if b < 0 else _boats[b].loops.values()
	for v in src:
		if v.id == id:
			return {"active": v.active, "want": v.want, "vol": v.vol, "pitch": v.pitch, "file": v.file,
				"bus": v.bus}
	return {}
