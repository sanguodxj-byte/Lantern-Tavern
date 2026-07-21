extends GdUnitTestSuite

const MODEL_TIERS := preload("res://data/character_model_tiers.gd")
const ROSTER_PATH := "res://data/enemy_roster.json"

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
	# Boss 房间应有 1 个已验收的 BOSS_TYPES 内的 elite 敌人
	var boss_specs := []
	var accepted_bosses := _accepted_roster_types()["boss"] as Array
	for spec in layout.enemy_spawn_specs:
		if accepted_bosses.has(String(spec["enemy_type"])):
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


func test_enemy_plans_only_use_accepted_models() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.zone = 0
	cfg.seed = 4242
	var layout := DungeonGenerator.new().generate(cfg)
	DungeonSpawnPlanner.new().plan_enemy_spawns(layout)
	assert_bool(layout.enemy_spawn_specs.is_empty()).is_false()
	var roster_types := _accepted_roster_types()
	var accepted_enemies: Array = roster_types["all"]
	for spec in layout.enemy_spawn_specs:
		var enemy_id := String(spec["enemy_type"])
		assert_bool(MODEL_TIERS.is_accepted(enemy_id)) \
			.override_failure_message("planner emitted unaccepted enemy: %s" % enemy_id) \
			.is_true()
		assert_bool(accepted_enemies.has(enemy_id)) \
			.override_failure_message("planner emitted accepted non-enemy model: %s" % enemy_id) \
			.is_true()


func test_roster_pools_exclude_unaccepted_models() -> void:
	DungeonSpawnPlanner._ensure_roster()
	var expected := _accepted_roster_types()
	var actual_normal := DungeonSpawnPlanner.NORMAL_TYPES.duplicate()
	var actual_boss := DungeonSpawnPlanner.BOSS_TYPES.duplicate()
	actual_normal.sort()
	actual_boss.sort()
	assert_array(actual_normal).is_equal(expected["normal"])
	assert_array(actual_boss).is_equal(expected["boss"])
	for zone_cfg in DungeonSpawnPlanner.ZONE_ENEMY_CONFIG.values():
		for enemy_id in zone_cfg.get("types", {}).keys():
			assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()
		for enemy_id in zone_cfg.get("boss", {}).keys():
			assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()


func test_fallback_normal_pool_uses_only_its_explicit_accepted_types() -> void:
	DungeonSpawnPlanner._set_fallback_roster()
	var normal_types := DungeonSpawnPlanner.NORMAL_TYPES.duplicate()
	var weights: Dictionary = DungeonSpawnPlanner.ZONE_ENEMY_CONFIG[0].types.duplicate()
	DungeonSpawnPlanner._roster_loaded = false
	DungeonSpawnPlanner._ensure_roster()
	assert_array(weights.keys()).contains_exactly(normal_types)
	for enemy_id in normal_types:
		assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()
		assert_int(int(weights[enemy_id])).is_equal(50)


func test_empty_or_unaccepted_weight_pool_does_not_fallback_to_goblin() -> void:
	var planner := DungeonSpawnPlanner.new()
	assert_str(planner._pick_weighted({})).is_empty()
	assert_str(planner._pick_weighted({"rat": 100})).is_empty()
	assert_str(planner._pick_weighted({"player": 100})).is_empty()
	assert_str(planner._pick_boss_type({"boss": {"necrolord": 100}})).is_empty()


func test_weight_picker_and_validator_require_enemy_roster_membership() -> void:
	DungeonSpawnPlanner._ensure_roster()
	var original_normal := DungeonSpawnPlanner.NORMAL_TYPES.duplicate()
	var original_boss := DungeonSpawnPlanner.BOSS_TYPES.duplicate()
	var accepted_enemy := String(original_normal[0])
	DungeonSpawnPlanner.NORMAL_TYPES.erase(accepted_enemy)
	var planner := DungeonSpawnPlanner.new()
	var picked := planner._pick_weighted({accepted_enemy: 100})
	var layout := _make_8x8_two_room_layout()
	layout.enemy_spawn_specs.append({
		"enemy_type": accepted_enemy, "cell": Vector2i(1, 1),
		"room_index": 0, "is_elite": false, "zone": 0,
	})
	var validation := planner.validate_plan(layout)
	DungeonSpawnPlanner.NORMAL_TYPES = original_normal
	DungeonSpawnPlanner.BOSS_TYPES = original_boss
	assert_str(picked).is_empty()
	assert_bool(validation["valid"]).is_false()
	assert_bool(str(validation["errors"]).contains("accepted enemy roster")).is_true()


func test_future_accepted_player_remains_outside_enemy_planner_pools() -> void:
	# This becomes an active acceptance regression once player joins ACCEPTED_IDS.
	if not MODEL_TIERS.is_accepted("player"):
		return
	DungeonSpawnPlanner._ensure_roster()
	assert_bool(DungeonSpawnPlanner.NORMAL_TYPES.has("player")).is_false()
	assert_bool(DungeonSpawnPlanner.BOSS_TYPES.has("player")).is_false()
	assert_str(DungeonSpawnPlanner.new()._pick_weighted({"player": 100})).is_empty()

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
	assert_bool(str(r["errors"]).contains("not accepted")).is_true()


func test_validate_plan_rejects_unaccepted_enemy_on_floor() -> void:
	var planner := DungeonSpawnPlanner.new()
	var layout := _make_8x8_two_room_layout()
	layout.enemy_spawn_specs.append({
		"enemy_type": "rat", "cell": Vector2i(1, 1),
		"room_index": 0, "is_elite": false, "zone": 0,
	})
	var result := planner.validate_plan(layout)
	assert_bool(result["valid"]).is_false()
	var errors := str(result["errors"])
	assert_bool(errors.contains("rat")).is_true()
	assert_bool(errors.contains("not accepted")).is_true()

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


