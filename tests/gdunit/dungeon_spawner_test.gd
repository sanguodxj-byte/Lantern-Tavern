extends GdUnitTestSuite
## 地牢怪物生成器测试
## 验证：DungeonSpawner autoload 注册 + 区域配置 + 怪物生成数量/种类/属性
## 新增：房间分类生成（BOSS 房只生成 BOSS 类，普通房只生成普通类，起始房不生成）

const MODEL_TIERS := preload("res://data/character_model_tiers.gd")
const ROSTER_PATH := "res://data/enemy_roster.json"

var _original_use_mock_nodes: bool = false

func before() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		_original_use_mock_nodes = spawner.get("use_mock_nodes") if "use_mock_nodes" in spawner else false
		spawner.set("use_mock_nodes", true)

func after() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", _original_use_mock_nodes)


func test_dungeon_spawner_autoload_registered() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	assert_object(spawner).is_not_null()


func test_enemy_display_name_localizes_via_translation_key() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	assert_str(spawner.get_display_name("goblin")).is_equal("哥布林")
	assert_str(spawner.get_display_name("elite_goblin")).is_equal("哥布林")
	TranslationServer.set_locale("en")
	var en_name: String = spawner.get_display_name("goblin")
	assert_bool(en_name == "Goblin" or en_name == "哥布林").is_true()
	TranslationServer.set_locale(prev)

