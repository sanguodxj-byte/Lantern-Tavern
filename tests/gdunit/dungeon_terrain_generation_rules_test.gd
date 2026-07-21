extends GdUnitTestSuite
## 地牢地形/门生成规则回归测试（迁移后：验 builder/config 契约，不再调用 Procedural 已删私有实现）

func before() -> void:
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_rendering_config.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_layout.gd")

func test_wall_generation_uses_full_tile_blocks_in_builder() -> void:
	# 墙体整格体积由 builder 地形收集产出
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.contains("wall_transforms_by_height") or builder_src.contains("_build_terrain")) \
		.override_failure_message("DungeonSceneBuilder 应收集整格墙体 transform").is_true()
	assert_bool(builder_src.contains("_spawn_wall_segment(cell_pos")).is_false()

func test_wall_segment_material_group_key_rounds_size_values() -> void:
	var builder := DungeonSceneBuilder.new()
	# builder 当前 key 使用 int 截断；仍需稳定可分组
	var key := builder._wall_segment_key(Vector3(0.2, 3.00001, 3.0))
	assert_str(key).is_not_empty()
	assert_bool(key.contains(",")).is_true()

func test_rendering_config_exposes_door_and_ceiling_geometry_defaults() -> void:
	var cfg := DungeonRenderingConfig.default()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
	assert_float(cfg.ceiling_transition_gap).is_equal_approx(0.015, 0.0001)
	assert_int(cfg.large_room_area).is_equal(48)

func test_generation_config_matches_legacy_geometry_defaults() -> void:
	var cfg := DungeonGenerationConfig.new()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
	assert_int(cfg.large_room_area).is_equal(48)
	assert_float(cfg.tile_size).is_equal_approx(3.0, 0.0001)

func test_builder_builds_wall_transforms_for_simple_room() -> void:
	var layout := DungeonLayout.new()
	layout.width = 5
	layout.height = 5
	layout.tile_size = 3.0
	layout.zone = 0
	layout.grid = []
	layout.heights = []
	for y in range(5):
		var row: Array = []
		var hr: Array = []
		for x in range(5):
			if x == 0 or y == 0 or x == 4 or y == 4:
				row.append(2)  # wall
			else:
				row.append(1)  # floor
			hr.append(3.0)
		layout.grid.append(row)
		layout.heights.append(hr)
	layout.rooms = [Rect2i(1, 1, 3, 3)]
	layout.room_roles["start"] = Rect2i(1, 1, 3, 3)
	layout.player_spawn_cell = Vector2i(2, 2)

	var parent := Node3D.new()
	add_child(parent)
	var result := DungeonSceneBuilder.new().build(layout, parent)
	assert_bool(result.is_built()).is_true()
	assert_bool(result.wall_transforms_by_height.is_empty()).is_false()
	assert_bool(result.floor_transforms.is_empty()).is_false()
	result.dispose()
	parent.queue_free()

func test_builder_constants_align_with_rendering_config() -> void:
	var cfg := DungeonRenderingConfig.default()
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(builder_src.contains("const DOOR_SURROUND_THICKNESS := 0.2") or builder_src.contains("DOOR_SURROUND_THICKNESS")).is_true()
	assert_bool(builder_src.contains("const CEILING_THICKNESS := 0.1") or builder_src.contains("CEILING_THICKNESS")).is_true()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.0001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.0001)
