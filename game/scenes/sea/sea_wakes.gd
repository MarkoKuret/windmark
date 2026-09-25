class_name SeaWakes
extends Node3D
## Bow waves, wakes and mist (water_render.md §5) for the boats in the scene, drawn on a Sea.
##
## Feed it every frame with update_boat(id, state) (the core binding or the placeholder sim source), where
## state holds the interpolated physics pose and the class dimensions:
##   x, y (m, world ENU), z (heave, m), psi (heading, rad), heel (rad), pitch (rad, + bow up),
##   lwl, bwl, transom_width (m), bow_x, stern_x (body x of the waterline ends, m), own (bool)
## and remove_boat(id) when a boat leaves. Rows are laid on the render clock of the Sea (render_time_ms).

const DT_EMIT := 0.05
const SPRAY_K := 2.5
const KNOT := 0.51444447
const WAKE_SHADER := preload("res://shaders/wake.gdshader")
const WAKE_NORMAL_SHADER := preload("res://shaders/wake_normal.gdshader")
const BOW_SHADER := preload("res://shaders/bow_wave.gdshader")
const MIST_SHADER := preload("res://shaders/mist.gdshader")
const BUFFER_SIZE := 512
const BUFFER_EXTENT := 400.0

@export var sea_path: NodePath

var sea: Sea:
	set = set_sea
## current: Callable(x, y) -> Vector2 (m/s), the surface current (wind.md §7); null = none.
var current = null

## Per boat: {bow, stern: WakeRibbon; mesh_bow, mesh_stern: MeshInstance3D (the ribbon, drawn on the sea);
## buf_bow, buf_stern: MeshInstance3D in the wake buffer or null; wave: MeshInstance3D (the bow wave sheets);
## drv: BowWave.Drivers; flow: foam flow distance; state; emission bookkeeping}
var _boats := {}
var _material: ShaderMaterial
var _bow_material: ShaderMaterial
var _mist_material: ShaderMaterial
## the mist sprites of every boat (BowWave.mist_sprite), drawn by _mist_mm
var _mist: Array = []
var _mist_mm: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
## The wake normal buffer (tiers M and H), created only while wakes are drawn on such a tier.
var _buffer: SubViewport
var _buffer_cam: Camera3D
var _buffer_material: ShaderMaterial
var _last_t := -1.0

const SHARED_UNIFORMS := ["n_comp", "comp", "sum_a", "sea_origin", "expo_tex", "expo_grid", "expo_size",
		"expo_default", "foam_tex", "col_foam"]
const RIBBONS := ["bow", "stern"]


func _ready() -> void:
	if sea == null and not sea_path.is_empty():
		sea = get_node_or_null(sea_path) as Sea
	_material = ShaderMaterial.new()
	_material.shader = WAKE_SHADER
	_buffer_material = ShaderMaterial.new()
	_buffer_material.shader = WAKE_NORMAL_SHADER
	_bow_material = ShaderMaterial.new()
	_bow_material.shader = BOW_SHADER
	_mist_material = ShaderMaterial.new()
	_mist_material.shader = MIST_SHADER
	_mist_mm = MultiMeshInstance3D.new()
	_mist_mm.name = "Mist"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	_mist_mm.multimesh = mm
	_mist_mm.material_override = _mist_material
	_mist_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the sprites move every frame over the whole scene: never culled
	_mist_mm.custom_aabb = AABB(Vector3(-1e5, -100.0, -1e5), Vector3(2e5, 200.0, 2e5))
	add_child(_mist_mm)


## The Sea the wakes are drawn on (also settable after _ready).
func set_sea(s: Sea) -> void:
	if sea == s:
		return
	if sea and sea.quality_changed.is_connected(_on_quality_changed):
		sea.quality_changed.disconnect(_on_quality_changed)
	_drop_buffer()
	sea = s
	if sea:
		sea.quality_changed.connect(_on_quality_changed)


## Boat pose and dimensions for this frame (see the class comment).
func update_boat(id: int, state: Dictionary) -> void:
	if not _boats.has(id):
		var b := {
			"bow": WakeRibbon.new(), "stern": WakeRibbon.new(), "last_t": -1.0, "last_bow": Vector2.ZERO,
			"last_stern": Vector2.ZERO, "dist": 0.0, "pulse_off": randf() * 100.0, "buf_bow": null, "buf_stern": null,
			"drv": BowWave.Drivers.new(), "flow": 0.0,
		}
		for r in RIBBONS:
			var mi := MeshInstance3D.new()
			mi.mesh = ArrayMesh.new()
			mi.material_override = _material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			b["mesh_" + r] = mi
		var wave := MeshInstance3D.new()
		wave.name = "BowWave%d" % id
		wave.mesh = ArrayMesh.new()
		wave.material_override = _bow_material
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wave)
		b["wave"] = wave
		_boats[id] = b
		if _buffer:
			_add_buffer_instances(b)
	_boats[id]["state"] = state


