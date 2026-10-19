extends GdUnitTestSuite

## 潜行警觉（stealth 战斗警报）测试：
## 1. 警觉敌人扩大视野（检测距离 9m / 视野半角 90°）
## 2. 目睹同伴被攻击的敌人立即进入战斗（is_alerted + 锁定攻击者为目标）
## 3. 墙后 / 超距的敌人不响应警报
## 4. 受伤广播走 enemies group，只有距离 + 视野 + 视线三重校验通过的同伴响应

# ==================== 警觉视野扩大 ====================

func test_alerted_enemy_expands_detection_range() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("const ALERTED_DETECTION_RANGE := 9.0")) \
		.override_failure_message("警觉敌人检测距离应扩为 9m").is_true()
	assert_bool(source.contains("func get_effective_detection_range")) \
		.override_failure_message("应提供 get_effective_detection_range 访问器").is_true()
	assert_bool(source.contains("func get_effective_vision_half_angle")) \
		.override_failure_message("应提供 get_effective_vision_half_angle 访问器").is_true()
	var enemy := _new_enemy()
	assert_float(enemy.get_effective_detection_range()) \
		.override_failure_message("未警觉时检测距离应保持默认 5m").is_equal_approx(5.0, 0.001)
	assert_float(enemy.get_effective_vision_half_angle()) \
		.override_failure_message("未警觉时视野半角应保持默认 60°").is_equal_approx(60.0, 0.001)
	enemy.is_alerted = true
	assert_float(enemy.get_effective_detection_range()) \
		.override_failure_message("警觉后检测距离应扩为 9m").is_equal_approx(9.0, 0.001)
	assert_float(enemy.get_effective_vision_half_angle()) \
		.override_failure_message("警觉后视野半角应扩为 90°").is_equal_approx(90.0, 0.001)
	enemy.free()

# ==================== 目睹同伴被攻击 → 进入战斗 ====================

func test_alert_to_combat_engages_visible_witness() -> void:
	var enemy_b := _new_enemy()
	var victim_a := _new_enemy()
	var player := _new_player()
	add_child(enemy_b)
	add_child(victim_a)
	add_child(player)
	enemy_b.global_position = Vector3.ZERO
	victim_a.global_position = Vector3(3.0, 0.0, 0.0)
	player.global_position = Vector3(2.0, 0.0, 0.0)
	# 等待物理世界初始化，使视线检测可用
	await get_tree().create_timer(0.05).timeout
	enemy_b.alert_to_combat(player, victim_a)
	assert_bool(enemy_b.is_alerted) \
		.override_failure_message("能目睹同伴被攻击的敌人应立即进入战斗警觉").is_true()
	assert_bool(enemy_b.player == player) \
		.override_failure_message("警觉后应锁定攻击者为目标").is_true()
	enemy_b._los_cache_timer = 0.0
	assert_bool(enemy_b.should_chase_player()) \
		.override_failure_message("警觉敌人下一 MOVING tick 应开始追击玩家").is_true()
	player.queue_free()
	victim_a.queue_free()
	enemy_b.queue_free()

func test_alert_to_combat_ignored_behind_wall() -> void:
	var enemy_b := _new_enemy()
	var victim_a := _new_enemy()
	var player := _new_player()
	add_child(enemy_b)
	add_child(victim_a)
	add_child(player)
	enemy_b.global_position = Vector3.ZERO
	victim_a.global_position = Vector3(3.0, 0.0, 0.0)
	player.global_position = Vector3(2.0, 0.0, 0.0)
	var wall := _new_wall(Vector3(1.5, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	enemy_b.alert_to_combat(player, victim_a)
	assert_bool(enemy_b.is_alerted) \
		.override_failure_message("墙后目睹的攻击不应触发警觉").is_false()
	assert_object(enemy_b.player) \
		.override_failure_message("视线被遮挡时不应锁定玩家目标").is_null()
	wall.queue_free()
	player.queue_free()
	victim_a.queue_free()
	enemy_b.queue_free()

func test_alert_to_combat_ignored_beyond_distance() -> void:
	var enemy_b := _new_enemy()
	var victim_a := _new_enemy()
	var player := _new_player()
	add_child(enemy_b)
	add_child(victim_a)
	add_child(player)
	enemy_b.global_position = Vector3.ZERO
	victim_a.global_position = Vector3(12.0, 0.0, 0.0)
	player.global_position = Vector3(2.0, 0.0, 0.0)
	await get_tree().create_timer(0.05).timeout
	enemy_b.alert_to_combat(player, victim_a)
	assert_bool(enemy_b.is_alerted) \
		.override_failure_message("超出 ALERT_RESPONSE_DISTANCE 的同伴被攻击不应触发警觉").is_false()
	assert_object(enemy_b.player).is_null()
	player.queue_free()
	victim_a.queue_free()
	enemy_b.queue_free()

# ==================== 受伤广播 → 组内同伴响应 ====================

func test_damaged_enemy_broadcasts_alert_to_witnesses() -> void:
	var enemy_b := _new_enemy()
	var victim_a := _new_enemy()
	var enemy_c := _new_enemy()
	var player := _new_player()
	add_child(enemy_b)
	add_child(victim_a)
	add_child(enemy_c)
	add_child(player)
	enemy_b.global_position = Vector3.ZERO
	victim_a.global_position = Vector3(3.0, 0.0, 0.0)
	enemy_c.global_position = Vector3(30.0, 0.0, 0.0)
	player.global_position = Vector3(2.0, 0.0, 0.0)
	# 等待物理世界初始化，使 B 对 A 的视线检测可用
	await get_tree().create_timer(0.05).timeout
	victim_a.try_receive_hit(player, 1)
	assert_bool(enemy_b.is_alerted) \
		.override_failure_message("能目睹同伴被攻击的敌人应立即进入战斗").is_true()
	assert_bool(enemy_b.player == player) \
		.override_failure_message("响应警报的敌人应锁定攻击者为目标").is_true()
	assert_bool(enemy_c.is_alerted) \
		.override_failure_message("超远距离的敌人不应响应战斗警报").is_false()
	player.queue_free()
	enemy_c.queue_free()
	victim_a.queue_free()
	enemy_b.queue_free()

func test_alert_broadcast_source_uses_enemies_group() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("get_nodes_in_group(\"enemies\")")) \
		.override_failure_message("战斗警报应通过 enemies group 广播给其他敌人").is_true()
	assert_bool(source.contains("func alert_to_combat")) \
		.override_failure_message("应提供 alert_to_combat 作为警报响应入口").is_true()

# ==================== 辅助方法 ====================

func _new_enemy() -> Enemy:
	var scene := load("res://scenes/characters/enemies/slime.tscn") as PackedScene
	var enemy := scene.instantiate() as Enemy
	# 与 enemy_detection_test 一致：rotation.y = -PI*0.5 使 +X 为敌人正前方。
	enemy.rotation.y = -PI * 0.5
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _new_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := scene.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player

## 创建一面墙壁 StaticBody3D（环境层），用于阻挡视野
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
