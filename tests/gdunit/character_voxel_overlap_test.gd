extends GdUnitTestSuite
## Accepted character GLBs must preserve the project voxel assembly contract.
## A-D entries remain rebuild-queue metadata and are intentionally not loaded here.

const TIERS := preload("res://data/character_model_tiers.gd")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const OUTPUT_CONSTANTS := ["STATIC_OUTPUT", "RIG_OUTPUT"]

## These original S assets remain visual references despite pre-guard topology.
## Never add a rebuilt A-D model here: newly accepted models must be overlap-free.
const LEGACY_S_GEOMETRY_DEBT := ["orc_raider", "rock_golem"]


func test_legacy_geometry_debt_is_fixed_to_existing_accepted_s_models() -> void:
	assert_array(LEGACY_S_GEOMETRY_DEBT).contains_exactly(["orc_raider", "rock_golem"])
	for model_id in LEGACY_S_GEOMETRY_DEBT:
		assert_bool(TIERS.is_accepted(model_id)).is_true()
		assert_str(TIERS.tier_for(model_id)).is_equal(TIERS.S)


func test_accepted_models_have_individual_generators_static_and_rig_outputs() -> void:
	var failures: Array[String] = []
	for model_id in TIERS.accepted_model_ids():
		var generator_path := _generator_path(model_id)
		if not FileAccess.file_exists(generator_path):
			failures.append("%s: missing generator %s" % [model_id, generator_path])
			continue
		var source := FileAccess.get_file_as_string(generator_path)
		if not source.contains('MODEL_ID = "%s"' % model_id):
			failures.append("%s: generator does not own its MODEL_ID" % model_id)
		if not source.contains("reject_target_override(MODEL_ID)"):
			failures.append("%s: generator lacks fixed-target guard" % model_id)
		for constant_name in OUTPUT_CONSTANTS:
			var path := _output_path(source, constant_name)
			if path.is_empty():
				failures.append("%s: cannot resolve %s" % [model_id, constant_name])
			elif not FileAccess.file_exists(path):
				failures.append("%s: missing %s at %s" % [model_id, constant_name, path])
	_assert_no_failures("accepted model output contract", failures)


func test_accepted_static_and_rig_glbs_have_no_positive_volume_overlap() -> void:
	var failures: Array[String] = []
	for model_id in TIERS.accepted_model_ids():
		var source := _read_generator(model_id, failures)
		if source.is_empty():
			continue
		for constant_name in OUTPUT_CONSTANTS:
			var path := _output_path(source, constant_name)
			var instance := _instantiate_output(model_id, constant_name, path, failures)
			if instance == null:
				continue
			var overlaps: Array[Dictionary] = SUPPORT.find_positive_volume_overlaps(instance)
			if LEGACY_S_GEOMETRY_DEBT.has(model_id):
				instance.free()
				continue
			for overlap in overlaps.slice(0, 12):
				failures.append("%s %s: %s overlaps %s by %s" % [
					model_id,
					constant_name,
					overlap["left"],
					overlap["right"],
					overlap["overlap"],
				])
			instance.free()
	_assert_no_failures("accepted model positive-volume overlap", failures)


func test_accepted_static_glbs_are_single_face_connected_components() -> void:
	var failures: Array[String] = []
	for model_id in TIERS.accepted_model_ids():
		var source := _read_generator(model_id, failures)
		if source.is_empty():
			continue
		var path := _output_path(source, "STATIC_OUTPUT")
		var instance := _instantiate_output(model_id, "STATIC_OUTPUT", path, failures)
		if instance == null:
			continue
		var disconnected: Array[String] = SUPPORT.find_face_disconnected_parts(instance)
		if LEGACY_S_GEOMETRY_DEBT.has(model_id):
			instance.free()
			continue
		if not disconnected.is_empty():
			failures.append("%s: disconnected static parts %s" % [
				model_id,
				str(disconnected.slice(0, 20)),
			])
		instance.free()
	_assert_no_failures("accepted model face connectivity", failures)


func _generator_path(model_id: String) -> String:
	return "res://tools/generate_voxel_%s.py" % model_id


func _read_generator(model_id: String, failures: Array[String]) -> String:
	var path := _generator_path(model_id)
	if not FileAccess.file_exists(path):
		failures.append("%s: missing generator %s" % [model_id, path])
		return ""
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		failures.append("%s: empty generator %s" % [model_id, path])
	return source


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


func _instantiate_output(
	model_id: String,
	constant_name: String,
	path: String,
	failures: Array[String],
) -> Node3D:
	if path.is_empty():
		failures.append("%s: cannot resolve %s" % [model_id, constant_name])
		return null
	if not FileAccess.file_exists(path):
		failures.append("%s: missing %s at %s" % [model_id, constant_name, path])
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("%s: unloadable %s at %s" % [model_id, constant_name, path])
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		failures.append("%s: cannot instantiate %s at %s" % [model_id, constant_name, path])
		return null
	add_child(instance)
	return instance


func _assert_no_failures(label: String, failures: Array[String]) -> void:
	if not failures.is_empty():
		fail("%s:\n%s" % [label, "\n".join(failures)])
		return
	assert_bool(true).is_true()
