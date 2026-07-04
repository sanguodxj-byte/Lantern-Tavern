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
	if not user_args.is_empty():
		for arg in user_args:
			runner_args.append(arg)
	else:
		runner_args.append("-a")
		runner_args.append("res://tests/gdunit/")
		runner_args.append("--ignoreHeadlessMode")
		
	cli_runner._debug_cmd_args = PackedStringArray(runner_args)
	root.add_child(cli_runner)


func _finalize() -> void:
	if is_instance_valid(root) and root.get_child_count() > 0:
		var child := root.get_child(0)
		if is_instance_valid(child):
			queue_delete(child)
