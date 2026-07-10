extends GdUnitTestSuite

# 阶段 1 测试：DungeonLayout 作为纯数据结果契约。
# 覆盖：空布局、正常网格、关键点读写、深拷贝独立性、validate 报告、禁止 Node 引用。

func test_empty_layout_is_empty() -> void:
	var layout := DungeonLayout.new()
	assert_bool(layout.is_empty()).is_true()

func test_normal_grid_not_empty() -> void:
	var layout := _make_3x3_floor_layout()
	assert_bool(layout.is_empty()).is_false()
	assert_int(layout.width).is_equal(3)
	assert_int(layout.height).is_equal(3)

func test_is_floor_cell_bounds_and_value() -> void:
	var layout := _make_3x3_floor_layout()
	assert_bool(layout.is_floor_cell(Vector2i(0, 0))).is_true()
	assert_bool(layout.is_floor_cell(Vector2i(-1, 0))).is_false()
	assert_bool(layout.is_floor_cell(Vector2i(99, 99))).is_false()
	# 中心格设为墙(0)
	layout.grid[1][1] = 0
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_false()

func test_key_cell_missing_detection() -> void:
	var layout := DungeonLayout.new()
	assert_bool(layout.is_key_cell_missing(layout.player_spawn_cell)).is_true()
	layout.player_spawn_cell = Vector2i(2, 2)
	assert_bool(layout.is_key_cell_missing(layout.player_spawn_cell)).is_false()

func test_cell_role_and_room_membership() -> void:
	var layout := _make_3x3_floor_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(2, 2, 1, 1)
	assert_str(layout.cell_role(Vector2i(0, 0))).is_equal("start")
	assert_str(layout.cell_role(Vector2i(2, 2))).is_equal("boss")
	assert_str(layout.cell_role(Vector2i(1, 1))).is_equal("")
	assert_bool(layout.is_start_room_cell(Vector2i(0, 0))).is_true()
	assert_bool(layout.is_boss_room_cell(Vector2i(2, 2))).is_true()
	assert_bool(layout.is_boss_reward_cell(Vector2i(2, 2))).is_true()

func test_duplicate_layout_is_independent() -> void:
	var layout := _make_3x3_floor_layout()
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.door_specs.append({"inside": Vector2i(0, 0), "outside": Vector2i(1, 0)})
	# 先设原件 start（副本要在 dup 之后还能独立持有原值）
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	var copy := layout.duplicate_layout()
	# 改原件，副本不受影响
	layout.grid[0][0] = 0
	layout.door_specs.clear()
	assert_int(copy.grid[0][0]).is_equal(1)
	assert_int(copy.door_specs.size()).is_equal(1)
	# Rect2i 值类型副本：改原件 start，副本仍保留原 Rect2i
	layout.room_roles["start"] = Rect2i(9, 9, 1, 1)
	var copy_start: Rect2i = copy.room_roles["start"]
	assert_int(copy_start.position.x).is_equal(0)

func test_validate_empty_layout_reports_error() -> void:
	var layout := DungeonLayout.new()
	var r := layout.validate()
	assert_bool(r["valid"]).is_false()
	assert_array(r["errors"]).is_not_empty()

func test_validate_normal_layout_passes() -> void:
	var layout := _make_3x3_floor_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(2, 2, 1, 1)
	layout.player_spawn_cell = Vector2i(0, 0)
	layout.boss_cell = Vector2i(2, 2)
	var r := layout.validate()
	assert_bool(r["valid"]).is_true()
	assert_array(r["errors"]).is_empty()

func test_validate_missing_required_roles_reports_error() -> void:
	var layout := _make_3x3_floor_layout()
	var r := layout.validate()
	assert_bool(r["valid"]).is_false()
	# 应同时报告缺 start 和 boss
	var errors: Array = r["errors"]
	var has_start_err := false
	var has_boss_err := false
	for e in errors:
		if e.contains("'start'"):
			has_start_err = true
		if e.contains("'boss'"):
			has_boss_err = true
	assert_bool(has_start_err).is_true()
	assert_bool(has_boss_err).is_true()

func test_validate_rejects_node_ref_in_spec() -> void:
	var layout := _make_3x3_floor_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(2, 2, 1, 1)
	# 构造一个含 PackedScene 引用的 door_spec（违反“生成阶段不持场景节点”原则）
	var bad_spec := {"inside": Vector2i(0, 0), "outside": Vector2i(1, 0)}
	bad_spec["scene"] = load("res://scenes/props/decor/bones.tscn")  # PackedScene
	layout.door_specs.append(bad_spec)
	var r := layout.validate()
	assert_bool(r["valid"]).is_false()

func test_spawn_specs_default_empty() -> void:
	var layout := DungeonLayout.new()
	assert_int(layout.enemy_spawn_specs.size()).is_equal(0)
	assert_int(layout.item_spawn_specs.size()).is_equal(0)
	assert_int(layout.chest_spawn_specs.size()).is_equal(0)
	assert_int(layout.door_specs.size()).is_equal(0)
	assert_int(layout.hazard_anchors.size()).is_equal(0)
	assert_int(layout.kick_lanes.size()).is_equal(0)

func test_heights_shape_mismatch_detected() -> void:
	var layout := DungeonLayout.new()
	layout.width = 3
	layout.height = 3
	layout.grid = [[1,1,1],[1,1,1],[1,1,1]]
	layout.heights = [[1.0,1.0],[1.0,1.0]]  # 行数不对、列数也不对
	layout.room_roles["start"] = Rect2i(0,0,1,1)
	layout.room_roles["boss"] = Rect2i(2,2,1,1)
	var r := layout.validate()
	assert_bool(r["valid"]).is_false()

func test_key_cell_out_of_bounds_detected() -> void:
	var layout := _make_3x3_floor_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	layout.room_roles["boss"] = Rect2i(2, 2, 1, 1)
	layout.player_spawn_cell = Vector2i(99, 99)  # 越界
	var r := layout.validate()
	assert_bool(r["valid"]).is_false()

# ── helpers ──────────────────────────────────────────────
func _make_3x3_floor_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 3
	layout.height = 3
	layout.grid = [[1,1,1],[1,1,1],[1,1,1]]
	layout.heights = [[3.0,3.0,3.0],[3.0,3.0,3.0],[3.0,3.0,3.0]]
	layout.tile_size = 3.0
	return layout
