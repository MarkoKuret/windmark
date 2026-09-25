class_name SailRequests
extends RefCounted
## controls.md §5.4: a sail key press, against the boat's sail state, to the sail request of the input frame.
## `F` is the front sail that is up, `S` the sail of the running change step.

const P := SimSource.Phase

## a press: slot index (0 = sail_1) or DROP
const DROP := -1


## The sail_req for a press (InputFrame.SAIL_*), or InputFrame.SAIL_NONE when the press matches no row.
static func map(press: int, sv: SimSource.SailsView, info: SimSource.ClassInfo) -> int:
	var f := sv.front
	if press == DROP:
		if not sv.busy():
			return InputFrame.SAIL_DROP_FRONT if f >= 0 else InputFrame.SAIL_NONE
		# cancel a first hoist (sails.md §4.2): nothing is up, a lone hoist of S is going up
		var r := sv.running()
		if f < 0 and _going_up(r) and _lone(sv, r.sail, [P.PREPARE_HOIST, P.HOISTING, P.UP]):
			return InputFrame.SAIL_DROP_FRONT
		return InputFrame.SAIL_NONE
	if press < 0 or press >= info.front_sails.size():
		return InputFrame.SAIL_NONE
	var x := info.front_sails[press]
	if not sv.busy():
		return InputFrame.SAIL_DROP_FRONT if x == f else InputFrame.hoist_req(x)
	var run := sv.running()
	var s := run.sail
	if _going_up(run) and s != f:
		if f >= 0 and (x == f or x == s):
			return InputFrame.hoist_req(f)  # cancels the hoist of S
		if f < 0 and x == s and _lone(sv, s, [P.PREPARE_HOIST, P.HOISTING, P.UP]):
			return InputFrame.SAIL_DROP_FRONT  # cancels a first hoist
	if x == s and (run.phase == P.PREPARE_DROP or run.phase == P.DROPPING) \
			and _lone(sv, s, [P.PREPARE_DROP, P.DROPPING, P.DOWN]):
		return InputFrame.hoist_req(s)  # cancels the drop
	return InputFrame.SAIL_NONE


static func _going_up(r: SimSource.SailStep) -> bool:
	return r != null and not r.reversed and (r.phase == P.PREPARE_HOIST or r.phase == P.HOISTING)


static func _lone(sv: SimSource.SailsView, sail: int, phases: Array) -> bool:
	if sv.queue_len != 3:
		return false
	for i in 3:
		var st: SimSource.SailStep = sv.queue[i]
		if st.sail != sail or st.phase != phases[i] or st.reversed:
			return false
	return true
