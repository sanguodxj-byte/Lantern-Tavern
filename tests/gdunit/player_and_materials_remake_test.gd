extends GdUnitTestSuite

const MANIFEST_PATH := "res://data/material_model_manifest.json"
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")

const CORE_DROP_IDS := [
	"skeleton_dust",
	"goblin_ear",
	"giant_rat_tail",
	"slime_jelly",
	"troll_blood",
	"soul_gem",
	"dragon_scale",
	"rat_tail",
	"dungeon_moss",
	"bone_shard",
]


func test_core_drop_and_material_models_exist() -> void:
	for mid in CORE_DROP_IDS:
		var path := "res://assets/models/materials/materials_%s.glb" % mid
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("missing material glb: " + path).is_true()
		var glb_size := FileAccess.get_file_as_bytes(path).size()
		assert_int(glb_size) \
			.override_failure_message("material glb too small: " + path) \
			.is_greater(500)
		for view in ["front", "side", "top"]:
			var preview := "res://reports/materials_preview/voxel_%s_%s.png" % [mid, view]
			assert_bool(FileAccess.file_exists(preview)) \
				.override_failure_message("missing material preview: " + preview).is_true()
			var img := Image.new()
			var err := img.load(preview)
			assert_int(err) \
				.override_failure_message("material preview unreadable: " + preview) \
				.is_equal(OK)
			assert_int(img.get_width()).is_greater(32)
			assert_int(img.get_height()).is_greater(32)
			var non_black := 0
			var step_x := maxi(1, img.get_width() / 32)
			var step_y := maxi(1, img.get_height() / 32)
			for y in range(0, img.get_height(), step_y):
				for x in range(0, img.get_width(), step_x):
					var c := img.get_pixel(x, y)
					if c.a > 0.05 and (c.r + c.g + c.b) > 0.05:
						non_black += 1
			assert_int(non_black) \
				.override_failure_message("material preview mostly blank: " + preview) \
				.is_greater(3)


func test_manifest_includes_core_drops_with_bbox() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_bool(text.is_empty()).is_false()
	var parsed = JSON.parse_string(text)
	assert_bool(typeof(parsed) == TYPE_DICTIONARY).is_true()
	var by_id := {}
	for entry in parsed.get("materials", []):
		by_id[entry.get("id", "")] = entry
	for mid in CORE_DROP_IDS:
		assert_bool(by_id.has(mid)).override_failure_message("manifest missing " + mid).is_true()
		var bbox: Array = by_id[mid].get("bbox", [])
		assert_array(bbox).has_size(3)
		assert_float(float(bbox[0])).is_greater(0.01)
		assert_float(float(bbox[1])).is_greater(0.01)
		assert_float(float(bbox[2])).is_greater(0.01)


func test_material_model_registry_resolves_new_drops() -> void:
	assert_str(MATERIAL_MODELS.get_model_path("skeleton_dust")).contains("materials_skeleton_dust.glb")
	assert_str(MATERIAL_MODELS.get_model_path("giant_rat_tail")).contains("materials_giant_rat_tail.glb")
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	assert_str(MATERIAL_MODELS.get_display_name("dungeon_moss")).is_equal("地牢苔")
	assert_str(MATERIAL_MODELS.get_display_name("skeleton_dust")).is_equal("白骨粉末")
	TranslationServer.set_locale(prev)


func test_core_drop_glbs_are_loadable_packed_scenes() -> void:
	for mid in CORE_DROP_IDS:
		var path := "res://assets/models/materials/materials_%s.glb" % mid
		var scene := load(path)
		assert_object(scene) \
			.override_failure_message("core drop GLB not loadable: " + path) \
			.is_instanceof(PackedScene)
		var inst := (scene as PackedScene).instantiate()
		assert_object(inst).is_not_null()
		assert_int(_count_meshes(inst)).is_greater_equal(1)
		inst.free()


func _count_meshes(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count_meshes(child)
	return n
