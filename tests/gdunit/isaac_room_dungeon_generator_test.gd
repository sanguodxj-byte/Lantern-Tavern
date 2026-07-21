extends GdUnitTestSuite

const GENERATOR := preload("res://scenes/expedition/isaac_room_dungeon_generator.gd")
const TEST_GRID_SIZE := 42
const TEST_GRID_CENTER := Vector2i(21, 21)


func test_isaac_room_generator_grows_rooms_from_center_and_assigns_terminal_roles() -> void:
	seed(71231)
	var generator: Node = GENERATOR.new()
	var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)

	assert_int(generator.rooms.size()).is_greater_equal(6)
	assert_bool(generator.room_roles.has("start")).is_true()
	assert_bool(generator.room_roles.has("reward")).is_true()
	assert_bool(generator.room_roles.has("boss")).is_true()
	assert_bool(generator.room_roles.has("stairs")).is_true()

	var start: Rect2i = generator.room_roles["start"]
	var boss: Rect2i = generator.room_roles["boss"]
	var reward: Rect2i = generator.room_roles["reward"]
	var stairs: Rect2i = generator.room_roles["stairs"]
	assert_bool(start.has_point(TEST_GRID_CENTER)) \
		.override_failure_message("出生房不应固定在地图中心") \
		.is_false()
	assert_bool(generator.get_terminal_macro_rooms().size() >= 4).is_true()
	assert_bool(_rect_center_distance(start, boss) >= 8.0).is_true()
	assert_bool(_rect_center_distance(start, reward) >= 6.0).is_true()
	assert_bool(_is_terminal_room(generator, boss)).is_true()
	assert_bool(_is_terminal_room(generator, reward)).is_true()
	assert_bool(_is_terminal_room(generator, stairs)).is_true()
	if generator.room_roles.has("extraction"):
		var extraction: Rect2i = generator.room_roles["extraction"]
		assert_bool(_is_terminal_room(generator, extraction)).is_true()
		assert_bool(extraction == boss) \
			.override_failure_message("抽中撤离点时必须复用末端 Boss 房间") \
			.is_true()
	assert_bool(boss != reward).is_true()

	assert_bool(_all_floor_cells_connected(grid)).is_true()
	generator.free()


func test_start_room_is_not_fixed_center_and_varies_by_seed() -> void:
	var start_centers: Dictionary = {}
	for test_seed in [9101, 9102, 9103, 9104, 9105, 9106, 9107, 9108]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		var start: Rect2i = generator.room_roles["start"]
		assert_bool(start.has_point(TEST_GRID_CENTER)) \
			.override_failure_message("出生房不应固定在地图中心，seed=%d start=%s" % [test_seed, start]) \
			.is_false()
		start_centers[_rect_center(start)] = true
		generator.free()

	assert_int(start_centers.size()) \
		.override_failure_message("多个 seed 的出生房应发生变化，而不是固定同一个房间") \
		.is_greater_equal(3)


func test_isaac_room_generator_marks_reward_and_boss_cells_for_content() -> void:
	seed(91811)
	var generator: Node = GENERATOR.new()
	var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
	var reward_center: Vector2i = _rect_center(generator.room_roles["reward"])
	var boss_center: Vector2i = _rect_center(generator.room_roles["boss"])

	assert_int(int(grid[reward_center.y][reward_center.x])).is_equal(BSP_DungeonGenerator.TileType.LOOT)
	assert_int(int(grid[boss_center.y][boss_center.x - 1])).is_equal(BSP_DungeonGenerator.TileType.RESOURCE)
	assert_int(int(grid[boss_center.y][boss_center.x + 1])).is_equal(BSP_DungeonGenerator.TileType.RESOURCE)
	generator.free()


func test_isaac_room_generator_creates_interconnected_room_loops() -> void:
	for test_seed in [3401, 71231, 91811, 271828]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		var connection_pairs: Array = generator.get_macro_connection_pairs()
		var cycle_rank: int = connection_pairs.size() - generator.rooms.size() + 1

		assert_int(cycle_rank) \
			.override_failure_message("地牢宏观拓扑互通性不足，不应退化为线状/树状连接: seed=%d rooms=%d edges=%d cycles=%d" % [test_seed, generator.rooms.size(), connection_pairs.size(), cycle_rank]) \
			.is_greater_equal(2)
		assert_bool(_all_floor_cells_connected(grid)) \
			.override_failure_message("拼合/摆动走廊后仍必须保持全地牢可通行: seed=%d" % test_seed) \
			.is_true()

		generator.free()


