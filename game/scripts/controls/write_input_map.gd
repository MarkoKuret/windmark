extends SceneTree
## Writes the default bindings (DefaultBindings) into the [input] section of project.godot. Run after changing
## the defaults:  godot --headless --path game -s res://scripts/controls/write_input_map.gd
## Only the [input] section is replaced; every other line of project.godot stays as it is.


func _init() -> void:
	var t := DefaultBindings.table()
	for p in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if n.begins_with("input/") and not t.has(n.substr(6)):
			ProjectSettings.set_setting(n, null)
	for action in t:
		ProjectSettings.set_setting("input/" + action,
			{"deadzone": DefaultBindings.deadzone(t[action]), "events": DefaultBindings.events(t[action])})
	# Godot's own save drops settings equal to their defaults (such as [rendering]), so render to a scratch
	# file and splice only its [input] section into project.godot.
	var tmp := OS.get_cache_dir().path_join("windmark_input_map.godot")
	var err := ProjectSettings.save_custom(tmp)
	if err != OK:
		push_error("save_custom failed: %s" % error_string(err))
		quit(1)
		return
	var input_section := _section(FileAccess.get_file_as_string(tmp), "input")
	DirAccess.remove_absolute(tmp)
	var path := ProjectSettings.globalize_path("res://project.godot")
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var outl: PackedStringArray = []
	var skipping := false
	var written := false
	for line in lines:
		if line.begins_with("["):
			skipping = line == "[input]"
			if skipping:
				outl.append_array(input_section)
				written = true
				continue
		if not skipping:
			outl.append(line)
	if not written:
		# insert before the first section after [application], else at the end
		var at := outl.size()
		var seen_app := false
		for i in outl.size():
			if outl[i] == "[application]":
				seen_app = true
			elif seen_app and outl[i].begins_with("["):
				at = i
				break
		var ins := input_section.duplicate()
		for i in ins.size():
			outl.insert(at + i, ins[i])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(outl))
	f.close()
	print("input map written: %d actions" % t.size())
	quit(0)


## the lines of section `name` including its header and one trailing blank line
func _section(text: String, name: String) -> PackedStringArray:
	var res: PackedStringArray = []
	var inside := false
	for line in text.split("\n"):
		if line.begins_with("["):
			inside = line == "[" + name + "]"
		if inside:
			res.append(line)
	while res.size() > 0 and res[res.size() - 1].strip_edges() == "":
		res.remove_at(res.size() - 1)
	res.append("")
	return res
