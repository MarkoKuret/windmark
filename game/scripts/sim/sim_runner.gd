class_name SimRunner
extends RefCounted
## Runs the simulation at its 50 ms tick from the rendered frame time: at each tick boundary the controls stamp
## the input frame for that tick (controls.md §1), then the sim steps. The render pose is interpolated between
## the last two ticks with alpha().
##
## Ticks ahead (controls.md §1.1, game/README.md "The simulation on a second core"): on a sim that steps on another
## thread (SimSource.can_step_async), prefetch() at the end of a frame (after the game's work, before the frame is
## drawn) stamps and starts the tick that the next frame would step, when the next frame, as long as this one,
## reaches the tick boundary. The tick then runs while the frame is drawn, and the next frame takes it in (settle(),
## or advance()) instead of stepping it. Inputs are stamped for the tick they are applied to and the ticks run one at
## a time in order, so the world steps exactly as without it; the input is only read up to one frame earlier.

signal ticked(tick: int)

const MAX_TICKS_PER_FRAME := 5

var sim: SimSource
var controls: PlayerControls
var boat := 0
## offline pause: no ticks (controls.md §7)
var paused := false
## the frames stamped so far (the newest last), for tests and replays
var frames: Array[InputFrame] = []
var keep_frames := 0
var _acc := 0.0
## the last frame's time (s), the estimate of the next one's
var _last_dt := 0.0
## the sim a tick was started ahead on, null when none runs
var _ahead: SimSource = null
var _ahead_frame: InputFrame = null


func _init(source: SimSource, player: PlayerControls, boat_index := 0) -> void:
	sim = source
	controls = player
	boat = boat_index


## Advances by the frame time; returns the number of ticks stepped (a tick started ahead counts).
func advance(dt: float) -> int:
	var n := settle()
	if paused:
		return n
	_acc += dt
	_last_dt = dt
	while not paused and _acc >= SimSource.DT - 1e-9 and n < MAX_TICKS_PER_FRAME:  # a tick may pause it
		step_tick()
		_acc -= SimSource.DT
		n += 1
	if n >= MAX_TICKS_PER_FRAME:
		_acc = minf(_acc, SimSource.DT)
	return n


## One tick now: stamp, apply, step.
func step_tick() -> InputFrame:
	settle()
	var f := controls.stamp(sim.tick()) if controls else InputFrame.new()
	sim.apply_input(boat, f)
	sim.step()
	_record(f)
	ticked.emit(sim.tick())
	return f


## Whether the next frame, as long as the last one, reaches the tick boundary.
func next_frame_ticks() -> bool:
	return not paused and _acc + _last_dt >= SimSource.DT - 1e-9


## At the end of a frame: starts the next tick on the sim's thread when the next frame will step it (this frame's
## time again reaches the tick boundary). True when a tick was started.
func prefetch() -> bool:
	if _ahead != null or paused or sim == null or not sim.can_step_async():
		return false
	if not next_frame_ticks():
		return false
	var f := controls.stamp(sim.tick()) if controls else InputFrame.new()
	sim.apply_input(boat, f)
	sim.step_begin()
	_ahead = sim
	_ahead_frame = f
	return true


## Takes in a tick started ahead (waits for it when it still runs): it counts as stepped now. Returns 1 when there
## was one, else 0.
func settle() -> int:
	if _ahead == null:
		return 0
	var s := _ahead
	var f := _ahead_frame
	_ahead = null
	_ahead_frame = null
	s.step_end()
	if s != sim:
		return 0  # the world was replaced meanwhile (a restart): its tick is gone with it
	_acc -= SimSource.DT
	_record(f)
	ticked.emit(sim.tick())
	return 1


func alpha() -> float:
	return clampf(_acc / SimSource.DT, 0.0, 1.0)


func _record(f: InputFrame) -> void:
	if keep_frames > 0:
		frames.append(f)
		if frames.size() > keep_frames:
			frames.pop_front()
