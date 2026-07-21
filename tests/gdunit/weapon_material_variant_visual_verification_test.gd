extends GdUnitTestSuite

## 代表性武器的真实 3D 材质变体确认。
## 变体由共享运行时适配器驱动，因此只需对一个多材质武器做渲染回归。

const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_crossbow.glb"
const OUTPUT_DIR := "res://reports/props_preview"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")


func test_capture_crossbow_material_tier_variants_in_real_3d() -> void:
	assert_bool(SUPPORT.real_renderer_available()) \
		.override_failure_message("crossbow material variant capture requires a non-headless renderer").is_true()
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	for material_tier in ["wood", "steel", "mithril"]:
		var output_paths := {}
		for view_name in ["preview", "front", "side", "top"]:
			output_paths[view_name] = "%s/voxel_crossbow_material_%s_%s.png" % [
				OUTPUT_DIR,
				material_tier,
				view_name,
			]
		var result: Dictionary = await SUPPORT.capture_four_views(
			self,
			packed,
			output_paths,
			func(model: Node3D) -> void:
				VOXEL_LIGHTING.apply_weapon_tree(model, material_tier),
		)
		assert_int(result["error"]).is_equal(OK)
		for view_name in ["preview", "front", "side", "top"]:
			var inspection: Dictionary = result["views"][view_name]
			assert_int(inspection["save_error"]).is_equal(OK)
			assert_bool(inspection["nonblank"]) \
				.override_failure_message("blank %s crossbow material capture: %s" % [material_tier, inspection["path"]]).is_true()
