extends GdUnitTestSuite

# 阶段 0 基线测试：记录 isaac 生成器的产出契约（弱断言，因生成器尚无 seed 字段）。
# 不 instantiate 任何场景节点（区别于 procedural_dungeon_test.gd）。
#
# 已知基线缺陷（不在本测试范围内修复，仅记录）：
#   - procedural_dungeon_test.gd 在 headless 下 >300s 未完成（instantiate 整个地牢）
#   - dungeon_spawner_test.gd 在 test_pick_enemy_type_weighted 上 signal 11 crash
#   - isaac_room_dungeon_generator 无 seed 字段，使用全局 randi()/randf()，
#     无法固定随机复现 —— 阶段 11 determinism 测试必须先补此能力。
#   因此本测试只断言产出“形状/存在性”，不锚定具体数值。

const ISAAC := "res://scenes/expedition/isaac_room_dungeon_generator.gd"

func test_grid_shape_matches_request() -> void:
	var gen: Node = load(ISAAC).new()
	var grid: Array = gen.generate_dungeon(42, 42)
	assert_int(grid.size()).is_equal(42)
	assert_int(grid[0].size()).is_equal(42)
	gen.free()

func test_room_count_in_target_range() -> void:
	var gen: Node = load(ISAAC).new()
	gen.generate_dungeon(42, 42)
	# isaac target_room_count 默认 14，clamp 到 [6,18]，实际房间数应在该范围内
	assert_int(gen.rooms.size()).is_greater_equal(6)
	assert_int(gen.rooms.size()).is_less_equal(18)
	gen.free()

func test_assigns_required_room_roles() -> void:
	var gen: Node = load(ISAAC).new()
	gen.generate_dungeon(42, 42)
	# start/boss/stairs/reward 是必 assign 的；extraction 是 0.2 概率
	assert_bool(gen.room_roles.has("start")).is_true()
	assert_bool(gen.room_roles.has("boss")).is_true()
	assert_bool(gen.room_roles.has("stairs")).is_true()
	assert_bool(gen.room_roles.has("reward")).is_true()
	for key in gen.room_roles.keys():
		assert_bool(gen.room_roles[key] is Rect2i).is_true()
	gen.free()

func test_start_room_differs_from_boss_room() -> void:
	var gen: Node = load(ISAAC).new()
	gen.generate_dungeon(42, 42)
	var start_rect: Rect2i = gen.room_roles["start"]
	var boss_rect: Rect2i = gen.room_roles["boss"]
	assert_bool(start_rect == boss_rect).is_false()
	gen.free()

func test_height_grid_matches_grid_size() -> void:
	var gen: Node = load(ISAAC).new()
	gen.generate_dungeon(42, 42)
	assert_int(gen.ceiling_heights.size()).is_equal(42)
	assert_int(gen.ceiling_heights[0].size()).is_equal(42)
	gen.free()

func test_grid_has_floor_cells() -> void:
	var gen: Node = load(ISAAC).new()
	var grid: Array = gen.generate_dungeon(42, 42)
	var floor_count := 0
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == 1:  # TileType.FLOOR
				floor_count += 1
	assert_int(floor_count).is_greater(0)
	gen.free()

# TODO 阶段11：isaac 加 seed 字段后，补 test_fixed_seed_determinism 锚定逐格一致。
