class_name SceneFade
extends CanvasLayer
## menus.md §5 fades: a scene change fades to navy over 0.35 s, changes the scene and fades the new one in over
## 0.45 s. The fade lives on the tree's root (not in the scene), so it outlives the change; the input is ignored
## while the screen is dark. change() falls back to a plain change outside a tree.
##
## The loading line (menus.md §5): when the build is expected to take longer than LINE_AFTER_S (the last build of
## the same scene file in this session did, or it has not been built yet), `line` shows centred on the navy for
## LINE_FRAMES frames before the change, so it is on the screen while the main thread builds. The warm-up: after the
## change the navy stays opaque while the new scene draws under it with a ShaderWarmup's copies in front of its
## cameras, at least WARM_MIN_FRAMES frames and then until a frame adds no mesh, surface or draw pipeline compilation
## (the specialisations compile in the background without a stutter), at most WARM_MAX_S.
## `--fade-log` prints each change's measures (`last`).

const COLOUR := Color("0b1620")
const OUT_S := 0.35
const IN_S := 0.45
## the loading line: shown when the build is expected to take longer than this (s), drawn on this many frames
## before the change; Barlow Semi Condensed Medium 22 px, the cloth at 55 % (menus.md §5)
const LINE_AFTER_S := 0.3
const LINE_FRAMES := 2
const LINE_SIZE := 22
const LINE_COLOUR := Color(0.957, 0.945, 0.910, 0.55)
const LINE_MENU := "Back to the menu"
const LINE_SCENARIO := "Setting up the scenario"
## the warm-up under the opaque navy: at least this many frames, the copies on the first WARM_COPY_FRAMES of them,
## at most this long (s)
const WARM_MIN_FRAMES := 3
const WARM_COPY_FRAMES := 2
const WARM_MAX_S := 1.0
const PIPELINE_INFOS := [
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
]

enum Phase { OUT, LINE, WARM, IN }

## the fade in progress (one at a time), null without one
static var running: SceneFade = null
## the last build of each scene file this session, s (the loading line's guess)
static var build_s := {}
## the last change's measures: path, line_shown, build_ms, warm_frames, warm_ms, copies, and the pipeline
## compilations (mesh, surface, draw, specialization) under the navy (`warm_pipelines`) and during the fade in
## (`in_pipelines`)
static var last := {}

var path := ""
## the loading line ("": none)
var line := ""
var rect: ColorRect
var label: Label
var warmup: ShaderWarmup
var _t := 0.0
var _phase := Phase.OUT
var _frames := 0
var _t0 := 0
var _warm_t0 := 0
var _built := false
var _pipes: Array[int] = []
var _pipes_start: Array[int] = []


## Fades out, changes the tree's scene to `path`, fades in. `loading_line` is the loading line (menus.md §5). A
## second call while one runs does nothing.
static func change(tree: SceneTree, to_path: String, loading_line := "") -> void:
	if tree == null:
		return
	if running != null and is_instance_valid(running):
		return
	var f := SceneFade.new()
	f.path = to_path
	f.line = loading_line
	running = f
	tree.root.add_child(f)


## The same for reloading the scene that is running.
static func reload(tree: SceneTree, loading_line := "") -> void:
	var cs := tree.current_scene if tree != null else null
	if cs != null and cs.scene_file_path != "":
		change(tree, cs.scene_file_path, loading_line)
	elif tree != null:
		tree.reload_current_scene()


## The loading line of a session (menus.md §5): Setting up <venue> for a race, the venue's name for free sail.
static func line_for(g: GameSetup) -> String:
	if g == null:
		return ""
	if g.mode == "scenario":
		return LINE_SCENARIO
	var v := MenuData.venue_name(g.venue)
	return v if g.mode == "free" else "Setting up %s" % v


## Whether the build of `p` is expected to take longer than LINE_AFTER_S.
static func expect_long(p: String) -> bool:
	return not build_s.has(p) or float(build_s[p]) > LINE_AFTER_S


func _ready() -> void:
	name = "SceneFade"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.color = Color(COLOUR, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rect)
	label = Label.new()
	label.name = "Line"
	label.text = line
	label.visible = false
	label.add_theme_font_override("font", MenuTheme.font(500, 0.0, LINE_SIZE))
	label.add_theme_font_size_override("font_size", LINE_SIZE)
	label.add_theme_color_override("font_color", LINE_COLOUR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	last = {"path": path, "line_shown": false}
	if get_tree().has_signal("scene_changed"):
		get_tree().scene_changed.connect(_on_scene_changed)


func _process(dt: float) -> void:
	_t += minf(dt, 0.1)
	match _phase:
		Phase.OUT:
			rect.color.a = clampf(_t / OUT_S, 0.0, 1.0)
			if _t >= OUT_S:
				rect.color.a = 1.0
				if line != "" and expect_long(path):
					label.visible = true
					last["line_shown"] = true
					_phase = Phase.LINE
					_frames = 0
				else:
					_change()
		Phase.LINE:
			_frames += 1
			if _frames >= LINE_FRAMES:
				_change()
		Phase.WARM:
			_warm_frame()
		Phase.IN:
			var a := 1.0 - clampf(_t / IN_S, 0.0, 1.0)
			rect.color.a = a
			label.modulate.a = a
			if _t >= IN_S:
				last["in_pipelines"] = _diff(_pipelines(), _pipes_start)
				if "--fade-log" in OS.get_cmdline_user_args():
					print("scene fade: ", JSON.stringify(last))
				running = null
				queue_free()


## One frame of the warm-up: the copies on the first frames, then until a frame adds no pipeline compilation.
func _warm_frame() -> void:
	rect.color.a = 1.0
	if not _built:
		_on_scene_changed()
	_frames += 1
	if _frames == 1:
		warmup = ShaderWarmup.start(get_tree().current_scene)
		last["copies"] = warmup.copies.size()
	elif _frames == WARM_COPY_FRAMES + 1:
		warmup.finish()
	var now := _pipelines()
	var still := now.slice(0, 3) == _pipes.slice(0, 3)  # the specialisations compile in the background
	_pipes = now
	var warm_s := (Time.get_ticks_usec() - _warm_t0) / 1e6
	if (_frames >= WARM_MIN_FRAMES and still) or warm_s >= WARM_MAX_S:
		if warmup != null:
			warmup.finish()
		last["warm_frames"] = _frames
		last["warm_ms"] = warm_s * 1000.0
		last["warm_pipelines"] = _diff(now, _pipes_start)
		_pipes_start = now
		_phase = Phase.IN
		_t = 0.0


func _change() -> void:
	_phase = Phase.WARM
	_frames = 0
	_built = false
	_pipes_start = _pipelines()
	_pipes = _pipes_start
	_t0 = Time.get_ticks_usec()
	get_tree().change_scene_to_file(path)


## The new scene is in the tree (SceneTree.scene_changed, or the first warm frame): the build's time.
func _on_scene_changed() -> void:
	if _phase != Phase.WARM or _built:
		return
	_built = true
	var s := (Time.get_ticks_usec() - _t0) / 1e6
	build_s[path] = s
	last["build_ms"] = s * 1000.0
	_warm_t0 = Time.get_ticks_usec()


static func _pipelines() -> Array[int]:
	var out: Array[int] = []
	for i: int in PIPELINE_INFOS:
		out.append(RenderingServer.get_rendering_info(i))
	return out


static func _diff(a: Array[int], b: Array[int]) -> Dictionary:
	return {"mesh": a[0] - b[0], "surface": a[1] - b[1], "draw": a[2] - b[2], "specialization": a[3] - b[3]}


func _input(_e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
