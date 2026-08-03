extends GdUnitTestSuite

## 怪物行为架构的公共行为契约。
## 这些测试锁定感知、目标记忆、局部避障和近邻分离，而不是某个状态类的实现细节。

func test_enemy_does_not_acquire_player_behind_its_facing_cone() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 3.0)
	GameState.current_player = player

	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("怪物背后的玩家不应在未转身时被索敌").is_false()
	assert_object(enemy.player) \
		.override_failure_message("未通过朝向检查时不应登记玩家目标").is_null()

	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()

func test_enemy_respects_configured_vision_cone_angle() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	var angle := deg_to_rad(75.0)
	player.global_position = Vector3(sin(angle) * 3.0, 0.0, -cos(angle) * 3.0)
	GameState.current_player = player

	assert_float(enemy.vision_half_angle_degrees).is_equal_approx(60.0, 0.001)
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("玩家在默认 120° 视野锥之外时不应被发现").is_false()

	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()

func test_enemy_uses_last_seen_position_after_losing_line_of_sight() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, -3.0)
	GameState.current_player = player
	await get_tree().create_timer(0.05).timeout

	assert_bool(enemy.should_chase_player()).is_true()
	var last_seen := enemy.get_navigation_target_position()
	assert_bool(last_seen.is_equal_approx(player.global_position)).is_true()

	var wall := _new_wall(Vector3(0.0, 0.0, -1.5), Vector3(3.0, 3.0, 0.2))
	add_child(wall)
	await get_tree().physics_frame
	player.global_position = Vector3(0.0, 0.0, -4.0)
	enemy._los_cache_timer = 0.0

	assert_bool(enemy.should_chase_player()).is_true()
	assert_bool(enemy.is_target_visible()).is_false()
	assert_bool(enemy.get_navigation_target_position().is_equal_approx(last_seen)).is_true()
	assert_bool(enemy.get_navigation_target_position().is_equal_approx(player.global_position)).is_false()

	GameState.current_player = null
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

func test_enemy_uses_last_seen_position_after_target_leaves_detection_range() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, -3.0)
	GameState.current_player = player
	await get_tree().physics_frame

	assert_bool(enemy.should_chase_player()).is_true()
	var last_seen := enemy.get_navigation_target_position()
	player.global_position = Vector3(0.0, 0.0, -6.0)
	enemy._los_cache_timer = 0.0

	assert_bool(enemy.should_chase_player()).is_true()
	assert_bool(enemy.is_target_visible()).is_false()
	assert_bool(enemy.get_navigation_target_position().is_equal_approx(last_seen)).is_true()
	assert_bool(enemy.get_navigation_target_position().is_equal_approx(player.global_position)).is_false()

	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()

func test_navigation_safe_velocity_is_consumed_by_enemy_body() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	assert_object(enemy.movement_controller).is_not_null()

	enemy.submit_navigation_velocity(Vector3(2.0, 0.0, 0.0))
	enemy.apply_navigation_safe_velocity(Vector3(0.0, 0.0, 1.25))

	assert_float(enemy.velocity.x).is_equal_approx(0.0, 0.001)
	assert_float(enemy.velocity.z).is_equal_approx(1.25, 0.001)
	enemy.queue_free()

func test_dark_erosion_hunt_applies_emergency_speed_multiplier() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.set_meta("dark_erosion_hunt", true)
	enemy.set_meta("environment_activity_mult", 1.0)

	assert_float(enemy.get_combat_speed_multiplier()) \
		.override_failure_message("满暗蚀追击必须提高敌人长距离追击速度").is_equal_approx(4.0, 0.001)
	enemy.queue_free()

func test_chase_speed_updates_navigation_avoidance_limit() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	var chase_speed := enemy.speed * 4.0
	enemy.set_navigation_max_speed(chase_speed)

	assert_float(enemy.nav_agent.max_speed).is_equal_approx(chase_speed, 0.001)
	enemy.queue_free()

func test_dark_erosion_relaxes_only_enemy_physics_collisions() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	var normal_mask := enemy.collision_mask
	enemy.set_dark_erosion_hunt(true)

	assert_int(enemy.collision_mask & PhysicsSetup.LAYER_ENEMY).is_equal(0)
	assert_int(enemy.collision_mask & PhysicsSetup.LAYER_ENVIRONMENT).is_equal(PhysicsSetup.LAYER_ENVIRONMENT)
	assert_int(enemy.collision_mask & PhysicsSetup.LAYER_PLAYER).is_equal(PhysicsSetup.LAYER_PLAYER)

	enemy.set_dark_erosion_hunt(false)
	assert_int(enemy.collision_mask).is_equal(normal_mask)
	enemy.queue_free()

