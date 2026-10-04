extends SceneTree
## The fleet's draw cost, headless (game/README.md "Measuring performance"): the renderer's draw-call and primitive
## counters read 0 without a GPU, so this counts what the main pass would draw from the scene itself. Runs the sail
## scene as a race on the core (the player's boat sailed by its AI, `--watch`), and every frame after a warm-up,
## from the scene's camera: per boat the mesh surfaces that are visible and inside the view frustum (one draw call
## each) and their triangles, the boats at each level of detail, and the CPU time of the scene's `boats` and `sails`
## sections (PerfStats) per boat. Shadow passes are not counted (they draw the same casters again within the shadow
## distance).
##   godot --headless --path game -s res://tests/fleet_cost.gd -- --fleet=10 [--seconds=20] [--csv=PATH] [--class=wm7]
##       [--no-lods] [--no-sheets]   (the boats without their levels of detail or sheets, to compare)

const WARMUP_S := 3.0

var fleet := 10
var seconds := 20.0
var csv := ""
var cls := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fleet="):
			fleet = a.trim_prefix("--fleet=").to_int()
		elif a.begins_with("--seconds="):
			seconds = a.trim_prefix("--seconds=").to_float()
		elif a.begins_with("--csv="):
			csv = a.trim_prefix("--csv=")
		elif a == "--no-lods":
			BoatView.use_lods = false
		elif a == "--no-sheets":
			BoatView.draw_sheets = false
		elif a.begins_with("--class="):
			cls = a.trim_prefix("--class=")
	_main()


func _main() -> void:
	await process_frame
	if not CoreSimSource.available():
		print("fleet cost: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.sim_kind = sc.SimKind.CORE
	sc.race_mode = true
	sc.fleet_size = fleet
	sc.watch = true
	sc.world_seed = 7
	if cls != "":
		sc.class_id = cls
	sc.with_pause_menu = false
	sc.apply_settings = false
	root.add_child(sc)
	await process_frame
	PerfStats.enabled = true
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var sum := {"draws": 0.0, "prims": 0.0, "all_draws": 0.0, "all_prims": 0.0, "boats_us": 0.0, "sails_us": 0.0}
	var lod_frames := [0.0, 0.0, 0.0, 0.0]
	var dist_sum := 0.0
	var tri_cache := {}
	while true:
		await process_frame
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		var acc := PerfStats.take()
		if el < WARMUP_S:
			continue
		if el > WARMUP_S + seconds:
			break
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		if cam == null:
			continue
		var planes := cam.get_frustum()
		frames += 1
		sum["boats_us"] += float(acc.get(&"boats", 0))
		sum["sails_us"] += float(acc.get(&"sails", 0))
		for bv: BoatView in sc.boat_views:
			var c := _count(bv, planes, tri_cache)
			sum["draws"] += c.x
			sum["prims"] += c.y
			var lod: int = bv.lod if "lod" in bv else 0
			lod_frames[clampi(lod, 0, 3)] += 1.0
			dist_sum += cam.global_position.distance_to(bv.global_position)
		var a := _count(sc, planes, tri_cache)
		sum["all_draws"] += a.x
		sum["all_prims"] += a.y
	var n := maxf(frames, 1.0)
	var boats: int = sc.boat_views.size()
	var line := {
		"boats": boats, "frames": frames,
		"boat_draw_calls": sum["draws"] / n, "boat_primitives": sum["prims"] / n,
		"scene_draw_calls": sum["all_draws"] / n, "scene_primitives": sum["all_prims"] / n,
		"lod0": lod_frames[0] / n, "lod1": lod_frames[1] / n, "lod2": lod_frames[2] / n,
		"mean_distance_m": dist_sum / n / maxf(boats, 1),
		"boats_ms": sum["boats_us"] / n / 1000.0, "sails_ms": sum["sails_us"] / n / 1000.0,
		"cpu_us_per_boat": (sum["boats_us"] + sum["sails_us"]) / n / maxf(boats, 1),
	}
	print("fleet cost: %d boats, %d frames" % [boats, frames])
	for k in line:
		print("  %-18s %s" % [k, str(snappedf(line[k], 0.01)) if line[k] is float else str(line[k])])
	if csv != "":
		var path := csv if csv.is_absolute_path() or csv.begins_with("res://") or csv.begins_with("user://") \
				else OS.get_environment("PWD").path_join(csv)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_line(",".join(line.keys()))
			f.store_line(",".join(line.values().map(func(v: Variant) -> String: return str(v))))
	quit(0)


## Surfaces (draw calls) and triangles of the visible meshes under `top` inside the frustum.
static func _count(top: Node, planes: Array[Plane], cache: Dictionary) -> Vector2:
	var out := Vector2.ZERO
	var stack: Array[Node] = [top]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and not (node as Node3D).visible:
			continue
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.global_transform * mi.get_aabb()
		var c := box.get_center()
		var r := 0.5 * box.size.length()
		var inside := true
		for pl in planes:
			if pl.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var key := mi.mesh.get_rid()
		if not cache.has(key) or (cache[key] as Vector2).x != mi.mesh.get_surface_count():
			var tris := 0
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				tris += (idx as PackedInt32Array).size() / 3 if idx != null \
						else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			cache[key] = Vector2(mi.mesh.get_surface_count(), tris)
		var v: Vector2 = cache[key]
		out += v
	return out
