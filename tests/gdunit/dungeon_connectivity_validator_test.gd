extends GdUnitTestSuite

# 阶段 4 测试：DungeonConnectivityValidator 只报告不修改 layout。
# 覆盖：连通、关键点可达、孤立房间、主路径 hazard、集成 isaac 产出。

func before() -> void:
	load("res://scenes/expedition/dungeon_connectivity_validator.gd")
	load("res://scenes/expedition/dungeon_layout.gd")

func test_empty_layout_reports_invalid() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := DungeonLayout.new()
	var r := v.validate(layout)
	assert_bool(r["valid"]).is_false()

func test_full_connected_layout_passes() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_full_floor()
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(3, 3)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(3, 3, 1, 1)
	var r := v.validate(layout)
	assert_bool(r["valid"]).override_failure_message(str(r)).is_true()
	assert_int(r["reachable_floor_count"]).is_equal(16)
	assert_int(r["floor_count"]).is_equal(16)

func test_split_layout_reports_unreachable_cells() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_split_by_wall()
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(3, 3)  # 在不可达区域
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(3, 3, 1, 1)
	var r := v.validate(layout)
	# 4x4 中间一整列墙（4格墙）：floor = 16-4 = 12；左半 8 格连通，右半 4 格孤立
	assert_bool(r["valid"]).is_false()
	assert_int(r["reachable_floor_count"]).is_equal(8)
	assert_int(r["floor_count"]).is_equal(12)
	assert_array(r["missing_required_points"]).contains("boss_cell")

func test_missing_player_spawn_reports_invalid() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_full_floor()
	# player_spawn_cell 保持 (-1,-1)
	layout.boss_cell = Vector2i(3, 3)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(3, 3, 1, 1)
	var r := v.validate(layout)
	assert_bool(r["valid"]).is_false()
	assert_array(r["missing_required_points"]).contains("player_spawn_cell")

func test_isolated_room_detected() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_full_floor()
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(0, 0)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(0, 0, 1, 1)
	# 加一个孤立房间（无地板格连通，纯 Rect 占位）
	layout.rooms.append(Rect2i(10, 10, 2, 2))
	var r := v.validate(layout)
	# 孤立房间 Rect 整房间无一可达格
	assert_array(r["unreachable_rooms"]).is_not_empty()

func test_main_path_through_hazard_detected() -> void:
	var v := DungeonConnectivityValidator.new()
	# 2×1 直线：(0,0)→(1,0) 必经 (1,0)，无绕行可能
	var layout := DungeonLayout.new()
	layout.width = 2
	layout.height = 1
	layout.grid = [[1, 1]]
	layout.heights = [[3.0, 3.0]]
	layout.tile_size = 3.0
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(1, 0)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(1, 0, 1, 1)
	layout.hazard_anchors.append({"anchor_cell": Vector2i(1, 0), "hazard_type": "spikes"})
	var r := v.validate(layout)
	assert_bool(r["main_path_uses_hazard"]).is_true()

func test_main_path_avoiding_hazard_detected() -> void:
	var v := DungeonConnectivityValidator.new()
	# 3×1 直线：(0,0)→(2,0)；hazard 锚点放远超 BFS 范围的孤立格
	var layout := DungeonLayout.new()
	layout.width = 3
	layout.height = 1
	layout.grid = [[1, 1, 1]]
	layout.heights = [[3.0, 3.0, 3.0]]
	layout.tile_size = 3.0
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(2, 0)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(2, 0, 1, 1)
	# 锚点不在 (0,0)→(2,0) 的路径上（不存在格 (99,99)）
	layout.hazard_anchors.append({"anchor_cell": Vector2i(99, 99), "hazard_type": "spikes"})
	var r := v.validate(layout)
	assert_bool(r["main_path_uses_hazard"]).is_false()

func test_is_cell_reachable_helper() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_full_floor()
	layout.player_spawn_cell = Vector2i(0, 0)
	assert_bool(v.is_cell_reachable(layout, Vector2i(3, 3))).is_true()
	assert_bool(v.is_cell_reachable(layout, Vector2i(99, 99))).is_false()

func test_validator_does_not_modify_layout() -> void:
	var v := DungeonConnectivityValidator.new()
	var layout := _make_4x4_full_floor()
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(3, 3)
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(3, 3, 1, 1)
	# 验证前快照
	var grid_before := layout.grid.duplicate(true)
	var roles_before := layout.room_roles.size()
	v.validate(layout)
	# 验证后 grid 与 room_roles 不变
	assert_array(layout.grid).is_equal(grid_before)
	assert_int(layout.room_roles.size()).is_equal(roles_before)

func test_integration_isaac_layout_validates() -> void:
	# isaac 真产出的必保契约：player_spawn/boss 可达，且两者不在同一房间。
	# 不强制 100% 全地板连通（isaac 的 shortcut/merged partition 可能留小孤立格），
	# 也不强制 extraction/stairs 命中（extraction 是 0.2 概率 role）。
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	var v := DungeonConnectivityValidator.new()
	var r := v.validate(layout)
	var missing: Array = r["missing_required_points"]
	# 必命中点不应在 missing 里
	assert_bool(not missing.has("player_spawn_cell")) \
		.override_failure_message("isaac 必保 player_spawn 可达，missing=%s" % str(missing)) \
		.is_true()
	assert_bool(not missing.has("boss_cell")) \
		.override_failure_message("isaac 必保 boss 可达，missing=%s" % str(missing)) \
		.is_true()
	# reachable 比例：至少 90% 地板格可达（isaac _ensure_walkable_connectivity 的现实契约）
	var floor_count: int = int(r["floor_count"])
	var reachable_count: int = int(r["reachable_floor_count"])
	if floor_count > 0:
		var ratio: float = float(reachable_count) / float(floor_count)
		assert_bool(ratio >= 0.9) \
			.override_failure_message("isaac reachable ratio %.2f < 0.9 (%d/%d)" % [ratio, reachable_count, floor_count]) \
			.is_true()


# ── helpers ──────────────────────────────────────────────────
func _make_4x4_full_floor() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 4
	layout.height = 4
	layout.grid = [
		[1,1,1,1],
		[1,1,1,1],
		[1,1,1,1],
		[1,1,1,1],
	]
	layout.heights = [
		[3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0],
	]
	layout.tile_size = 3.0
	return layout

func _make_4x4_split_by_wall() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 4
	layout.height = 4
	# 中间一整列墙（x=2），左右两半地板互不可达
	layout.grid = [
		[1,1,2,1],
		[1,1,2,1],
		[1,1,2,1],
		[1,1,2,1],
	]
	layout.heights = [
		[3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0],
			[3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0],
	]
	layout.tile_size = 3.0
	return layout
