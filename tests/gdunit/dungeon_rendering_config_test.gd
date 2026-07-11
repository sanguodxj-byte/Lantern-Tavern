extends GdUnitTestSuite

# 阶段 E 步2：DungeonRenderingConfig 呑约测试

func before() -> void:
	load("res://scenes/expedition/dungeon_rendering_config.gd")

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

func test_procedural_top_consts_match_default_config() -> void:
	# procedural 顶仍持旧 const（迁移期暂保，下回合删改读 cfg.*）
	var src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(src.contains("const LARGE_ROOM_AREA := 48")).is_true()
	assert_bool(src.contains("const DOOR_SURROUND_THICKNESS := 0.2") or src.contains("const DOOR_SURROUND_THICKNESS := 0.2")).is_true()
	assert_bool(src.contains("const CEILING_THICKNESS := 0.1")).is_true()
