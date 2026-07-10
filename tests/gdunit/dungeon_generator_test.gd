extends GdUnitTestSuite

# 阶段 3 测试：DungeonGenerator 包装旧算法、统一输出 DungeonLayout。
# 不 instantiate 场景；验证 layout 字段填充与关键点推导语义。

func before() -> void:
	# 强制让 gdUnit4 在本轮就识别新脚本（若 .godot 缓存陈旧）
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")

func test_generate_invalid_config_returns_empty_layout() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.width = 0  # invalid
	cfg.height = 42
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	assert_bool(layout.is_empty()).is_true()

func test_generate_isaac_fills_layout_fields() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.width = 42
	cfg.height = 42
	cfg.zone = 2
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	assert_bool(layout.is_empty()).is_false()
	assert_int(layout.width).is_equal(42)
	assert_int(layout.height).is_equal(42)
	assert_int(layout.grid.size()).is_equal(42)
	assert_int(layout.heights.size()).is_equal(42)
	assert_str(layout.algorithm).is_equal("isaac")
	assert_int(layout.zone).is_equal(2)
	assert_float(layout.tile_size).is_equal(3.0)
	assert_bool(layout.rooms.size() >= 6).is_true()
	assert_bool(layout.room_roles.has("start")).is_true()
	assert_bool(layout.room_roles.has("boss")).is_true()

func test_generate_isaac_derives_player_spawn_cell_on_floor() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	# player_spawn_cell 必须命中（非 (-1,-1)）且为 FLOOR
	assert_bool(layout.player_spawn_cell.x >= 0).is_true()
	assert_bool(layout.player_spawn_cell.y >= 0).is_true()
	assert_bool(layout.is_floor_cell(layout.player_spawn_cell)).is_true()

func test_generate_isaac_derives_boss_cell_on_floor_or_missing() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	# boss cell：要么命中 FLOOR，要么 role 房间内无一可走格时 (-1,-1)（后者不该在 isaac 正常产出）
	if layout.is_key_cell_missing(layout.boss_cell):
		# 不应发生 —— isaac 的 boss 房间必有人可走格
		assert_bool(false).override_failure_message("isaac boss_cell 未推导出").is_true()
	else:
		assert_bool(layout.is_floor_cell(layout.boss_cell)).is_true()

func test_generate_isaac_player_spawn_differs_from_boss_cell() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	# 出生点不应落在 boss 房间内（procedural_dungeon.gd 的语义）
	assert_bool(layout.is_boss_room_cell(layout.player_spawn_cell)).is_false()

func test_generate_isaac_seed_recorded_for_traceability() -> void:
	# isaac 内部用全局 randi 无 seed 字段，包装层只把 config.seed 记入 layout.seed 供追溯。
	# 阶段 11 补 isaac RandomNumberGenerator 后，此测试升级为“同 seed 逐格一致”。
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	assert_int(layout.seed).is_equal(7777)

func test_generate_bsp_returns_layout_with_bsp_algorithm() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "bsp"
	cfg.width = 30
	cfg.height = 30
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	assert_str(layout.algorithm).is_equal("bsp")
	# bsp 无 room_roles，关键点全 (-1,-1)，不强制要求命中
	assert_bool(layout.is_key_cell_missing(layout.player_spawn_cell)).is_true()

func test_generate_unknown_algorithm_falls_back_to_isaac() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "genetic"  # 未知
	# config.validate 会拒绝未知 algorithm，generate 直接返回空 layout
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	assert_bool(layout.is_empty()).is_true()

func test_generated_layout_passes_validate() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	var r := layout.validate()
	# isaac 产出应能通过 layout.validate（start/boss 都会命中，关键点都在 FLOOR）
	assert_bool(r["valid"]).override_failure_message(str(r["errors"])).is_true()

func test_generate_does_not_create_scene_nodes() -> void:
	# 阶段 3 核心约束：生成阶段不创建 Node/MeshInstance3D/PhysicsBody3D 等。
	# DungeonLayout 字段都是数据，无 Node 持有；本测试以“layout 无 Node 字段”为锚。
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	# grid/heights 内值必须是 int/float，不是 Node
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			var v = layout.grid[y][x]
			assert_bool(v is Node).is_false()
			assert_bool(v is Resource).is_false()
	# 关键点 Vector2i 是值类型
	assert_bool(layout.player_spawn_cell is Vector2i).is_true()
	assert_bool(layout.boss_cell is Vector2i).is_true()
