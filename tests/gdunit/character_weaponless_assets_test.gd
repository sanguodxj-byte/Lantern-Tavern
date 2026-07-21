extends GdUnitTestSuite
## Accepted character meshes must remain body-only; equipment is attached separately.
## A-D rebuild-queue entries deliberately have no asset or generator requirement.

const TIERS := preload("res://data/character_model_tiers.gd")

const WEAPON_DIR := "res://assets/meshes/weapons"
const OUTPUT_CONSTANTS := ["STATIC_OUTPUT", "RIG_OUTPUT"]

const FORBIDDEN_PART_PREFIXES := [
	"axe_",
	"blade_hilt",
	"blade_guard",
	"blade_edge",
	"blade_tip",
	"blade_handle",
	"miner_pickaxe",
	"pyromancer_staff",
	"crossbow_stock",
	"crossbow_limb",
	"crossbow_string",
	"staff_shaft",
	"staff_hand_grip",
	"staff_skull",
	"staff_soul_flame",
	"shield_plate",
]

const SEPARATE_WEAPON_GLBS := [
	"weapons_voxel_axe.glb",
	"weapons_voxel_shortsword.glb",
	"weapons_voxel_crossbow.glb",
	"weapons_voxel_staff.glb",
	"weapons_voxel_shield.glb",
	"weapons_voxel_pickaxe.glb",
]


func test_separate_weapon_and_shield_glbs_exist() -> void:
	for file_name in SEPARATE_WEAPON_GLBS:
		var path := "%s/%s" % [WEAPON_DIR, file_name]
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("missing separate weapon/shield model: " + file_name) \
			.is_true()


func test_accepted_character_static_and_rig_outputs_do_not_bake_equipment() -> void:
	var failures: Array[String] = []
	for model_id in TIERS.accepted_model_ids():
		var generator_path := "res://tools/generate_voxel_%s.py" % model_id
		if not FileAccess.file_exists(generator_path):
			failures.append("%s: missing generator %s" % [model_id, generator_path])
			continue
		var source := FileAccess.get_file_as_string(generator_path)
		for constant_name in OUTPUT_CONSTANTS:
			var path := _output_path(source, constant_name)
			if path.is_empty():
				failures.append("%s: cannot resolve %s" % [model_id, constant_name])
				continue
			if not FileAccess.file_exists(path):
				failures.append("%s: missing %s at %s" % [model_id, constant_name, path])
				continue
			var packed := load(path) as PackedScene
			if packed == null:
				failures.append("%s: unloadable %s at %s" % [model_id, constant_name, path])
				continue
			var instance := packed.instantiate()
			var names: Array[String] = []
			_collect_names(instance, names)
			for part_name in names:
				var forbidden := _matching_forbidden_prefix(part_name)
				if not forbidden.is_empty():
					failures.append("%s %s bakes equipment part %s (%s)" % [
						model_id,
						constant_name,
						part_name,
						forbidden,
					])
			instance.free()
	_assert_no_failures("accepted body-only GLBs", failures)


func test_accepted_generators_document_body_only_policy() -> void:
	var failures: Array[String] = []
	for model_id in TIERS.accepted_model_ids():
		var path := "res://tools/generate_voxel_%s.py" % model_id
		if not FileAccess.file_exists(path):
			failures.append("%s: missing generator %s" % [model_id, path])
			continue
		var source := FileAccess.get_file_as_string(path)
		if not source.contains('MODEL_ID = "%s"' % model_id):
			failures.append("%s: generator owns the wrong MODEL_ID" % model_id)
		if not source.contains("reject_target_override(MODEL_ID)"):
			failures.append("%s: generator lacks fixed-target guard" % model_id)
		for forbidden_part in FORBIDDEN_PART_PREFIXES:
			if source.contains(forbidden_part):
				failures.append("%s generator authors forbidden equipment marker %s" % [
					model_id,
					forbidden_part,
				])
	_assert_no_failures("accepted body-only generators", failures)


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


func _matching_forbidden_prefix(part_name: String) -> String:
	for prefix in FORBIDDEN_PART_PREFIXES:
		if part_name.begins_with(prefix):
			return prefix
	return ""


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(String(node.name))
	for child in node.get_children():
		_collect_names(child, names)


func _assert_no_failures(label: String, failures: Array[String]) -> void:
	if not failures.is_empty():
		fail("%s:\n%s" % [label, "\n".join(failures)])
		return
	assert_bool(true).is_true()
