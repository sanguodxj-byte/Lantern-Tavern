extends GdUnitTestSuite

# hazard 规划/实例化契约：走 DungeonHazardPlanner + DungeonSceneBuilder，
# 不再依赖 ProceduralDungeon 旧 _spawn_hazard_anchors 路径。

func before() -> void:
	load("res://scenes/expedition/dungeon_hazard_planner.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_hazard_anchor_helpers_require_two_cell_kick_lane() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_open_layout(6, 6)
	assert_bool(planner._find_kick_lane_direction(layout, 3, 3, 2) != Vector2i.ZERO).is_true()
	# 堵住 (1,1) 四周，使其无法形成 2 格 kick lane
	layout.grid[1][2] = 2
	layout.grid[1][3] = 2
	layout.grid[2][1] = 2
	layout.grid[3][1] = 2
	assert_bool(planner._find_kick_lane_direction(layout, 1, 1, 2) == Vector2i.ZERO).is_true()

func test_spawn_hazard_anchors_marks_traps_with_kick_lane_metadata() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_open_layout(12, 12)
	# start 小房间 + 大非 start 房间（planner 跳过 start）
	layout.rooms = [Rect2i(1, 1, 2, 2), Rect2i(3, 3, 7, 7)]
	layout.room_roles["start"] = Rect2i(1, 1, 2, 2)
	layout.player_spawn_cell = Vector2i(1, 1)
	planner.plan(layout)
	assert_int(layout.hazard_anchors.size()).is_greater(0)
	for anchor in layout.hazard_anchors:
		assert_bool(anchor.has("hazard_type")).is_true()
		assert_bool(anchor.has("anchor_cell")).is_true()
		assert_bool(anchor.has("direction")).is_true()
		assert_bool(anchor.has("kick_lane_index")).is_true()
		var idx: int = anchor["kick_lane_index"]
		assert_int(idx).is_greater_equal(0)
		assert_int(idx).is_less(layout.kick_lanes.size())

	var parent := Node3D.new()
	add_child(parent)
	var result := DungeonSceneBuilder.new().build(layout, parent)
	assert_int(result.hazards_root.get_child_count()).is_equal(layout.hazard_anchors.size())
	for trap in result.hazards_root.get_children():
		assert_bool(trap.get_meta("hazard_anchor", false)).is_true()
		assert_str(str(trap.get_meta("placement_role", ""))).is_equal("terrain_damage_anchor")
		assert_bool(trap.get_meta("kick_lane_dir") is Vector2i).is_true()
	result.dispose()
	parent.queue_free()

func test_room_hazard_candidates_avoid_entrance_padding() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_open_layout(9, 9)
	var room := Rect2i(1, 1, 7, 7)
	layout.rooms = [room]
	layout.player_spawn_cell = Vector2i(100, 100)  # 远离，避免 spawn 距离过滤
	# 在房间北缘开一个出入口
	layout.grid[0][4] = 1
	layout.grid[1][4] = 1
	var candidates: Array = planner._collect_hazard_candidates_for_room(layout, room)
	assert_int(candidates.size()).is_greater(0)
	for candidate in candidates:
		var cell: Vector2i = candidate["cell"]
		assert_bool(abs(cell.x - 4) + abs(cell.y - 1) > 2) \
			.override_failure_message("危险锚点不应贴近房间出入口").is_true()
		assert_bool(room.has_point(cell)).is_true()


func _make_open_layout(width: int, height: int) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = width
	layout.height = height
	layout.tile_size = 3.0
	layout.grid = []
	layout.heights = []
	for y in range(height):
		var row: Array = []
		var hr: Array = []
		for x in range(width):
			# planner.plan 早退条件含 is_floor_at(0,0)，故 (0,0) 必须是地板
			if x == 0 and y == 0:
				row.append(1)
			elif x == 0 or y == 0 or x == width - 1 or y == height - 1:
				row.append(2)
			else:
				row.append(1)
			hr.append(3.0)
		layout.grid.append(row)
		layout.heights.append(hr)
	return layout
