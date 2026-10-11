extends SceneTree
## Writes the colour grade LUT of each old light preset name (clear, fair, hazy, late: their conditions at the hour
## of their afternoon sun on the default site, Daylight.ALIASES; LookFx, water_render.md §4.5) to
## generated/look/lut_<name>.png for the offline previews (tests/cine_preview.py): the N slices of the N³ LUT side by
## side (blue across the slices), and generated/look/look.json with the look constants (the LUT size; no
## vignette). The daylight previews take each shot's own LUT from its dump (tests/water_preview_dump.gd).
##   godot --headless --path game -s res://tests/look_lut_dump.gd

const OUT := "res://generated/look"


func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var site := Daylight.DEFAULT_SITE
	for name in Daylight.ALIASES:
		var a: Dictionary = Daylight.ALIASES[name]
		var g: Dictionary = Daylight.light(site, Daylight.hour_for_sun(site, a["sun"]), a["conditions"])["grade"]
		LookFx.lut_strip(LookFx.scaled(g, LookFx.grade_strength)).save_png(dir.path_join("lut_%s.png" % name))
	var f := FileAccess.open(dir.path_join("look.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(LookFx.look_constants(), "  "))
	print("look LUTs: %d names in %s" % [Daylight.ALIASES.size(), dir])
	quit(0)
