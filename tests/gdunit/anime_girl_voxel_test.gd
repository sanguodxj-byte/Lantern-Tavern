extends GdUnitTestSuite
## Dedicated unit tests for the anime_girl voxel model.

const MODEL_ID := "anime_girl"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const STATIC_PATH := "res://assets/meshes/characters/voxel_anime_girl_48px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_anime_girl_48px_rig.glb"

## 包络随重制模型更新（2026-08 重制导出：宽度 18px / 高 52px / 深 26px，
## 双臂前伸姿态使深度大于宽度；旧值 12×48×10 已失效）。
const EXPECTED_ENVELOPE_PX := Vector3(18.0, 52.0, 26.0)
const ENVELOPE_TOLERANCE_PX := 1.5


func test_generator_exists_and_owns_model_id() -> void:
	var generator_path := "res://tools/generate_voxel_%s.py" % MODEL_ID
	assert_bool(FileAccess.file_exists(generator_path)).is_true()
	var source := FileAccess.get_file_as_string(generator_path)
	assert_str(source).contains('MODEL_ID = "%s"' % MODEL_ID)
	assert_str(source).contains("reject_target_override(MODEL_ID)")


func test_static_glb_exists() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)).is_true()


func test_rig_glb_exists() -> void:
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()


func test_static_glb_has_no_positive_volume_overlap() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	var overlaps: Array[Dictionary] = SUPPORT.find_positive_volume_overlaps(instance)
	instance.free()
	assert_array(overlaps).is_empty()


func test_static_glb_is_single_face_connected_component() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	var disconnected: Array[String] = SUPPORT.find_face_disconnected_parts(instance)
	instance.free()
	assert_array(disconnected).is_empty()


func test_envelope_matches_expected_dimensions() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	var bounds := SUPPORT.combined_aabb(instance)
	instance.free()
	var size_px := bounds.size * 32.0
	assert_float(size_px.x).is_equal_approx(EXPECTED_ENVELOPE_PX.x, ENVELOPE_TOLERANCE_PX)
	assert_float(size_px.y).is_equal_approx(EXPECTED_ENVELOPE_PX.y, ENVELOPE_TOLERANCE_PX)
	assert_float(size_px.z).is_equal_approx(EXPECTED_ENVELOPE_PX.z, ENVELOPE_TOLERANCE_PX)


func test_symmetry_for_mirrored_parts() -> void:
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	var missing := SUPPORT.find_unmirrored_parts(
		instance,
		Vector3(-1.0, 1.0, 1.0),
		Vector3.ZERO,
		[
			"ahoge", "ribbon_bow", "collar_front", "collar_back", "belt_buckle", "mouth", "cheek_l", "cheek_r",
			# 重制模型的手臂为不对称姿态（一臂抬起一臂垂下，双臂前伸）
			"right_forearm", "right_sleeve", "right_upper_arm",
			"left_forearm", "left_sleeve", "left_upper_arm",
		]
	)
	instance.free()
	assert_array(missing).is_empty()


func test_preview_images_exist_and_are_nonblank() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var path := "res://reports/characters_preview/voxel_%s_render_%s.png" % [MODEL_ID, view_name]
		var info := SUPPORT.inspect_image_file(path)
		assert_bool(info["exists"]).is_true()
		assert_bool(info["readable"]).is_true()
		assert_bool(info["nonblank"]).is_true()
