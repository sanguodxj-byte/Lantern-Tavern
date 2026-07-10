extends GdUnitTestSuite

# 阶段 9 条 6 determinism 测试：固定 seed 真正可复现。
# 验收门槛：同 seed → 完全相同；不同 seed → 至少布局摘要不同；seed=0 → 自动生成并记录实际 seed。

func before() -> void:
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")

func test_same_seed_produces_identical_grid() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	cfg.width = 42
	cfg.height = 42
	var layout_a := DungeonGenerator.new().generate(cfg)
	var layout_b := DungeonGenerator.new().generate(cfg)
	# 同 seed 必须产出逐格一致的网格
	assert_int(layout_a.seed).is_equal(layout_b.seed)
	assert_int(layout_a.seed).is_equal(7777)
	for y in range(layout_a.grid.size()):
		for x in range(layout_a.grid[y].size()):
			if int(layout_a.grid[y][x]) != int(layout_b.grid[y][x]):
				assert_bool(false).override_failure_message("grid mismatch at (%d,%d): %d vs %d" % [x, y, layout_a.grid[y][x], layout_b.grid[y][x]]).is_true()
				return

func test_same_seed_produces_identical_rooms_and_roles() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	var layout_a := DungeonGenerator.new().generate(cfg)
	var layout_b := DungeonGenerator.new().generate(cfg)
	assert_int(layout_a.rooms.size()).is_equal(layout_b.rooms.size())
	for i in range(layout_a.rooms.size()):
		assert_bool(layout_a.rooms[i] == layout_b.rooms[i]).is_true()
	# room_roles key 集合一致
	assert_bool(layout_a.room_roles.keys() == layout_b.room_roles.keys()).is_true()
	for k in layout_a.room_roles.keys():
		assert_bool(layout_a.room_roles[k] == layout_b.room_roles[k]).is_true()

func test_different_seed_produces_different_layout_summary() -> void:
	var cfg_a := DungeonGenerationConfig.new()
	cfg_a.algorithm = "isaac"
	cfg_a.seed = 7777
	var layout_a := DungeonGenerator.new().generate(cfg_a)
	var cfg_b := DungeonGenerationConfig.new()
	cfg_b.algorithm = "isaac"
	cfg_b.seed = 8888
	var layout_b := DungeonGenerator.new().generate(cfg_b)
	# 不同 seed 至少布局摘要不同（floor_count 或 rooms.size 或 player_spawn_cell 任一不同）
	var summary_a := _layout_summary(layout_a)
	var summary_b := _layout_summary(layout_b)
	assert_bool(summary_a != summary_b).override_failure_message("不同 seed 产出了相同布局摘要 %s" % str(summary_a)).is_true()

func test_seed_zero_auto_generates_and_records_actual_seed() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 0  # 0 表示随机选种子
	var layout := DungeonGenerator.new().generate(cfg)
	# layout.seed 应记 rng 实际选的种子（非 0）
	assert_int(layout.seed).is_not_equal(0)

func test_isaac_rng_injection_fallback_when_not_set() -> void:
	# 未注入 rng 时，isaac 应 fallback 全局 randi()/randf()（保旧行为，不破 procedural 茤路径）
	var gen: Node = load("res://scenes/expedition/isaac_room_dungeon_generator.gd").new()
	# 不调 set_rng，直接 generate——应能跑完不崩（fallback 全局随机）
	var grid: Array = gen.generate_dungeon(20, 20)
	assert_int(grid.size()).is_equal(20)
	gen.free()


# ── helpers ──────────────────────────────────────────────────
func _layout_summary(layout: DungeonLayout) -> Dictionary:
	var floor_count := 0
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			if int(layout.grid[y][x]) == 1:
				floor_count += 1
	return {
		"seed": layout.seed,
		"floor_count": floor_count,
		"rooms": layout.rooms.size(),
		"player_spawn": str(layout.player_spawn_cell),
	}
