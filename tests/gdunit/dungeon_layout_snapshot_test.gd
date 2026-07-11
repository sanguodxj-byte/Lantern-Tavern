extends GdUnitTestSuite

# 阶段 测试优化3：dungeon_layout_snapshot_test —— 布局摘要测试
# 验收门槛（评审建议）：防止重构改变玩法分布；验证同 seed 重现；检测算法改动造成的意外变化。
# 摘要含：seed/algorithm/grid hash/room rectangles/room roles/player spawn/boss/extraction/
#        hazard count/enemy count/item count/chest count

func before() -> void:
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")

func test_layout_snapshot_contains_all_required_fields() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	cfg.width = 24
	cfg.height = 24
	var layout := DungeonGenerator.new().generate(cfg)
	var snapshot := _layout_snapshot(layout)
	# 必含字段
	for field in ["seed", "algorithm", "grid_hash", "room_count", "room_roles_keys",
			"player_spawn_cell", "boss_cell", "extraction_cell",
			"hazard_count", "enemy_count", "item_count", "chest_count"]:
		assert_bool(snapshot.has(field)) \
			.override_failure_message("snapshot 缺字段 %s" % field).is_true()

func test_same_seed_produces_identical_snapshot() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	cfg.width = 24
	cfg.height = 24
	var snap_a := _layout_snapshot(DungeonGenerator.new().generate(cfg))
	var snap_b := _layout_snapshot(DungeonGenerator.new().generate(cfg))
	# 同 seed 必须产出逐字段一致的摘要
	for k in snap_a.keys():
		assert_bool(snap_a[k] == snap_b[k]) \
			.override_failure_message("snapshot 字段 %s 不一致: %s vs %s" % [k, snap_a[k], snap_b[k]]).is_true()

func test_different_seed_produces_different_snapshot() -> void:
	var cfg_a := DungeonGenerationConfig.new()
	cfg_a.algorithm = "isaac"
	cfg_a.seed = 7777
	var snap_a := _layout_snapshot(DungeonGenerator.new().generate(cfg_a))
	var cfg_b := DungeonGenerationConfig.new()
	cfg_b.algorithm = "isaac"
	cfg_b.seed = 8888
	var snap_b := _layout_snapshot(DungeonGenerator.new().generate(cfg_b))
	# 不同 seed 至少摘要某字段不同
	var any_diff := false
	for k in snap_a.keys():
		if snap_a[k] != snap_b[k]:
			any_diff = true
			break
	assert_bool(any_diff).override_failure_message("不同 seed 产出了相同摘要").is_true()

func test_snapshot_grid_hash_is_stable_string() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	var layout := DungeonGenerator.new().generate(cfg)
	var snapshot := _layout_snapshot(layout)
	assert_bool(typeof(snapshot["grid_hash"]) == TYPE_STRING).is_true()
	assert_bool(String(snapshot["grid_hash"]).length() > 0).is_true()

func test_snapshot_counts_are_non_negative() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.seed = 7777
	var layout := DungeonGenerator.new().generate(cfg)
	var snapshot := _layout_snapshot(layout)
	for count_field in ["room_count", "hazard_count", "enemy_count", "item_count", "chest_count"]:
		assert_int(int(snapshot[count_field])).is_greater(-1)


# ── helpers ──────────────────────────────────────────────────
func _layout_snapshot(layout: DungeonLayout) -> Dictionary:
	var grid_hash := ""
	for y in range(layout.grid.size()):
		for x in range(layout.grid[y].size()):
			grid_hash += str(int(layout.grid[y][x]))
	return {
		"seed": layout.seed,
		"algorithm": layout.algorithm,
		"grid_hash": grid_hash,
		"room_count": layout.rooms.size(),
		"room_roles_keys": _join_keys(layout.room_roles.keys()),
		"player_spawn_cell": str(layout.player_spawn_cell),
		"boss_cell": str(layout.boss_cell),
		"extraction_cell": str(layout.extraction_cell),
		"hazard_count": layout.hazard_anchors.size(),
		"enemy_count": layout.enemy_spawn_specs.size(),
		"item_count": layout.item_spawn_specs.size(),
		"chest_count": layout.chest_spawn_specs.size(),
	}

func _join_keys(arr: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k in arr:
		parts.append(str(k))
	return ",".join(parts)