func remove_boat(id: int) -> void:
	if not _boats.has(id):
		return
	for r in RIBBONS:
		for k in ["mesh_", "buf_"]:
			var n = _boats[id][k + r]
			if n:
				n.queue_free()
	_boats[id]["wave"].queue_free()
	_boats.erase(id)


func boat_ribbons(id: int) -> Array:
	return [_boats[id]["bow"], _boats[id]["stern"]] if _boats.has(id) else []


## The wake normal buffer viewport, null while there is none (no wakes drawn, or tier L).
func wake_buffer() -> SubViewport:
	return _buffer


func _on_quality_changed(_tier: int) -> void:
	_drop_buffer()


## Wake normal buffer (tiers M, H): a 512 x 512 viewport of its own world over 400 m around the camera, made when
## the first wake is drawn on such a tier and dropped when none is, or the tier changes.
func _ensure_buffer(want: bool) -> void:
	if want == (_buffer != null):
		return
	if not want:
		_drop_buffer()
		return
	_buffer = SubViewport.new()
	_buffer.name = "WakeBuffer"
	_buffer.size = Vector2i(BUFFER_SIZE, BUFFER_SIZE)
	_buffer.own_world_3d = true
	_buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_buffer.msaa_3d = Viewport.MSAA_DISABLED
	_buffer.positional_shadow_atlas_size = 0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_buffer.add_child(we)
	_buffer_cam = Camera3D.new()
	_buffer_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_buffer_cam.size = BUFFER_EXTENT
	_buffer_cam.near = 1.0
	_buffer_cam.far = 1000.0
	_buffer.add_child(_buffer_cam)
	add_child(_buffer)
	for id in _boats:
		_add_buffer_instances(_boats[id])
	if sea:
		sea.set_wake_buffer(_buffer.get_texture(), BUFFER_EXTENT, 0.35)


## The boat's ribbon meshes drawn a second time into the wake buffer (the meshes are shared).
func _add_buffer_instances(b: Dictionary) -> void:
	for r in RIBBONS:
		var bi := MeshInstance3D.new()
		bi.mesh = b["mesh_" + r].mesh
		bi.material_override = _buffer_material
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_buffer.add_child(bi)
		b["buf_" + r] = bi


func _drop_buffer() -> void:
	if _buffer == null:
		return
	for id in _boats:
		for r in RIBBONS:
			_boats[id]["buf_" + r] = null
	_buffer.queue_free()
	_buffer = null
	_buffer_cam = null
	if sea:
		sea.set_wake_buffer(null, BUFFER_EXTENT, 0.0)


func _height(x: float, y: float) -> float:
	return sea.height_at(x, y) if sea else 0.0


func _process(_delta: float) -> void:
	if sea == null or sea.material == null:
		return
	var t_s := sea.render_time_ms * 0.001
	var dt := 0.0 if _last_t < 0.0 else maxf(t_s - _last_t, 0.0)
	_last_t = t_s
	var tier := sea.get_tier()
	var o := sea.origin
	var active := _select(tier, o)
	_ensure_buffer(tier["wake_buffer"] and not active.is_empty())
	if _buffer_cam:
		_buffer_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD),
				Vector3(o.x, 500.0, -o.y))
	for mat in [_material, _bow_material]:
		for n in SHARED_UNIFORMS:
			mat.set_shader_parameter(n, sea.material.get_shader_parameter(n))
		mat.set_shader_parameter("grid_q", sea.grid_ratio())
		mat.set_shader_parameter("grid_segments", float(tier["segments"]))
	for n in ["foam_tex", "sky_horizon", "sun_color", "sun_dir"]:
		_mist_material.set_shader_parameter(n, sea.material.get_shader_parameter(n))

	var h := Callable(self, "_height")
	for id in _boats:
		var b: Dictionary = _boats[id]
		var on: bool = active.has(id)
		for r in RIBBONS:
			b["mesh_" + r].visible = on
			if b["buf_" + r]:
				b["buf_" + r].visible = on
		b["wave"].visible = on
		if not on:
			continue
		var st: Dictionary = b["state"]
		var spray: bool = tier["spray"] == "all" or (tier["spray"] == "own" and st.get("own", false))
		if b["last_t"] < 0.0 or t_s - b["last_t"] >= DT_EMIT:
			_emit(b, st, t_s, spray)
		for r in RIBBONS:
			var rib: WakeRibbon = b[r]
			rib.step(t_s, dt, h, current)
			var mesh: ArrayMesh = b["mesh_" + r].mesh
			mesh.clear_surfaces()
			var arrays := rib.build_arrays(t_s)
			if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_build_wave(b, st, dt)
	_draw_mist(dt)


## The bow wave sheets of a boat for this frame (BowWave), the foam flowing aft at the boat's speed.
func _build_wave(b: Dictionary, st: Dictionary, dt: float) -> void:
	var drv: BowWave.Drivers = b["drv"]
	b["flow"] = fposmod(float(b["flow"]) + drv.v * dt, 20.0)
	var mesh: ArrayMesh = b["wave"].mesh
	mesh.clear_surfaces()
	var arrays := BowWave.build_arrays(st, drv)
	if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# every frame the sheet moves with the boat: keep it from being culled on stale bounds
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		mesh.custom_aabb = AABB(v[0] - Vector3(20.0, 10.0, 20.0), Vector3(40.0, 20.0, 40.0))
	(b["wave"] as MeshInstance3D).set_instance_shader_parameter("flow", b["flow"])


