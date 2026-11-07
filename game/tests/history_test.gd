extends SceneTree
## Race history tests (menus.md §6, §5 Best line), headless, on a temporary file (never the player's own):
## a missing file, the save and load round trip, the cap of 50, the best per course and class, races and wins per
## class, the best line's cases, a corrupt file, an unknown version, an entry of the wrong shape, the temporary file
## moved over the old one, and a test run that never writes the default path.
##   godot --headless --path game -s res://tests/history_test.gd

const TEST_PATH := "user://history_test.cfg"

var t := TestLog.new()


func _init() -> void:
	RaceHistory.path = TEST_PATH
	_clear()
	test_missing()
	test_round_trip()
	test_cap()
	test_bests()
	test_best_line()
	test_corrupt()
	test_shape()
	test_guard()
	_clear()
	t.finish(self, "history_test")


func _clear() -> void:
	for p in [TEST_PATH, TEST_PATH + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write(text: String) -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _e(place: int, time: float, cls := "wm7", course := "practice_waters/example_wl", code := "") -> Dictionary:
	return RaceHistory.entry(cls, course.get_slice("/", 0), course, 10, "easy", "local", place, code, time,
		NAN if place != 1 else 0.0, "2026-11-07 18:47")


func test_missing() -> void:
	t.begin("a missing file: an empty history")
	_clear()
	var h := RaceHistory.new()
	t.ok(h.load_file() == ERR_FILE_NOT_FOUND, "load says not found")
	t.ok(h.results.is_empty() and h.bests.is_empty() and h.races.is_empty(), "empty")
	t.ok(is_nan(h.best("practice_waters/example_wl", "wm7")), "no best")
	t.ok(not FileAccess.file_exists(TEST_PATH), "reading does not create the file")


func test_round_trip() -> void:
	t.begin("save and load: results, bests, races and wins")
	_clear()
	var h := RaceHistory.new()
	h.add(_e(2, 1412.35))
	h.add(_e(1, 1390.5))
	h.add(_e(0, NAN, "wm9", "solent/round_the_cans", "RET"))
	t.ok(h.save_file() == OK and FileAccess.file_exists(TEST_PATH), "saved")
	t.ok(not FileAccess.file_exists(TEST_PATH + ".tmp"), "no temporary file left")
	var g := RaceHistory.load_from()
	t.ok(g.results.size() == 3, "three results: %d" % g.results.size())
	var a: Dictionary = g.results[0]
	t.ok(a["date"] == "2026-11-07 18:47" and a["class"] == "wm7" and a["venue"] == "practice_waters"
		and a["course"] == "practice_waters/example_wl" and a["fleet"] == 10 and a["ai_level"] == "easy"
		and a["weather"] == "local" and a["place"] == 2 and a["code"] == "" and absf(a["time"] - 1412.35) < 1e-6
		and a["gap"] == -1.0, "the first entry's fields: %s" % str(a))
	var r: Dictionary = g.results[2]
	t.ok(r["code"] == "RET" and r["place"] == 0 and r["time"] == -1.0 and r["gap"] == -1.0, "RET: no place, no time")
	t.ok(float(g.results[1]["gap"]) == 0.0, "the winner's gap is 0")
	t.near(g.best("practice_waters/example_wl", "wm7"), 1390.5, 1e-6, "the best here")
	t.ok(is_nan(g.best("solent/round_the_cans", "wm9")), "no best without a finish")
	t.ok(g.races == {"wm7": 2, "wm9": 1} and g.wins == {"wm7": 1}, "races %s, wins %s" % [g.races, g.wins])
	t.ok(RaceHistory.entry("wm7", "v", "v/c", 4, "pro", "random", 3, "", 100.0, 5.0).get("date", "").length() == 16,
		"a date from the clock")


func test_cap() -> void:
	t.begin("the cap: never more than 50 results")
	_clear()
	var h := RaceHistory.new()
	for i in 60:
		h.add(_e(3, 1000.0 + i))
	t.ok(h.results.size() == RaceHistory.CAP, "50 in memory: %d" % h.results.size())
	t.ok(absf(float(h.results[0]["time"]) - 1010.0) < 1e-6, "the oldest ten dropped")
	t.ok(h.races["wm7"] == 60, "the count is kept past the cap: %d" % h.races["wm7"])
	t.near(h.best("practice_waters/example_wl", "wm7"), 1000.0, 1e-6, "the best is kept past the cap")
	h.save_file()
	var g := RaceHistory.load_from()
	t.ok(g.results.size() == RaceHistory.CAP, "50 in the file")
	# a file with more (written by hand or an older build) loads its last 50 and saves 50
	var list := []
	for i in 70:
		list.append(_e(4, 2000.0 + i))
	var cf := ConfigFile.new()
	cf.set_value("history", "version", RaceHistory.VERSION)
	cf.set_value("history", "results", list)
	cf.save(TEST_PATH)
	g = RaceHistory.load_from()
	t.ok(g.results.size() == RaceHistory.CAP and absf(float(g.results[0]["time"]) - 2020.0) < 1e-6,
		"70 in the file: the last 50 read (%d)" % g.results.size())
	g.record(_e(5, 3000.0))
	cf = ConfigFile.new()
	cf.load(TEST_PATH)
	t.ok((cf.get_value("history", "results") as Array).size() == RaceHistory.CAP, "a record writes 50")


func test_bests() -> void:
	t.begin("the best per course and class")
	_clear()
	var h := RaceHistory.new()
	h.add(_e(3, 1500.0))
	h.add(_e(5, 1600.0))
	t.near(h.best("practice_waters/example_wl", "wm7"), 1500.0, 1e-6, "a slower race keeps the best")
	h.add(_e(4, 1450.0))
	t.near(h.best("practice_waters/example_wl", "wm7"), 1450.0, 1e-6, "a faster race is the new best")
	h.add(_e(0, 1200.0, "wm7", "practice_waters/example_wl", "OCS"))
	t.near(h.best("practice_waters/example_wl", "wm7"), 1450.0, 1e-6, "a finish scored OCS does not count")
	h.add(_e(1, 1300.0, "wm9"))
	t.near(h.best("practice_waters/example_wl", "wm7"), 1450.0, 1e-6, "another class: its own best")
	t.near(h.best("practice_waters/example_wl", "wm9"), 1300.0, 1e-6, "wm9's best")
	h.add(_e(1, 900.0, "wm7", "practice_waters/other"))
	t.near(h.best("practice_waters/example_wl", "wm7"), 1450.0, 1e-6, "another course: its own best")
	t.ok(h.wins == {"wm9": 1, "wm7": 1} and h.races == {"wm7": 5, "wm9": 1}, "wins %s races %s" % [h.wins, h.races])
	h.add({"class": "wm7"})
	t.ok(h.races["wm7"] == 5, "an incomplete entry is not added")


func test_best_line() -> void:
	t.begin("the results screen's best line (menus.md §5)")
	_clear()
	var h := RaceHistory.new()
	var c := "practice_waters/example_wl"
	t.ok(h.best_line(c, "wm7", 3, 1392.4) == "First race here", "first race: %s" % h.best_line(c, "wm7", 3, 1392.4))
	h.add(_e(0, NAN, "wm7", c, "RET"))
	t.ok(h.best_line(c, "wm7", 3, 1392.4) == "First finish here", "raced, never finished, now a finish")
	t.ok(h.best_line(c, "wm7", 0, NAN) == "", "raced, never finished, again no finish: no line")
	h.add(_e(2, 1392.4))
	t.ok(h.best_line(c, "wm7", 4, 1400.0) == "Your best here: 0:23:12.40", "slower: %s" % h.best_line(c, "wm7", 4, 1400.0))
	t.ok(h.best_line(c, "wm7", 2, 1392.4) == "Your best here: 0:23:12.40", "equal: not a new best")
	t.ok(h.best_line(c, "wm7", 0, NAN) == "Your best here: 0:23:12.40", "no finish: the best")
	t.ok(h.best_line(c, "wm7", 1, 1380.0) == "New best: 0:23:00.00, was 0:23:12.40", "faster: %s"
		% h.best_line(c, "wm7", 1, 1380.0))
	t.ok(h.best_line(c, "wm9", 1, 1380.0) == "First race here", "another class: first race")
	for ln in [h.best_line(c, "wm7", 1, 1380.0), h.best_line(c, "wm7", 4, 1400.0)]:
		t.ok(not String(ln).contains("—"), "no em dash: %s" % ln)


func test_corrupt() -> void:
	t.begin("a corrupt file or an unknown version starts fresh")
	_clear()
	_write("this is not [ a config = file ((\n")
	var h := RaceHistory.new()
	t.ok(h.load_file() != OK and h.results.is_empty(), "corrupt: empty")
	t.ok(h.record(_e(2, 1500.0)) == OK, "a record over it")
	var g := RaceHistory.load_from()
	t.ok(g.results.size() == 1 and not is_nan(g.best("practice_waters/example_wl", "wm7")), "a fresh file, read back")
	_write("")
	t.ok(RaceHistory.load_from().results.is_empty(), "an empty file: empty")
	var cf := ConfigFile.new()
	cf.set_value("history", "version", 99)
	cf.set_value("history", "results", [_e(1, 1000.0)])
	cf.set_value("best", "practice_waters/example_wl|wm7", 1000.0)
	cf.save(TEST_PATH)
	h = RaceHistory.new()
	t.ok(h.load_file() == ERR_FILE_UNRECOGNIZED and h.results.is_empty() and h.bests.is_empty(),
		"version 99: ignored")
	cf.set_value("history", "version", "1")
	cf.save(TEST_PATH)
	t.ok(RaceHistory.load_from().results.is_empty(), "a version of the wrong type: ignored")
	cf.erase_section_key("history", "version")
	cf.save(TEST_PATH)
	t.ok(RaceHistory.load_from().results.is_empty(), "no version: ignored")


func test_shape() -> void:
	t.begin("entries of the wrong shape are dropped, the rest kept")
	_clear()
	var good := _e(3, 1500.0)
	var no_time := good.duplicate()
	no_time.erase("time")
	var bad_type := good.duplicate()
	bad_type["class"] = 7
	var cf := ConfigFile.new()
	cf.set_value("history", "version", RaceHistory.VERSION)
	cf.set_value("history", "results", [good, "nonsense", no_time, bad_type, 42, good])
	cf.set_value("best", "practice_waters/example_wl|wm7", "fast")
	cf.set_value("best", "practice_waters/example_wl|wm9", -3.0)
	cf.set_value("best", "practice_waters/example_wl|wm12", 1700)
	cf.set_value("races", "wm7", "many")
	cf.set_value("races", "wm9", 4)
	cf.set_value("wins", "wm9", -1)
	cf.save(TEST_PATH)
	var h := RaceHistory.load_from()
	t.ok(h.results.size() == 2, "the two good entries: %d" % h.results.size())
	t.ok(h.bests.keys() == ["practice_waters/example_wl|wm12"], "bests of the right type: %s" % str(h.bests))
	t.ok(h.races == {"wm9": 4} and h.wins.is_empty(), "counts of the right type: %s %s" % [h.races, h.wins])
	cf = ConfigFile.new()
	cf.set_value("history", "version", RaceHistory.VERSION)
	cf.set_value("history", "results", "not a list")
	cf.save(TEST_PATH)
	t.ok(RaceHistory.load_from().results.is_empty(), "results not a list: none")


func test_guard() -> void:
	t.begin("a test run never writes the player's own file")
	var real := ProjectSettings.globalize_path(RaceHistory.DEFAULT_PATH)
	var had := FileAccess.file_exists(RaceHistory.DEFAULT_PATH)
	var mod := FileAccess.get_modified_time(real) if had else 0
	var h := RaceHistory.new()
	h.add(_e(1, 1.0))
	t.ok(h.save_file(RaceHistory.DEFAULT_PATH) == ERR_UNAUTHORIZED, "save to the default path refused")
	t.ok(FileAccess.file_exists(RaceHistory.DEFAULT_PATH) == had
		and (not had or FileAccess.get_modified_time(real) == mod), "the player's file untouched")
