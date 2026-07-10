extends GdUnitTestSuite

# 阶段 6 测试：DungeonSpawnPlanner 只规划 spec、不实例化。
# 覆盖：起始房无普通敌、Boss 房二选一、敌人不在墙内/不在陷阱、Boss 只在 Boss 房、
#       boss_chest 只在 Boss 房、validate、集成 isaac。

func before() -> void:
	load("res://scenes/expedition/dungeon_spawn_planner.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_hazard_planner.gd")

func test_plan_empty_layout_does_nothing() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := DungeonLayout.new()
	planner.plan_enemy_spawns(layout)
	planner.plan_item_spawns(layout)
	planner.plan_chest_spawns(layout)
	assert_int(layout.enemy_spawn_specs.size()).is_equal(0)
	assert_int(layout.item_spawn_specs.size()).is_equal(0)
	assert_int(layout.chest_spawn_specs.size()).is_equal(0)

func test_plan_enemy_skips_start_room() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan_enemy_spawns(layout)
	# 起始房间内不应有 enemy spec
	for spec in layout.enemy_spawn_specs:
		var cell: Vector2i = spec["cell"]
		assert_bool(not layout.is_start_room_cell(cell)) \
			.override_failure_message("enemy %s 落在起始房" % str(cell)).is_true()

func test_plan_enemy_boss_room_picks_boss_type() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	planner.plan_enemy_spawns(layout)
	# Boss 房间应有 1 个 BOSS_TYPES 内的 elite 敌人
	var boss_specs := []
	for spec in layout.enemy_spawn_specs:
		if String(spec["enemy_type"]) in ["necrolord", "dragon"]:
			boss_specs.append(spec)
	assert_int(boss_specs.size()).is_equal(1)
	assert_bool(bool(boss_specs[0]["is_elite"])).is_true()

func test_plan_enemy_not_on_hazard_anchor() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	# 先规划 hazard，再规划 enemy，验证 enemy 避开 hazard 锚点格
	var hazard_planner := DungeonHazardPlanner.new()
	hazard_planner.plan(layout)
	planner.plan_enemy_spawns(layout)
	var hazard_cells := {}
	for anchor in layout.hazard_anchors:
		hazard_cells[anchor["anchor_cell"]] = true
	for spec in layout.enemy_spawn_specs:
		assert_bool(not hazard_cells.has(spec["cell"])) \
			.override_failure_message("enemy %s 落在 hazard 锚点" % str(spec["cell"])).is_true()

func test_plan_chest_boss_chest_only_in_boss_room() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	layout.reward_cell = Vector2i(6, 6)
	planner.plan_chest_spawns(layout)
	for spec in layout.chest_spawn_specs:
		if String(spec["chest_type"]) == "boss_chest":
			assert_bool(layout.is_boss_room_cell(spec["cell"])).is_true()

func test_plan_does_not_load_prefab_scenes() -> void:
	var script := load("res://scenes/expedition/dungeon_spawn_planner.gd") as GDScript
	var src: String = script.source_code
	assert_bool(not src.contains("preload(\"res://scenes/characters/enemies/")) \
		.override_failure_message("planner 不应 preload 敌人 prefab").is_true()
	assert_bool(not src.contains("preload(\"res://scenes/props/chest/")) \
		.override_failure_message("planner 不应 preload 宝箱 prefab").is_true()
	assert_bool(not src.contains("preload(\"res://scenes/equipment/")) \
		.override_failure_message("planner 不应 preload 装备 prefab").is_true()
	assert_bool(not src.contains("instantiate()")) \
		.override_failure_message("planner 不应 instantiate 场景").is_true()
	assert_bool(not src.contains("add_child(")) \
		.override_failure_message("planner 不应 add_child").is_true()

func test_spec_uses_stable_string_ids_not_packed_scene() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.room_roles["start"] = Rect2i(0, 0, 3, 3)
	layout.room_roles["boss"] = Rect2i(5, 5, 3, 3)
	layout.rooms.append(Rect2i(0, 0, 3, 3))
	layout.rooms.append(Rect2i(5, 5, 3, 3))
	layout.player_spawn_cell = Vector2i(1, 1)
	layout.boss_cell = Vector2i(6, 6)
	layout.reward_cell = Vector2i(6, 6)
	planner.plan_enemy_spawns(layout)
	planner.plan_item_spawns(layout)
	planner.plan_chest_spawns(layout)
	for spec in layout.enemy_spawn_specs:
		assert_bool(spec["enemy_type"] is String).is_true()
		assert_bool(spec["enemy_type"] is Node).is_false()
		assert_bool(spec["enemy_type"] is Resource).is_false()
	for spec in layout.item_spawn_specs:
		assert_bool(spec["item_id"] is String).is_true()
	for spec in layout.chest_spawn_specs:
		assert_bool(spec["chest_type"] is String).is_true()

func test_validate_plan_reports_enemy_in_wall() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	# 手工塞一个墙内敌人 spec
	layout.enemy_spawn_specs.append({
		"enemy_type": "rat", "cell": Vector2i(4, 0),  # (4,0) 是墙
		"room_index": -1, "is_elite": false, "zone": 0,
	})
	var r := planner.validate_plan(layout)
	assert_bool(r["valid"]).is_false()

func test_integration_isaac_layout_all_planners_run() -> void:
	# isaac 真产出：hazard + spawn 三个 planner 都能跑完，validate 全绿
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var gen := DungeonGenerator.new()
	var layout := gen.generate(cfg)
	DungeonHazardPlanner.new().plan(layout)
	var spawn_planner := DungeonSpawnPlanner.new()
	spawn_planner.plan_enemy_spawns(layout)
	spawn_planner.plan_item_spawns(layout)
	spawn_planner.plan_chest_spawns(layout)
	var r := spawn_planner.validate_plan(layout)
	assert_bool(r["valid"]).override_failure_message(str(r["errors"])).is_true()
	# 抽查：敌人 spec 至少有 1 个（普通房或 boss 房）
	assert_bool(layout.enemy_spawn_specs.size() >= 1).is_true()


# ── helpers（与 dungeon_hazard_planner_test 同款，避免跨文件 import）──────────
func _make_8x8_two_room_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 8
	layout.height = 8
	var g := []
	for y in range(8):
		var row := []
		for x in range(8):
			row.append(2)
		g.append(row)
	for y in range(0, 3):
		for x in range(0, 3):
			g[y][x] = 1
	for y in range(5, 8):
		for x in range(5, 8):
			g[y][x] = 1
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
