extends GdUnitTestSuite

# Regression test: every tr("...") / _tr("...") literal key used in runtime
# scripts must exist in translations.csv (case-sensitive). Prevents silent
# untranslated UI text when someone introduces a new tr() key without adding
# the matching CSV row.

const CSV_PATH := "res://scenes/ui/localization/translations.csv"
const SCAN_DIRS := ["res://scenes", "res://globals", "res://data", "res://fx"]
const SKIP_DIRS := ["addons", "tests", "tools"]

var _csv_keys: Dictionary = {}
var _manager: Node = null


func before() -> void:
	_manager = auto_free(load("res://globals/core/localization_manager.gd").new())
	_load_csv_keys()


func _load_csv_keys() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_bool(f != null).is_true()
	if f == null:
		return
	var header := f.get_line()  # skip header row
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var fields: PackedStringArray = _manager._parse_csv_line(line)
		if fields.size() < 1 or fields[0].is_empty():
			continue
		_csv_keys[fields[0]] = true
	f.close()


func _collect_gd_files(base: String, out: Array[String]) -> void:
	var dir := DirAccess.open(base)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := base.path_join(name)
		if dir.current_is_dir():
			if name not in SKIP_DIRS and not name.begins_with("."):
				_collect_gd_files(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()


func _extract_keys(text: String) -> Dictionary:
	# Returns { key: count } for tr("...") / _tr("...") literal string calls,
	# ignoring full-line comments.
	var keys := {}
	var re := RegEx.new()
	var pattern := '\\b(?:tr|_tr)\\(\\s*"((?:[^"\\\\]|\\\\.)*)"'
	assert_bool(re.compile(pattern) == OK).is_true()
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m in re.search_all(line):
			var raw := m.get_string(1)
			var key := _unescape_gd_string(raw)
			if key.is_empty():
				continue
			keys[key] = keys.get(key, 0) + 1
	return keys


func _unescape_gd_string(raw: String) -> String:
	# Convert GDScript string-literal escapes used inside tr() keys to the
	# runtime value tr() sees (e.g. "\n" -> real newline), matching how the
	# CSV parser unescapes literal \n in CSV rows.
	var out := ""
	var i := 0
	while i < raw.length():
		var c := raw[i]
		if c == "\\" and i + 1 < raw.length():
			var n := raw[i + 1]
			match n:
				"n":
					out += "\n"
				"t":
					out += "\t"
				"\\":
					out += "\\"
				'"':
					out += '"'
				_:
					out += n
			i += 2
		else:
			out += c
			i += 1
	return out


func test_every_tr_literal_key_exists_in_csv() -> void:
	var all_files: Array[String] = []
	for dir in SCAN_DIRS:
		_collect_gd_files(dir, all_files)
	var missing: Dictionary = {}  # key -> [file, ...]
	for path in all_files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var keys := _extract_keys(text)
		for key in keys:
			if not _csv_keys.has(key):
				if not missing.has(key):
					missing[key] = []
				missing[key].append(path)
	if not missing.is_empty():
		var msg := "tr() literal keys missing from translations.csv:"
		for key in missing:
			msg += "\n  [%s]  (%s)" % [key, ", ".join(missing[key])]
		fail(msg)
