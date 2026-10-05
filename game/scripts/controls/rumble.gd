class_name Rumble
extends RefCounted
## Gamepad vibration (controls.md §6): a contact rumble of min(1, closing_speed / 2) for 0.2 s on the strong motor
## when the own boat's contact begins, and a light buzz (0.1) on the weak motor while let fly is on or the driving
## sail shivers (luff_shiver > 0.8), both scaled by the vibration setting (0 = off). tick() reads the sim after a
## tick, frame() drives the pads once per rendered frame.

const CONTACT_S := 0.2
const BUZZ := 0.1
const SHIVER := 0.8

## the vibration setting, 0..1 (Settings.vibration)
var strength := 1.0
## this frame's motor levels after the setting: weak (buzz), strong (contact)
var weak := 0.0
var strong := 0.0
## the pad devices to drive; empty: every connected pad
var devices: Array = []

var _contact := 0.0
var _contact_left := 0.0
var _shiver := false
var _was_on := false


## After a tick: the own boat's contact begins and its driving sail's shiver.
func tick(sim: SimSource, boat: int) -> void:
	for ev in sim.contact_events():
		if int(ev.get("boat", -1)) == boat and bool(ev.get("begin", false)):
			_contact = maxf(_contact if _contact_left > 0.0 else 0.0,
				minf(1.0, float(ev.get("closing_speed", 0.0)) / 2.0))
			_contact_left = CONTACT_S
	_shiver = false
	var sv := sim.sails(boat)
	if sv != null:
		for o in sv.out:
			if o != null and (o as SimSource.SailOutput).luff_shiver > SHIVER:
				_shiver = true


## One rendered frame: the levels and, with `active` (the player sails, not paused or watching), the pads.
func frame(dt: float, let_fly: bool, active := true) -> void:
	_contact_left = maxf(_contact_left - dt, 0.0)
	var s := clampf(strength, 0.0, 1.0) if active else 0.0
	strong = (_contact if _contact_left > 0.0 else 0.0) * s
	weak = (BUZZ if let_fly or _shiver else 0.0) * s
	_drive()


func _drive() -> void:
	var on := weak > 0.0 or strong > 0.0
	if not on and not _was_on:
		return
	var pads: Array = devices if not devices.is_empty() else Input.get_connected_joypads()
	for d in pads:
		if on:
			Input.start_joy_vibration(int(d), weak, strong, 0.1)
		else:
			Input.stop_joy_vibration(int(d))
	_was_on = on


func stop() -> void:
	weak = 0.0
	strong = 0.0
	_contact_left = 0.0
	_drive()
