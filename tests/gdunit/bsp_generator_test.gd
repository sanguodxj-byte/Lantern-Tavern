extends GdUnitTestSuite

# Test suite for BSP_DungeonGenerator

var _bsp: BSP_DungeonGenerator

func before() -> void:
	_bsp = load("res://scenes/expedition/bsp_generator.gd").new()

func after() -> void:
	if is_instance_valid(_bsp):
		_bsp.free()

func test_dungeon_size_match() -> void:
	var width := 30
	var height := 30
	var grid = _bsp.generate_dungeon(width, height)
	
	assert_int(grid.size()).is_equal(height)
	for row in grid:
		assert_int(row.size()).is_equal(width)


func test_outermost_border_is_always_wall() -> void:
	var width := 25
	var height := 25
	var grid = _bsp.generate_dungeon(width, height)
	
	for y in range(height):
		for x in range(width):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				assert_int(grid[y][x]) \
					.override_failure_message("Border tile at (%d, %d) is not WALL" % [x, y]) \
					.is_equal(2) # TileType.WALL is 2


func test_all_floor_tiles_are_connected() -> void:
	# Test connectivity of rooms using Flood Fill (BFS)
	var width := 30
	var height := 30
	var grid = _bsp.generate_dungeon(width, height)
	
	# Find first FLOOR (1) tile to act as flood source
	var start_x := -1
	var start_y := -1
	for y in range(height):
		for x in range(width):
			if grid[y][x] == 1: # TileType.FLOOR is 1
				start_x = x
				start_y = y
				break
		if start_x != -1:
			break
			
	# Assert a start point was indeed found (meaning rooms exist)
	assert_int(start_x).is_not_equal(-1)
	
	# BFS Flood Fill
	var queue := [Vector2i(start_x, start_y)]
	var visited := {}
	visited[Vector2i(start_x, start_y)] = true
	var directions := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	
	while queue.size() > 0:
		var curr = queue.pop_front()
		for dir in directions:
			var nx = curr.x + dir.x
			var ny = curr.y + dir.y
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				var cell_type = grid[ny][nx]
				# walkable tile types: FLOOR(1), LOOT(3), RESOURCE(4), PILLAR(5)
				if cell_type in [1, 3, 4, 5]:
					var pos = Vector2i(nx, ny)
					if not visited.has(pos):
						visited[pos] = true
						queue.append(pos)
						
	# Assert that every FLOOR / LOOT / RESOURCE / PILLAR in the generated grid was visited
	# This proves there are 0 isolated room islands!
	for y in range(height):
		for x in range(width):
			var cell_type = grid[y][x]
			if cell_type in [1, 3, 4, 5]:
				var pos = Vector2i(x, y)
				assert_bool(visited.has(pos)) \
					.override_failure_message("Isolated tile of type %d found at (%d, %d)" % [cell_type, x, y]) \
					.is_true()

func test_ceiling_heights() -> void:
	var width := 30
	var height := 30
	var grid = _bsp.generate_dungeon(width, height)
	var heights = _bsp.ceiling_heights
	
	assert_int(heights.size()).is_equal(height)
	for y in range(height):
		assert_int(heights[y].size()).is_equal(width)
		for x in range(width):
			var cell_type = grid[y][x]
			var h = heights[y][x]
			
			if cell_type == 1 or cell_type == 5:
				# Walkable floors/pillars must have valid heights: 2.4 (corridor), 3.0 (small), 3.8 (medium), 4.6 (large)
				assert_bool(h in [2.4, 3.0, 3.8, 4.6]) \
					.override_failure_message("Invalid floor ceiling height %.1f at (%d, %d)" % [h, x, y]) \
					.is_true()
			elif cell_type == 2:
				# Outer borders walls must be default 3.0 initially
				if x == 0 or x == width - 1 or y == 0 or y == height - 1:
					assert_float(h).is_equal(3.0)

func test_rooms_are_recorded_for_room_based_hazard_generation() -> void:
	var width := 30
	var height := 30
	_bsp.generate_dungeon(width, height)
	assert_int(_bsp.rooms.size()).is_greater(0)
	for room in _bsp.rooms:
		assert_bool(room.size.x > 0 and room.size.y > 0).is_true()
		assert_bool(room.position.x >= 0 and room.position.y >= 0).is_true()
		assert_bool(room.position.x + room.size.x <= width).is_true()
		assert_bool(room.position.y + room.size.y <= height).is_true()
