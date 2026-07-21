extends GdUnitTestSuite
## 敌方索敌与追击门槛测试

func test_enemy_default_detection_range_is_five_meters() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("const DEFAULT_DETECTION_RANGE := 5.0")) \
		.override_failure_message("敌人默认索敌距离应统一为 5m").is_true()
	assert_bool(source.contains("@export var detection_range: float = DEFAULT_DETECTION_RANGE")) \
		.override_failure_message("索敌距离应可导出但默认使用统一 5m").is_true()

func test_enemy_detection_area_radius_is_configured_from_detection_range() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var enemy := scene.instantiate()
	add_child(enemy)
	var shape_node := enemy.get_node("PlayerDetectionArea/CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as SphereShape3D
	assert_object(shape).is_not_null()
	assert_float(shape.radius) \
		.override_failure_message("PlayerDetectionArea 的 Sphere 半径应由 detection_range 配置为 5m").is_equal_approx(5.0, 0.001)
	enemy.queue_free()

func test_should_chase_player_only_within_detection_range() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(5.1, 0.0, 0.0)
	enemy.player = player
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("普通状态下超过 5m 不应继续追击").is_false()
	assert_object(enemy.player) \
		.override_failure_message("目标超出索敌距离后应清空已登记玩家").is_null()
	player.queue_free()
	enemy.queue_free()

func test_should_chase_player_within_five_meters() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(5.0, 0.0, 0.0)
	enemy.player = player
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("5m 内应进入追击").is_true()
	assert_bool(enemy.player == player).is_true()
	player.queue_free()
	enemy.queue_free()

func test_dark_erosion_hunt_ignores_detection_range() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(50.0, 0.0, 0.0)
	enemy.player = player
	enemy.set_meta("dark_erosion_hunt", true)
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("100% 暗蚀强制猎杀应绕过 5m 索敌距离").is_true()
	assert_bool(enemy.player == player).is_true()
	player.queue_free()
	enemy.queue_free()

func test_enemy_detection_area_disconnects_lost_player() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("body_exited.connect(on_player_lost)")) \
		.override_failure_message("玩家离开索敌 Area 时应清空目标").is_true()
	assert_bool(source.contains("func on_player_lost")) \
		.override_failure_message("敌人应实现离开索敌范围回调").is_true()

# ==================== 视野检测（禁止跨墙发现） ====================

func test_enemy_has_line_of_sight_method() -> void:
	var script := load("res://scenes/characters/enemies/enemy.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func has_line_of_sight_to")) \
		.override_failure_message("敌人应实现 has_line_of_sight_to 视野检测方法").is_true()
	assert_bool(source.contains("MASK_VISION_OBSTRUCTION")) \
		.override_failure_message("视野检测应使用 PhysicsSetup.MASK_VISION_OBSTRUCTION 遮挡层掩码").is_true()

func test_physics_setup_has_vision_obstruction_mask() -> void:
	var script := load("res://globals/core/physics_setup.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("MASK_VISION_OBSTRUCTION")) \
		.override_failure_message("PhysicsSetup 应定义 MASK_VISION_OBSTRUCTION 视野遮挡层掩码").is_true()

func test_line_of_sight_true_in_open_space() -> void:
	# 空旷场景中，敌人应能看见同距离内的玩家
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	# 等待物理世界初始化
	await get_tree().create_timer(0.05).timeout
	assert_bool(enemy.has_line_of_sight_to(player)) \
		.override_failure_message("空旷场景中应视线畅通").is_true()
	player.queue_free()
	enemy.queue_free()

func test_line_of_sight_false_when_wall_blocks_view() -> void:
	# 墙壁在敌人与玩家之间时，应判定视线被遮挡
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(4.0, 0.0, 0.0)
	# 在中间放置一面墙（环境层）
	var wall := _new_wall(Vector3(2.0, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	assert_bool(enemy.has_line_of_sight_to(player)) \
		.override_failure_message("墙壁遮挡时视线应被阻断").is_false()
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

func test_should_chase_player_blocked_by_wall() -> void:
	# 玩家在索敌范围内但墙后，敌人不应发现（初次检测路径）
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	# player 未登记，should_chase_player 走 GameState.current_player fallback 路径
	# 在中间放墙
	var wall := _new_wall(Vector3(1.5, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	# 模拟 GameState.current_player（绕过 Area3D 的 fallback 检测路径）
	GameState.current_player = player
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("墙后玩家不应被发现（禁止跨墙索敌）").is_false()
	assert_object(enemy.player) \
		.override_failure_message("跨墙检测失败后不应登记玩家").is_null()
	GameState.current_player = null
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

func test_should_chase_player_detects_without_wall() -> void:
	# 无墙时，玩家在索敌范围内应被发现（初次检测路径）
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().create_timer(0.05).timeout
	GameState.current_player = player
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("无墙遮挡时应在索敌范围内发现玩家").is_true()
	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()

func test_chase_continues_for_registered_player_behind_wall() -> void:
	# 已登记的玩家即使在墙后，也应继续追击（允许绕墙短暂追击）
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.player = player  # 模拟已通过视野检测并登记
	var wall := _new_wall(Vector3(1.5, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("已登记玩家在墙后也应继续追击").is_true()
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

func test_on_player_detected_ignores_player_behind_wall() -> void:
	# Area3D 触发 on_player_detected 时，若墙遮挡则不登记
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	var wall := _new_wall(Vector3(1.5, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	enemy.on_player_detected(player)
	assert_object(enemy.player) \
		.override_failure_message("墙后玩家进入 Area3D 时不应被登记").is_null()
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

func test_on_player_detected_registers_player_in_open_space() -> void:
	# 无墙时，Area3D 触发 on_player_detected 应正常登记玩家
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().create_timer(0.05).timeout
	enemy.on_player_detected(player)
	assert_object(enemy.player) \
		.override_failure_message("空旷场景中 Area3D 触发应正常登记玩家").is_not_null()
	assert_bool(enemy.player == player).is_true()
	player.queue_free()
	enemy.queue_free()

func test_dark_erosion_hunt_ignores_wall() -> void:
	# 100% 暗蚀强制猎杀应绕过视野检测
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.set_meta("dark_erosion_hunt", true)
	var wall := _new_wall(Vector3(1.5, 0.0, 0.0), Vector3(0.2, 3.0, 3.0))
	add_child(wall)
	await get_tree().create_timer(0.05).timeout
	assert_bool(enemy.should_chase_player()) \
		.override_failure_message("暗蚀强制猎杀应绕过视野检测").is_true()
	wall.queue_free()
	player.queue_free()
	enemy.queue_free()

# ==================== 辅助方法 ====================

func _new_enemy() -> Enemy:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	return scene.instantiate() as Enemy

func _new_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	return scene.instantiate() as Player

## 创建一面墙壁 StaticBody3D（环境层），用于阻挡视野
func _new_wall(pos: Vector3, box_size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	body.collision_mask = 0
	body.global_position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
	return body