## Moves the mist sprites and writes them into the MultiMesh (camera-facing in the shader).
func _draw_mist(dt: float) -> void:
	var live: Array = []
	for m in _mist:
		if BowWave.mist_step(m, dt):
			live.append(m)
	_mist = live
	var mm := _mist_mm.multimesh
	mm.instance_count = _mist.size()
	for i in _mist.size():
		var m: Dictionary = _mist[i]
		var look := BowWave.mist_look(m)
		var p: Vector3 = m["pos"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * look.x), Vector3(p.x, p.z, -p.y)))
		mm.set_instance_custom_data(i, Color(look.y, m["seed"], 0.0, 0.0))


## Mist sprites in the scene (tests, previews): [{pos, vel, age, life, s0, s1, seed}].
func mist_sprites() -> Array:
	return _mist


## Boats that get wakes on this tier: own boat only (L), own and the 6 nearest (M), all within 400 m (H).
func _select(tier: Dictionary, o: Vector2) -> Dictionary:
	var out := {}
	var others := []
	for id in _boats:
		var st: Dictionary = _boats[id].get("state", {})
		if st.get("own", false):
			out[id] = true
		else:
			var d := Vector2(st.get("x", 0.0), st.get("y", 0.0)).distance_to(o)
			others.append([d, id])
	others.sort_custom(func(a, b): return a[0] < b[0])
	var n: int = tier["wake_boats"] - 1
	var rmax: float = tier["wake_radius"]
	for e in others:
		if n <= 0:
			break
		if rmax > 0.0 and e[0] > rmax:
			break
		out[e[1]] = true
		n -= 1
	return out


func _emit(b: Dictionary, st: Dictionary, t_s: float, spray: bool) -> void:
	var psi: float = st.get("psi", 0.0)
	var fwd := Vector2(sin(psi), cos(psi))
	var pos := Vector2(st.get("x", 0.0), st.get("y", 0.0))
	var lwl: float = st.get("lwl", 6.0)
	var bwl: float = st.get("bwl", 2.0)
	var bow_x: float = st.get("bow_x", 0.5 * lwl)
	var stern_x: float = st.get("stern_x", -0.5 * lwl)
	var pitch: float = st.get("pitch", 0.0)
	var z: float = st.get("z", 0.0)
	var bow := pos + fwd * bow_x
	var stern := pos + fwd * stern_x
	var first: bool = b["last_t"] < 0.0
	var dt: float = t_s - b["last_t"]
	var v := 0.0 if first or dt <= 0.0 else bow.distance_to(b["last_bow"]) / dt
	var v_s := 0.0 if first or dt <= 0.0 else stern.distance_to(b["last_stern"]) / dt
	var bow_prev: Vector2 = b["last_bow"]
	b["last_t"] = t_s
	b["last_bow"] = bow
	b["last_stern"] = stern
	if first:
		return
	var v_ref := 1.34 * sqrt(lwl / 0.3048) * KNOT
	var ratio := v / v_ref
	b["dist"] += v * dt
	var sea_bow := _height(bow.x, bow.y)
	var bow_z := z + bow_x * sin(pitch)
	var visible := bow_z - sea_bow <= 1.0
	var drv: BowWave.Drivers = b["drv"]
	drv.advance(dt, v if visible else 0.0, ratio if visible else 0.0, bow_z - sea_bow)
	var w0 := 0.35 * bwl * minf(1.0, ratio + 0.2)
	var row := (b["bow"] as WakeRibbon).emit(t_s, bow, psi, v, w0, ratio, visible, b["dist"])
	var a: float = b["dist"] + b["pulse_off"]
	var pulse := maxf(0.01, 1.0 - (0.3 * sin(0.07 * a + 1.0) + 0.4 * sin(0.5 * a) + 0.4 * sin(0.3 * a)))
	if spray and visible:
		# the mist off the bow wave (drawn), and the spray reach of the ribbon (not drawn)
		var boat_vel := (bow - bow_prev) / dt
		for _k in BowWave.mist_count(drv, pulse, dt):
			if _mist.size() < BowWave.MIST_MAX:
				_mist.append(BowWave.mist_sprite(st, drv, sea_bow, boat_vel, _rng))
		var e := WakeRibbon.edges(row, t_s)
		var zs := [_height(e[0].x, e[0].y) + 0.1, _height(e[1].x, e[1].y) + 0.1]
		(b["bow"] as WakeRibbon).launch_spray(row, SPRAY_K * ratio * ratio * pulse, st.get("heel", 0.0), zs)
	var tw: float = st.get("transom_width", 0.6 * bwl)
	(b["stern"] as WakeRibbon).emit(t_s, stern, psi, v_s, 0.4 * tw, v_s / v_ref, true, b["dist"])