func test_shortcut_connections_are_broken_up_by_connector_chambers() -> void:
	for test_seed in [3401, 71231, 91811, 271828]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		var shortcuts: Array = generator.get_shortcut_macro_connection_pairs()
		var connector_rects: Array = generator.get_shortcut_connector_rects()

		assert_int(shortcuts.size()) \
			.override_failure_message("测试需要生成 shortcut 连接来验证长通道拆分: seed=%d" % test_seed) \
			.is_greater_equal(1)
		assert_int(connector_rects.size()) \
			.override_failure_message("shortcut 不应形成裸长通道，需要记录并生成中继连接厅: seed=%d" % test_seed) \
			.is_greater_equal(1)
		for connector_rect in connector_rects:
			assert_int(_walkable_cells_in_rect(grid, connector_rect)) \
				.override_failure_message("shortcut 连接厅必须是可通行空间，而不是只有一条线: seed=%d rect=%s" % [test_seed, connector_rect]) \
				.is_greater_equal(20)
		for shortcut in shortcuts:
			var a: Vector2i = shortcut["a"]
			var b: Vector2i = shortcut["b"]
			var delta := b - a
			var distance: int = absi(delta.x) + absi(delta.y)
			if distance <= 1:
				continue
			assert_bool(_has_connector_between_macro_cells(connector_rects, a, b)) \
				.override_failure_message("每条跨格 shortcut 都需要至少一个中继连接厅: seed=%d shortcut=%s->%s" % [test_seed, a, b]) \
				.is_true()

		generator.free()


func test_room_centers_are_relaxed_off_macro_grid() -> void:
	seed(24680)
	var generator: Node = GENERATOR.new()
	generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
	var relaxed_count := 0

	for item in generator.room_metadata:
		var macro: Vector2i = item["macro"]
		var center: Vector2i = _rect_center(item["rect"])
		if center != _macro_grid_center(macro):
			relaxed_count += 1

	assert_int(relaxed_count) \
		.override_failure_message("房间中心过度贴合宏格，会暴露明显棋盘网格布局") \
		.is_greater_equal(4)

	generator.free()


func test_some_adjacent_rooms_are_merged_into_compound_rooms() -> void:
	for test_seed in [3401, 71231, 91811, 24680]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		var merged_pairs: Array = generator.get_merged_macro_connection_pairs()
		var partition_rects: Array = generator.get_merged_partition_rects()
		var boss_rect: Rect2i = generator.room_roles["boss"]

		assert_int(merged_pairs.size()) \
			.override_failure_message("需要允许部分相邻房间拼合成复合房间，降低棋盘网格感: seed=%d" % test_seed) \
			.is_greater_equal(2)
		assert_int(partition_rects.size()) \
			.override_failure_message("拼合后的复合房间需要生成短隔墙/残墙，避免大空间过于空旷: seed=%d" % test_seed) \
			.is_greater_equal(4)
		assert_int(_wall_cells_in_rects(grid, partition_rects)) \
			.override_failure_message("拼合房间记录了隔墙区域，但没有实际墙体: seed=%d" % test_seed) \
			.is_greater_equal(8)
		for pair in merged_pairs:
			var a: Vector2i = pair["a"]
			var b: Vector2i = pair["b"]
			var a_rect := _room_rect_for_macro(generator.room_metadata, a)
			var b_rect := _room_rect_for_macro(generator.room_metadata, b)
			assert_bool(a_rect == boss_rect or b_rect == boss_rect) \
				.override_failure_message("Boss 房不应参与普通房间拼合: seed=%d pair=%s->%s boss=%s" % [test_seed, a, b, boss_rect]) \
				.is_false()
			var bridge_probe := _compound_bridge_probe_rect(a_rect, b_rect)
			assert_int(_walkable_cells_in_rect(grid, bridge_probe)) \
				.override_failure_message("拼合房间需要宽共享区域，而不是一格门或细走廊: seed=%d pair=%s->%s probe=%s" % [test_seed, a, b, bridge_probe]) \
				.is_greater_equal(12)

		generator.free()


