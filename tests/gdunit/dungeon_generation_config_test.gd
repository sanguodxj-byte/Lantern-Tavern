extends GdUnitTestSuite

# 阶段 2 测试：DungeonGenerationConfig 只收拢生成期规则，不含 runtime 视觉配置。
# 覆盖：默认值锚、validate、duplicate 独立性、matches_procedural_dungeon_defaults。

func test_default_config_has_procedural_dungeon_defaults() -> void:
	var cfg := DungeonGenerationConfig.new()
	# 锚：与 procedural_dungeon.gd 现存 const 同值（迁移期回归锚）
	assert_float(cfg.tile_size).is_equal(3.0)
	assert_int(cfg.large_room_area).is_equal(48)
	assert_float(cfg.door_surround_thickness).is_equal(0.2)
	assert_float(cfg.ceiling_thickness).is_equal(0.1)
	assert_float(cfg.ceiling_transition_gap).is_equal(0.015)
	assert_vector(cfg.standard_door_size_meters).is_equal(Vector2(1.0, 2.0))
	assert_vector(cfg.boss_door_size_meters).is_equal(Vector2(2.0, 2.0))
	assert_int(cfg.target_room_count).is_equal(14)
	assert_str(cfg.algorithm).is_equal("isaac")

func test_default_config_matches_procedural_dungeon_defaults_helper() -> void:
	var cfg := DungeonLayout.new()  # 占位，避免 import 段
	var cfg_real := DungeonGenerationConfig.new()
	assert_bool(cfg_real.matches_procedural_dungeon_defaults()).is_true()
	# 改一字段后应失配
	cfg_real.target_room_count = 7
	assert_bool(cfg_real.matches_procedural_dungeon_defaults()).is_false()

func test_default_for_zone_sets_zone_only() -> void:
	var cfg := DungeonGenerationConfig.default_for_zone(3)
	assert_int(cfg.zone).is_equal(3)
	# 其余字段仍为默认
	assert_int(cfg.target_room_count).is_equal(14)

func test_validate_rejects_zero_dimensions() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.width = 0
	cfg.height = 42
	var r := cfg.validate()
	assert_bool(r["valid"]).is_false()
	assert_array(r["errors"]).is_not_empty()

func test_validate_rejects_unknown_algorithm() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "genetic"
	var r := cfg.validate()
	assert_bool(r["valid"]).is_false()

func test_validate_rejects_out_of_range_target_room_count() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.target_room_count = 999
	var r := cfg.validate()
	assert_bool(r["valid"]).is_false()

func test_validate_rejects_negative_extraction_probability() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.isaac_params["extraction_room_probability"] = -0.5
	var r := cfg.validate()
	assert_bool(r["valid"]).is_false()

func test_validate_accepts_default_config() -> void:
	var cfg := DungeonGenerationConfig.new()
	var r := cfg.validate()
	assert_bool(r["valid"]).is_true()
	assert_array(r["errors"]).is_empty()

func test_duplicate_config_is_independent() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.isaac_params["room_size"] = 7
	var copy := cfg.duplicate_config()
	# 改原件，副本不受影响
	cfg.isaac_params["room_size"] = 5
	cfg.width = 99
	assert_int(copy.isaac_params["room_size"]).is_equal(7)
	assert_int(copy.width).is_equal(42)

func test_config_does_not_hold_scene_prefabs() -> void:
	# 阶段 2 核心约束：生成配置不得 preload .tscn / 持 Node/PackedScene/Material。
	# 顶层字段都是值类型或 Dictionary，本测试以“无 Resource 类型字段”为锚。
	var cfg := DungeonGenerationConfig.new()
	# 强制逐字段反射检查（GDScript 无反射，枚举已知字段）
	var fields := [
		["seed", cfg.seed], ["zone", cfg.zone], ["width", cfg.width], ["height", cfg.height],
		["tile_size", cfg.tile_size], ["algorithm", cfg.algorithm], ["target_room_count", cfg.target_room_count],
		["large_room_area", cfg.large_room_area], ["door_surround_thickness", cfg.door_surround_thickness],
		["ceiling_thickness", cfg.ceiling_thickness], ["ceiling_transition_gap", cfg.ceiling_transition_gap],
		["ceiling_height_base", cfg.ceiling_height_base], ["enable_hazards", cfg.enable_hazards],
		["enable_spawn_planning", cfg.enable_spawn_planning], ["enable_connectivity_check", cfg.enable_connectivity_check],
		["enable_extraction_room", cfg.enable_extraction_room],
	]
	for pair in fields:
		var v = pair[1]
		assert_bool(v is Node).is_false()
		assert_bool(v is Resource).is_false()
	# isaac_params 内值也不能含 Resource
	for k in cfg.isaac_params.keys():
		var v = cfg.isaac_params[k]
		assert_bool(v is Resource).is_false()
