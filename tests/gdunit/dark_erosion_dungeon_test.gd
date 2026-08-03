extends GdUnitTestSuite

# 暗蚀/压力视野逻辑已迁入 DungeonRuntime

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime.gd")
	load("res://scenes/expedition/dungeon_rendering_config.gd")

func test_runtime_applies_dark_erosion_to_player_light() -> void:
	var previous_player = GameState.current_player
	var runtime := DungeonRuntime.new()
	add_child(runtime)
	var player := Player.new()
	var light := OmniLight3D.new()
	light.name = Player.PLAYER_VISION_LIGHT_NAME
	player.add_child(light)
	GameState.current_player = player

	runtime.apply_player_vision_pressure(1.0)
	assert_bool(light.visible).is_true()
	assert_float(light.light_energy).is_equal_approx(2.2, 0.01)
	assert_float(light.omni_range).is_equal_approx(10.5, 0.01)

	runtime.apply_player_vision_pressure(0.5)
	assert_bool(light.visible).is_true()
	assert_float(light.light_energy).is_equal_approx(1.1, 0.01)
	assert_float(light.omni_range).is_equal_approx(5.25, 0.01)

	runtime.apply_player_vision_pressure(0.0)
	assert_bool(light.visible).is_false()
	assert_float(light.light_energy).is_equal_approx(0.0, 0.01)
	assert_float(light.omni_range).is_equal_approx(0.0, 0.01)

	# 先恢复 autoload 引用，再释放测试节点（避免写回 previously freed）
	if previous_player != null and is_instance_valid(previous_player):
		GameState.current_player = previous_player
	else:
		GameState.current_player = null
	player.free()
	runtime.free()

func test_runtime_pressure_snapshot_forces_monster_hunt_path() -> void:
	var source := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(source.contains("apply_monster_hunt_pressure") or source.contains("_apply_monster_hunt_pressure")) \
		.override_failure_message("暗蚀 100% 时应强制全地牢怪物开始追踪玩家") \
		.is_true()
	assert_bool(source.contains("enemy.player = player_node") or source.contains(".player = player_node")) \
		.override_failure_message("强制追踪必须把玩家引用写入每个 Enemy，让移动状态开始寻路") \
		.is_true()
	assert_bool(source.contains("force_monster_hunt")) \
		.override_failure_message("地牢应从 ExplorationPressure snapshot 读取 100% 暗蚀狩猎标记") \
		.is_true()

func test_runtime_toggles_hunt_state_on_real_enemy() -> void:
	var previous_player = GameState.current_player
	var runtime := DungeonRuntime.new()
	add_child(runtime)
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var enemy := (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate() as Enemy
	add_child(enemy)
	GameState.current_player = player

	runtime.apply_monster_hunt_pressure(true)
	assert_bool(enemy.get_meta("dark_erosion_hunt", false)).is_true()
	assert_bool(enemy.player == player).is_true()
	runtime.apply_monster_hunt_pressure(false)
	assert_bool(enemy.get_meta("dark_erosion_hunt", false)).is_false()

	GameState.current_player = previous_player if previous_player != null and is_instance_valid(previous_player) else null
	enemy.queue_free()
	player.queue_free()
	runtime.queue_free()


func test_runtime_opens_dungeon_doors_for_monster_hunt_without_pressure_action() -> void:
	var previous_player = GameState.current_player
	var runtime := DungeonRuntime.new()
	add_child(runtime)
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var doors_root := Node3D.new()
	add_child(doors_root)
	var door := DungeonDoor.new()
	doors_root.add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new())
	var actions: Array[String] = []
	door.pressure_action.connect(func(action: String) -> void:
		actions.append(action)
	)
	var result := DungeonBuildResult.new()
	result.doors_root = doors_root
	runtime.build_result = result
	GameState.current_player = player

	runtime.apply_monster_hunt_pressure(true)

	assert_bool(door.is_open).is_true()
	assert_array(actions).is_empty()
	GameState.current_player = previous_player if previous_player != null and is_instance_valid(previous_player) else null
	result.dispose()
	door.queue_free()
	doors_root.queue_free()
	player.queue_free()
	runtime.queue_free()
