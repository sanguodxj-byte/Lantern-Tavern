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
	assert_float(light.light_energy).is_equal_approx(2.4, 0.01)
	assert_float(light.omni_range).is_equal_approx(10.0, 0.01)

	runtime.apply_player_vision_pressure(0.5)
	assert_bool(light.visible).is_true()
	assert_float(light.light_energy).is_equal_approx(1.2, 0.01)
	assert_float(light.omni_range).is_equal_approx(5.0, 0.01)

	runtime.apply_player_vision_pressure(0.0)
	assert_bool(light.visible).is_false()
	assert_float(light.light_energy).is_equal_approx(0.0, 0.01)
	assert_float(light.omni_range).is_equal_approx(0.0, 0.01)

	# 先恢复 autoload 引用，再释放测试节点（避免写回 previously freed）
	if previous_player != null and is_instance_valid(previous_player):
		GameState.current_player = previous_player
	else:
		GameState.current_player = null
	player.queue_free()
	runtime.queue_free()

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