func test_zone_config_exists_for_all_6_zones() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	for z in range(6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		assert_bool(cfg.is_empty()).is_false()
		assert_bool(cfg.has("types")).is_true()
		assert_bool(cfg.has("count_per_room")).is_true()
		assert_bool(cfg.has("hp_mult")).is_true()

func test_zone_zero_only_contains_accepted_normal_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var cfg: Dictionary = spawner.get_zone_config(0)
	var expected_normal: Array = _accepted_roster_types()["normal"]
	var actual_normal: Array = cfg.types.keys()
	actual_normal.sort()
	assert_array(actual_normal).is_equal(expected_normal)
	assert_int(cfg.types.size()).is_equal(expected_normal.size())

func test_higher_zones_have_no_normal_types_and_only_accepted_bosses() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var cfg: Dictionary = spawner.get_zone_config(4)
	assert_bool(cfg.types.is_empty()).is_true()
	var expected_bosses: Array = _accepted_roster_types()["boss"]
	var actual_bosses: Array = cfg.boss.keys()
	actual_bosses.sort()
	assert_array(actual_bosses).is_equal(expected_bosses)
	assert_int(cfg.boss.size()).is_equal(expected_bosses.size())

func test_difficulty_scales_with_zone() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var hp_0: float = float(spawner.get_zone_config(0).hp_mult)
	var hp_5: float = float(spawner.get_zone_config(5).hp_mult)
	assert_bool(hp_5 > hp_0).is_true()

func test_spawn_enemies_returns_array() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	# 构造 mock grid: 10x10 全 FLOOR(1)
	var grid: Array = []
	for y in range(10):
		var row: Array = []
		for x in range(10):
			row.append(1)
		grid.append(row)
	# mock parent 节点
	var parent: Node3D = Node3D.new()
	add_child(parent)
	# mock player（Node3D 占位，dungeon_spawner 用 set_meta 注入避免类型错误）
	var player: Node3D = Node3D.new()
	add_child(player)
	var spawn_pos: Vector3 = Vector3(100, 0.5, 100)  # 远离 grid，确保所有格子可用
	var result: Array = spawner.spawn_enemies(parent, grid, 0, player, spawn_pos, 3.0)
	assert_bool(result is Array).is_true()
	assert_bool(result.size() >= 4).is_true()
	assert_bool(result.size() <= 16).is_true()
	# 清理生成的敌人
	for e in result:
		if is_instance_valid(e):
			e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_spawn_enemies_avoids_spawn_position() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var grid: Array = []
	for y in range(8):
		var row: Array = []
		for x in range(8):
			row.append(1)
		grid.append(row)
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	# 玩家出生点设在 grid 中心（偏移后约 0,0.5,0）
	var spawn_pos: Vector3 = Vector3(0, 0.5, 0)
	var result: Array = spawner.spawn_enemies(parent, grid, 0, player, spawn_pos, 3.0)
	# 所有生成的敌人应距 spawn_pos >= 6 米
	for e in result:
		if is_instance_valid(e):
			assert_bool(e.global_position.distance_to(spawn_pos) >= 6.0).is_true()
			e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_pick_enemy_type_weighted() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var goblin_count: int = 0
	var total: int = 100
	for i in range(total):
		var t: String = spawner._pick_enemy_type({"goblin": 70, "orc_raider": 30, "rat": 1000})
		assert_bool(t == "goblin" or t == "orc_raider").is_true()
		if t == "goblin":
			goblin_count += 1
	assert_bool(goblin_count > total * 0.5).is_true()
	assert_bool(goblin_count < total * 0.9).is_true()

# ============================================================
# 房间分类生成测试（BOSS 房 / 普通房 / 起始房）
# ============================================================

## 辅助：构造一个含起始房、普通房、BOSS 房的 mock grid + rooms + room_roles
func _build_mock_room_layout() -> Dictionary:
	# 30x30 grid，全 WALL(2)，然后挖出 3 个房间
	var grid: Array = []
	for y in range(30):
		var row: Array = []
		for x in range(30):
			row.append(2)  # WALL
		grid.append(row)
	# 起始房: (2,2) 6x6
	var start_room: Rect2i = Rect2i(2, 2, 6, 6)
	# 普通房: (12,2) 6x6
	var normal_room: Rect2i = Rect2i(12, 2, 6, 6)
	# BOSS 房: (22,2) 6x6
	var boss_room: Rect2i = Rect2i(22, 2, 6, 6)
	# 挖通地板
	for rect in [start_room, normal_room, boss_room]:
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				grid[y][x] = 1  # FLOOR
	# 连接走廊
	for x in range(8, 12):
		grid[4][x] = 1
	for x in range(18, 22):
		grid[4][x] = 1
	var rooms: Array = [start_room, normal_room, boss_room]
	var room_roles: Dictionary = {
		"start": start_room,
		"boss": boss_room,
	}
	return {
		"grid": grid,
		"rooms": rooms,
		"room_roles": room_roles,
		"start_room": start_room,
		"normal_room": normal_room,
		"boss_room": boss_room,
	}

func test_is_boss_type_correctly_classifies() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	# 只有已验收且在 roster 声明为 boss 的 S 模型可成为 BOSS。
	assert_bool(spawner.is_boss_type("dragon")).is_true()
	assert_bool(spawner.is_boss_type("rock_golem")).is_true()
	assert_bool(spawner.is_boss_type("elite_dragon")).is_true()
	assert_bool(spawner.is_boss_type("elite_rock_golem")).is_true()
	assert_bool(spawner.is_boss_type("necrolord")).is_false()
	assert_bool(spawner.is_boss_type("troll")).is_false()
	assert_bool(spawner.is_boss_type("goblin")).is_false()
	assert_bool(spawner.is_boss_type("rat")).is_false()
	assert_bool(spawner.is_boss_type("skeleton")).is_false()
	assert_bool(spawner.is_boss_type("slime")).is_false()

func test_boss_types_list_correct() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var boss_types: Array = spawner.get_boss_types()
	var expected_bosses: Array = _accepted_roster_types()["boss"]
	boss_types.sort()
	assert_array(boss_types).is_equal(expected_bosses)
	assert_int(boss_types.size()).is_equal(expected_bosses.size())
	assert_bool(boss_types.has("necrolord")).is_false()

func test_normal_types_list_correct() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var normal_types: Array = spawner.get_normal_types()
	normal_types.sort()
	assert_array(normal_types).is_equal(_accepted_roster_types()["normal"])


func test_fallback_pool_uses_only_its_explicit_accepted_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	spawner._fallback_minimal_roster()
	var normal_types: Array = spawner.NORMAL_TYPES.duplicate()
	var boss_types: Array = spawner.BOSS_TYPES.duplicate()
	var fallback_types: Array = spawner.get_all_enemy_types()
	var weights: Dictionary = spawner.ZONE_ENEMY_CONFIG[0].types.duplicate()
	spawner._load_roster()
	assert_array(weights.keys()).contains_exactly(normal_types)
	var expected_fallback_types: Array = normal_types + boss_types
	fallback_types.sort()
	expected_fallback_types.sort()
	assert_array(fallback_types).is_equal(expected_fallback_types)
	assert_bool(fallback_types.has("player")).is_false()
	for enemy_id in normal_types:
		assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()
		assert_int(int(weights[enemy_id])).is_equal(50)
	for enemy_id in boss_types:
		assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()


func test_fallback_source_never_enumerates_all_accepted_models() -> void:
	var source := FileAccess.get_file_as_string("res://globals/dungeon/dungeon_spawner.gd")
	var start := source.find("func _fallback_minimal_roster()")
	var finish := source.find("\n\n##", start)
	var fallback_source := source.substr(start, finish - start)
	assert_bool(start >= 0 and finish > start).is_true()
	assert_bool(fallback_source.contains("NORMAL_TYPES + BOSS_TYPES")).is_true()
	assert_bool(fallback_source.contains("accepted_model_ids")).is_false()


func test_spawn_with_rooms_returns_enemies() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var mock: Dictionary = _build_mock_room_layout()
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	# 起始房中心作为 spawn_pos
	var start_room: Rect2i = mock["start_room"]
	var spawn_pos: Vector3 = Vector3(
		(start_room.position.x + 3) * 3.0 - 45.0,
		0.5,
		(start_room.position.y + 3) * 3.0 - 45.0
	)
	var result: Array = spawner.spawn_enemies(
		parent, mock["grid"], 0, player, spawn_pos, 3.0,
		Vector3.ZERO, mock["rooms"], mock["room_roles"]
	)
	assert_bool(result is Array).is_true()
	assert_bool(result.size() > 0).is_true()
	for e in result:
		if is_instance_valid(e):
			e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_boss_room_only_spawns_boss_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var mock: Dictionary = _build_mock_room_layout()
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	var start_room: Rect2i = mock["start_room"]
	var spawn_pos: Vector3 = Vector3(
		(start_room.position.x + 3) * 3.0 - 45.0,
		0.5,
		(start_room.position.y + 3) * 3.0 - 45.0
	)
	var result: Array = spawner.spawn_enemies(
		parent, mock["grid"], 0, player, spawn_pos, 3.0,
		Vector3.ZERO, mock["rooms"], mock["room_roles"]
	)
	# BOSS 房间生成的怪物应全部是 BOSS 类
	var boss_room: Rect2i = mock["boss_room"]
	for e in result:
		if not is_instance_valid(e):
			continue
		var pos: Vector3 = e.global_position
		# 检查是否在 BOSS 房范围内（世界坐标）
		var cell_x: float = (pos.x + 45.0) / 3.0
		var cell_y: float = (pos.z + 45.0) / 3.0
		if boss_room.has_point(Vector2i(int(cell_x), int(cell_y))):
			# 该怪物在 BOSS 房内，必须是 BOSS 类
			var enemy_type: String = e.get_meta("enemy_type", "")
			var is_boss: bool = spawner.is_boss_type(enemy_type)
			assert_bool(is_boss).override_failure_message(
				"BOSS 房间内出现了非 BOSS 类怪物: %s (pos=%s)" % [enemy_type, pos]
			).is_true()
		e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_normal_room_never_spawns_boss_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var mock: Dictionary = _build_mock_room_layout()
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	var start_room: Rect2i = mock["start_room"]
	var spawn_pos: Vector3 = Vector3(
		(start_room.position.x + 3) * 3.0 - 45.0,
		0.5,
		(start_room.position.y + 3) * 3.0 - 45.0
	)
	var result: Array = spawner.spawn_enemies(
		parent, mock["grid"], 0, player, spawn_pos, 3.0,
		Vector3.ZERO, mock["rooms"], mock["room_roles"]
	)
	# 普通房间生成的怪物不应包含 BOSS 类
	var normal_room: Rect2i = mock["normal_room"]
	for e in result:
		if not is_instance_valid(e):
			continue
		var pos: Vector3 = e.global_position
		var cell_x: float = (pos.x + 45.0) / 3.0
		var cell_y: float = (pos.z + 45.0) / 3.0
		if normal_room.has_point(Vector2i(int(cell_x), int(cell_y))):
			# 该怪物在普通房内，不能是 BOSS 类
			var enemy_type: String = e.get_meta("enemy_type", "")
			var is_boss: bool = spawner.is_boss_type(enemy_type)
			assert_bool(not is_boss).override_failure_message(
				"普通房间内出现了 BOSS 类怪物: %s (pos=%s)" % [enemy_type, pos]
			).is_true()
		e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_start_room_has_no_enemies() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var mock: Dictionary = _build_mock_room_layout()
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	var start_room: Rect2i = mock["start_room"]
	var spawn_pos: Vector3 = Vector3(
		(start_room.position.x + 3) * 3.0 - 45.0,
		0.5,
		(start_room.position.y + 3) * 3.0 - 45.0
	)
	var result: Array = spawner.spawn_enemies(
		parent, mock["grid"], 0, player, spawn_pos, 3.0,
		Vector3.ZERO, mock["rooms"], mock["room_roles"]
	)
	# 起始房间不应有怪物
	for e in result:
		if not is_instance_valid(e):
			continue
		var pos: Vector3 = e.global_position
		var cell_x: float = (pos.x + 45.0) / 3.0
		var cell_y: float = (pos.z + 45.0) / 3.0
		assert_bool(not start_room.has_point(Vector2i(int(cell_x), int(cell_y)))) \
			.override_failure_message("起始房间内出现了怪物: pos=%s" % pos).is_true()
		e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_pick_boss_type_returns_elite_prefixed() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var config: Dictionary = spawner.get_zone_config(0)
	# 多次采样验证 _pick_boss_type 返回 "elite_" 前缀
	for i in range(20):
		var t: String = spawner._pick_boss_type(config)
		assert_bool(t.begins_with("elite_")).override_failure_message(
			"_pick_boss_type 应返回 elite_ 前缀: %s" % t
		).is_true()
		var base: String = t.trim_prefix("elite_")
		assert_bool(spawner.is_boss_type(base)).is_true()

func test_zone_config_has_boss_subconfig() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	for z in range(6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		assert_bool(cfg.has("boss")).override_failure_message(
			"区域 %d 缺少 boss 子配置" % z
		).is_true()
		var boss_cfg: Dictionary = cfg["boss"]
		assert_bool(boss_cfg.size() > 0).is_true()
		# boss 配置中的 key 必须都是 BOSS 类
		for key in boss_cfg.keys():
			assert_bool(spawner.is_boss_type(key)).override_failure_message(
				"区域 %d boss 配置包含非 BOSS 类: %s" % [z, key]
			).is_true()

func test_all_zone_normal_types_are_not_boss() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	for z in range(6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		var types: Dictionary = cfg.types
		for key in types.keys():
			# 普通房间配置中的 key 不能是 BOSS 类（去 elite_ 前缀后检查）
			var base: String = key.trim_prefix("elite_")
			assert_bool(not spawner.is_boss_type(base)).override_failure_message(
				"区域 %d 普通配置包含 BOSS 类: %s" % [z, key]
			).is_true()

func test_zone_normal_types_are_accepted_and_follow_roster_weights() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	for z in range(6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		var types: Dictionary = cfg.types
		for enemy_id in types.keys():
			assert_bool(MODEL_TIERS.is_accepted(String(enemy_id))).is_true()
	if spawner.get_zone_config(0).types.size() > 0:
		var actual_normal: Array = spawner.get_zone_config(0).types.keys()
		actual_normal.sort()
		assert_array(actual_normal).is_equal(_accepted_roster_types()["normal"])
	for z in range(1, 6):
		assert_bool(spawner.get_zone_config(z).types.is_empty()).is_true()

func test_all_zones_only_use_accepted_bosses() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var expected_bosses: Array = _accepted_roster_types()["boss"]
	for z in range(6):
		var cfg: Dictionary = spawner.get_zone_config(z)
		var boss_cfg: Dictionary = cfg["boss"]
		var actual_bosses: Array = boss_cfg.keys()
		actual_bosses.sort()
		assert_array(actual_bosses).is_equal(expected_bosses)
		assert_int(boss_cfg.size()).is_equal(expected_bosses.size())

func test_boss_room_always_spawns_exactly_one() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var mock: Dictionary = _build_mock_room_layout()
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var player: Node3D = Node3D.new()
	add_child(player)
	var start_room: Rect2i = mock["start_room"]
	var spawn_pos: Vector3 = Vector3(
		(start_room.position.x + 3) * 3.0 - 45.0,
		0.5,
		(start_room.position.y + 3) * 3.0 - 45.0
	)
	var result: Array = spawner.spawn_enemies(
		parent, mock["grid"], 5, player, spawn_pos, 3.0,
		Vector3.ZERO, mock["rooms"], mock["room_roles"]
	)
	# BOSS 房间应固定只有 1 只 BOSS
	var boss_room: Rect2i = mock["boss_room"]
	var boss_count: int = 0
	for e in result:
		if not is_instance_valid(e):
			continue
		var pos: Vector3 = e.global_position
		var cell_x: float = (pos.x + 45.0) / 3.0
		var cell_y: float = (pos.z + 45.0) / 3.0
		if boss_room.has_point(Vector2i(int(cell_x), int(cell_y))):
			boss_count += 1
	assert_int(boss_count).override_failure_message(
		"BOSS 房间应固定只有 1 只 BOSS，实际: %d" % boss_count
	).is_equal(1)
	for e in result:
		if is_instance_valid(e):
			e.queue_free()
	parent.queue_free()
	player.queue_free()

func test_pick_boss_only_returns_accepted_bosses() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var config: Dictionary = spawner.get_zone_config(0)
	var expected_bosses: Array = _accepted_roster_types()["boss"]
	for i in range(50):
		var t: String = spawner._pick_boss_type(config)
		assert_bool(expected_bosses.has(t.trim_prefix("elite_"))).override_failure_message(
			"_pick_boss_type 返回了未验收 boss: %s" % t
		).is_true()


func test_empty_or_unaccepted_pools_do_not_fallback_to_goblin() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_str(spawner._pick_enemy_type({})).is_empty()
	assert_str(spawner._pick_enemy_type({"rat": 100})).is_empty()
	assert_str(spawner._pick_boss_type({"boss": {"necrolord": 100}})).is_empty()


func test_unaccepted_and_unknown_prefabs_do_not_fallback_to_goblin() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_object(spawner._get_enemy_prefab("rat")).is_null()
	assert_object(spawner._get_enemy_prefab("not_a_real_enemy")).is_null()
	assert_object(spawner._instantiate_enemy("rat", Vector3.ZERO, null, {})).is_null()
	assert_object(spawner._instantiate_enemy("not_a_real_enemy", Vector3.ZERO, null, {})).is_null()
	assert_str(spawner.get_body_size("rat")).is_empty()
	assert_str(spawner.get_display_name("rat")).is_empty()
	assert_str(spawner.get_drop_id("rat")).is_empty()
	assert_str(spawner.get_drop_id("not_a_real_enemy")).is_empty()


func test_layout_specs_with_unaccepted_ids_spawn_nothing() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var layout := DungeonLayout.new()
	layout.width = 2
	layout.height = 1
	layout.grid = [[1, 1]]
	layout.heights = [[3.0, 3.0]]
	layout.enemy_spawn_specs.append({"enemy_type": "rat", "cell": Vector2i(0, 0), "is_elite": false})
	layout.enemy_spawn_specs.append({"enemy_type": "not_a_real_enemy", "cell": Vector2i(1, 0), "is_elite": false})
	var spawn_root := Node3D.new()
	add_child(spawn_root)
	var result: Array = spawner.spawn_enemies_from_layout(layout, spawn_root, null)
	assert_array(result).is_empty()
	assert_int(spawn_root.get_child_count()).is_equal(0)
	spawn_root.queue_free()


func test_runtime_enemy_types_match_accepted_roster_subset() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	assert_array(spawner.get_all_enemy_types()).is_equal(_accepted_roster_types()["all"])


func test_future_accepted_player_never_enters_spawner_enemy_types() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	spawner._fallback_minimal_roster()
	var fallback_types: Array = spawner.get_all_enemy_types()
	spawner._load_roster()
	assert_bool(fallback_types.has("player")).is_false()
	assert_bool(spawner.get_all_enemy_types().has("player")).is_false()
	if MODEL_TIERS.is_accepted("player"):
		assert_object(spawner._instantiate_enemy("player", Vector3.ZERO, null, {})).is_null()


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
