extends GdUnitTestSuite

## Real regression coverage for dropped-item accessibility and one-shot knockback.

const PICKABLE_SCENE := preload("res://scenes/equipment/pickable_item.tscn")
const THROWN_SCENE := preload("res://scenes/equipment/thrown_item.tscn")


func test_player_does_not_physically_block_pickables_but_select_raycast_can_hit_them() -> void:
	assert_int(PhysicsSetup.MASK_PLAYER & PhysicsSetup.LAYER_PICKABLE) \
		.override_failure_message("玩家不应以实体碰撞推挤地面拾取物，避免掉落物被持续唤醒") \
		.is_equal(0)
	assert_bool((PhysicsSetup.MASK_SELECTABLE & PhysicsSetup.LAYER_PICKABLE) != 0) \
		.override_failure_message("移除实体碰撞后，准心射线仍必须能选中拾取物") \
		.is_true()
	assert_bool((PhysicsSetup.MASK_PICKABLE & PhysicsSetup.LAYER_PICKABLE) == 0) \
		.override_failure_message("地面拾取物之间不应互相推挤唤醒") \
		.is_true()


func test_enemy_pushback_is_not_added_to_velocity_every_physics_frame() -> void:
	var enemy := Enemy.new()
	enemy.pushback_force = Vector3(6.0, 0.0, 0.0)
	enemy.process_pushback(0.016)
	var velocity_after_first_step := enemy.velocity.x
	enemy.process_pushback(0.016)

	assert_float(enemy.velocity.x) \
		.override_failure_message("踢击/冲撞击退不得在第二个物理帧再次叠加到敌人速度") \
		.is_equal_approx(velocity_after_first_step, 0.001)
	enemy.free()


func test_dropping_weapon_immediately_creates_a_selectable_pickable() -> void:
	var previous_level: Node = GameState.current_level
	var level := Node3D.new()
	var equipment := EquipmentComponent.new()
	add_child(level)
	add_child(equipment)
	GameState.current_level = level

	var weapon: WeaponData = WeaponRegistry.get_weapon_data("shortsword")
	assert_object(weapon).is_not_null()
	equipment.call("_spawn_dropped_weapon", weapon, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), true)
	await await_idle_frame()

	var pickable := _first_pickable(level)
	assert_object(pickable) \
		.override_failure_message("普通丢弃不能等待 ThrownItem 休眠后才变为可拾取物") \
		.is_not_null()
	if pickable != null:
		assert_int(pickable.collision_layer).is_equal(PhysicsSetup.LAYER_PICKABLE)
		assert_object(pickable.weapon_data).is_equal(weapon)

	GameState.current_level = previous_level
	equipment.queue_free()
	level.queue_free()


func test_dropped_pickable_settles_on_static_floor_and_stays_selectable() -> void:
	var previous_level: Node = GameState.current_level
	var level := Node3D.new()
	add_child(level)
	GameState.current_level = level

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	floor_body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(4.0, 0.2, 4.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position.y = -0.1
	level.add_child(floor_body)

	var pickable := PICKABLE_SCENE.instantiate() as PickableItem
	pickable.weapon_data = WeaponRegistry.get_weapon_data("shortsword")
	pickable.position = Vector3(0.0, 1.0, 0.0)
	level.add_child(pickable)
	await _wait_physics_frames(120)

	assert_bool(pickable.sleeping) \
		.override_failure_message("地面掉落物应在静态地面上进入休眠，不能持续抖动或闪烁") \
		.is_true()
	assert_bool((PhysicsSetup.MASK_SELECTABLE & pickable.collision_layer) != 0) \
		.override_failure_message("掉落物休眠后仍必须保留可选择碰撞层") \
		.is_true()
	var settled_position := pickable.position
	await _wait_physics_frames(20)
	assert_float(pickable.position.distance_to(settled_position)) \
		.override_failure_message("休眠后的掉落物位置必须稳定，不能在地面持续跳动") \
		.is_less(0.001)

	GameState.current_level = previous_level
	level.queue_free()


func test_thrown_item_does_not_convert_when_sleep_signal_reports_awake() -> void:
	var previous_level: Node = GameState.current_level
	var level := Node3D.new()
	var thrown := THROWN_SCENE.instantiate() as ThrownItem
	add_child(level)
	GameState.current_level = level
	thrown.weapon_data = WeaponRegistry.get_weapon_data("shortsword")
	level.add_child(thrown)
	await await_idle_frame()

	thrown.sleeping = false
	thrown.on_sleep()
	await await_idle_frame()

	assert_bool(thrown.is_queued_for_deletion()) \
		.override_failure_message("刚体被唤醒时不得错误地转换为地面拾取物") \
		.is_false()
	assert_object(_first_pickable(level)).is_null()

	GameState.current_level = previous_level
	thrown.queue_free()
	level.queue_free()


func test_charge_state_does_not_apply_an_extra_self_impulse_or_move_twice() -> void:
	var source := (load("res://scenes/characters/player/state/player_state_charging.gd") as GDScript).source_code
	var start := source.find("func _physics_process")
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start)

	assert_bool(body.contains("pushback_force")) \
		.override_failure_message("冲撞本体速度已由 state 设置，不得再持续写入 pushback_force") \
		.is_false()
	assert_bool(body.contains("move_and_slide()")) \
		.override_failure_message("Player 根节点已统一移动，冲撞状态不得同帧再次 move_and_slide") \
		.is_false()


func _first_pickable(parent: Node) -> PickableItem:
	for child in parent.get_children():
		if child is PickableItem:
			return child as PickableItem
	return null


func _wait_physics_frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().physics_frame
