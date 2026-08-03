extends GdUnitTestSuite
## 武器投掷/丢弃后状态固化测试
## 验证 throw_weapon / drop_shield 后 GameState 的 weapon_slot_ids 被同步更新，
## 避免 apply_equipment_to_player 从过期数据恢复已离手的装备。

# ============================================================================
# 1. 源码级验证：throw_weapon / drop_shield 包含 _persist_equipment_state 调用
# ============================================================================

func test_throw_weapon_calls_persist() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var fn_start := source.find("func throw_weapon(")
	assert_int(fn_start).is_greater(0)
	var fn_end := source.find("\nfunc ", fn_start + 1)
	var fn_body := source.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_persist_equipment_state()")) \
		.override_failure_message("throw_weapon 末尾必须调用 _persist_equipment_state 固化状态").is_true()


func test_drop_shield_calls_persist() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	var fn_start := source.find("func drop_shield(")
	assert_int(fn_start).is_greater(0)
	var fn_end := source.find("\nfunc ", fn_start + 1)
	var fn_body := source.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_persist_equipment_state()")) \
		.override_failure_message("drop_shield 末尾必须调用 _persist_equipment_state 固化状态").is_true()


func test_persist_equipment_state_function_exists() -> void:
	var source := (load("res://scenes/characters/component/equipment_component.gd") as GDScript).source_code
	assert_bool(source.contains("func _persist_equipment_state()")) \
		.override_failure_message("缺少 _persist_equipment_state 函数").is_true()
	assert_bool(source.contains("save_equipment_from_player")) \
		.override_failure_message("_persist_equipment_state 必须调用 save_equipment_from_player").is_true()


# ============================================================================
# 2. 功能验证：throw_weapon 后 GameState 状态被固化
# ============================================================================

## 创建带 equipment 属性的测试用玩家节点。
func _create_mock_player() -> Node3D:
	var player := Node3D.new()
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node3D\nvar equipment: Node\nvar health: RefCounted\n"
	mock_script.reload()
	player.set_script(mock_script)
	var health_obj := RefCounted.new()
	var health_script := GDScript.new()
	health_script.source_code = "extends RefCounted\nvar current_life: int = 100\nvar max_life: int = 100\n"
	health_script.reload()
	health_obj.set_script(health_script)
	player.health = health_obj
	return player


func test_throw_weapon_persists_empty_slot_to_game_state() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			gs = tree.root.get_node_or_null("GameState")
	assert_object(gs).is_not_null()
	# 保存初始状态
	var old_weapon_slot_ids: Array = gs.weapon_slot_ids.duplicate()
	var old_active: int = gs.active_weapon_slot

	# 创建 mock player + EquipmentComponent
	var player := _create_mock_player()
	add_child(player)
	var eq: Node = load("res://scenes/characters/component/equipment_component.tscn").instantiate()
	player.add_child(eq)
	player.equipment = eq
	equip_weapon_to_slot(eq, 0, "shortsword")

	# 确保 GameState 注册玩家并保存当前装备
	if gs.has_method("register_player"):
		# register_player 可能触发 apply_equipment_to_player，需先设置已保存状态
		gs.weapon_slot_ids[0] = "shortsword"
	# 直接调用 save 让 GameState 同步
	gs.save_equipment_from_player(player)
	# 验证 GameState 记录了武器
	assert_str(String(gs.weapon_slot_ids[0])).is_equal("shortsword")

	# 执行 throw_weapon（drop 模式）
	# _spawn_dropped_weapon 在无 level 时安全 return，不影响状态固化
	eq.throw_weapon(true)

	# 验证 EquipmentComponent 武器已清空
	assert_object(eq.weapon_data).is_null()
	assert_object(eq.weapon_slots[0]).is_null()
	# 验证 GameState 状态已固化（weapon_slot_ids 被清空）
	assert_str(String(gs.weapon_slot_ids[0])).is_equal("")

	# 恢复
	eq.queue_free()
	player.queue_free()
	gs.weapon_slot_ids = old_weapon_slot_ids
	gs.active_weapon_slot = old_active


## 将指定武器配置到 EquipmentComponent 的指定槽位。
func equip_weapon_to_slot(eq: Node, slot_index: int, weapon_id: String) -> void:
	var data: WeaponData = WeaponRegistry.get_weapon_data(weapon_id)
	assert_object(data).is_not_null()
	eq.configure_weapon_slot(slot_index, data, slot_index == 0)
