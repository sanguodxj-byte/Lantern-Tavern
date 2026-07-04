extends GdUnitTestSuite
## 地牢怪物生成器测试
## 验证：DungeonSpawner autoload 注册 + 区域配置 + 怪物生成数量/种类/属性

func test_dungeon_spawner_autoload_registered() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node_or_null("DungeonSpawner")
	assert_object(spawner).is_not_null()

func test_zone_config_exists_for_all_4_zones() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	for z in range(4):
		var cfg: Dictionary = spawner.get_zone_config(z)
		assert_bool(cfg.is_empty()).is_false()
		assert_bool(cfg.has("types")).is_true()
		assert_bool(cfg.has("count_per_room")).is_true()
		assert_bool(cfg.has("hp_mult")).is_true()

func test_forest_zone_goblin_dominant() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var cfg: Dictionary = spawner.get_zone_config(0)
	assert_int(int(cfg.types.goblin)).is_equal(70)
	assert_int(int(cfg.types.kobold)).is_equal(30)

func test_volcano_zone_kobold_only() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var cfg: Dictionary = spawner.get_zone_config(3)
	assert_int(int(cfg.types.kobold)).is_equal(100)
	assert_bool(cfg.types.has("goblin")).is_false()

func test_difficulty_scales_with_zone() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	var hp_0: float = float(spawner.get_zone_config(0).hp_mult)
	var hp_3: float = float(spawner.get_zone_config(3).hp_mult)
	assert_bool(hp_3 > hp_0).is_true()

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
	assert_bool(result.size() >= 3).is_true()
	assert_bool(result.size() <= 12).is_true()
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
	# 森林区 70% goblin / 30% kobold，多次采样验证权重倾向
	var goblin_count: int = 0
	var total: int = 100
	for i in range(total):
		var t: String = spawner._pick_enemy_type({"goblin": 70, "kobold": 30})
		if t == "goblin":
			goblin_count += 1
	# goblin 应占多数（允许浮动，60-80%）
	assert_bool(goblin_count > total * 0.5).is_true()
	assert_bool(goblin_count < total * 0.95).is_true()
