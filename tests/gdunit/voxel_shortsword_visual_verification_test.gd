extends GdUnitTestSuite

const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_shortsword.glb"
const OUTPUT_DIR := "res://reports/props_preview"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")


func test_capture_shortsword_real_3d_views_in_godot() -> void:
	assert_bool(SUPPORT.real_renderer_available()) \
		.override_failure_message("shortsword material capture requires a non-headless renderer") \
		.is_true()
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var output_paths := {
		"preview": "%s/voxel_shortsword_godot_preview.png" % OUTPUT_DIR,
		"front": "%s/voxel_shortsword_godot_front.png" % OUTPUT_DIR,
		"side": "%s/voxel_shortsword_godot_side.png" % OUTPUT_DIR,
		"top": "%s/voxel_shortsword_godot_top.png" % OUTPUT_DIR,
	}
	var result: Dictionary = await SUPPORT.capture_four_views(
		self,
		packed,
		output_paths,
		func(model: Node3D) -> void: VOXEL_LIGHTING.apply_weapon_tree(model),
	)
	assert_int(result["error"]).is_equal(OK)
	for view_name in ["preview", "front", "side", "top"]:
		var inspection: Dictionary = result["views"][view_name]
		assert_int(inspection["save_error"]).is_equal(OK)
		assert_bool(inspection["nonblank"]) \
			.override_failure_message("blank Godot shortsword capture: %s" % inspection["path"]) \
			.is_true()
