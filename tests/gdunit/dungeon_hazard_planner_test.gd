extends GdUnitTestSuite

# 阶段 5 测试：DungeonHazardPlanner 只规划不 instantiate prefab。
# 覆盖：禁放区、KickLane 必存、hazard_type 稳定 ID、安全站位、validate_plan、集成 isaac。

func before() -> void:
	load("res://scenes/expedition/dungeon_hazard_planner.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_generator.gd")

func test_plan_empty_layout_does_nothing() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := DungeonLayout.new()
	planner.plan(layout)
	assert_int(layout.hazard_anchors.size()).is_equal(0)
	assert_int(layout.kick_lanes.size()).is_equal(0)

func test_plan_skips_start_room() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_5x5_one_room_layout()
	layout.room_roles["start"] = Rect2i(1, 1, 3, 3)  # 唯一房间 = start
	layout.rooms.append(Rect2i(1, 1, 3, 3))
	layout.player_spawn_cell = Vector2i(2, 2)
	planner.plan(layout)
	# start 房间不放 hazard
	assert_int(layout.hazard_anchors.size()).is_equal(0)

func test_plan_does_not_place_on_forbidden_cells() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan(layout)
	# 无 hazard 锚点落在出生格/boss格或其紧邻
	var forbidden := {layout.player_spawn_cell: true, layout.boss_cell: true}
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
		forbidden[layout.player_spawn_cell + d] = true
		forbidden[layout.boss_cell + d] = true
	for anchor in layout.hazard_anchors:
		var cell: Vector2i = anchor["anchor_cell"]
		assert_bool(not forbidden.has(cell)) \
			.override_failure_message("hazard anchor %s 落在禁放区" % str(cell)) \
			.is_true()

func test_plan_every_anchor_has_kick_lane() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan(layout)
	for anchor in layout.hazard_anchors:
		assert_bool(anchor.has("kick_lane_index")).is_true()
		var idx: int = anchor["kick_lane_index"]
		assert_int(idx).is_greater_equal(0)
		assert_int(idx).is_less(layout.kick_lanes.size())
		# kick_lane 长度 ≥ 2
		var lane: Dictionary = layout.kick_lanes[idx]
		assert_int(lane["length_cells"]).is_greater_equal(2)

func test_plan_anchor_on_floor() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan(layout)
	for anchor in layout.hazard_anchors:
		assert_bool(layout.is_floor_cell(anchor["anchor_cell"])).is_true()

func test_plan_hazard_type_is_stable_id() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan(layout)
	for anchor in layout.hazard_anchors:
		var ht: String = anchor["hazard_type"]
		assert_bool(ht in ["spikes", "acid", "flame_vent"]) \
			.override_failure_message("hazard_type '%s' 不是稳定 ID" % ht).is_true()

func test_plan_does_not_load_prefab_scenes() -> void:
	# 阶段 5 核心约束：planner 不加载 spikes_trap.tscn / acid_trap.tscn / flame_vent_trap.tscn
	# 验证：planner 类源不含 preload("res://scenes/traps/...") 字面量
	var script := load("res://scenes/expedition/dungeon_hazard_planner.gd") as GDScript
	var src: String = script.source_code
	assert_bool(not src.contains("preload(\"res://scenes/traps/")) \
		.override_failure_message("planner 不应 preload 陷阱 prefab").is_true()
	assert_bool(not src.contains("instantiate()")) \
		.override_failure_message("planner 不应 instantiate 场景").is_true()
	assert_bool(not src.contains("add_child(")) \
		.override_failure_message("planner 不应 add_child").is_true()

func test_validate_plan_reports_anchor_overlapping_forbidden() -> void:
	var planner := DungeonHazardPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	# 手工塞一个落在出生格的非法锚点
	layout.hazard_anchors.append({
		"hazard_type": "spikes", "anchor_cell": Vector2i(1, 1),
		"direction": Vector2i(1, 0), "room_index": 0,
		"safe_approach_cells": [], "kick_lane_index": 0,
	})
	layout.kick_lanes.append({"start": Vector2i(2,1), "end": Vector2i(4,1), "length_cells": 3, "hazard_index": 0})
	var r := planner.validate_plan(layout)
	assert_bool(r["valid"]).is_false()

func test_plan_real_isaac_layout_produces_hazard_anchors() -> void:
	# 回归：仿真发现 planner 的 is_floor_at(0,0) 守卫对真实地牢永远 false，
	# 导致 hazard_anchors 恒为 0（spikes/acid/flame_vent 陷阱永不生成）。
	# 这里断言多个真实种子至少产出一个 hazard 锚点。
	var seeds := [20260717, 1234, 99173, 555, 7777, 24680, 13579, 80808]
	var total_anchors := 0
	for s in seeds:
		var cfg := DungeonGenerationConfig.new()
		cfg.seed = s
		cfg.algorithm = "isaac"
		var gen := DungeonGenerator.new()
		var layout := gen.generate(cfg)
		var planner := DungeonHazardPlanner.new()
		planner.plan(layout)
		total_anchors += layout.hazard_anchors.size()
		var r := planner.validate_plan(layout)
		assert_bool(r["valid"]).override_failure_message("seed %d validate_plan: %s" % [s, str(r["errors"])]).is_true()
		assert_bool(layout.hazard_anchors.size() > 0) \
			.override_failure_message("seed %d 未规划任何 hazard 锚点（陷阱永不生成）" % s).is_true()
	assert_int(total_anchors).is_greater(0) \
		.override_failure_message("所有种子 hazard_anchors 均为 0，陷阱生成已失效")


