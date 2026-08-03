extends GdUnitTestSuite


class TorchPlacementRecorder extends DungeonSceneBuilder:
	var captured_positions: Array[Vector3] = []

	func _spawn_torch_on_wall(_result: DungeonBuildResult, _parent: Node3D, cell_pos: Vector3,
			_wall_dir: Vector2i, _wall_height: float, _tile_size: float) -> void:
		captured_positions.append(cell_pos)

	func _spawn_random_decor(_result: DungeonBuildResult, _parent: Node3D,
			_runtime_cfg: DungeonRuntimeConfig, _pos: Vector3) -> void:
		pass


func test_random_wall_torches_follow_elevated_floor_height() -> void:
	var layout := _elevated_checkerboard_layout()
	var result := DungeonBuildResult.new()
	for y in range(layout.height):
		for x in range(layout.width):
			if int(layout.grid[y][x]) == 2:
				result.wall_h_map[Vector2i(x, y)] = 4.0
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	var builder := TorchPlacementRecorder.new()
	seed(20260801)
	builder._build_decor_and_torches(layout, result, parent)

	assert_int(builder.captured_positions.size()) \
		.override_failure_message("固定种子必须生成至少一盏随机墙面火把") \
		.is_greater(0)
	for cell_pos in builder.captured_positions:
		assert_float(cell_pos.y) \
			.override_failure_message("随机墙面火把必须以当前格的抬升地面为高度基准") \
			.is_equal_approx(1.25, 0.001)


func test_elevated_wall_torch_stays_between_floor_and_ceiling() -> void:
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	var result := DungeonBuildResult.new()
	result.decor_root = Node3D.new()
	parent.add_child(result.decor_root)
	var builder := DungeonSceneBuilder.new()
	var floor_position := Vector3(0.0, 1.25, 0.0)
	var wall_top_y := 4.0

	builder._spawn_torch_on_wall(result, parent, floor_position, Vector2i(0, 1), wall_top_y, 3.0)

	assert_int(result.decor_root.get_child_count()).is_equal(1)
	var torch := result.decor_root.get_child(0) as Node3D
	assert_float(torch.position.y).is_equal_approx(2.4875, 0.001)
	assert_float(torch.position.y).is_greater(floor_position.y)
	assert_float(torch.position.y + builder.TORCH_VISUAL_TOP_LOCAL_Y) \
		.override_failure_message("抬升地面上的火把实体顶端必须低于墙顶") \
		.is_less_equal(wall_top_y - builder.TORCH_CEILING_CLEARANCE + 0.001)


func _elevated_checkerboard_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.zone = 0
	layout.tile_size = 3.0
	layout.width = 24
	layout.height = 24
	for y in range(layout.height):
		var row: Array[int] = []
		var height_row: Array[float] = []
		var elevation_row: Array[float] = []
		for x in range(layout.width):
			row.append(1 if (x + y) % 2 == 0 else 2)
			height_row.append(4.0)
			elevation_row.append(1.25)
		layout.grid.append(row)
		layout.heights.append(height_row)
		layout.floor_elevations.append(elevation_row)
	return layout