func test_start_room_only_contains_walkable_material_or_chest_special_cells() -> void:
	for test_seed in [424242, 101, 202, 303, 404, 505, 606, 707]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		var start: Rect2i = generator.room_roles["start"]

		for y in range(start.position.y, start.position.y + start.size.y):
			for x in range(start.position.x, start.position.x + start.size.x):
				var cell_type := int(grid[y][x])
				assert_bool(cell_type in [
					BSP_DungeonGenerator.TileType.FLOOR,
					BSP_DungeonGenerator.TileType.WALL,
					BSP_DungeonGenerator.TileType.LOOT,
					BSP_DungeonGenerator.TileType.RESOURCE,
				]) \
					.override_failure_message("出生房只允许普通地面、素材或宝箱格，seed=%d 当前 (%d,%d)=%d" % [test_seed, x, y, cell_type]) \
					.is_true()

		generator.free()


func test_terminal_rooms_have_materials_or_chest_and_optional_extraction_stays_terminal() -> void:
	for test_seed in [159753, 111, 222, 333, 444, 555, 666, 777]:
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)

		if generator.room_roles.has("extraction"):
			assert_bool(generator.room_roles["extraction"] == generator.room_roles["boss"]) \
				.override_failure_message("撤离点必须位于末端 Boss 房间，seed=%d" % test_seed) \
				.is_true()

		for terminal in generator.get_terminal_rooms():
			var loot_count := _count_cells_in_rect(grid, terminal, BSP_DungeonGenerator.TileType.LOOT)
			var resource_count := _count_cells_in_rect(grid, terminal, BSP_DungeonGenerator.TileType.RESOURCE)
			assert_bool(loot_count >= 1 or resource_count >= 3) \
				.override_failure_message("末端房间至少需要 3 个素材或 1 个宝箱: seed=%d %s loot=%d resource=%d" % [test_seed, terminal, loot_count, resource_count]) \
				.is_true()

		generator.free()


func test_extraction_room_probability_is_about_one_in_five() -> void:
	var extraction_count := 0
	var generated_count := 200
	for test_seed in range(1000, 1000 + generated_count):
		seed(test_seed)
		var generator: Node = GENERATOR.new()
		generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
		if generator.room_roles.has("extraction"):
			extraction_count += 1
			assert_bool(_is_terminal_room(generator, generator.room_roles["extraction"])) \
				.override_failure_message("撤离点必须位于末端房间，seed=%d" % test_seed) \
				.is_true()
		generator.free()

	assert_int(extraction_count) \
		.override_failure_message("撤离点概率应接近 20%%: count=%d/%d" % [extraction_count, generated_count]) \
		.is_between(25, 55)


func test_isaac_room_generator_varies_room_shape_size_height_and_content() -> void:
	seed(112358)
	var generator: Node = GENERATOR.new()
	var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
	var metadata: Array = generator.room_metadata

	assert_int(metadata.size()).is_greater_equal(10)
	assert_int(_unique_string_values(metadata, "shape").size()) \
		.override_failure_message("房间形状过于单一，需要稳定生成多种房型") \
		.is_greater_equal(10)
	assert_int(_max_int_value(metadata, "area") - _min_int_value(metadata, "area")) \
		.override_failure_message("房间大小差异不足") \
		.is_greater_equal(60)
	assert_float(_max_float_value(metadata, "height") - _min_float_value(metadata, "height")) \
		.override_failure_message("房间高度差异不足") \
		.is_greater_equal(1.2)
	assert_int(_count_non_rectangular_rooms(grid, metadata)) \
		.override_failure_message("需要至少存在十字/L形/凹室等非完整矩形房间") \
		.is_greater_equal(6)
	assert_int(_metadata_with_shapes(metadata, ["jagged_cavern", "double_chamber", "offset_chamber", "crescent", "broken_ring"]).size()) \
		.override_failure_message("需要稳定生成非对称房型，而不是只旋转矩形房间") \
		.is_greater_equal(4)
	assert_int(_count_rectilinear_shape_names(metadata)) \
		.override_failure_message("普通矩形房间占比过高，会看起来像同一房型旋转复用") \
		.is_less_equal(metadata.size() / 2)
	assert_int(_count_cells(grid, BSP_DungeonGenerator.TileType.PILLAR)) \
		.override_failure_message("内容差异不足：需要柱厅或柱子内容") \
		.is_greater_equal(1)
	assert_int(_count_cells(grid, BSP_DungeonGenerator.TileType.LOOT)) \
		.override_failure_message("内容差异不足：需要奖励/宝藏格") \
		.is_greater_equal(1)
	assert_int(_count_cells(grid, BSP_DungeonGenerator.TileType.RESOURCE)) \
		.override_failure_message("内容差异不足：需要资源/特殊内容格") \
		.is_greater_equal(2)

	generator.free()


