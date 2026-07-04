extends GdUnitTestSuite

# Tests for BSP_DungeonGenerator

func test_bsp_generator_10x10_grid() -> void:
	var gen := BSP_DungeonGenerator.new()
	gen.grid = gen.generate_dungeon(10, 10)
	assert_int(gen.grid.size()).is_equal(10)
	for row in gen.grid:
		assert_int(row.size()).is_equal(10)


func test_bsp_generator_20x20_grid() -> void:
	var gen := BSP_DungeonGenerator.new()
	gen.grid = gen.generate_dungeon(20, 20)
	assert_int(gen.grid.size()).is_equal(20)


func test_bsp_generator_varying_sizes() -> void:
	for size in [8, 16, 24, 32]:
		var gen := BSP_DungeonGenerator.new()
		gen.grid = gen.generate_dungeon(size, size)
		assert_int(gen.grid.size()).is_equal(size)
		for row in gen.grid:
			assert_int(row.size()).is_equal(size)


func test_bsp_tile_types_enum() -> void:
	assert_int(BSP_DungeonGenerator.TileType.EMPTY).is_equal(0)
	assert_int(BSP_DungeonGenerator.TileType.FLOOR).is_equal(1)
	assert_int(BSP_DungeonGenerator.TileType.WALL).is_equal(2)
	assert_int(BSP_DungeonGenerator.TileType.LOOT).is_equal(3)
	assert_int(BSP_DungeonGenerator.TileType.RESOURCE).is_equal(4)
	assert_int(BSP_DungeonGenerator.TileType.PILLAR).is_equal(5)


func test_bsp_has_at_least_some_floor() -> void:
	var gen := BSP_DungeonGenerator.new()
	gen.grid = gen.generate_dungeon(20, 20)
	var floor_count := 0
	for row in gen.grid:
		for cell in row:
			if cell == BSP_DungeonGenerator.TileType.FLOOR:
				floor_count += 1
	assert_bool(floor_count > 0).is_true()


func test_bsp_has_walls() -> void:
	var gen := BSP_DungeonGenerator.new()
	gen.grid = gen.generate_dungeon(15, 15)
	var wall_count := 0
	for row in gen.grid:
		for cell in row:
			if cell == BSP_DungeonGenerator.TileType.WALL:
				wall_count += 1
	assert_bool(wall_count > 0).is_true()


func test_bsp_leaf_split_logic() -> void:
	var leaf := BSP_DungeonGenerator.Leaf.new(0, 0, 40, 40)
	var split := leaf.split(5)
	assert_bool(split).is_true()
	assert_object(leaf.child_1).is_not_null()
	assert_object(leaf.child_2).is_not_null()


func test_bsp_leaf_too_small_not_split() -> void:
	var leaf := BSP_DungeonGenerator.Leaf.new(0, 0, 5, 5)
	var split := leaf.split(5)
	assert_bool(split).is_false()
	assert_object(leaf.child_1).is_null()
	assert_object(leaf.child_2).is_null()