func test_dark_erosion_disables_agent_avoidance_at_runtime() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	assert_bool(enemy.nav_agent.avoidance_enabled) \
		.override_failure_message("导航地图首轮同步前不应启动 NavigationAgent 避让").is_false()
	enemy.set_dark_erosion_hunt(true)
	assert_bool(enemy.nav_agent.avoidance_enabled) \
		.override_failure_message("满暗蚀时 NavigationAgent 避让必须关闭").is_false()
	enemy.set_dark_erosion_hunt(false)
	assert_bool(enemy.nav_agent.avoidance_enabled) \
		.override_failure_message("显式退出满暗蚀后普通敌人应恢复 NavigationAgent 避让").is_true()
	enemy.queue_free()

func test_navigation_avoidance_waits_for_map_sync() -> void:
	var controller_script: GDScript = load("res://scenes/characters/enemies/behavior/enemy_movement_controller.gd") as GDScript
	var enemy_script: GDScript = load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := controller_script.source_code
	assert_bool(source.contains("map_get_iteration_id")) \
		.override_failure_message("NavigationAgent 避让必须等待导航图首轮同步").is_true()
	assert_bool(source.contains("agent.avoidance_enabled = false")) \
		.override_failure_message("NavigationAgent 初始配置必须关闭避让").is_true()
	assert_bool(enemy_script.source_code.contains("refresh_navigation_avoidance")) \
		.override_failure_message("Enemy 必须在移动状态刷新导航避让就绪状态").is_true()

func test_dark_erosion_reverse_avoidance_velocity_keeps_chase_direction() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.set_meta("dark_erosion_hunt", true)
	enemy.submit_navigation_velocity(Vector3(1.0, 0.0, 0.0))
	enemy.apply_navigation_safe_velocity(Vector3(-2.0, 0.0, 0.0))

	assert_float(enemy.velocity.x) \
		.override_failure_message("满暗蚀追击不能接受将敌人推离导航目标的反向避让速度").is_greater(0.0)
	enemy.queue_free()

func test_dark_erosion_zero_avoidance_velocity_keeps_chase_progress() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.set_meta("dark_erosion_hunt", true)
	enemy.submit_navigation_velocity(Vector3(1.0, 0.0, 0.0))
	enemy.apply_navigation_safe_velocity(Vector3.ZERO)

	assert_float(enemy.velocity.x) \
		.override_failure_message("满暗蚀追击不能因零避让速度永久停在原地").is_greater(0.0)
	enemy.queue_free()

func test_dark_erosion_disables_agent_avoidance_and_local_separation() -> void:
	var controller_script: GDScript = load("res://scenes/characters/enemies/behavior/enemy_movement_controller.gd") as GDScript
	var source := controller_script.source_code
	assert_bool(source.contains("agent.avoidance_enabled = not active")) \
		.override_failure_message("满暗蚀全图追击必须关闭 NavigationAgent 避让，避免大群代理互相阻塞").is_true()
	assert_bool(source.contains("if bool(owner.get_meta(\"dark_erosion_hunt\", false))")) \
		.override_failure_message("满暗蚀时不能继续计算敌人之间的局部分离速度").is_true()
	assert_bool(source.contains("not agent.avoidance_enabled")) \
		.override_failure_message("关闭 RVO 后必须忽略迟到的 velocity_computed 回调").is_true()

func test_rvo_enabled_path_does_not_repeat_group_wide_local_separation_scan() -> void:
	var controller_script: GDScript = load("res://scenes/characters/enemies/behavior/enemy_movement_controller.gd") as GDScript
	var source := controller_script.source_code
	assert_bool(source.contains("agent == null or not agent.avoidance_enabled")) \
		.override_failure_message("RVO 已启用时不得再对 enemies group 做 O(N²) 的本地分离扫描").is_true()


func test_non_finite_avoidance_velocity_cannot_pollute_enemy_body() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.submit_navigation_velocity(Vector3(1.0, 0.0, 0.0))
	enemy.apply_navigation_safe_velocity(Vector3(NAN, 0.0, 0.0))

	assert_bool(is_finite(enemy.velocity.x)) \
		.override_failure_message("导航避让回调的非有限速度不能污染 CharacterBody3D.velocity").is_true()
	assert_float(enemy.velocity.x).is_equal_approx(1.0, 0.001)
	enemy.queue_free()

func test_stale_avoidance_callback_cannot_restart_stopped_enemy() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.submit_navigation_velocity(Vector3(1.0, 0.0, 0.0))
	enemy.stop_navigation()
	enemy.apply_navigation_safe_velocity(Vector3(0.0, 0.0, 2.0))

	assert_float(Vector2(enemy.velocity.x, enemy.velocity.z).length()) \
		.override_failure_message("stop_navigation 后迟到的避障回调不得重新推动怪物").is_less(0.001)
	enemy.queue_free()

