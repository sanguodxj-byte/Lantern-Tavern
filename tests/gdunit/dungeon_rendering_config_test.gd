extends GdUnitTestSuite

# 阶段 E：DungeonRenderingConfig 契约测试

func before() -> void:
	load("res://scenes/expedition/dungeon_rendering_config.gd")
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/procedural_dungeon.gd")

func test_default_config_matches_procedural_legacy_constants() -> void:
	var cfg := DungeonRenderingConfig.default()
	assert_int(cfg.large_room_area).is_equal(48)
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.001)
	assert_float(cfg.ceiling_transition_gap).is_equal_approx(0.015, 0.001)
	assert_float(cfg.player_vision_base_energy).is_equal_approx(2.4, 0.001)
	assert_float(cfg.player_vision_base_range).is_equal_approx(10.0, 0.001)

func test_fields_are_mutable() -> void:
	var cfg := DungeonRenderingConfig.default()
	cfg.large_room_area = 64
	cfg.ceiling_thickness = 0.15
	assert_int(cfg.large_room_area).is_equal(64)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.15, 0.001)

func test_builder_and_procedural_use_rendering_config_source() -> void:
	# 配置唯一定义来源已迁出；builder 持对齐常量，procedural 持 _rendering_cfg
	var cfg := DungeonRenderingConfig.default()
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	var pd_src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(builder_src.contains("DOOR_SURROUND_THICKNESS") or builder_src.contains("door_surround")).is_true()
	assert_bool(builder_src.contains("CEILING_THICKNESS") or builder_src.contains("ceiling_thickness")).is_true()
	assert_bool(pd_src.contains("DungeonRenderingConfig") and pd_src.contains("_rendering_cfg")).is_true()
	assert_float(cfg.door_surround_thickness).is_equal_approx(0.2, 0.001)
	assert_float(cfg.ceiling_thickness).is_equal_approx(0.1, 0.001)
