class_name BuildInfo
extends RefCounted
## The build string of the main menu's corner (menus.md §1): v<application/config/version>, then the export stamp
## (game/build.txt, written by tools/stamp_build.sh from git describe before an export), else "dev".

const STAMP := "res://build.txt"


static func text() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	var stamp := ""
	if FileAccess.file_exists(STAMP):
		stamp = FileAccess.get_file_as_string(STAMP).strip_edges()
	if stamp == "":
		stamp = "dev"
	return ("v%s  %s" % [v, stamp]) if v != "" else stamp
