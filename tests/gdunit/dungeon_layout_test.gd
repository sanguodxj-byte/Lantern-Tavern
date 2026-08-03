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
	# 中心格设为 EMPTY(0) 不可走
	layout.grid[1][1] = 0
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_false()
	# WALL(2) 不可走
	layout.grid[1][1] = 2
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_false()
	# LOOT/RESOURCE/PILLAR 与 isaac walkable 一致，视为可走
	layout.grid[1][1] = 3  # LOOT
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_true()
	layout.grid[1][1] = 4  # RESOURCE
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_true()
	layout.grid[1][1] = 5  # PILLAR
	assert_bool(layout.is_floor_cell(Vector2i(1, 1))).is_true()

func test_floor_height_defaults_to_zero_and_reads_elevated_cells() -> void:
	var layout := _make_3x3_floor_layout()
	assert_float(layout.floor_height_at(Vector2i(1, 1))).is_equal(0.0)
	layout.floor_elevations = [[0.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 0.0]]
	assert_float(layout.floor_height_at(Vector2i(1, 1))).is_equal(1.0)
	assert_float(layout.floor_height_at(Vector2i(99, 99))).is_equal(0.0)

func test_subcell_spawn_offsets_are_deterministic_and_not_centered() -> void:
	var layout := _make_3x3_floor_layout()
	layout.seed = 94021
	var cell := Vector2i(1, 1)
	var enemy_offset: Vector2 = layout.subcell_offset_for("enemy", cell, 0)
	var enemy_offset_again: Vector2 = layout.subcell_offset_for("enemy", cell, 0)
	var item_offset: Vector2 = layout.subcell_offset_for("item", cell, 0)
	assert_bool(enemy_offset.is_equal_approx(enemy_offset_again)).is_true()
	assert_bool(not enemy_offset.is_zero_approx()) \
		.override_failure_message("敌人生成偏移不能退化为格中心").is_true()
	assert_bool(not item_offset.is_zero_approx()) \
		.override_failure_message("物品生成偏移不能退化为格中心").is_true()
	assert_bool(not enemy_offset.is_equal_approx(item_offset)) \
		.override_failure_message("不同实体类别应使用不同的格内分布，避免全部沿格中心线").is_true()
	assert_float(absf(enemy_offset.x)).is_less_equal(0.35)
	assert_float(absf(enemy_offset.y)).is_less_equal(0.35)

func test_cell_to_world_shares_center_formula_and_applies_category_offset() -> void:
	var layout := _make_3x3_floor_layout()
	layout.floor_elevations = [[0.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 0.0]]
	layout.seed = 94021
	var cell := Vector2i(1, 1)
	var center := layout.cell_to_world(cell, 0.5)
	var item := layout.cell_to_world(cell, 0.5, "item", 0)
	assert_float(center.x).is_equal_approx(-1.5, 0.001)
	assert_float(center.y).is_equal_approx(1.5, 0.001)
	assert_float(center.z).is_equal_approx(-1.5, 0.001)
	assert_bool(not item.is_equal_approx(center)).is_true()

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
	layout.floor_elevations = [[1.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	layout.room_composition_specs.append({"composition_kind": "elevation", "platform_cells": [Vector2i(0, 0)]})
	# 先设原件 start（副本要在 dup 之后还能独立持有原值）
	layout.room_roles["start"] = Rect2i(0, 0, 1, 1)
	var copy := layout.duplicate_layout()
	# 改原件，副本不受影响
	layout.grid[0][0] = 0
	layout.door_specs.clear()
	layout.floor_elevations[0][0] = 0.0
	layout.room_composition_specs.clear()
	assert_int(copy.grid[0][0]).is_equal(1)
	assert_int(copy.door_specs.size()).is_equal(1)
	assert_float(copy.floor_height_at(Vector2i(0, 0))).is_equal(1.0)
	assert_int(copy.room_composition_specs.size()).is_equal(1)
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
	bad_spec["scene"] = load("res://scenes/props/dungeon/decor/bones.tscn")  # PackedScene
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
