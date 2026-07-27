extends GdUnitTestSuite

## Verify remade material models spawn through the dungeon item path and have dungeon preview captures.

const PICKABLE_PATH := "res://scenes/equipment/pickable_item.tscn"
const CAPTURE_TOOL := "res://tools/dungeon_material_visual_capture.gd"
const PROCEDURAL_CAPTURE_TOOL := "res://tools/dungeon_procedural_material_visual_capture.gd"
const PROCEDURAL_OVERVIEW_PATH := "res://reports/dungeon_materials_preview/dungeon_procedural_materials_overview.png"
const OVERVIEW_PATH := "res://reports/dungeon_materials_preview/dungeon_materials_overview.png"
const MATERIAL_MODELS := preload("res://data/material_model_registry.gd")
const ITEM_SPAWNER_SCRIPT := preload("res://globals/equipment/item_spawner.gd")

const SAMPLE_IDS := [
	"rat_tail",
	"rusty_nail",
	"glowshroom",
	"deeprock_moss",
	"goblin_ear",
	"dragon_scale",
	"soul_gem",
	"slime_jelly",
]


func test_capture_tool_exists_and_covers_full_roster() -> void:
	assert_bool(FileAccess.file_exists(CAPTURE_TOOL)).is_true()
	var source := FileAccess.get_file_as_string(CAPTURE_TOOL)
	assert_str(source).contains("dungeon_materials_overview.png")
	assert_str(source).contains("materials_%s.glb")
	assert_str(source).contains("dragon_scale")
	assert_str(source).contains("soul_gem")
	assert_str(source).contains("OmniLight3D")


func test_item_spawner_places_remade_materials_with_meshes() -> void:
	var spawner: Node = ITEM_SPAWNER_SCRIPT.new()
	add_child(spawner)
	var parent := Node3D.new()
	add_child(parent)
	for mat_id in SAMPLE_IDS:
		var item: Node = spawner._spawn_material_instance(mat_id, Vector3(float(SAMPLE_IDS.find(mat_id)), 0.0, 0.0), parent, 0)
		assert_object(item) \
			.override_failure_message("ItemSpawner failed to spawn %s" % mat_id) \
			.is_not_null()
		assert_str(String(item.get_meta("material_id", ""))).is_equal(mat_id)
		assert_str(String(item.get_meta("item_tag", ""))).is_equal("material")
		assert_int(_count_meshes(item)) \
			.override_failure_message("%s spawned without visible meshes" % mat_id) \
			.is_greater_equal(1)
		var glb_path := MATERIAL_MODELS.get_model_path(mat_id)
		assert_bool(ResourceLoader.exists(glb_path)).is_true()
	parent.free()
	spawner.free()


func test_resource_cells_in_level_grid_spawn_materials() -> void:
	var spawner: Node = ITEM_SPAWNER_SCRIPT.new()
	add_child(spawner)
	var parent := Node3D.new()
	add_child(parent)
	# Cell type 4 = RESOURCE fixed material slot in ItemSpawner.spawn_items_for_level.
	var grid := [
		[1, 1, 1],
		[1, 4, 1],
		[1, 1, 1],
	]
	var result: Array = spawner.spawn_items_for_level(grid, 0, Vector3(999, 0, 999), 3.0, Vector3.ZERO, parent)
	var material_count := 0
	for item in result:
		if item != null and item.has_meta("item_tag") and String(item.get_meta("item_tag")) == "material":
			material_count += 1
			assert_bool(item.has_meta("material_id")).is_true()
			assert_int(_count_meshes(item)).is_greater_equal(1)
	assert_int(material_count).is_greater_equal(1)
	parent.free()
	spawner.free()


func test_dungeon_overview_capture_exists_when_generated() -> void:
	# Capture may be produced by tools/dungeon_material_visual_capture.gd in a non-dummy renderer.
	# If present, it must be a real non-trivial image.
	if not FileAccess.file_exists(OVERVIEW_PATH):
		print("[dungeon_material_visual_verification] overview not generated yet; spawn path still validated")
		return
	var img := Image.new()
	assert_int(img.load(OVERVIEW_PATH)).is_equal(OK)
	assert_int(img.get_width()).is_greater_equal(320)
	assert_int(img.get_height()).is_greater_equal(240)
	var lit := 0
	var step_x := maxi(1, img.get_width() / 40)
	var step_y := maxi(1, img.get_height() / 40)
	for y in range(0, img.get_height(), step_y):
		for x in range(0, img.get_width(), step_x):
			var c := img.get_pixel(x, y)
			if c.a > 0.05 and (c.r + c.g + c.b) > 0.12:
				lit += 1
	assert_int(lit).is_greater(12)


func test_procedural_capture_tool_companion_exists() -> void:
	assert_bool(FileAccess.file_exists(PROCEDURAL_CAPTURE_TOOL)).is_true()
	var source := FileAccess.get_file_as_string(PROCEDURAL_CAPTURE_TOOL)
	assert_str(source).contains("DungeonSceneBuilder")
	assert_str(source).contains("dungeon_procedural_materials_overview.png")
	if FileAccess.file_exists(PROCEDURAL_OVERVIEW_PATH):
		var img := Image.new()
		assert_int(img.load(PROCEDURAL_OVERVIEW_PATH)).is_equal(OK)
		assert_int(img.get_width()).is_greater_equal(320)


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