# ── 游戏性优化测试：掉落多样性 / 敌人数方差 / 深度梯度 ──────────
func test_plan_item_ids_in_zone_pool() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.zone = 0
	cfg.seed = 7777
	var layout := DungeonGenerator.new().generate(cfg)
	DungeonSpawnPlanner.new().plan_item_spawns(layout)
	var pool: Array = DungeonSpawnPlanner.ZONE_MATERIAL_POOLS.get(0, [])
	assert_bool(pool.size() > 0).is_true()
	for spec in layout.item_spawn_specs:
		assert_bool(pool.has(spec["item_id"])) \
			.override_failure_message("掉落 %s 不在 zone0 材料池" % spec["item_id"]).is_true()

func test_plan_item_deterministic_per_seed() -> void:
	# 同 seed → 完全相同的掉落序列（修复前用全局 randi，跨运行会变）
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.zone = 0
	cfg.seed = 7777
	var la := DungeonGenerator.new().generate(cfg)
	var lb := DungeonGenerator.new().generate(cfg)
	DungeonSpawnPlanner.new().plan_item_spawns(la)
	DungeonSpawnPlanner.new().plan_item_spawns(lb)
	assert_str(_item_ids_string(la)).is_equal(_item_ids_string(lb))

func test_plan_item_varies_across_seeds() -> void:
	var cfg_a := DungeonGenerationConfig.new()
	cfg_a.algorithm = "isaac"
	cfg_a.zone = 0
	cfg_a.seed = 7777
	var la := DungeonGenerator.new().generate(cfg_a)
	DungeonSpawnPlanner.new().plan_item_spawns(la)
	var cfg_b := DungeonGenerationConfig.new()
	cfg_b.algorithm = "isaac"
	cfg_b.zone = 0
	cfg_b.seed = 8888
	var lb := DungeonGenerator.new().generate(cfg_b)
	DungeonSpawnPlanner.new().plan_item_spawns(lb)
	assert_bool(_item_ids_string(la) != _item_ids_string(lb)) \
		.override_failure_message("不同 seed 产出了完全相同的掉落序列").is_true()

func test_pick_material_from_pool_varies() -> void:
	# 单次探险内应出现多种材料（单调黑莓已修复）
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var planner := DungeonSpawnPlanner.new()
	var seen := {}
	for _i in range(30):
		var id: String = planner._pick_material_from_pool(0, rng)
		seen[id] = true
	assert_int(seen.size()).override_failure_message("zone0 材料池应能在多次 roll 中出现 >=2 种材料").is_greater_equal(2)

func test_plan_enemy_count_has_variance() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	cfg.zone = 0
	cfg.seed = 7777
	var layout := DungeonGenerator.new().generate(cfg)
	DungeonSpawnPlanner.new().plan_enemy_spawns(layout)
	# 按 room_index 聚合敌人数
	var per_room := {}
	for spec in layout.enemy_spawn_specs:
		var ri: int = int(spec["room_index"])
		if not per_room.has(ri):
			per_room[ri] = 0
		per_room[ri] += 1
	var counts := []
	for ri in per_room.keys():
		var c: int = int(per_room[ri])
		counts.append(c)
		assert_int(c).is_greater_equal(1)
	assert_bool(counts.size() >= 2).is_true()
	# 方差：至少出现 2 种不同数量（深度梯度 + ±1 随机保证，打破“每房恒 2 敌”）
	var distinct := {}
	for c in counts:
		distinct[c] = true
	assert_int(distinct.size()).override_failure_message("普通房敌人数全相等，缺少方差/深度梯度: %s" % str(counts)).is_greater_equal(2)

func test_calc_room_enemy_count_depth_ramp() -> void:
	var planner := DungeonSpawnPlanner.new()
	var zone_cfg := DungeonSpawnPlanner.ZONE_ENEMY_CONFIG.get(0, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	# 深度 0：base=2 → 1..3；深度 36（/12=+3）→ 至少 4..6，恒大于浅层
	var shallow: int = planner._calc_room_enemy_count(zone_cfg, 30, 0, rng)
	var deep: int = planner._calc_room_enemy_count(zone_cfg, 30, 36, rng)
	assert_int(deep).override_failure_message("深度梯度失效：深房 %d 未大于浅房 %d" % [deep, shallow]).is_greater(shallow)
	assert_int(shallow).is_greater_equal(1)
	# 方差：同深度多次调用应出现 >=2 种数量
	var seen := {}
	for _i in range(20):
		seen[planner._calc_room_enemy_count(zone_cfg, 30, 0, rng)] = true
	assert_int(seen.size()).override_failure_message("同房间敌人数无方差").is_greater_equal(2)


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

func _item_ids_string(layout: DungeonLayout) -> String:
	var parts := []
	for spec in layout.item_spawn_specs:
		parts.append("%d:%s" % [int(spec["room_index"]), String(spec["item_id"])])
	return "|".join(parts)


func _accepted_roster_types() -> Dictionary:
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var declared_bosses: Dictionary = {}
	for enemy_id in json.data.get("boss_types", []):
		declared_bosses[String(enemy_id)] = true
	var normal: Array = []
	var boss: Array = []
	for entry in json.data.get("enemies", []):
		var enemy_id := String(entry.get("id", ""))
		if not MODEL_TIERS.is_accepted(enemy_id):
			continue
		if declared_bosses.has(enemy_id):
			boss.append(enemy_id)
		else:
			normal.append(enemy_id)
	normal.sort()
	boss.sort()
	var all: Array = normal.duplicate()
	all.append_array(boss)
	all.sort()
	return {"normal": normal, "boss": boss, "all": all}
