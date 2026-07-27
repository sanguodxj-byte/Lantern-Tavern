extends GdUnitTestSuite

const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const PX := 32.0

const PIECES := [
	{"id": "leather_helmet", "path": "res://assets/meshes/armor/armor_voxel_leather_helmet.glb", "min_w": 14.0, "min_h": 12.0, "min_d": 12.0},
	{"id": "iron_helmet", "path": "res://assets/meshes/armor/armor_voxel_iron_helmet.glb", "min_w": 22.0, "min_h": 16.0, "min_d": 12.0},
	{"id": "leather_bracers", "path": "res://assets/meshes/armor/armor_voxel_leather_bracers.glb", "min_w": 8.0, "min_h": 10.0, "min_d": 8.0},
	{"id": "iron_bracers", "path": "res://assets/meshes/armor/armor_voxel_iron_bracers.glb", "min_w": 9.0, "min_h": 11.0, "min_d": 9.0},
	{"id": "leather_boots", "path": "res://assets/meshes/armor/armor_voxel_leather_boots.glb", "min_w": 8.0, "min_h": 10.0, "min_d": 11.0},
	{"id": "iron_boots", "path": "res://assets/meshes/armor/armor_voxel_iron_boots.glb", "min_w": 9.0, "min_h": 11.0, "min_d": 12.0},
]


func test_set_piece_generators_declare_target_envelope() -> void:
	for piece in PIECES:
		var gen_path := "res://tools/generate_voxel_%s.py" % String(piece["id"])
		var source := FileAccess.get_file_as_string(gen_path)
		assert_str(source).contains("TARGET_ENVELOPE_PX")
		assert_str(source).contains("reject_target_override(MODEL_ID)")
		assert_str(source).contains("assert_parts_no_positive_volume_overlap")


func test_set_piece_glbs_meet_minimum_envelopes_and_have_no_overlap() -> void:
	for piece in PIECES:
		var path := String(piece["path"])
		assert_bool(FileAccess.file_exists(path)).override_failure_message("missing %s" % path).is_true()
		var packed := load(path) as PackedScene
		var instance := packed.instantiate() as Node3D
		add_child(instance)
		var size_px := _combined_aabb(instance).size * PX
		var axes := [size_px.x, size_px.y, size_px.z]
		axes.sort()
		var mins := [float(piece["min_d"]), float(piece["min_h"]), float(piece["min_w"])]
		mins.sort()
		assert_float(axes[0]).override_failure_message("%s small axis %.1f" % [piece["id"], axes[0]]).is_greater_equal(mins[0] - 1.5)
		assert_float(axes[1]).is_greater_equal(mins[1] - 1.5)
		assert_float(axes[2]).is_greater_equal(mins[2] - 1.5)
		assert_array(SUPPORT.find_positive_volume_overlaps(instance)).override_failure_message("%s has overlaps" % piece["id"]).is_empty()
		instance.free()


func _combined_aabb(node: Node3D) -> AABB:
	var boxes: Array[Dictionary] = []
	_collect_boxes(node, node, boxes)
	var result := AABB()
	var first := true
	for entry in boxes:
		var box: AABB = entry["aabb"]
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _collect_boxes(root_node: Node3D, node: Node, boxes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var root_space := root_node.global_transform.affine_inverse() * mesh_node.global_transform
			boxes.append({"aabb": root_space * mesh_node.get_aabb()})
	for child in node.get_children():
		_collect_boxes(root_node, child, boxes)


func test_iron_helmet_has_nordic_horn_identity_parts() -> void:
	var packed := load("res://assets/meshes/armor/armor_voxel_iron_helmet.glb") as PackedScene
	var instance := packed.instantiate() as Node3D
	add_child(instance)
	var names := _mesh_names(instance)
	for required in ["horn_tip_left", "horn_tip_right", "horn_flare_left", "nasal_guard", "dome_low"]:
		assert_bool(names.has(required)).override_failure_message("iron_helmet missing part %s in %s" % [required, str(names)]).is_true()
	assert_bool(names.has("front_brim")).is_false()
	instance.free()


func test_leather_helmet_is_soft_cap_not_horned() -> void:
	var packed := load("res://assets/meshes/armor/armor_voxel_leather_helmet.glb") as PackedScene
	var instance := packed.instantiate() as Node3D
	add_child(instance)
	var names := _mesh_names(instance)
	for required in ["crown_base", "front_brim", "ear_flap_left", "strap_buckle"]:
		assert_bool(names.has(required)).override_failure_message("leather_helmet missing part %s" % required).is_true()
	assert_bool(names.has("horn_tip_left")).is_false()
	assert_bool(names.has("nasal_guard")).is_false()
	instance.free()


func _mesh_names(node: Node) -> Dictionary:
	var result := {}
	if node is MeshInstance3D:
		result[String(node.name)] = true
	for child in node.get_children():
		result.merge(_mesh_names(child))
	return result
