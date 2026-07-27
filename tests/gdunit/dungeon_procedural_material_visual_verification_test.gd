extends GdUnitTestSuite

## Verify remade materials can be planned/spawned in a real procedural dungeon path
## and that the procedural dungeon visual capture tool/report artifacts exist.

const CAPTURE_TOOL := "res://tools/dungeon_procedural_material_visual_capture.gd"
const CAPTURE_SCENE := "res://tools/dungeon_procedural_material_visual_capture_scene.tscn"
const MOCK_CAPTURE_TOOL := "res://tools/dungeon_material_visual_capture.gd"
const OVERVIEW_PATH := "res://reports/dungeon_materials_preview/dungeon_procedural_materials_overview.png"
const EYELEVEL_PATH := "res://reports/dungeon_materials_preview/dungeon_procedural_materials_eyelevel.png"
const GALLERY_PATH := "res://reports/dungeon_materials_preview/dungeon_procedural_materials_gallery.png"
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const DungeonGeneratorScript := preload("res://scenes/expedition/dungeon_generator.gd")
const DungeonGenerationConfigScript := preload("res://scenes/expedition/dungeon_generation_config.gd")
const DungeonSpawnPlannerScript := preload("res://scenes/expedition/dungeon_spawn_planner.gd")

const SAMPLE_IDS := [
	"rat_tail",
	"glowshroom",
	"deeprock_moss",
	"soul_gem",
	"dragon_scale",
	"slime_jelly",
]


func test_procedural_capture_tool_exists_and_targets_real_dungeon_pipeline() -> void:
	assert_bool(FileAccess.file_exists(CAPTURE_TOOL)).is_true()
	assert_bool(FileAccess.file_exists(CAPTURE_SCENE)).is_true()
	var source := FileAccess.get_file_as_string(CAPTURE_TOOL)
	assert_str(source).contains("DungeonGenerator")
	assert_str(source).contains("DungeonSceneBuilder")
	assert_str(source).contains("plan_item_spawns")
	assert_str(source).contains("dungeon_procedural_materials_overview.png")
	assert_str(source).contains("dungeon_procedural_materials_gallery.png")
	assert_str(source).contains("materials_%s.glb")
	assert_str(source).contains("dragon_scale")
	# Keep the mock-room tool as a lighter companion, not a replacement.
	assert_bool(FileAccess.file_exists(MOCK_CAPTURE_TOOL)).is_true()


func test_procedural_layout_plans_material_item_specs_for_fixed_seed() -> void:
	seed(94021)
	var config = DungeonGenerationConfigScript.default_for_zone(0)
	config.seed = 94021
	var layout = DungeonGeneratorScript.new().generate(config)
	assert_object(layout).is_not_null()
	assert_bool(layout.is_empty()).is_false()
	var planner = DungeonSpawnPlannerScript.new()
	var specs: Array = planner.plan_item_spawns(layout)
	assert_int(specs.size()) \
		.override_failure_message("fixed-seed dungeon should plan material item specs") \
		.is_greater_equal(1)
	var material_count := 0
	for spec in specs:
		if String(spec.get("item_type", "")) != "material":
			continue
		material_count += 1
		var mat_id := String(spec.get("item_id", ""))
		assert_str(mat_id).is_not_empty()
		var glb_path := MATERIAL_MODELS.get_model_path(mat_id)
		if glb_path.is_empty():
			glb_path = "res://assets/models/materials/materials_%s.glb" % mat_id
		assert_bool(ResourceLoader.exists(glb_path)) \
			.override_failure_message("planned material missing remade glb: %s" % mat_id) \
			.is_true()
		assert_bool(layout.is_floor_cell(spec["cell"])) \
			.override_failure_message("material spec not on floor: %s" % mat_id) \
			.is_true()
	assert_int(material_count).is_greater_equal(1)


func test_sample_roster_models_exist_for_dungeon_placement() -> void:
	for mat_id in SAMPLE_IDS:
		var glb_path := MATERIAL_MODELS.get_model_path(mat_id)
		if glb_path.is_empty():
			glb_path = "res://assets/models/materials/materials_%s.glb" % mat_id
		assert_bool(ResourceLoader.exists(glb_path)) \
			.override_failure_message("missing remade material model for dungeon placement: %s" % mat_id) \
			.is_true()
		var placement := MATERIAL_MODELS.get_placement(mat_id)
		assert_dict(placement).is_not_empty()


func test_procedural_capture_images_are_real_when_generated() -> void:
	for path in [OVERVIEW_PATH, EYELEVEL_PATH, GALLERY_PATH]:
		if not FileAccess.file_exists(path):
			print("[dungeon_procedural_material_visual_verification] missing %s; run capture tool to generate" % path)
			continue
		var img := Image.new()
		assert_int(img.load(path)).is_equal(OK)
		assert_int(img.get_width()).is_greater_equal(320)
		assert_int(img.get_height()).is_greater_equal(240)
		var lit := 0
		var step_x := maxi(1, img.get_width() / 40)
		var step_y := maxi(1, img.get_height() / 40)
		for y in range(0, img.get_height(), step_y):
			for x in range(0, img.get_width(), step_x):
				var c := img.get_pixel(x, y)
				if c.a > 0.05 and (c.r + c.g + c.b) > 0.10:
					lit += 1
		assert_int(lit) \
			.override_failure_message("procedural dungeon capture looks blank: %s lit=%d" % [path, lit]) \
			.is_greater(12)
