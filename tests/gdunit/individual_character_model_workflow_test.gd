extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")

const FORBIDDEN_NON_MODEL_IDS := ["character", "bear"]

const REMOVED_BATCH_ENTRY_POINTS := [
	"res://tools/remake_all_voxel_weapons.py",
	"res://tools/generate_voxel_armor.py",
	"res://tools/generate_tutorial_voxel_environment.py",
	"res://tools/generate_voxel_material_samples.py",
	"res://tools/bake_all_props.gd",
	"res://tools/bake_all_props.gd.uid",
	"res://tools/remake_all_fail_characters.py",
	"res://tools/generate_voxel_creature_batch.py",
	"res://tools/generate_voxel_humanoid_remakes.py",
	"res://tools/generate_voxel_roguelike_monsters.py",
	"res://tools/generate_voxel_creature_rigs.py",
	"res://tools/generate_enemy_scenes_from_roster.py",
	"res://tools/remake_player_and_materials.py",
	"res://tools/render_character_previews.py",
	"res://tools/capture_roguelike_monster_views.bat",
	"res://tools/build_voxel_rigid_rigs.py",
	"res://tools/generate_character_combat_animations.py",
	"res://_run_regen.bat",
]

const FORBIDDEN_MULTI_TARGET_MARKERS := [
	"argparse.ArgumentParser",
	"sys.argv",
	"--all",
	"MONSTERS =",
	"HUMANOID_RIGS =",
	"CREATURE_CONFIGS =",
	"MODEL_REGISTRY =",
	"for model_id in",
	"for creature_id in",
	".glob(",
	".rglob(",
	".iterdir(",
	"os.listdir(",
	"subprocess.run(",
]

const REMOVED_MODEL_DIAGNOSTICS := [
	"res://tools/animation_track_diag.gd",
	"res://tools/animation_track_diag.gd.uid",
	"res://tools/runtime_vs_preview_diag.gd",
	"res://tools/runtime_vs_preview_diag.gd.uid",
	"res://tools/skeleton_facing_diag.gd",
	"res://tools/skeleton_facing_diag.gd.uid",
	"res://tools/_skeleton_orientation_diag.gd",
	"res://tools/_skeleton_orientation_diag.gd.uid",
	"res://tools/_skeleton_anim_capture.gd",
	"res://tools/_skeleton_anim_capture.gd.uid",
	"res://tools/_probe_player_rig_anims.gd.uid",
	"res://tools/_probe_rig_names.gd.uid",
	"res://tools/_probe_rig_tracks.gd.uid",
]

func test_agents_requires_one_model_per_modeling_workflow() -> void:
	var agents := FileAccess.get_file_as_string("res://AGENTS.md")
	assert_str(agents).contains("One Model Per Modeling Workflow")
	assert_str(agents).contains("must always target exactly one model")
	assert_str(agents).contains("Batch model generators are forbidden")
	assert_str(agents).contains("characters, creatures, players, weapons, armor, props, and environment assets")
	assert_str(agents).contains("Shared base-body, generic humanoid, creature-family, and silhouette templates are forbidden")
	assert_str(agents).contains("Mesh or part count is not a quality metric")
	assert_str(agents).contains("must never overwrite one another")
	assert_str(agents).contains("Read-only validation may scan multiple existing assets")


func test_agents_documents_only_the_single_spec_blender_pipeline() -> void:
	var agents := FileAccess.get_file_as_string("res://AGENTS.md")
	assert_str(agents).contains("exactly one JSON asset spec for exactly one asset")
	assert_str(agents).contains("run_pipeline.py --spec <spec.json>")
	assert_str(agents).contains("repeated `--spec`, `--batch`")
	assert_str(agents).not_contains("asset_specs/weapons/*.json")
	assert_str(agents).not_contains("run_all.py (Blender)")


func test_batch_3d_modeling_entry_points_are_removed() -> void:
	for path in REMOVED_BATCH_ENTRY_POINTS:
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("batch modeling entry point must be removed: %s" % path) \
			.is_false()
	var prop_source := FileAccess.get_file_as_string("res://scenes/props/voxel_prop.gd")
	assert_str(prop_source).not_contains("bake_all_props")
	assert_str(prop_source).not_contains("trigger_bake")
	assert_str(prop_source).contains("func bake_to_asset()")


func test_rejected_non_models_and_generic_body_template_are_absent() -> void:
	for model_id in FORBIDDEN_NON_MODEL_IDS:
		assert_bool(FileAccess.file_exists("res://tools/generate_voxel_%s.py" % model_id)).is_false()
	assert_bool(FileAccess.file_exists("res://tools/voxel_single_humanoid.py")).is_false()


