extends GdUnitTestSuite

const MANIFEST_PATH := "res://data/material_model_manifest.json"
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const MATERIAL_IDS := [
	"rat_tail",
	"moldy_bread",
	"rusty_nail",
	"dungeon_moss",
	"bone_shard",
	"stale_water",
	"prison_lichen",
	"cellar_mushroom",
	"blackberry",
	"glowshroom",
	"moongrass",
	"pixie_dust",
	"poison_berry",
	"deeprock_moss",
	"black_rye_root",
	"stalactite_sap",
	"goblin_nail",
	"mistflower",
	"wolfear_herb",
	"cyclops_beard",
	"geothermal_ear",
	"luminous_fern",
	"quartz_dust",
	"blindfish_jerky",
]

func test_material_model_manifest_exists_and_lists_generated_assets() -> void:
	var manifest := _load_manifest()
	# Base scatter set (24) + combat drops remade into the same catalog.
	assert_int(manifest.get("materials", []).size()).is_greater_equal(24)
	var ids: Array = []
	for entry in manifest["materials"]:
		ids.append(entry.get("id", ""))
	for id in MATERIAL_IDS:
		assert_array(ids).contains(id)
	for drop_id in ["skeleton_dust", "goblin_ear", "giant_rat_tail", "slime_jelly", "troll_blood", "soul_gem", "dragon_scale"]:
		assert_array(ids).contains(drop_id)

func test_generated_material_glbs_exist() -> void:
	for entry in _load_manifest()["materials"]:
		var path := String(entry.get("glb_path", ""))
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("Missing generated material model: " + path) \
			.is_true()

func test_generated_material_glbs_are_loadable_packed_scenes() -> void:
	for entry in _load_manifest()["materials"]:
		var path := String(entry.get("glb_path", ""))
		var scene := load(path)
		assert_object(scene) \
			.override_failure_message("Generated material GLB is not loadable: " + path) \
			.is_instanceof(PackedScene)

func test_material_model_bounding_boxes_are_not_uniform() -> void:
	var signatures: Dictionary = {}
	for entry in _load_manifest()["materials"]:
		var bbox: Array = entry.get("bbox", [])
		assert_array(bbox).has_size(3)
		var signature := "%.3f,%.3f,%.3f" % [float(bbox[0]), float(bbox[1]), float(bbox[2])]
		signatures[signature] = true
	assert_int(signatures.size()).is_greater_equal(14)

func test_material_model_sizes_match_expected_roles() -> void:
	## bbox 来自 Blender 世界轴 (x,y,z)。用 max/min 语义断言角色尺寸，避免轴约定脆弱。
	var by_id := _manifest_by_id()
	# 鼠尾 / 盲鱼干：明显细长
	assert_bool(_is_elongated(by_id["rat_tail"]["bbox"], 4.0)).is_true()
	assert_bool(_is_elongated(by_id["blindfish_jerky"]["bbox"], 3.5)).is_true()
	# 铁钉：细长尖刺
	assert_bool(_is_elongated(by_id["rusty_nail"]["bbox"], 4.0)).is_true()
	# 地衣：扁平（最小轴很薄）
	assert_bool(_min_axis(by_id["prison_lichen"]["bbox"]) < 0.08).is_true()
	# 蘑菇高度显著大于积水厚度（积水占地可很宽，不能比 max 轴）
	assert_bool(_max_axis(by_id["cellar_mushroom"]["bbox"]) > _min_axis(by_id["stale_water"]["bbox"]) * 2.0).is_true()
	# 月光草 / 荧光蕨：相对较高的植物
	assert_bool(_max_axis(by_id["moongrass"]["bbox"]) > 0.25).is_true()
	assert_bool(_max_axis(by_id["luminous_fern"]["bbox"]) > 0.22).is_true()
	# 深岩苔藓占地宽于妖精尘
	assert_bool(_max_axis(by_id["deeprock_moss"]["bbox"]) > _max_axis(by_id["pixie_dust"]["bbox"]) * 1.3).is_true()

func test_material_model_manifest_defines_placement_for_every_asset() -> void:
	for entry in _load_manifest()["materials"]:
		var placement: Dictionary = entry.get("placement", {})
		assert_bool(not placement.is_empty()) \
			.override_failure_message("Missing placement for " + String(entry.get("id", ""))) \
			.is_true()
		assert_bool(placement.has("location_preference")).is_true()
		assert_bool(placement.has("visual_rotation_degrees")).is_true()
		assert_bool(placement.has("spawn_offset")).is_true()

