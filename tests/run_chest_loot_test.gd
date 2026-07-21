#!/usr/bin/env -S godot -s
extends SceneTree


func _initialize() -> void:
	print("=== CHEST LOOT TEST RUNNER ===")
	
	# Preload the GdUnit4 CLI runner to force class_name registration
	var runner_script = load("res://addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd")
	if not runner_script:
		print("ERROR: Failed to load GdUnitTestCIRunner")
		quit(1)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var cli_runner = runner_script.new()
	# Hardcode the test file path
	var runner_args: Array[String] = [
		"GdUnitCmdTool.gd",
		"--ignoreHeadlessMode",
		"-a",
		"res://tests/gdunit/chest_loot_panel_test.gd"
	]
	cli_runner._debug_cmd_args = PackedStringArray(runner_args)
	root.add_child(cli_runner)


func _finalize() -> void:
	if is_instance_valid(root) and root.get_child_count() > 0:
		var child := root.get_child(0)
		if is_instance_valid(child):
			queue_delete(child)
