class_name PerfMonitor
extends CanvasLayer
## The frame-time overlay and its CSV log (hud.md §17). Add it to a scene (the sail scene does, with `scene` set to
## itself so the set-up columns can read its sea, sim and camera rig by name). Shift+F9 shows and hides the panel
## (F9 alone is the look panel, LookPanel, which has a row for it too);
## `log_path` writes one line per second; `seconds` > 0 ends the run after that long (quits the game when
## `quit_when_done`). It measures only while the panel is shown or a log is open.

signal finished

const TOGGLE_KEY := KEY_F9
## the window of the 1 % worst frame time
const WINDOW_S := 5.0

const COLUMNS := ["time_s", "frames", "fps", "frame_ms", "frame_max_ms", "frame_p99_ms", "process_ms", "physics_ms",
	"render_cpu_ms", "setup_cpu_ms", "gpu_ms", "gpu_other_ms", "draw_calls", "primitives", "objects",
	"input_ms", "sim_ms", "sim_max_ms", "hud_ms", "audio_ms", "sails_ms", "boats_ms", "wakes_ms", "sea_ms",
	"course_ms", "camera_ms", "render_scale", "render_w", "render_h", "window_w", "window_h", "upscaler",
	"quality", "boats", "camera", "renderer", "driver", "vsync", "max_fps", "video_mem_mb", "main_ms", "rest_ms"]

## the scene whose `sea`, `sim` and `rig` the set-up columns read (duck typed); may be null
var scene: Node = null
## the panel is shown
var overlay := false
## "" = no log; absolute, user:// or relative to the shell's working directory
var log_path := ""
## > 0: finish after this many seconds
var seconds := 0.0
var quit_when_done := true
## the last full second (column -> value), empty before the first
var last := {}
## lines written to the log
var lines := 0

var _panel: PanelContainer
var _label: Label
var _file: FileAccess
var _start_us := 0
var _second_us := 0
var _frames: Array = []  # [t_us, frame_ms] over the last WINDOW_S
var _sum := {}
var _n := 0
var _frame_max := 0.0
var _sim_max := 0.0
var _subs: Array = []  # other viewports measured (RIDs)
var _done := false
## the start of this frame's process step (µs), stamped by the first node to process (_Stamp)
static var _process_start_us := 0
var _stamp: Node


## Stamps the start of the frame's process step: it processes before every other node.
class _Stamp extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -1000000

	func _process(_dt: float) -> void:
		PerfMonitor._process_start_us = Time.get_ticks_usec()


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after the scene's own frame work
	_panel = PanelContainer.new()
	_panel.name = "PerfPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.name = "PerfText"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.9))
	_label.text = "measuring..."
	_panel.add_child(_label)
	_stamp = _Stamp.new()
	_stamp.name = "PerfStamp"
	get_tree().root.add_child.call_deferred(_stamp)
	_start_us = Time.get_ticks_usec()
	_second_us = _start_us
	if log_path != "":
		open_log(log_path)
	_panel.visible = overlay
	_update_measuring()


func _exit_tree() -> void:
	close_log()
	if is_instance_valid(_stamp):
		_stamp.queue_free()
	PerfStats.enabled = false


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == TOGGLE_KEY \
			and (e as InputEventKey).shift_pressed:
		toggle()


func toggle() -> void:
	overlay = not overlay
	_panel.visible = overlay
	_update_measuring()


func measuring() -> bool:
	return overlay or _file != null


func _update_measuring() -> void:
	var on := measuring()
	PerfStats.enabled = on
	PerfStats.take()
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), on)
	for rid in _subs:
		RenderingServer.viewport_set_measure_render_time(rid, on)
	_reset_second(Time.get_ticks_usec())


## A path from the command line: user:// and absolute as they are, anything else relative to the shell's working
## directory (Godot runs in the project folder).
static func resolve_path(p: String) -> String:
	if p.begins_with("user://") or p.begins_with("res://") or p.is_absolute_path():
		return p
	var pwd := OS.get_environment("PWD")
	return pwd.path_join(p) if pwd != "" else p


