class_name SoundFormula
extends RefCounted
## The formula language of audio.md §2: terms (clamped power laws of one input), their product, gates with a hold
## time and triggers with a cooldown, plus the ambience bed crossfade (§6) and the smoothing of §1. Inputs are a
## Dictionary input name -> float; an input that is not there reads 0.


## A term with every key and its default: in ("one"), c (0), k (1), p (1), lo (-INF), hi (INF). SoundMap stores
## its terms this way, so term() reads them without defaults.
static func norm_term(t: Dictionary) -> Dictionary:
	return {"in": String(t.get("in", "one")), "c": float(t.get("c", 0.0)), "k": float(t.get("k", 1.0)),
		"p": float(t.get("p", 1.0)), "lo": float(t.get("lo", -INF)), "hi": float(t.get("hi", INF))}


## term(in) = clamp(c + k * pow(fabs(x), p), lo, hi), on a normalised term (norm_term); the input "one" is 1
static func term(t: Dictionary, inputs: Dictionary) -> float:
	var name: String = t["in"]
	var x := 1.0 if name == "one" else absf(float(inputs.get(name, 0.0)))
	var p: float = t["p"]
	return clampf(t["c"] + t["k"] * (x if p == 1.0 else pow(x, p)), t["lo"], t["hi"])


## the product of the (normalised) terms, 1 without any
static func value(terms: Array, inputs: Dictionary) -> float:
	var v := 1.0
	for t in terms:
		v *= term(t, inputs)
	return v


## One condition {in, above | below | equals (a number or a list)}.
static func holds_one(c: Dictionary, inputs: Dictionary) -> bool:
	var x := float(inputs.get(String(c.get("in", "")), 0.0))
	if c.has("above") and not (x > float(c["above"])):
		return false
	if c.has("below") and not (x < float(c["below"])):
		return false
	if c.has("equals"):
		var e: Variant = c["equals"]
		if e is Array:
			var any := false
			for v in e:
				any = any or is_equal_approx(x, float(v))
			return any
		return is_equal_approx(x, float(e))
	return true


## every condition holds
static func holds(conds: Array, inputs: Dictionary) -> bool:
	for c in conds:
		if not holds_one(c, inputs):
			return false
	return true


## A gate's conditions: {"all": [...]} or the gate itself as one condition.
static func gate_conditions(g: Dictionary) -> Array:
	if g.has("all"):
		return g["all"]
	return [g]


## audio.md §1: exponential smoothing toward x with time constant tau
static func smooth(y: float, x: float, dt: float, tau: float) -> float:
	return y + (x - y) * Frames.smooth_k(dt, tau)


## audio.md §6: the weights of the ambience beds (bounds between them, crossfade width) at wind w
static func bed_weights(w: float, bounds: Array, xfade: float) -> PackedFloat32Array:
	var n := bounds.size() + 1
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var up := 1.0  # fades in above the lower bound
		var down := 1.0  # fades out above the upper bound
		if i > 0:
			up = clampf((w - (float(bounds[i - 1]) - 0.5 * xfade)) / maxf(xfade, 1e-6), 0.0, 1.0)
		if i < n - 1:
			down = 1.0 - clampf((w - (float(bounds[i]) - 0.5 * xfade)) / maxf(xfade, 1e-6), 0.0, 1.0)
		out[i] = up * down
	return out


## audio.md §2 gate: opens once its condition has held for hold_s, closes once it has failed for hold_s.
class Gate:
	var conds: Array = []
	var hold := 0.0
	var open := false
	var _pending := false
	var _t := 0.0

	func _init(g: Dictionary = {}) -> void:
		conds = SoundFormula.gate_conditions(g) if not g.is_empty() else []
		hold = float(g.get("hold_s", 0.0))

	func update(inputs: Dictionary, dt: float) -> bool:
		var c := SoundFormula.holds(conds, inputs)
		if c == open:
			_pending = false
			return open
		if not _pending:
			_pending = true
			_t = 0.0
		else:
			_t += dt
		if _t >= hold - 1e-6:
			open = c
			_pending = false
		return open


## audio.md §2 trigger: a crossing, a sign change, a from/to change of a value, or an event; `when` conditions
## and a cooldown (a trigger inside the cooldown of the last play is dropped).
class Trigger:
	var input := ""
	var kind := ""  # rises, falls, sign, from_to, event
	var event := ""
	var x := 0.0
	var a := 0.0
	var b := 0.0
	var when: Array = []
	var cooldown := 0.0
	var _prev := NAN
	var _last := -INF

	func _init(t: Dictionary = {}) -> void:
		input = String(t.get("in", ""))
		when = t.get("when", [])
		cooldown = float(t.get("cooldown_s", 0.0))
		if t.has("event"):
			kind = "event"
			event = String(t["event"])
		elif t.has("rises_above"):
			kind = "rises"
			x = float(t["rises_above"])
		elif t.has("falls_below"):
			kind = "falls"
			x = float(t["falls_below"])
		elif t.has("changes_sign"):
			kind = "sign"
		elif t.has("from") and t.has("to"):
			kind = "from_to"
			a = float(t["from"])
			b = float(t["to"])

	## a value trigger at time t (s): true when it fires
	func update(inputs: Dictionary, t: float) -> bool:
		if kind == "event" or kind == "":
			return false
		var v := float(inputs.get(input, 0.0))
		var crossed := false
		if not is_nan(_prev):
			match kind:
				"rises":
					crossed = _prev <= x and v > x
				"falls":
					crossed = _prev >= x and v < x
				"sign":
					crossed = _prev != 0.0 and v != 0.0 and (_prev < 0.0) != (v < 0.0)
				"from_to":
					crossed = is_equal_approx(_prev, a) and is_equal_approx(v, b)
		_prev = v
		return crossed and _fire(inputs, t)

	## an event trigger at time t (the event's values in inputs)
	func on_event(inputs: Dictionary, t: float) -> bool:
		return kind == "event" and _fire(inputs, t)

	func _fire(inputs: Dictionary, t: float) -> bool:
		if not SoundFormula.holds(when, inputs):
			return false
		if t - _last < cooldown - 1e-6:
			return false
		_last = t
		return true

	func reset() -> void:
		_prev = NAN
		_last = -INF