func test_isaac_room_generator_carves_round_and_perlin_cavern_rooms() -> void:
	seed(271828)
	var generator: Node = GENERATOR.new()
	var grid: Array = generator.generate_dungeon(TEST_GRID_SIZE, TEST_GRID_SIZE, 14)
	var metadata: Array = generator.room_metadata

	var organic_shapes := _metadata_with_shapes(metadata, ["circle", "ellipse", "noise_cavern", "jagged_cavern", "crescent"])
	assert_int(organic_shapes.size()) \
		.override_failure_message("需要稳定生成圆形、椭圆、柏林噪声洞室或锯齿洞室房间") \
		.is_greater_equal(4)
	assert_bool(_unique_string_values(organic_shapes, "shape").has("circle")).is_true()
	assert_bool(_unique_string_values(organic_shapes, "shape").has("ellipse")).is_true()
	assert_bool(_unique_string_values(organic_shapes, "shape").has("noise_cavern")).is_true()
	assert_bool(_unique_string_values(organic_shapes, "shape").has("jagged_cavern")).is_true()

	for item in organic_shapes:
		var rect: Rect2i = item["rect"]
		var floor_count := _walkable_cells_in_rect(grid, rect)
		assert_int(floor_count) \
			.override_failure_message("有机房型不应被雕成完整矩形: %s %s" % [item["shape"], rect]) \
			.is_less(rect.size.x * rect.size.y)
		assert_int(_corner_wall_count(grid, rect)) \
			.override_failure_message("圆形/洞室房间需要有可见的切角轮廓: %s %s" % [item["shape"], rect]) \
			.is_greater_equal(2)

	generator.free()


func _all_floor_cells_connected(grid: Array) -> bool:
	var floor_cells: Array[Vector2i] = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var cell_type := int(grid[y][x])
			if cell_type != BSP_DungeonGenerator.TileType.EMPTY and cell_type != BSP_DungeonGenerator.TileType.WALL:
				floor_cells.append(Vector2i(x, y))
	if floor_cells.is_empty():
		return false
	var visited: Dictionary = {floor_cells[0]: true}
	var queue: Array[Vector2i] = [floor_cells[0]]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + dir
			if visited.has(next):
				continue
			if next.y < 0 or next.y >= grid.size() or next.x < 0 or next.x >= grid[next.y].size():
				continue
			var cell_type := int(grid[next.y][next.x])
			if cell_type == BSP_DungeonGenerator.TileType.EMPTY or cell_type == BSP_DungeonGenerator.TileType.WALL:
				continue
			visited[next] = true
			queue.append(next)
	return visited.size() == floor_cells.size()


func _rect_center(rect: Rect2i) -> Vector2i:
	return rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)


func _rect_center_distance(a: Rect2i, b: Rect2i) -> float:
	return Vector2(_rect_center(a)).distance_to(Vector2(_rect_center(b)))


func _is_terminal_room(generator: Node, rect: Rect2i) -> bool:
	for terminal in generator.get_terminal_rooms():
		if terminal == rect:
			return true
	return false


func _macro_grid_center(macro: Vector2i) -> Vector2i:
	return TEST_GRID_CENTER + macro * 8


