extends GdUnitTestSuite
## Voxel animation specification, validator, and accepted-rig integration tests.
## A-D model IDs remain queue metadata and are never treated as existing assets here.

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")
const SPEC_PATH := "res://globals/visual/voxel_animation_spec.gd"
const CREATURE_IDS := ["dragon", "slime", "spider"]
const VISUAL_REVIEW_SA_IDS := [
	"dragon", "rock_golem",
	"drow_blade", "spider", "orc_raider", "skeleton", "troll", "player",
	"minotaur", "slime",
]
const FACING_ROTATIONS := {
	"dragon": -PI / 2.0,
	"slime": PI,
	"spider": PI,
}

var spec: Variant


func before_test() -> void:
	spec = load(SPEC_PATH)


func test_spec_meters_per_pixel_matches_voxel_workflow() -> void:
	assert_float(spec.METERS_PER_PIXEL).is_equal(1.0 / 32.0)


func test_spec_humanoid_required_bones_includes_weapon_hands() -> void:
	var bones = spec.HUMANOID_REQUIRED_BONES
	assert_bool(bones.has("Hand.R")).is_true()
	assert_bool(bones.has("Hand.L")).is_true()
	assert_str(spec.WEAPON_HAND_BONE).is_equal("Hand.R")
	assert_str(spec.SHIELD_HAND_BONE).is_equal("Hand.L")


func test_spec_humanoid_required_bones_has_17_entries() -> void:
	assert_int(spec.HUMANOID_REQUIRED_BONES.size()).is_equal(17)


func test_spec_weapon_attack_animations_complete() -> void:
	var expected := [
		"slash",
		"slash_one_hand",
		"slash_heavy",
		"slash_dagger",
		"thrust_spear",
		"bash_shield",
		"claw_swipe",
	]
	for animation_name in expected:
		assert_bool(spec.WEAPON_ATTACK_ANIMATIONS.has(animation_name)).is_true()
	assert_int(spec.WEAPON_ATTACK_ANIMATIONS.size()).is_equal(expected.size())


func test_spec_humanoid_required_animations_is_union() -> void:
	var required = spec.humanoid_required_animations()
	var expected_size: int = spec.BASE_ANIMATIONS.size() \
		+ spec.WEAPON_ATTACK_ANIMATIONS.size() \
		+ spec.POSE_ANIMATIONS.size()
	assert_int(required.size()).is_equal(expected_size)
	for animation_name in ["slash_one_hand", "hold_weapon", "default", "idle"]:
		assert_bool(required.has(animation_name)).is_true()


func test_spec_creature_required_animations_minimal() -> void:
	var required = spec.creature_required_animations()
	for animation_name in ["slash", "claw_swipe", "default"]:
		assert_bool(required.has(animation_name)).is_true()


func test_spec_no_duplicate_animation_names() -> void:
	var seen := {}
	for animation_name in spec.humanoid_required_animations():
		assert_bool(seen.has(animation_name)).is_false()
		seen[animation_name] = true


func test_shared_humanoid_animation_authoring_contains_only_game_actions() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_character_rig.py")
	assert_str(source).not_contains("debug_")
	assert_str(source).not_contains("import random")
	var pattern := RegEx.new()
	assert_int(pattern.compile('make_action\\(armature, "([^"]+)"')).is_equal(OK)
	var authored: Array[String] = []
	for match_result in pattern.search_all(source):
		authored.append(match_result.get_string(1))
	var expected: Array[String] = []
	expected.assign(spec.humanoid_required_animations())
	authored.sort()
	expected.sort()
	assert_array(authored).is_equal(expected)


func test_spec_classifies_weapon_bones_and_attacks() -> void:
	assert_bool(spec.is_weapon_bone("Hand.R")).is_true()
	assert_bool(spec.is_weapon_bone("Hand.L")).is_true()
	assert_bool(spec.is_weapon_bone("Head")).is_false()
	assert_bool(spec.is_weapon_attack_animation("slash_heavy")).is_true()
	assert_bool(spec.is_weapon_attack_animation("idle")).is_false()


func test_validator_invalid_path_reports_error() -> void:
	var report = VALIDATOR.validate_glb("res://nonexistent_rig.glb", true)
	assert_bool(report.ok).is_false()
	assert_bool(report.errors.is_empty()).is_false()