func test_every_accepted_character_has_one_fixed_identity_generator_and_unique_outputs() -> void:
	var seen_model_ids := {}
	var seen_outputs := {}
	for expected_id in TIERS.accepted_model_ids():
		var path := "res://tools/generate_voxel_%s.py" % expected_id
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("missing individual generator: %s" % path) \
			.is_true()
		if not FileAccess.file_exists(path):
			continue

		var source := FileAccess.get_file_as_string(path)
		for constant_name in ["MODEL_ID", "STATIC_OUTPUT", "RIG_OUTPUT"]:
			assert_int(_assignment_count(source, constant_name)) \
				.override_failure_message("%s must declare %s exactly once" % [path, constant_name]) \
				.is_equal(1)

		var model_id := _quoted_assignment_value(source, "MODEL_ID")
		assert_str(model_id) \
			.override_failure_message("generator owns the wrong MODEL_ID: %s" % path) \
			.is_equal(expected_id)
		assert_bool(seen_model_ids.has(model_id)) \
			.override_failure_message("MODEL_ID is owned by more than one generator: %s" % model_id) \
			.is_false()
		if not model_id.is_empty():
			seen_model_ids[model_id] = path

		var static_output := _resolved_output_path(source, "STATIC_OUTPUT")
		var rig_output := _resolved_output_path(source, "RIG_OUTPUT")
		_assert_owned_output(path, expected_id, static_output, false, seen_outputs)
		_assert_owned_output(path, expected_id, rig_output, true, seen_outputs)
		assert_str(static_output) \
			.override_failure_message("static and rig outputs must differ: %s" % path) \
			.is_not_equal(rig_output)


func test_individual_generators_reject_alternate_and_multi_target_modes() -> void:
	for model_id in TIERS.accepted_model_ids():
		var path := "res://tools/generate_voxel_%s.py" % model_id
		if not FileAccess.file_exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		assert_str(source) \
			.override_failure_message("generator must import the fixed-target guard: %s" % path) \
			.contains("from voxel_single_model_cli import reject_target_override")
		assert_str(source) \
			.override_failure_message("generator main must reject alternate targets: %s" % path) \
			.contains("reject_target_override(MODEL_ID)")
		assert_str(source) \
			.override_failure_message("accepted generator must not use the rejected generic body template: %s" % path) \
			.not_contains("voxel_single_humanoid")
		for marker in FORBIDDEN_MULTI_TARGET_MARKERS:
			assert_str(source) \
				.override_failure_message("generator contains multi-target behavior '%s': %s" % [marker, path]) \
				.not_contains(marker)


func test_fixed_target_guard_accepts_only_the_owned_model_identity() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_single_model_cli.py")
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains("args == [model_id]")
	assert_str(source).contains("raise SystemExit")
	assert_str(source).not_contains('args == ["all"]')


func test_legacy_model_diagnostics_and_orphan_probe_uids_are_removed() -> void:
	for path in REMOVED_MODEL_DIAGNOSTICS:
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("legacy model diagnostic must be removed: %s" % path) \
			.is_false()


func test_monster_three_view_capture_is_single_target_and_allowlisted() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	var monster_block := _source_between(source, "const MONSTER_SCENES := {", "var _had_error := false")
	var accepted_ids := _accepted_model_ids_sorted()
	var capture_ids := _quoted_dictionary_keys(monster_block)
	assert_array(capture_ids) \
		.override_failure_message("monster capture allowlist must exactly match CharacterModelTiers.ACCEPTED_IDS") \
		.is_equal(accepted_ids)
	for removed_flag in ["--monsters-only", "--spider-only", "--bear-only"]:
		assert_str(source) \
			.override_failure_message("removed monster capture selector returned: %s" % removed_flag) \
			.not_contains(removed_flag)
	assert_str(source).not_contains("for monster_id in MONSTER_SCENES.keys()")
	assert_int(source.count("_capture_monster(")) \
		.override_failure_message("monster capture must only be called for one requested asset") \
		.is_equal(2)
	assert_str(source).contains("model capture requires exactly one --asset=<model_id>")


