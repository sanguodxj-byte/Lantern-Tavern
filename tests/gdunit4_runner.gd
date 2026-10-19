#!/usr/bin/env -S godot -s
extends SceneTree


func _initialize() -> void:
	print("=== GDUNIT4 RUNNER START ===")
	print("OS.get_cmdline_args(): ", OS.get_cmdline_args())
	print("OS.get_cmdline_user_args(): ", OS.get_cmdline_user_args())
	
	# Preload the GdUnit4 CLI runner to force class_name registration
	var runner_script = load("res://addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd")
	if not runner_script:
		print("ERROR: Failed to load GdUnitTestCIRunner")
		quit(1)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var cli_runner = runner_script.new()
	# Build the debug arguments. GdUnit4 expects "GdUnitCmdTool.gd" as the script identifier.
	var runner_args: Array[String] = ["GdUnitCmdTool.gd"]
	var user_args := OS.get_cmdline_user_args()
	# Check if user_args contains a -a flag with a test path
	var has_test_arg := false
	for arg in user_args:
		if arg == "-a":
			has_test_arg = true
	# Also check OS.get_cmdline_args() for -a (Windows CMD may not pass -- correctly)
	if not has_test_arg:
		var cmd_args := OS.get_cmdline_args()
		for i in range(cmd_args.size()):
			if cmd_args[i] == "-a" and i + 1 < cmd_args.size():
				user_args = ["--ignoreHeadlessMode", "-a", cmd_args[i + 1]]
				has_test_arg = true
				break
	if not user_args.is_empty():
		# Pre-validate every '-a' argument so a typo'd path fails with a
		# non-zero exit code instead of gdUnit4 silently exiting 0.
		var validation_errors := validate_paths(user_args)
		if not validation_errors.is_empty():
			for error_msg in validation_errors:
				printerr("ERROR: " + error_msg)
			printerr("ERROR: Test path validation failed, aborting test run.")
			quit(1)
			return
		for arg in user_args:
			runner_args.append(arg)
	else:
		runner_args.append("-a")
		runner_args.append("res://tests/gdunit/")
		runner_args.append("--ignoreHeadlessMode")
		
	cli_runner._debug_cmd_args = PackedStringArray(runner_args)
	root.add_child(cli_runner)


## Validates every '-a' argument in [args] (the gdUnit4 CLI user args).
## Returns a list of human-readable error strings; an empty list means all
## '-a' paths are valid. A path is invalid if it does not exist, or if it
## exists but matches no test scripts (empty directory / non-test file).
static func validate_paths(args: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] != "-a":
			i += 1
			continue
		i += 1
		if i >= args.size():
			errors.append("Missing test path after '-a'")
			break
		var path := args[i]
		i += 1
		var fs_path := _to_fs_path(path)
		var is_file := FileAccess.file_exists(fs_path)
		var is_dir := DirAccess.dir_exists_absolute(fs_path)
		if not is_file and not is_dir:
			errors.append("Test path does not exist: %s" % path)
			continue
		if is_dir:
			if _count_test_scripts(fs_path) == 0:
				errors.append("Test directory contains no test scripts: %s" % path)
			continue
		if not _looks_like_test_script(fs_path):
			errors.append("File is not a GdUnit test script (missing 'extends GdUnitTestSuite'): %s" % path)
	return errors


## Recursively counts .gd scripts under [dir_path]. Returns 0 for a missing
## or non-directory path.
static func _count_test_scripts(dir_path: String) -> int:
	var count := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				count += _count_test_scripts(dir_path.path_join(entry))
		elif entry.ends_with(".gd"):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


## Lightweight heuristic: a GdUnit test script must extend GdUnitTestSuite
## (or GdUnitTestCase). Scans the first 50 non-empty lines for the extends.
static func _looks_like_test_script(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false
	var lines_read := 0
	while not file.eof_reached() and lines_read < 50:
		var line := file.get_line().strip_edges()
		lines_read += 1
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("extends GdUnitTestSuite") or line.begins_with("extends GdUnitTestCase"):
			file.close()
			return true
	file.close()
	return false


## Converts a gdUnit4 '-a' path (res://, relative, or absolute) into an
## absolute OS filesystem path for FileAccess/DirAccess checks.
static func _to_fs_path(path: String) -> String:
	if path.contains("://"):
		return ProjectSettings.globalize_path(path)
	if path.length() > 1 and path[1] == ":":
		return path  # Windows absolute path, e.g. D:\...
	if path.begins_with("/"):
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _finalize() -> void:
	if is_instance_valid(root) and root.get_child_count() > 0:
		var child := root.get_child(0)
		if is_instance_valid(child):
			queue_delete(child)
