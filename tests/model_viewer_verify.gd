#!/usr/bin/env -S godot -s
extends SceneTree

## Standalone verification script for model_viewer.gd logic.
## Run: godot --headless -s tests/model_viewer_verify.gd
## Writes results to user://model_viewer_verify.txt

func _initialize() -> void:
	print("=== MODEL VIEWER VERIFY START ===")
	var output: Array[String] = []
	var pass_count := 0
	var fail_count := 0

	# Load the model viewer script
	var script := load("res://scenes/ui/model_viewer.gd")
	if script == null:
		_write_output("FATAL: Failed to load model_viewer.gd")
		quit(1)
		return

	var viewer: Control = script.new()

	# ── Test: _filename_to_display_name ────────────────────────────────
	var cases := {
		"weapons_axe.glb": "Axe",
		"weapons_shortsword.glb": "Shortsword",
		"weapons_voxel_longsword.glb": "Voxel Longsword",
		"armor_voxel_chain_armor.glb": "Voxel Chain Armor",
		"armor_voxel_plate_armor.glb": "Voxel Plate Armor",
		"props_fireplace.glb": "Fireplace",
		"materials_voxel_glowcap.glb": "Voxel Glowcap",
		"materials_blackberry.glb": "Blackberry",
		"environment_tutorial_road_blocker.glb": "Road Blocker",
		"voxel_goblin_32px.glb": "Voxel Goblin",
		"voxel_dragon_256px.glb": "Voxel Dragon",
		"voxel_troll_64x.glb": "Voxel Troll",
		"barrel-fragmented.glb": "Barrel Fragmented",
		"voxel_door_frame.glb": "Door Frame",
		"voxel_ceiling_tiles.glb": "Ceiling Tiles",
		"voxel_character.glb": "Voxel Character",
		"torch.glb": "Torch",
		"voxel_buckler.glb": "Voxel Buckler",
	}

	output.append("=== _filename_to_display_name tests ===")
	for input in cases.keys():
		var expected: String = cases[input]
		var actual: String = viewer._filename_to_display_name(input)
		if actual == expected:
			pass_count += 1
			output.append("  PASS: %s -> '%s'" % [input, actual])
		else:
			fail_count += 1
			output.append("  FAIL: %s -> '%s' (expected '%s')" % [input, actual, expected])

	# ── Test: Meshy AI model name ──────────────────────────────────────
	var meshy_name: String = viewer._filename_to_display_name("Meshy_AI_Crimson_Ironclad_0705221238_texture.glb")
	if meshy_name == "Crimson Ironclad":
		pass_count += 1
		output.append("  PASS: Meshy AI -> '%s'" % meshy_name)
	else:
		fail_count += 1
		output.append("  FAIL: Meshy AI -> '%s' (expected 'Crimson Ironclad')" % meshy_name)

	# ── Test: GLB scan config ──────────────────────────────────────────
	output.append("\n=== GLB scan config tests ===")
	var config: Dictionary = viewer._GLB_SCAN_CONFIG
	var expected_cats := ["Characters & Monsters", "Dungeon Structures", "Voxel Materials", "Environment"]
	for cat in expected_cats:
		if config.has(cat):
			pass_count += 1
			output.append("  PASS: config has '%s'" % cat)
		else:
			fail_count += 1
			output.append("  FAIL: config missing '%s'" % cat)

	# ── Test: scan directories exist ───────────────────────────────────
	output.append("\n=== Directory existence tests ===")
	for cat in config.keys():
		for dir_path in config[cat]:
			var dir := DirAccess.open(dir_path)
			if dir != null:
				pass_count += 1
				output.append("  PASS: %s exists (%s)" % [dir_path, cat])
			else:
				fail_count += 1
				output.append("  FAIL: %s not found (%s)" % [dir_path, cat])

	# ── Test: directories have GLB files ───────────────────────────────
	output.append("\n=== GLB file count tests ===")
	var count_cases := {
		"res://assets/meshes/characters/": 5,
		"res://assets/meshes/weapons/": 10,
		"res://assets/meshes/armor/": 4,
		"res://assets/models/materials/": 10,
		"res://assets/models/environment/": 3,
	}
	for dir_path in count_cases.keys():
		var min_expected: int = count_cases[dir_path]
		var count := _count_glbs(dir_path)
		if count >= min_expected:
			pass_count += 1
			output.append("  PASS: %s has %d GLBs (>= %d)" % [dir_path, count, min_expected])
		else:
			fail_count += 1
			output.append("  FAIL: %s has %d GLBs (expected >= %d)" % [dir_path, count, min_expected])

	# ── Test: source code checks ───────────────────────────────────────
	output.append("\n=== Source code tests ===")
	var source: String = script.source_code
	var source_checks := {
		"WeaponRegistry": "uses WeaponRegistry",
		"_build_asset_database": "has dynamic database builder",
		"_scan_glb_directory": "has directory scanner",
		"DirAccess": "uses DirAccess",
	}
	for pattern in source_checks.keys():
		if source.contains(pattern):
			pass_count += 1
			output.append("  PASS: %s" % source_checks[pattern])
		else:
			fail_count += 1
			output.append("  FAIL: missing '%s'" % pattern)

	# ── Test: no OBJ references ────────────────────────────────────────
	output.append("\n=== No OBJ references ===")
	var obj_patterns := [".obj", "_classify_obj", "_obj_to_display_name", "_add_obj_models", "_OBJ_DIR", "_OBJ_MONSTERS"]
	for pattern in obj_patterns:
		if not source.contains(pattern):
			pass_count += 1
			output.append("  PASS: '%s' not found in source" % pattern)
		else:
			fail_count += 1
			output.append("  FAIL: '%s' still in source" % pattern)

	# ── Summary ────────────────────────────────────────────────────────
	output.append("\n=== SUMMARY ===")
	output.append("Total: %d passed, %d failed" % [pass_count, fail_count])
	if fail_count == 0:
		output.append("ALL TESTS PASSED")
	else:
		output.append("SOME TESTS FAILED")

	_write_output("\n".join(PackedStringArray(output)))
	viewer.free()
	quit(0 if fail_count == 0 else 1)


func _count_glbs(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".glb") and not fn.ends_with(".import"):
			count += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return count


func _write_output(text: String) -> void:
	# Try user:// path first (always writable), then fall back to res://
	var path := "user://model_viewer_verify.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
		print("Results written to: ", path)
	# Also try res:// for convenience
	var res_file := FileAccess.open("res://reports/model_viewer_verify.txt", FileAccess.WRITE)
	if res_file:
		res_file.store_string(text)
		res_file.close()
	print(text)