func test_validator_report_to_string_ok() -> void:
	var validator_script = load("res://globals/visual/voxel_rig_validator.gd")
	var report = validator_script.Report.new()
	report.ok = true
	report.bone_names.assign(["Root", "Torso"])
	report.animation_names.assign(["idle", "run"])
	assert_str(str(report)).contains("OK")
	assert_str(str(report)).contains("bones=2")


func test_validator_report_to_string_fail() -> void:
	var validator_script = load("res://globals/visual/voxel_rig_validator.gd")
	var report = validator_script.Report.new()
	report.ok = false
	report.missing_animations.assign(["slash_one_hand"])
	assert_str(str(report)).contains("FAIL")
	assert_str(str(report)).contains("slash_one_hand")


func test_every_accepted_model_has_generator_static_and_rig_outputs() -> void:
	var failures: Array[String] = []
	for entry in _accepted_entries():
		var model_id: String = entry["id"]
		var generator_path: String = entry["generator_path"]
		var source: String = entry["source"]
		if source.is_empty():
			failures.append("%s: missing or empty generator %s" % [model_id, generator_path])
			continue
		if not source.contains('MODEL_ID = "%s"' % model_id):
			failures.append("%s: generator owns the wrong MODEL_ID" % model_id)
		if not source.contains("reject_target_override(MODEL_ID)"):
			failures.append("%s: generator lacks fixed-target guard" % model_id)
		for key in ["static_path", "rig_path"]:
			var path: String = entry[key]
			if path.is_empty():
				failures.append("%s: cannot resolve %s" % [model_id, key])
			elif not FileAccess.file_exists(path):
				failures.append("%s: missing %s at %s" % [model_id, key, path])
	_assert_no_failures("accepted model rig output contract", failures)


func test_accepted_humanoid_rigs_have_required_bones_and_animations() -> void:
	var failures: Array[String] = []
	for entry in _accepted_entries():
		if not bool(entry["humanoid"]):
			continue
		if not _require_rig(entry, failures):
			continue
		var model_id: String = entry["id"]
		var report = VALIDATOR.validate_glb(entry["rig_path"], true)
		for error in report.errors:
			failures.append("%s: %s" % [model_id, error])
		for bone_name in report.missing_bones:
			failures.append("%s: missing bone %s" % [model_id, bone_name])
		for animation_name in report.missing_animations:
			failures.append("%s: missing animation %s" % [model_id, animation_name])
		for animation_name in spec.WEAPON_ATTACK_ANIMATIONS:
			if not report.animation_names.has(animation_name):
				failures.append("%s: missing weapon animation %s" % [model_id, animation_name])
		for pose_name in ["hold_weapon", "default"]:
			if not report.animation_names.has(pose_name):
				failures.append("%s: missing pose %s" % [model_id, pose_name])
	_assert_no_failures("accepted humanoid rig contract", failures)


func test_visual_review_s_and_a_models_have_their_own_correct_skeletons() -> void:
	var entries := _accepted_entries()
	var by_id: Dictionary = {}
	for entry in entries:
		by_id[String(entry["id"])] = entry
	var failures: Array[String] = []
	for model_id in VISUAL_REVIEW_SA_IDS:
		if not by_id.has(model_id):
			failures.append("%s: S/A visual-review model is not accepted" % model_id)
			continue
		var entry: Dictionary = by_id[model_id]
		if not bool(entry["humanoid"]):
			continue
		var report = VALIDATOR.validate_glb(entry["rig_path"], true)
		for error in report.errors:
			failures.append("%s: %s" % [model_id, error])
		for bone_name in report.missing_bones:
			failures.append("%s: missing bone %s" % [model_id, bone_name])
	_assert_no_failures("visual-review S/A skeleton contract", failures)


func test_accepted_creature_rigs_have_required_animations() -> void:
	var failures: Array[String] = []
	for entry in _accepted_entries():
		if bool(entry["humanoid"]):
			continue
		if not _require_rig(entry, failures):
			continue
		var model_id: String = entry["id"]
		var report = VALIDATOR.validate_glb(entry["rig_path"], false)
		for error in report.errors:
			failures.append("%s: %s" % [model_id, error])
		for animation_name in report.missing_animations:
			failures.append("%s: missing animation %s" % [model_id, animation_name])
		if not report.animation_names.has("claw_swipe"):
			failures.append("%s: missing claw_swipe" % model_id)
	_assert_no_failures("accepted creature rig contract", failures)


