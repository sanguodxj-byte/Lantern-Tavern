extends GdUnitTestSuite
## 卓尔剑士体素模型资产回归测试：静态 GLB + rig + 语义部件 + 渲染/三视图

const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")

const STATIC_PATH := "res://assets/meshes/characters/voxel_drow_blade_48px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_drow_blade_48px_rig.glb"

const REQUIRED_PARTS := [
	"head_main",
	"face_front",
	"eye_left",
	"eye_right",
	"ear_left_base",
	"ear_left_tip",
	"ear_right_base",
	"ear_right_tip",
	"hair_top",
	"hair_bangs",
	"hair_back_strand_top",
	"torso_main",
	"chest_plate",
	"pauldron_left",
	"pauldron_right",
	"belt_main",
	"pelvis_main",
	"left_upper_arm",
	"left_bracer",
	"left_hand",
	"right_upper_arm",
	"right_bracer",
	"right_hand",
	"left_thigh",
	"left_greave",
	"left_foot",
	"right_thigh",
	"right_greave",
	"right_foot",
]

const REQUIRED_BONES := [
	"Root", "Pelvis", "Torso", "Neck", "Head",
	"UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
]


func test_voxel_drow_blade_static_and_rig_exist() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)) \
		.override_failure_message("missing static drow_blade glb").is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)) \
		.override_failure_message("missing drow_blade rig glb").is_true()

	for image_name in [
		"voxel_drow_blade_render_preview.png",
		"voxel_drow_blade_render_front.png",
		"voxel_drow_blade_render_side.png",
		"voxel_drow_blade_render_top.png",
		"voxel_drow_blade_front.png",
		"voxel_drow_blade_side.png",
		"voxel_drow_blade_top.png",
	]:
		assert_bool(FileAccess.file_exists("res://reports/characters_preview/%s" % image_name)) \
			.override_failure_message("missing drow_blade preview: " + image_name).is_true()


func test_voxel_drow_blade_static_contains_semantic_parts() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate()
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)
	for part_name in REQUIRED_PARTS:
		assert_bool(names.has(part_name)) \
			.override_failure_message("drow_blade static GLB missing part: %s" % part_name) \
			.is_true()

	var skeleton := _find_skeleton(inst)
	assert_object(skeleton).is_not_null()
	for bone_name in REQUIRED_BONES:
		assert_int(skeleton.find_bone(bone_name)) \
			.override_failure_message("drow_blade static skeleton missing bone: %s" % bone_name) \
			.is_greater(-1)
	inst.free()


func test_voxel_drow_blade_rig_validates_and_keeps_semantic_parts() -> void:
	assert_bool(VALIDATOR.validate_glb(RIG_PATH, true).ok) \
		.override_failure_message("drow_blade rig failed VoxelRigValidator").is_true()

	var packed := load(RIG_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate()
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)
	for part_name in ["ear_left_tip", "ear_right_tip", "chest_plate", "pauldron_left", "hair_top"]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("drow_blade rig missing semantic part: %s" % part_name) \
			.is_true()
	inst.free()


func _collect_names(node: Node, out: Array[String]) -> void:
	out.append(node.name)
	for child in node.get_children():
		_collect_names(child, out)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
