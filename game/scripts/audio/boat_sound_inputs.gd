class_name BoatSoundInputs
extends RefCounted
## The inputs of audio.md §2 for one boat, read once per tick from the sim's records (rates are the change over the
## tick). `inputs` is the Dictionary the formulas read; the camera inputs (cam_height, cam_onboard, cam_wind) are
## written by GameAudio every frame. Sail slots: main, front (the front sail that is up), change (the front sail of
## the running change step) and every sail by id; a slot without a sail reads 0.

const KN := 1.0 / 0.514444
const DT := SimSource.DT
const SAIL_KEYS := ["luff", "motion", "beta", "beta_rate", "phase", "progress", "kite", "furling"]

var inputs := {"one": 1.0}
## body-frame x of the bow end of the waterline, m (anchors and bow_dz)
var bow_x := 3.0
## sail id -> furling (class file)
var furling := {}

var _first := true
var _bow_rel := 0.0
var _h := 0.0
var _beta := {}  # sail index -> beta at the last tick


func _init(bow := 3.0, furl := {}) -> void:
	bow_x = bow
	furling = furl


## Forget the last tick (the rates start over at the next update).
func reset() -> void:
	_first = true
	_beta.clear()


func is_reset() -> bool:
	return _first


## The tick's values from the sim.
func update(sim: SimSource, b: int) -> void:
	var s := sim.state(b)
	if s == null:
		return
	var o := sim.outputs(b)
	inputs["v_kn"] = s.v * KN
	inputs["sog_kn"] = (o.sog if o != null else s.v) * KN
	inputs["aws"] = s.aws
	inputs["tws"] = s.tws
	inputs["aws_kn"] = s.aws * KN
	inputs["tws_kn"] = s.tws * KN
	inputs["awa_abs"] = absf(s.awa)
	inputs["heel_abs"] = absf(s.phi)
	inputs["pitch_rate"] = s.theta_rate
	inputs["helm_abs"] = absf(s.h)
	# the bow point against the sea under it
	var bow := Frames.boat_transform(s.pos_x, s.pos_y, s.z, s.psi, s.theta, s.phi) * Frames.body_to_model(
		Vector3(bow_x, 0.0, 0.0))
	var enu := Frames.scene_to_enu(bow)
	var rel := enu.z - sim.sea_height(enu.x, enu.y)
	inputs["helm_rate"] = 0.0 if _first else absf(s.h - _h) / DT
	inputs["bow_dz"] = 0.0 if _first else (rel - _bow_rel) / DT
	_bow_rel = rel
	_h = s.h
	_sails(sim, b)
	_first = false


func _sails(sim: SimSource, b: int) -> void:
	var sv := sim.sails(b)
	var info := sim.class_info(b)
	if sv == null or info == null:
		return
	var rates := {}
	for i in mini(sv.sails.size(), sv.out.size()):
		var beta := sv.sails[i].beta
		rates[i] = 0.0 if _first or not _beta.has(i) else absf(beta - float(_beta[i])) / DT
		_beta[i] = beta
		if i < info.sails.size():
			_slot(info.sails[i].name, sv, info, i, rates[i])
	var change := -1
	var step := sv.running()
	if step != null and step.sail != info.main_sail:
		change = step.sail
	_slot("main", sv, info, info.main_sail, rates.get(info.main_sail, 0.0))
	_slot("front", sv, info, sv.front, rates.get(sv.front, 0.0))
	_slot("change", sv, info, change, rates.get(change, 0.0))
	inputs["front_index"] = sv.front
	inputs["change_index"] = change


func _slot(k: String, sv: SimSource.SailsView, info: SimSource.ClassInfo, i: int, rate: float) -> void:
	var p := "sail.%s." % k
	if i < 0 or i >= sv.sails.size() or i >= sv.out.size() or i >= info.sails.size():
		for key in SAIL_KEYS:
			inputs[p + key] = 0.0
		return
	var st: SimSource.SailState = sv.sails[i]
	var out: SimSource.SailOutput = sv.out[i]
	var si: SimSource.SailInfo = info.sails[i]
	inputs[p + "luff"] = out.luff_shiver
	inputs[p + "motion"] = float(out.motion)
	inputs[p + "beta"] = st.beta
	inputs[p + "beta_rate"] = rate
	inputs[p + "phase"] = float(st.phase)
	inputs[p + "progress"] = st.progress
	inputs[p + "kite"] = 1.0 if si.type.begins_with("spinnaker") else 0.0
	inputs[p + "furling"] = 1.0 if bool(furling.get(si.name, false)) else 0.0
