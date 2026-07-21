extends GdUnitTestSuite

## 只读巡检现有武器 GLB 的材料阶位差分。
## 这是视觉验证，不是模型生成：只实例化已有 GLB，不写回资产。

const JSON_PATH := "res://data/weapons/weapons.json"
const OUTPUT_DIR := "res://reports/props_preview/weapon_material_roster"
const VIEW_SIZE := 640
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")


func test_capture_all_weapon_material_variant_contact_sheets() -> void:
	assert_bool(SUPPORT.real_renderer_available()) \
		.override_failure_message("weapon material roster capture requires a non-headless renderer").is_true()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	assert_object(parsed).is_not_null()
	var entries: Array = parsed.get("weapons", [])
	assert_int(entries.size()).is_equal(12)

	for entry_value in entries:
		var entry: Dictionary = entry_value if entry_value is Dictionary else {}
		var weapon_id := String(entry.get("id", ""))
		var packed := load(String(entry.get("glb_path", ""))) as PackedScene
		assert_object(packed) \
			.override_failure_message("missing weapon GLB for material roster: %s" % weapon_id).is_not_null()
		var tiers: Array = entry.get("tiers", [])
		assert_int(tiers.size()).is_equal(3)
		var sheet := Image.create(VIEW_SIZE * 3, VIEW_SIZE, false, Image.FORMAT_RGBA8)
		for tier_index in range(3):
			var tier: Dictionary = tiers[tier_index] if tiers[tier_index] is Dictionary else {}
			var material_tier := String(tier.get("material_tier", "iron"))
			var output_paths := {}
			for view_name in ["preview", "front", "side", "top"]:
				output_paths[view_name] = "%s/%s_%s_%s.png" % [
					OUTPUT_DIR,
					weapon_id,
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
			if int(result["error"]) != OK:
				continue
			var inspection: Dictionary = result["views"]["preview"]
			assert_int(inspection["save_error"]).is_equal(OK)
			assert_bool(inspection["nonblank"]) \
				.override_failure_message("blank %s %s preview" % [weapon_id, material_tier]).is_true()
			var preview_path := ProjectSettings.globalize_path(String(output_paths["preview"]))
			var preview := Image.load_from_file(preview_path)
			assert_bool(preview != null and not preview.is_empty()).is_true()
			if preview != null and not preview.is_empty():
				preview.convert(Image.FORMAT_RGBA8)
				sheet.blend_rect(preview, Rect2i(0, 0, VIEW_SIZE, VIEW_SIZE), Vector2i(tier_index * VIEW_SIZE, 0))

		var contact_path := "%s/%s_contact.png" % [OUTPUT_DIR, weapon_id]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		assert_int(sheet.save_png(contact_path)).is_equal(OK)
		assert_bool(FileAccess.file_exists(contact_path)).is_true()