func _has_connector_between_macro_cells(connector_rects: Array, a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	var distance: int = absi(delta.x) + absi(delta.y)
	if distance <= 1:
		return true
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	for step in range(1, distance):
		var macro_center := _macro_grid_center(a + dir * step)
		for connector_rect in connector_rects:
			if connector_rect.has_point(macro_center) or _rect_center(connector_rect).distance_to(macro_center) <= 2.0:
				return true
	return false


func _room_rect_for_macro(metadata: Array, macro: Vector2i) -> Rect2i:
	for item in metadata:
		if item["macro"] == macro:
			return item["rect"]
	return Rect2i()


func _compound_bridge_probe_rect(a: Rect2i, b: Rect2i) -> Rect2i:
	var a_center := _rect_center(a)
	var b_center := _rect_center(b)
	if abs(a_center.x - b_center.x) >= abs(a_center.y - b_center.y):
		var x0 := mini(a.position.x + a.size.x - 1, b.position.x + b.size.x - 1)
		var x1 := maxi(a.position.x, b.position.x)
		var y := roundi(float(a_center.y + b_center.y) * 0.5)
		return Rect2i(Vector2i(mini(x0, x1) - 1, y - 2), Vector2i(absi(x1 - x0) + 3, 5))
	var y0 := mini(a.position.y + a.size.y - 1, b.position.y + b.size.y - 1)
	var y1 := maxi(a.position.y, b.position.y)
	var x := roundi(float(a_center.x + b_center.x) * 0.5)
	return Rect2i(Vector2i(x - 2, mini(y0, y1) - 1), Vector2i(5, absi(y1 - y0) + 3))


func _unique_string_values(metadata: Array, key: String) -> Array[String]:
	var seen: Dictionary = {}
	for item in metadata:
		seen[String(item[key])] = true
	var result: Array[String] = []
	for value in seen.keys():
		result.append(String(value))
	return result


func _min_int_value(metadata: Array, key: String) -> int:
	var result := 999999
	for item in metadata:
		result = mini(result, int(item[key]))
	return result


func _max_int_value(metadata: Array, key: String) -> int:
	var result := -999999
	for item in metadata:
		result = maxi(result, int(item[key]))
	return result


func _min_float_value(metadata: Array, key: String) -> float:
	var result := 999999.0
	for item in metadata:
		result = minf(result, float(item[key]))
	return result


func _max_float_value(metadata: Array, key: String) -> float:
	var result := -999999.0
	for item in metadata:
		result = maxf(result, float(item[key]))
	return result


func _count_non_rectangular_rooms(grid: Array, metadata: Array) -> int:
	var count := 0
	for item in metadata:
		var rect: Rect2i = item["rect"]
		var floor_count := _walkable_cells_in_rect(grid, rect)
		if floor_count < rect.size.x * rect.size.y:
			count += 1
	return count


func _metadata_with_shapes(metadata: Array, shapes: Array[String]) -> Array:
	var result: Array = []
	for item in metadata:
		if String(item["shape"]) in shapes:
			result.append(item)
	return result


func _count_rectilinear_shape_names(metadata: Array) -> int:
	var count := 0
	for item in metadata:
		if String(item["shape"]) in ["square", "compact", "wide", "tall", "great_hall", "pillar_hall"]:
			count += 1
	return count


func _walkable_cells_in_rect(grid: Array, rect: Rect2i) -> int:
	var floor_count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell_type := int(grid[y][x])
			if cell_type != BSP_DungeonGenerator.TileType.EMPTY and cell_type != BSP_DungeonGenerator.TileType.WALL:
				floor_count += 1
	return floor_count


func _wall_cells_in_rects(grid: Array, rects: Array) -> int:
	var count := 0
	for rect in rects:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
					continue
				if int(grid[y][x]) == BSP_DungeonGenerator.TileType.WALL:
					count += 1
	return count


func _corner_wall_count(grid: Array, rect: Rect2i) -> int:
	var count := 0
	for cell in [
		rect.position,
		Vector2i(rect.position.x + rect.size.x - 1, rect.position.y),
		Vector2i(rect.position.x, rect.position.y + rect.size.y - 1),
		rect.position + rect.size - Vector2i.ONE,
	]:
		var cell_type := int(grid[cell.y][cell.x])
		if cell_type == BSP_DungeonGenerator.TileType.EMPTY or cell_type == BSP_DungeonGenerator.TileType.WALL:
			count += 1
	return count


func _count_cells(grid: Array, cell_type: int) -> int:
	var count := 0
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) == cell_type:
				count += 1
	return count


func _count_cells_in_rect(grid: Array, rect: Rect2i, cell_type: int) -> int:
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if int(grid[y][x]) == cell_type:
				count += 1
	return count
