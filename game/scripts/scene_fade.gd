class_name SceneFade
extends CanvasLayer
## menus.md §5 fades: a scene change fades to navy over 0.35 s, changes the scene and fades the new one in over
## 0.45 s. The fade lives on the tree's root (not in the scene), so it outlives the change; the input is ignored
## while the screen is dark. change() falls back to a plain change outside a tree.

const COLOUR := Color("0b1620")
const OUT_S := 0.35
const IN_S := 0.45

## the fade in progress (one at a time), null without one
static var running: SceneFade = null

var path := ""
var rect: ColorRect
var _t := 0.0
var _phase := 0  # 0 out, 1 changed (one frame to settle), 2 in


## Fades out, changes the tree's scene to `path`, fades in. A second call while one runs does nothing.
static func change(tree: SceneTree, to_path: String) -> void:
	if tree == null:
		return
	if running != null and is_instance_valid(running):
		return
	var f := SceneFade.new()
	f.path = to_path
	running = f
	tree.root.add_child(f)


## The same for reloading the scene that is running.
static func reload(tree: SceneTree) -> void:
	var cs := tree.current_scene if tree != null else null
	if cs != null and cs.scene_file_path != "":
		change(tree, cs.scene_file_path)
	elif tree != null:
		tree.reload_current_scene()


func _ready() -> void:
	name = "SceneFade"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.color = Color(COLOUR, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rect)


func _process(dt: float) -> void:
	_t += minf(dt, 0.1)
	match _phase:
		0:
			rect.color.a = clampf(_t / OUT_S, 0.0, 1.0)
			if _t >= OUT_S:
				_phase = 1
				_t = 0.0
				get_tree().change_scene_to_file(path)
		1:
			rect.color.a = 1.0
			if _t > 0.0:
				_phase = 2
				_t = 0.0
		2:
			rect.color.a = 1.0 - clampf(_t / IN_S, 0.0, 1.0)
			if _t >= IN_S:
				running = null
				queue_free()


func _input(_e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