func test_integration_isaac_layout_planner_runs() -> void:
	# isaac 真产出：planner 应能跑完不报错、每个锚点有 kick_lane、不落在出生格紧邻
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	var planner := DungeonHazardPlanner.new()
	planner.plan(layout)
	var r := planner.validate_plan(layout)
	assert_bool(r["valid"]).override_failure_message(str(r["errors"])).is_true()
	# 抽查：无锚点落在出生格或其紧邻
	for anchor in layout.hazard_anchors:
		var cell: Vector2i = anchor["anchor_cell"]
		var dist: int = absi(cell.x - layout.player_spawn_cell.x) + absi(cell.y - layout.player_spawn_cell.y)
		assert_bool(dist >= 2).override_failure_message("锚点 %s 距出生格 %s 仅 %d" % [str(cell), str(layout.player_spawn_cell), dist]).is_true()


# ── 游戏性优化测试：最靠近出生点的房间设为无陷阱喘息房 ──────────
func test_plan_reserves_nearest_rooms_as_breather() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.zone = 0
	cfg.seed = 7777
	var layout := DungeonGenerator.new().generate(cfg)
	var planner := DungeonHazardPlanner.new()
	planner.plan(layout)
	# 选出的喘息房 index 应无 hazard 锚点（节奏对比：入口附近有安全房）
	var breather: Dictionary = planner._select_breather_rooms(layout)
	assert_int(breather.size()).override_failure_message("未选出任何喘息房").is_greater(0)
	for anchor in layout.hazard_anchors:
		var ri: int = int(anchor["room_index"])
		assert_bool(not breather.has(ri)) \
			.override_failure_message("喘息房 %d 仍出现 hazard 锚点" % ri).is_true()
	# 其他房仍应有陷阱（breather 未掏空整张图）
	assert_bool(layout.hazard_anchors.size() > 0).is_true()

func test_plan_breather_disabled_when_few_rooms() -> void:
	# 房间数 < MIN_ROOMS_FOR_BREATHER ⇒ 不设喘息房，否则会把仅有的 2 个普通房全跳过 → 0 陷阱
	var planner := DungeonHazardPlanner.new()
	var layout := _make_3room_no_boss_layout()
	planner.plan(layout)
	assert_int(layout.hazard_anchors.size()).override_failure_message("小地牢（3 房）被喘息房逻辑掏空陷阱").is_greater(0)


# ── helpers ──────────────────────────────────────────────────
func _make_5x5_one_room_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 5
	layout.height = 5
	layout.grid = [
		[2,2,2,2,2],
		[2,1,1,1,2],
		[2,1,1,1,2],
		[2,1,1,1,2],
		[2,2,2,2,2],
	]
	layout.heights = [
		[3.0,3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0,3.0],
		[3.0,3.0,3.0,3.0,3.0],
	]
	layout.tile_size = 3.0
	return layout

func _make_8x8_two_room_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 8
	layout.height = 8
	# 两个 3x3 房间（(0,0)-(2,2) 和 (5,5)-(7,7)），中间 4 格走廊连接
	var g := []
	for y in range(8):
		var row := []
		for x in range(8):
			row.append(2)
		g.append(row)
	# 房间 A
	for y in range(0, 3):
		for x in range(0, 3):
			g[y][x] = 1
	# 房间 B
	for y in range(5, 8):
		for x in range(5, 8):
			g[y][x] = 1
	# 走廊（x=3, y=1 和 x=4, y=1）连 A→B —— 但要连通，走对角线
	g[1][3] = 1
	g[1][4] = 1
	g[2][4] = 1
	g[3][4] = 1
	g[4][4] = 1
	g[4][5] = 1
	g[4][6] = 1
	g[5][4] = 1
	layout.grid = g
	layout.heights = []
	for y in range(8):
		var hr := []
		for x in range(8):
			hr.append(3.0)
		layout.heights.append(hr)
	layout.tile_size = 3.0
	return layout

func _make_3room_no_boss_layout() -> DungeonLayout:
	# 三间 6x6 地板块（start + 2 普通房，无 boss），用于验证“房间少时不设喘息房”。
	# 房间必须够大（>= 20 面积、inner 多格）才能产出 hazard 候选；3x3 房 inner 仅 1 格，
	# 会被出生距离/入口 padding 过滤成 0 候选 —— 那不是 breather 掏空，是几何太挤。
	var layout := DungeonLayout.new()
	layout.width = 20
	layout.height = 6
	layout.tile_size = 3.0
	var g := []
	for y in range(6):
		var row := []
		for x in range(20):
			row.append(2)  # 默认墙
		g.append(row)
	# 三块 6x6 地板（x:0-5 / 7-12 / 14-19，y:0-5）
	for block_x in [0, 7, 14]:
		for y in range(6):
			for x in range(block_x, block_x + 6):
				g[y][x] = 1
	layout.grid = g
	layout.heights = []
	for y in range(6):
		var hr := []
		for x in range(20):
			hr.append(3.0)
		layout.heights.append(hr)
	layout.rooms = [Rect2i(0, 0, 6, 6), Rect2i(7, 0, 6, 6), Rect2i(14, 0, 6, 6)]
	layout.room_roles["start"] = Rect2i(0, 0, 6, 6)
	layout.player_spawn_cell = Vector2i(1, 1)
	return layout