func open_log(p: String) -> bool:
	close_log()
	var full := resolve_path(p)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	_file = FileAccess.open(full, FileAccess.WRITE)
	if _file == null:
		push_warning("perf log: cannot write %s (%s)" % [full, error_string(FileAccess.get_open_error())])
		return false
	_file.store_line(",".join(COLUMNS))
	_file.flush()
	return true


func close_log() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


func _reset_second(now: int) -> void:
	_second_us = now
	_sum = {}
	_n = 0
	_frame_max = 0.0
	_sim_max = 0.0


func _add(k: String, v: float) -> void:
	_sum[k] = float(_sum.get(k, 0.0)) + v


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if not measuring():
		_check_done(now)
		return
	var root := get_tree().root
	var frame_ms := delta * 1000.0
	_frames.append([now, frame_ms])
	while not _frames.is_empty() and now - int(_frames[0][0]) > int(WINDOW_S * 1e6):
		_frames.pop_front()
	_n += 1
	_frame_max = maxf(_frame_max, frame_ms)
	_add("frame_ms", frame_ms)
	# the main thread's process step (every node's _process, the game's work) and the rest of the frame (physics,
	# the renderer's CPU work on the main thread and any wait for the GPU)
	var main := float(now - _process_start_us) * 0.001 if _process_start_us > 0 else 0.0
	_add("main_ms", main)
	_add("rest_ms", maxf(frame_ms - main, 0.0))
	_add("process_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("physics_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var rid := root.get_viewport_rid()
	_add("render_cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(rid))
	_add("setup_cpu_ms", RenderingServer.get_frame_setup_time_cpu())
	_add("gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(rid))
	var other := 0.0
	for s in _subs:
		other += RenderingServer.viewport_get_measured_render_time_gpu(s)
	_add("gpu_other_ms", other)
	_add("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_add("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var sec := PerfStats.take()
	for k in PerfStats.SECTIONS:
		_add(String(k) + "_ms", float(sec.get(k, 0)) * 0.001)
	_sim_max = maxf(_sim_max, float(sec.get(&"sim", 0)) * 0.001)
	if now - _second_us >= 1000000:
		_close_second(now)
	_check_done(now)


## One second's means (and the set-up) into `last`, the log and the panel.
func _close_second(now: int) -> void:
	var el := float(now - _second_us) * 1e-6
	var d := {}
	d["time_s"] = snappedf(float(now - _start_us) * 1e-6, 0.01)
	d["frames"] = _n
	d["fps"] = snappedf(_n / el, 0.1) if el > 0.0 else 0.0
	for k in _sum:
		d[k] = snappedf(float(_sum[k]) / maxi(_n, 1), 0.001)
	d["draw_calls"] = roundi(d.get("draw_calls", 0.0))
	d["primitives"] = roundi(d.get("primitives", 0.0))
	d["objects"] = roundi(d.get("objects", 0.0))
	d["frame_max_ms"] = snappedf(_frame_max, 0.001)
	d["frame_p99_ms"] = snappedf(worst_1pct(_frames.map(func(f: Array) -> float: return f[1])), 0.001)
	d["sim_max_ms"] = snappedf(_sim_max, 0.001)
	d.merge(setup_columns(), true)
	d["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	last = d
	if _file != null:
		var row := PackedStringArray()
		for c in COLUMNS:
			row.append(str(d.get(c, "")))
		_file.store_line(",".join(row))
		_file.flush()
		lines += 1
	if overlay:
		_label.text = text(d)
	_find_viewports()
	_reset_second(now)


## The 99th percentile of the frame times (the 1 % worst frame time).
static func worst_1pct(times: Array) -> float:
	if times.is_empty():
		return 0.0
	var s := times.duplicate()
	s.sort()
	return float(s[clampi(ceili(0.99 * s.size()) - 1, 0, s.size() - 1)])


## The other viewports (the wake normal buffer and any other SubViewport) have their GPU time measured too.
func _find_viewports() -> void:
	var rids: Array = []
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		rids.append((n as Viewport).get_viewport_rid())
	for rid in rids:
		if not _subs.has(rid):
			RenderingServer.viewport_set_measure_render_time(rid, true)
	_subs = rids


## The render scale, sizes, tier, boats, camera, renderer, vsync and frame rate limit.
func setup_columns() -> Dictionary:
	var root := get_tree().root
	var sc := root.scaling_3d_scale
	var d := {
		"render_scale": snappedf(sc, 0.01), "render_w": roundi(root.size.x * sc), "render_h": roundi(root.size.y * sc),
		"window_w": root.size.x, "window_h": root.size.y,
		"upscaler": Settings.upscaler_name(root.scaling_3d_mode) if sc < 1.0 else "none",
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"max_fps": Engine.max_fps, "quality": "", "boats": 0, "camera": "",
	}
	if scene != null:
		var sea: Variant = scene.get("sea")
		if sea is Sea:
			d["quality"] = SeaQuality.get_tier((sea as Sea).quality)["name"]
		var sim: Variant = scene.get("sim")
		if sim is SimSource:
			d["boats"] = (sim as SimSource).boat_count()
		var rig: Variant = scene.get("rig")
		if rig is CameraRig:
			d["camera"] = String(CameraRig.Mode.keys()[(rig as CameraRig).mode]).to_lower()
	return d


## The panel's text for one second's values.
static func text(d: Dictionary) -> String:
	var l := PackedStringArray()
	l.append("FPS %.0f   frame %.1f ms avg   %.1f ms 1%% worst (%.0f s)   max %.1f" % [d.get("fps", 0.0),
		d.get("frame_ms", 0.0), d.get("frame_p99_ms", 0.0), WINDOW_S, d.get("frame_max_ms", 0.0)])
	l.append("CPU process %.2f ms   render %.2f ms   setup %.2f ms   GPU %.2f ms (+ %.2f other views)" % [
		d.get("process_ms", 0.0), d.get("render_cpu_ms", 0.0), d.get("setup_cpu_ms", 0.0), d.get("gpu_ms", 0.0),
		d.get("gpu_other_ms", 0.0)])
	l.append("draw calls %d   primitives %s   objects %d" % [d.get("draw_calls", 0),
		_count(d.get("primitives", 0)), d.get("objects", 0)])
	l.append("3D %d x %d (%d %%, %s)   window %d x %d   tier %s   boats %d   %s / %s   vsync %s   limit %s" % [
		d.get("render_w", 0), d.get("render_h", 0), roundi(float(d.get("render_scale", 1.0)) * 100.0),
		d.get("upscaler", ""), d.get("window_w", 0), d.get("window_h", 0), d.get("quality", ""), d.get("boats", 0),
		d.get("renderer", ""), d.get("driver", ""), "on" if d.get("vsync", false) else "off",
		str(d.get("max_fps", 0)) if int(d.get("max_fps", 0)) > 0 else "off"])
	var s := PackedStringArray()
	for k in PerfStats.SECTIONS:
		s.append("%s %.2f" % [k, d.get(String(k) + "_ms", 0.0)])
	l.append("ms per frame: " + "  ".join(s) + "   (sim max %.2f)" % d.get("sim_max_ms", 0.0))
	return "\n".join(l)


static func _count(n: int) -> String:
	if n >= 1000000:
		return "%.2f M" % (n / 1e6)
	if n >= 1000:
		return "%.1f k" % (n / 1e3)
	return str(n)


func _check_done(now: int) -> void:
	if _done or seconds <= 0.0 or float(now - _start_us) * 1e-6 < seconds:
		return
	_done = true
	close_log()
	finished.emit()
	if quit_when_done:
		get_tree().quit()
