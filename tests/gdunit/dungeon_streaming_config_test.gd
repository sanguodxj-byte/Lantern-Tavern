extends GdUnitTestSuite

# 阶段 E：DungeonStreamingConfig 契约测试
# 验收：streaming 配置有唯一定义来源（DungeonStreamingConfig / Controller）。

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_config.gd")
	load("res://scenes/expedition/dungeon_streaming_controller.gd")

func test_default_config_matches_procedural_legacy_constants() -> void:
	var cfg := DungeonStreamingConfig.default()
	assert_int(cfg.chunk_size_cells).is_equal(8)
	assert_int(cfg.light_chunk_radius).is_equal(2)
	assert_int(cfg.physics_chunk_radius).is_equal(1)
	assert_int(cfg.visual_chunk_radius).is_equal(1)
	assert_int(cfg.terrain_chunk_radius).is_equal(1)
	assert_float(cfg.update_interval).is_equal_approx(0.25, 0.001)
	assert_int(cfg.visible_local_light_budget).is_equal(12)

func test_fields_are_mutable() -> void:
	var cfg := DungeonStreamingConfig.default()
	cfg.chunk_size_cells = 16
	cfg.update_interval = 0.5
	assert_int(cfg.chunk_size_cells).is_equal(16)
	assert_float(cfg.update_interval).is_equal_approx(0.5, 0.001)

func test_streaming_controller_defaults_align_with_config() -> void:
	# controller 持有与 config 对齐的默认 chunk 常量
	var cfg := DungeonStreamingConfig.default()
	var src := (load("res://scenes/expedition/dungeon_streaming_controller.gd") as GDScript).source_code
	assert_bool(src.contains("const STREAM_CHUNK_SIZE_CELLS := %d" % cfg.chunk_size_cells)).is_true()
	assert_bool(src.contains("const STREAM_UPDATE_INTERVAL := %s" % str(cfg.update_interval))).is_true()
	assert_bool(src.contains("const DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET := %d" % cfg.visible_local_light_budget)).is_true()

func test_procedural_reads_streaming_config_not_top_level_const() -> void:
	var src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	assert_bool(src.contains("DungeonStreamingConfig")).is_true()
	assert_bool(src.contains("_streaming_cfg")).is_true()
	assert_bool(src.contains("const STREAM_CHUNK_SIZE_CELLS := 8")).is_false()
