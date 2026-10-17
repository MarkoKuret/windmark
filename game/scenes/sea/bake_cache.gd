class_name BakeCache
extends RefCounted
## Load-time bakes kept on disk (PERFORMANCE.md A6): an image or table that a script builds from constants (the
## whitecap foam texture, the grade's LUT) is written to `user://cache/` the first time and read back after, so a
## later start skips the build. The key is the md5 of the script that builds it plus the build's parameters and the
## engine version, so a change to the formulas or the engine never serves a stale bake. Every read and write is
## guarded: without the folder, the file or the permission, the caller just builds as before.

const DIR := "user://cache"
## tests and measured runs: off builds every time (nothing is read or written)
static var enabled := true
## how many bakes the last `read` found (tests)
static var hits := 0
static var misses := 0


## The cache key of a bake built by `script_path` (res://) with `params` (anything that changes the result).
static func key(script_path: String, params: String) -> String:
	var src := FileAccess.get_md5(script_path)
	if src == "":
		src = "nosrc"
	return (src + "|" + params + "|" + Engine.get_version_info().get("string", "")).md5_text()


static func _path(k: String) -> String:
	return DIR + "/bake_" + k + ".bin"


## The bake's bytes, or an empty array when there is none (or the cache is off).
static func read(k: String) -> PackedByteArray:
	if not enabled:
		return PackedByteArray()
	var f := FileAccess.open(_path(k), FileAccess.READ)
	if f == null:
		misses += 1
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	hits += 1
	return bytes


## Writes a bake; quietly does nothing where it cannot.
static func write(k: String, bytes: PackedByteArray) -> void:
	if not enabled or bytes.is_empty():
		return
	if not DirAccess.dir_exists_absolute(DIR) and DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return
	var f := FileAccess.open(_path(k), FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()


## Forgets every bake on disk (tests).
static func clear() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for n in d.get_files():
		if n.begins_with("bake_"):
			d.remove(n)