func test_leaving_moving_state_revokes_navigation_request() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	enemy.submit_navigation_velocity(Vector3(1.0, 0.0, 0.0))
	enemy.switch_state(Enemy.State.STUNNED)

	assert_bool(enemy.movement_controller.movement_requested) \
		.override_failure_message("进入战斗状态时必须撤销移动控制器的导航请求").is_false()
	enemy.queue_free()

func test_nearby_enemy_receives_separation_steering() -> void:
	var enemy := _new_enemy()
	var neighbor := _new_enemy()
	add_child(enemy)
	add_child(neighbor)
	enemy.global_position = Vector3.ZERO
	neighbor.global_position = Vector3(0.3, 0.0, 0.0)

	var separation := enemy.get_local_separation_velocity()
	assert_float(separation.x) \
		.override_failure_message("重叠风险来自右侧时，怪物应获得向左的分离速度").is_less(0.0)
	enemy.queue_free()
	neighbor.queue_free()

func test_enemy_separates_before_capsules_overlap() -> void:
	var enemy := _new_enemy()
	var neighbor := _new_enemy()
	add_child(enemy)
	add_child(neighbor)
	enemy.global_position = Vector3.ZERO
	neighbor.global_position = Vector3(0.48, 0.0, 0.0)

	var physical_contact_distance := enemy.nav_agent.radius + neighbor.nav_agent.radius
	assert_float(enemy.global_position.distance_to(neighbor.global_position)) \
		.override_failure_message("测试前提：两个胶囊尚未接触").is_greater(physical_contact_distance)
	assert_float(enemy.get_local_separation_velocity().x) \
		.override_failure_message("局部分离应在物理重叠前介入").is_less(0.0)
	enemy.queue_free()
	neighbor.queue_free()

func test_spawner_player_reference_is_candidate_not_engaged_target() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	enemy.set_meta("player_ref", player)
	add_child(player)
	add_child(enemy)
	assert_object(enemy.player) \
		.override_failure_message("生成器候选引用不能让全地图敌人出生即进入已交战 AI").is_null()
	assert_float(enemy.nav_agent.max_speed).is_equal_approx(enemy.speed, 0.001)
	player.queue_free()
	enemy.queue_free()

func test_spawner_speed_multiplier_updates_avoidance_speed_limit() -> void:
	var enemy := _new_enemy()
	var base_speed := enemy.speed
	enemy.set_meta("speed_mult", 1.5)
	add_child(enemy)

	assert_float(enemy.speed).is_equal_approx(base_speed * 1.5, 0.001)
	assert_float(enemy.nav_agent.max_speed).is_equal_approx(enemy.speed, 0.001)
	enemy.queue_free()

func test_patrol_origin_survives_moving_state_reentry() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	var origin := Vector3(2.0, 0.0, 3.0)
	enemy.spawn_position = origin
	enemy.global_position = Vector3(8.0, 0.0, 8.0)
	enemy.switch_state(Enemy.State.MOVING)
	assert_bool(enemy.spawn_position.is_equal_approx(origin)).is_true()
	enemy.queue_free()

func test_dungeon_spawn_meta_initializes_patrol_origin_before_ready() -> void:
	var enemy := _new_enemy()
	var spawn := Vector3(8.0, 0.5, 6.0)
	enemy.set_meta("spawn_pos", spawn)
	add_child(enemy)
	assert_bool(enemy.spawn_position.is_equal_approx(spawn)) \
		.override_failure_message("地牢生成的巡逻中心必须使用真实出生点，不能落回世界原点").is_true()
	assert_bool(enemy.global_position.is_equal_approx(spawn)) \
		.override_failure_message("地牢敌人 ready 时应先落在描述符指定的出生点").is_true()
	enemy.queue_free()

func test_dungeon_spawn_meta_can_assign_room_patrol_center_and_radius() -> void:
	var enemy := _new_enemy()
	var spawn := Vector3(8.0, 0.5, 6.0)
	var patrol_center := Vector3(12.0, 1.5, 6.0)
	enemy.set_meta("spawn_pos", spawn)
	enemy.set_meta("patrol_center", patrol_center)
	enemy.set_meta("patrol_radius", 4.5)
	add_child(enemy)
	assert_bool(enemy.spawn_position.is_equal_approx(patrol_center)).is_true()
	assert_float(enemy.patrol_radius).is_equal_approx(4.5, 0.001)
	enemy.queue_free()

func _new_enemy() -> Enemy:
	var scene := load("res://scenes/characters/enemies/slime.tscn") as PackedScene
	var enemy := scene.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _new_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := scene.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player

func _new_wall(pos: Vector3, box_size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
	return body
