class_name SimRunner
extends RefCounted
## Runs the simulation at its 50 ms tick from the rendered frame time: at each tick boundary the controls stamp
## the input frame for that tick (controls.md §1), then the sim steps. The render pose is interpolated between
## the last two ticks with alpha().

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


func _init(source: SimSource, player: PlayerControls, boat_index := 0) -> void:
	sim = source
	controls = player
	boat = boat_index


## Advances by the frame time; returns the number of ticks stepped.
func advance(dt: float) -> int:
	if paused:
		return 0
	_acc += dt
	var n := 0
	while not paused and _acc >= SimSource.DT - 1e-9 and n < MAX_TICKS_PER_FRAME:  # a tick may pause it
		step_tick()
		_acc -= SimSource.DT
		n += 1
	if n == MAX_TICKS_PER_FRAME:
		_acc = minf(_acc, SimSource.DT)
	return n


## One tick now: stamp, apply, step.
func step_tick() -> InputFrame:
	var f := controls.stamp(sim.tick()) if controls else InputFrame.new()
	sim.apply_input(boat, f)
	sim.step()
	if keep_frames > 0:
		frames.append(f)
		if frames.size() > keep_frames:
			frames.pop_front()
	ticked.emit(sim.tick())
	return f


func alpha() -> float:
	return clampf(_acc / SimSource.DT, 0.0, 1.0)