func test_accepted_rigs_have_authored_facing_rotation() -> void:
	var failures: Array[String] = []
	for entry in _accepted_entries():
		if not _require_rig(entry, failures):
			continue
		var model_id: String = entry["id"]
		var scene := load(entry["rig_path"]) as PackedScene
		if scene == null:
			failures.append("%s: rig is not loadable" % model_id)
			continue
		var instance := scene.instantiate()
		var expected: float = float(FACING_ROTATIONS.get(model_id, PI))
		if not _has_facing_rotation(instance, expected):
			var dump: Array[String] = []
			_dump_rotations(instance, "", dump)
			failures.append("%s: missing expected facing rotation %.4f\n%s" % [
				model_id,
				expected,
				"\n".join(dump),
			])
		instance.free()
	_assert_no_failures("accepted rig facing", failures)


func _accepted_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for model_id in TIERS.accepted_model_ids():
		var generator_path := "res://tools/generate_voxel_%s.py" % model_id
		var source := FileAccess.get_file_as_string(generator_path) \
			if FileAccess.file_exists(generator_path) else ""
		entries.append({
			"id": model_id,
			"generator_path": generator_path,
			"source": source,
			"static_path": _output_path(source, "STATIC_OUTPUT"),
			"rig_path": _output_path(source, "RIG_OUTPUT"),
			"humanoid": not CREATURE_IDS.has(model_id),
		})
	return entries


func _require_rig(entry: Dictionary, failures: Array[String]) -> bool:
	var model_id: String = entry["id"]
	if String(entry["source"]).is_empty():
		failures.append("%s: missing generator %s" % [model_id, entry["generator_path"]])
		return false
	var path: String = entry["rig_path"]
	if path.is_empty():
		failures.append("%s: cannot resolve RIG_OUTPUT" % model_id)
		return false
	if not FileAccess.file_exists(path):
		failures.append("%s: missing rig %s" % [model_id, path])
		return false
	return true


func _output_path(source: String, constant_name: String) -> String:
	var prefix := "%s =" % constant_name
	var expression := ""
	for raw_line in source.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with(prefix):
			expression = line.trim_prefix(prefix).strip_edges()
			break
	if expression.is_empty():
		return ""
	var regex := RegEx.new()
	if regex.compile('"([^"]+)"') != OK:
		return ""
	var tokens: Array[String] = []
	for match_result in regex.search_all(expression):
		tokens.append(match_result.get_string(1))
	if tokens.size() < 2:
		return ""
	return "res://%s" % "/".join(tokens)


func _rot_y_matches(rot_y: float, expected: float, tolerance: float = 0.05) -> bool:
	var norm_actual := fmod(rot_y, TAU)
	if norm_actual < 0.0:
		norm_actual += TAU
	var norm_expected := fmod(expected, TAU)
	if norm_expected < 0.0:
		norm_expected += TAU
	var difference := absf(norm_actual - norm_expected)
	if difference > PI:
		difference = TAU - difference
	return difference < tolerance


func _has_facing_rotation(root: Node, expected_rot_y: float) -> bool:
	if root is Node3D and _rot_y_matches((root as Node3D).rotation.y, expected_rot_y):
		return true
	for child in root.get_children():
		if _has_facing_rotation(child, expected_rot_y):
			return true
	return false


func _dump_rotations(node: Node, indent: String, output: Array[String]) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		output.append("%s%s rot=(%.4f, %.4f, %.4f)" % [
			indent,
			node.name,
			node_3d.rotation.x,
			node_3d.rotation.y,
			node_3d.rotation.z,
		])
	for child in node.get_children():
		_dump_rotations(child, indent + "  ", output)


func _assert_no_failures(label: String, failures: Array[String]) -> void:
	if not failures.is_empty():
		fail("%s:\n%s" % [label, "\n".join(failures)])
		return
	assert_bool(true).is_true()
