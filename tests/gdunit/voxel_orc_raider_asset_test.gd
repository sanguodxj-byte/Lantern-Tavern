extends GdUnitTestSuite
## 兽人掠夺者体素重做资产回归：静态 GLB + rig + 语义部件 + 预览图

const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")

const STATIC_PATH := "res://assets/meshes/characters/voxel_orc_raider_48px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_orc_raider_48px_rig.glb"

const REQUIRED_PARTS := [
	"head_main",
	"head_jaw",
	"brow_ridge",
	"nose_bridge",
	"eye_left",
	"eye_right",
	"tusk_left",
	"tusk_right",
	"ear_left_base",
	"ear_right_base",
	"hair_top",
	"torso_main",
	"chest_plate",
	"pauldron_left",
	"pauldron_right",
	"belt_main",
	"pelvis_main",
	"left_upper_arm_main",
	"left_forearm_main",
	"left_hand_fist",
	"right_upper_arm_main",
	"right_forearm_main",
	"right_hand_fist",
	"left_thigh_main",
	"left_shin_main",
	"left_foot_main",
	"right_thigh_main",
	"right_shin_main",
	"right_foot_main",
]

const REQUIRED_BONES := [
	"Root", "Pelvis", "Torso", "Neck", "Head",
	"UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
]


func test_voxel_orc_raider_static_and_rig_exist() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)) \
		.override_failure_message("missing static orc glb").is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)) \
		.override_failure_message("missing orc rig glb").is_true()
	for image_name in [
		"voxel_orc_raider_preview.png",
		"voxel_orc_raider_front.png",
		"voxel_orc_raider_side.png",
		"voxel_orc_raider_top.png",
	]:
		assert_bool(FileAccess.file_exists("res://reports/characters_preview/%s" % image_name)) \
			.override_failure_message("missing orc preview: " + image_name).is_true()


func test_voxel_orc_raider_static_contains_semantic_parts() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate()
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)
	for part_name in REQUIRED_PARTS:
		assert_bool(names.has(part_name)) \
			.override_failure_message("orc static GLB missing part: %s" % part_name) \
			.is_true()

	var skeleton := _find_skeleton(inst)
	assert_object(skeleton).is_not_null()
	for bone_name in REQUIRED_BONES:
		assert_int(skeleton.find_bone(bone_name)) \
			.override_failure_message("orc static skeleton missing bone: %s" % bone_name) \
			.is_greater(-1)
	inst.free()


func test_voxel_orc_raider_rig_validates_and_keeps_semantic_parts() -> void:
	assert_bool(VALIDATOR.validate_glb(RIG_PATH, true).ok) \
		.override_failure_message("orc rig failed VoxelRigValidator").is_true()

	var packed := load(RIG_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate()
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)
	for part_name in ["tusk_left", "tusk_right", "chest_plate", "pauldron_left"]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("orc rig missing semantic part: %s" % part_name) \
			.is_true()
	for forbidden in ["axe_haft", "axe_head", "axe_blade", "axe_spike"]:
		assert_bool(names.has(forbidden)) \
			.override_failure_message("orc rig still bakes weapon part: %s" % forbidden) \
			.is_false()
	inst.free()


func test_orc_raider_generator_script_documents_scale_and_workflow() -> void:
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_orc_raider.py")
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains("1m = 32px")
	assert_str(source).contains("ORC_HEIGHT_PX = 48.0")
	assert_str(source).contains("weaponless")
	assert_str(source).contains("parent_parts_by_bone")
	assert_str(source).contains("voxel_orc_raider_48px.glb")
	assert_str(source).not_contains("axe_haft")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var res := _find_skeleton(child)
		if res:
			return res
	return null


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(node.name)
	for child in node.get_children():
		_collect_names(child, names)
