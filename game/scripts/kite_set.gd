class_name KiteSet
extends RefCounted
## The kite set parameters of docs/specs/sail_visuals.md §4.1: per spinnaker, the class file's
## `visual.sails.<id>.set` block over the defaults of its type, which the flying shape (SailShape, native and
## reference) reads at set-up. The table here is the GDScript one (BoatView, SailShapeRef, the kite tuner, the
## tests); game/native/src/sail_shape.cpp and tools/boatgen/boatgen/sail_set.py hold the same defaults and
## tools/boatgen/boatgen/classfile.py the same ranges. Presentation only: nothing in the core reads them.

const DEG := PI / 180.0

## every key in tuner order: [key, group, label, unit ("" share, "deg" an angle in rad shown in degrees),
## min, max, step, kinds ("" both, "asym", "sym", "pole": only a kite on a pole)]
const PARAMS := [
	["depth_peak_h", "Depth", "Deepest at height", "", 0.1, 0.9, 0.01, ""],
	["depth_foot", "Depth", "Foot depth", "", 0.0, 1.5, 0.01, ""],
	["depth_head", "Depth", "Head depth", "", 0.0, 1.5, 0.01, ""],
	["draft_low", "Draft", "Draft, lower sail", "", 0.25, 0.75, 0.005, ""],
	["draft_head", "Draft", "Draft at the head", "", 0.25, 0.75, 0.005, ""],
	["draft_from_h", "Draft", "Draft moves aft from", "", 0.0, 0.95, 0.01, ""],
	["belly_aft", "Belly", "Belly blown aft", "", 0.0, 2.0, 0.01, ""],
	["belly_up", "Belly", "Belly lifted", "", 0.0, 2.0, 0.01, ""],
	["twist_exp", "Twist", "Twist profile", "", 0.5, 5.0, 0.05, ""],
	["twist_awa_lo", "Twist", "Twist starts at AWA", "deg", 20.0 * DEG, 150.0 * DEG, 1.0 * DEG, "asym"],
	["twist_awa_hi", "Twist", "Full twist from AWA", "deg", 40.0 * DEG, 180.0 * DEG, 1.0 * DEG, "asym"],
	["twist_run", "Twist", "Twist fades before run", "deg", 3.0 * DEG, 60.0 * DEG, 1.0 * DEG, "asym"],
	["foot_sag", "Foot", "Foot sag", "", 0.0, 1.0, 0.01, ""],
	["foot_sag_h", "Foot", "Sag reaches up to", "", 0.05, 0.9, 0.01, ""],
	["girth_foot", "Girth", "Girth at the foot", "", 0.6, 1.4, 0.01, ""],
	["girth_mid", "Girth", "Girth at mid height", "", 0.6, 1.4, 0.01, ""],
	["girth_head", "Girth", "Girth at the head", "", 0.6, 1.4, 0.01, ""],
	["luff_curl", "Edges", "Luff curl", "", -1.0, 1.0, 0.01, ""],
	["leech_curl", "Edges", "Leech curl", "", -1.0, 1.0, 0.01, ""],
	["head_drop", "Corners", "Head eased down", "", 0.0, 0.15, 0.002, ""],
	["clew_lift", "Corners", "Clew raised", "", -0.3, 0.3, 0.005, ""],
	["clew_out", "Corners", "Clew let out", "", -0.3, 0.3, 0.005, ""],
	["clew_h", "Corners", "Clew moves reach up to", "", 0.05, 0.8, 0.01, ""],
	["tack_rise", "Corners", "Tack raised", "", 0.0, 0.15, 0.002, ""],
	["forward", "Forward", "Projected forward", "", -0.1, 0.3, 0.005, ""],
	["stay_clear", "Forward", "Ahead of the forestay", "", 0.0, 1.0, 0.01, "pole"],
	["stay_width", "Forward", "Forestay half width", "", 0.1, 1.5, 0.01, "pole"],
	["stay_head", "Forward", "Stay shift fades over top", "", 0.05, 0.9, 0.01, "pole"],
	["stay_luff", "Forward", "Stay shift full from chord", "", 0.05, 0.95, 0.01, "pole"],
	["stay_leech", "Forward", "Stay shift lost at leech", "", 0.0, 1.0, 0.01, "pole"],
]

## the look keys (§4) the tuner edits with the set: [key, group, label, unit, min, max, step]
const LOOK_PARAMS := [
	["camber", "Depth", "Camber (deepest row)", "", 0.05, 0.45, 0.005],
	["twist_top", "Twist", "Twist at the head", "deg", 0.0, 50.0 * DEG, 0.5 * DEG],
]

const _COMMON := {"draft_from_h": 0.55, "belly_aft": 0.5, "belly_up": 0.5, "twist_awa_lo": 60.0 * DEG,
	"twist_awa_hi": 130.0 * DEG, "twist_run": 25.0 * DEG, "foot_sag_h": 0.35, "girth_foot": 1.0, "girth_mid": 1.0,
	"girth_head": 1.0, "luff_curl": 0.0, "leech_curl": 0.0, "head_drop": 0.0, "clew_lift": 0.0, "clew_out": 0.0,
	"clew_h": 0.3, "forward": 0.0, "tack_rise": 0.0, "stay_clear": 0.25, "stay_width": 0.6, "stay_head": 0.3,
	"stay_luff": 0.5, "stay_leech": 0.3}


## The defaults of a kite type (`spinnaker_asym` or `spinnaker_sym`); {} for any other sail.
static func defaults(sail_type: String) -> Dictionary:
	var d := {}
	if sail_type == "spinnaker_asym":
		d = _COMMON.duplicate()
		d.merge({"depth_peak_h": 0.3, "depth_foot": 0.8, "depth_head": 0.45, "draft_low": pow(0.5, 1.0 / 0.8),
			"draft_head": pow(0.5, 1.0 / 1.4), "twist_exp": 2.5, "foot_sag": 0.0}, true)
	elif sail_type == "spinnaker_sym":
		d = _COMMON.duplicate()
		d.merge({"depth_peak_h": 0.5, "depth_foot": 1.0, "depth_head": 0.7, "draft_low": 0.5, "draft_head": 0.5,
			"twist_exp": 1.5, "foot_sag": 0.35}, true)
	return d


## The kite's parameters: `given` (a class file's or sidecar's set block) over the defaults of its type, every key
## a float; unknown keys are left out.
static func resolve(sail_type: String, given: Variant) -> Dictionary:
	var d := defaults(sail_type)
	if given is Dictionary:
		for k in given:
			if d.has(k) and (given[k] is float or given[k] is int):
				d[k] = float(given[k])
	return d


static func is_kite(sail_type: String) -> bool:
	return sail_type == "spinnaker_asym" or sail_type == "spinnaker_sym"


## The class file's `visual.sails.<id>` entry, {} when there is none.
static func class_entry(cls: Variant, sail_id: String) -> Dictionary:
	if not cls is Dictionary:
		return {}
	var v: Variant = (cls as Dictionary).get("visual", {})
	if not v is Dictionary:
		return {}
	var s: Variant = (v as Dictionary).get("sails", {})
	if not s is Dictionary:
		return {}
	var e: Variant = (s as Dictionary).get(sail_id, {})
	return e if e is Dictionary else {}
