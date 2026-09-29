class_name PerfStats
extends RefCounted
## The game's own per-frame sections (hud.md §17): callers time their work with Time.get_ticks_usec() and add
## it here; the PerfMonitor takes the frame's sums once per frame. Nothing is kept while no monitor measures.

## the sections, in the order the overlay and the log show them
const SECTIONS: Array[StringName] = [&"input", &"sim", &"hud", &"audio", &"sails", &"boats", &"wakes", &"sea",
	&"course", &"camera"]

## set by the PerfMonitor while it measures
static var enabled := false
static var _acc := {}


## Adds `usec` microseconds to a section of the current frame.
static func add(section: StringName, usec: int) -> void:
	if enabled:
		_acc[section] = int(_acc.get(section, 0)) + usec


## The sums since the last take (section -> µs), and a fresh frame.
static func take() -> Dictionary:
	var d := _acc
	_acc = {}
	return d