func test_character_material_preview_is_single_target_and_has_four_godot_render_outputs() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_material_render_preview.gd")
	var character_block := _source_between(source, "const CHARACTER_SCENES := {", "const PREVIEW_SCENES := [")
	var accepted_ids := _accepted_model_ids_sorted()
	var capture_ids := _quoted_dictionary_keys(character_block)
	assert_array(capture_ids) \
		.override_failure_message("material preview allowlist must exactly match CharacterModelTiers.ACCEPTED_IDS") \
		.is_equal(accepted_ids)
	for removed_flag in ["--dragon-only", "--spider-only"]:
		assert_str(source) \
			.override_failure_message("removed material preview selector returned: %s" % removed_flag) \
			.not_contains(removed_flag)
	assert_int(source.count("_add_character_preview(")) \
		.override_failure_message("material preview must instantiate only one requested character") \
		.is_equal(2)
	assert_str(source).not_contains("for model_id in CHARACTER_SCENES")
	assert_str(source).contains("requires exactly one --asset=<model_id>")
	assert_str(source).contains("voxel_%s_render_%s.png")
	assert_str(source).contains("voxel_%s_godot_material.png")
	for view_name in ["preview", "front", "side", "top"]:
		assert_str(source).contains('"%s"' % view_name)
	assert_str(source).contains('"front": Vector3(0.0, 0.0, -1.0)')
	assert_str(source).contains('"side": Vector3(1.0, 0.0, 0.0)')
	assert_str(source).contains('"top": Vector3(0.0, 1.0, 0.0)')
	assert_str(source).contains("func _frame_character_camera(")
	assert_str(source).contains("screen_up_vector := direction.cross(right_vector).normalized()")
	assert_str(source).contains("offset.dot(screen_up_vector)")
	assert_str(source).contains("func _validate_rendered_image(")
	assert_str(source).contains("func _sample_foreground_count(")
	var capture_block := _source_between(
		source,
		"func _capture_character_views(",
		"func _frame_character_camera("
	)
	assert_str(capture_block).contains("for view_name in CHARACTER_VIEW_ORDER")
	assert_str(capture_block).contains("await process_frame")
	assert_str(capture_block).contains("_validate_rendered_image(image, label, 12, true)")
	assert_str(capture_block).not_contains("CHARACTER_SCENES")
	assert_str(capture_block).not_contains("instantiate()")


func _assignment_count(source: String, constant_name: String) -> int:
	var count := 0
	for raw_line in source.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with("%s =" % constant_name):
			count += 1
	return count


func _assignment_expression(source: String, constant_name: String) -> String:
	var prefix := "%s =" % constant_name
	for raw_line in source.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with(prefix):
			return line.trim_prefix(prefix).strip_edges()
	return ""


func _quoted_assignment_value(source: String, constant_name: String) -> String:
	var expression := _assignment_expression(source, constant_name)
	var tokens := _quoted_tokens(expression)
	if tokens.size() != 1:
		return ""
	return tokens[0]


func _resolved_output_path(source: String, constant_name: String) -> String:
	var expression := _assignment_expression(source, constant_name)
	var visited := {}
	while expression.is_valid_identifier() and not visited.has(expression):
		visited[expression] = true
		expression = _assignment_expression(source, expression)
	var tokens := _quoted_tokens(expression)
	return "/".join(tokens)


func _quoted_tokens(expression: String) -> Array[String]:
	var tokens: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile('"([^"]+)"') != OK:
		return tokens
	for match_result in pattern.search_all(expression):
		tokens.append(match_result.get_string(1))
	return tokens


func _source_between(source: String, start_marker: String, end_marker: String) -> String:
	var start := source.find(start_marker)
	var end := source.find(end_marker, start + start_marker.length())
	if start < 0 or end < 0:
		return ""
	return source.substr(start, end - start)


func _accepted_model_ids_sorted() -> Array[String]:
	var ids: Array[String] = TIERS.ACCEPTED_IDS.duplicate()
	ids.sort()
	return ids


func _quoted_dictionary_keys(source_block: String) -> Array[String]:
	var keys: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile('(?m)^\\s*"([^"]+)"\\s*:') != OK:
		return keys
	for match_result in pattern.search_all(source_block):
		keys.append(match_result.get_string(1))
	keys.sort()
	return keys


func _assert_owned_output(
	generator_path: String,
	model_id: String,
	output_path: String,
	is_rig: bool,
	seen_outputs: Dictionary
) -> void:
	assert_bool(output_path.is_empty()) \
		.override_failure_message("unresolvable fixed output in %s" % generator_path) \
		.is_false()
	assert_str(output_path) \
		.override_failure_message("output must stay in the character asset directory: %s" % generator_path) \
		.starts_with("assets/meshes/characters/")
	var file_name := output_path.get_file()
	assert_str(file_name) \
		.override_failure_message("output filename does not belong to %s: %s" % [model_id, file_name]) \
		.starts_with("voxel_%s_" % model_id)
	if is_rig:
		assert_str(file_name).ends_with("_rig.glb")
	else:
		assert_str(file_name).ends_with(".glb")
		assert_str(file_name).not_contains("_rig.glb")
	assert_bool(seen_outputs.has(output_path)) \
		.override_failure_message("output is written by multiple generators: %s" % output_path) \
		.is_false()
	if not output_path.is_empty():
		seen_outputs[output_path] = generator_path
