#!/usr/bin/env -S godot -s
extends SceneTree


func _initialize() -> void:
	# Bootstrap GDUnit4: force-load all class_name scripts so they're registered
	_load_dir("res://addons/gdUnit4/src")
	
	# Now load the CLI test runner (GdUnitTestCIRunner should now be available)
	var cmd_script = load("res://addons/gdUnit4/bin/GdUnitCmdTool.gd")
	if not cmd_script:
		print("ERROR: Failed to load GdUnitCmdTool")
		quit(1)
		return
	
	# Run the normal _initialize flow from GdUnitCmdTool
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var runner = cmd_script.new()
	root.add_child(runner)


# Recursively load all .gd scripts to register class_names
func _load_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			_load_dir(dir_path.path_join(file_name))
		elif file_name.ends_with(".gd"):
			var path = dir_path.path_join(file_name)
			load(path)
		file_name = dir.get_next()