func test_wall_base_materials_have_near_wall_placement() -> void:
	for id in ["cellar_mushroom", "glowshroom", "dungeon_moss", "prison_lichen", "deeprock_moss", "stalactite_sap", "geothermal_ear"]:
		assert_str(MATERIAL_MODELS.get_location_preference(id)).is_equal("near_wall")
		assert_bool(MATERIAL_MODELS.should_align_to_wall(id)).is_true()

func test_floor_splinters_and_roots_are_rotated_to_lie_flat() -> void:
	assert_bool(MATERIAL_MODELS.get_visual_rotation_degrees("rusty_nail").is_equal_approx(Vector3(0, 0, 90))).is_true()
	assert_bool(MATERIAL_MODELS.get_visual_rotation_degrees("bone_shard").is_equal_approx(Vector3(0, 0, 90))).is_true()
	assert_bool(MATERIAL_MODELS.get_visual_rotation_degrees("black_rye_root").is_equal_approx(Vector3(90, 0, 0))).is_true()
	assert_bool(MATERIAL_MODELS.get_visual_rotation_degrees("goblin_nail").is_equal_approx(Vector3(0, 0, 90))).is_true()
	assert_bool(MATERIAL_MODELS.get_visual_rotation_degrees("cyclops_beard").is_equal_approx(Vector3(0, 0, 90))).is_true()

func test_pickable_item_prefers_generated_material_glb_path() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	assert_str(item._material_glb_path("rat_tail")).is_equal("res://assets/models/materials/materials_rat_tail.glb")
	assert_bool(ResourceLoader.exists(item._material_glb_path("rat_tail"))).is_true()
	item.free()

func test_pickable_item_instantiates_generated_material_and_sizes_collision() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	item.material_id = "rat_tail"
	add_child(item)
	assert_object(item.mesh_node).is_not_null()
	assert_object(item.collision_shape.shape).is_instanceof(BoxShape3D)
	var box := item.collision_shape.shape as BoxShape3D
	assert_bool(maxf(box.size.x, box.size.z) > box.size.y * 3.0).is_true()
	remove_child(item)
	item.free()

func test_pickable_item_applies_manifest_visual_rotation_to_generated_material() -> void:
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	item.material_id = "rusty_nail"
	add_child(item)
	var visual := item.get_child(2) as Node3D
	assert_object(visual).is_not_null()
	assert_bool(visual.rotation_degrees.is_equal_approx(Vector3(0, 0, 90))).is_true()
	var box := item.collision_shape.shape as BoxShape3D
	assert_bool(maxf(box.size.x, box.size.z) > box.size.y * 2.5).is_true()
	remove_child(item)
	item.free()


func test_manifest_materials_have_three_view_previews() -> void:
	## 每个 manifest 条目必须有 front/side/top 三视图，且文件非空。
	for entry in _load_manifest()["materials"]:
		var mid := String(entry.get("id", ""))
		for view in ["front", "side", "top"]:
			var preview := "res://reports/materials_preview/voxel_%s_%s.png" % [mid, view]
			assert_bool(FileAccess.file_exists(preview)) \
				.override_failure_message("missing material three-view: " + preview) \
				.is_true()
			var size := FileAccess.get_file_as_bytes(preview).size()
			assert_int(size) \
				.override_failure_message("material three-view too small: " + preview) \
				.is_greater(1000)


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var parsed = JSON.parse_string(file.get_as_text())
	assert_bool(typeof(parsed) == TYPE_DICTIONARY).is_true()
	return parsed

func _manifest_by_id() -> Dictionary:
	var result := {}
	for entry in _load_manifest()["materials"]:
		result[String(entry["id"])] = entry
	return result


func _max_axis(bbox: Array) -> float:
	return maxf(float(bbox[0]), maxf(float(bbox[1]), float(bbox[2])))


func _min_axis(bbox: Array) -> float:
	return minf(float(bbox[0]), minf(float(bbox[1]), float(bbox[2])))


func _is_elongated(bbox: Array, ratio: float) -> bool:
	return _max_axis(bbox) > _min_axis(bbox) * ratio
