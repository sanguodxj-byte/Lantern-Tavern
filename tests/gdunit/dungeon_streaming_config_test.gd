extends GdUnitTestSuite

# 阶段 E：DungeonStreamingConfig 夑约测试
# 验收：收拢 procedural 顶散落的 streaming const，让 streaming 配置有唯一定义来源。

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_config.gd")

func test_default_config_matches_procedural_legacy_constants() -> void:
	# 与 procedural 旧 const 值一致（保旧行为）
	var cfg := DungeonStreamingConfig.default()
	assert_int(cfg.chunk_size_cells).is_equal(8)
	assert_int(cfg.light_chunk_radius).is_equal(2)
	assert_int(cfg.physics_chunk_radius).is_equal(1)
	assert_int(cfg.visual_chunk_radius).is_equal(1)
	assert_int(cfg.terrain_chunk_radius).is_equal(1)
	assert_float(cfg.update_interval).is_equal_approx(0.25, 0.001)
	assert_int(cfg.visible_local_light_budget).is_equal(12)

func test_fields_are_mutable() -> void:
	# 调用方可覆写配置
	var cfg := DungeonStreamingConfig.default()
	cfg.chunk_size_cells = 16
	cfg.update_interval = 0.5
	assert_int(cfg.chunk_size_cells).is_equal(16)
	assert_float(cfg.update_interval).is_equal_approx(0.5, 0.001)

func test_procedural_top_consts_match_default_config() -> void:
	# 验 procedural 顶 streaming const 与本 config default 值一致（保迁移期契约）
	var src := (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	# procedural 顶仍持旧 const（迁移期暂保，下回合删改读 cfg.*）
	assert_bool(src.contains("const STREAM_CHUNK_SIZE_CELLS := 8")).is_true()
	assert_bool(src.contains("const STREAM_UPDATE_INTERVAL := 0.25")).is_true()
	assert_bool(src.contains("const DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET := 12")).is_true()
