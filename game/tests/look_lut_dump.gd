extends SceneTree
## Writes the colour grade LUT of every light preset (LookFx, water_render.md §4.5) to generated/look/lut_<preset>.png
## for the offline previews (tests/cine_preview.py): the N slices of the N³ LUT side by side (blue across the slices),
## and generated/look/look.json with the vignette constants.
##   godot --headless --path game -s res://tests/look_lut_dump.gd

const OUT := "res://generated/look"


func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := LookFx.LUT_SIZE
	for name in SkyRig.PRESET_NAMES:
		var slices := LookFx.lut_images(LookFx.GRADES[SkyRig.PRESET_NAMES[name]], n)
		var strip := Image.create_empty(n * n, n, false, Image.FORMAT_RGBA8)
		for b in n:
			strip.blit_rect(slices[b], Rect2i(0, 0, n, n), Vector2i(b * n, 0))
		strip.save_png(dir.path_join("lut_%s.png" % name))
	var f := FileAccess.open(dir.path_join("look.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"lut_size": n, "vignette_regular": LookFx.VIGNETTE_REGULAR,
		"vignette_clip": LookFx.VIGNETTE_CLIP, "vignette_inner": LookFx.VIGNETTE_INNER}, "  "))
	print("look LUTs: %d presets in %s" % [SkyRig.PRESET_NAMES.size(), dir])
	quit(0)
