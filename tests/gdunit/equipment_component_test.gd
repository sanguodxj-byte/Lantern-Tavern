extends GdUnitTestSuite

# EquipmentComponent 装备组件测试（纯逻辑，无需场景）

func test_equipment_component_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/component/equipment_component.gd")).is_true()


func test_has_weapon_initially_false() -> void:
	# 创建组件但不设置武器
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	assert_bool(eq.has_weapon()).is_false()


func test_has_shield_initially_false() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	assert_bool(eq.has_shield()).is_false()


func test_has_furniture_initially_false() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	assert_bool(eq.has_furniture()).is_false()


func test_weapon_data_defaults() -> void:
	var data = WeaponData.new()
	data.name = "Test Sword"
	data.condition = 20
	data.max_condition = 20
	data.damage_min = 3
	data.damage_max = 7
	data.reach = 2.0
	assert_str(data.name).is_equal("Test Sword")
	assert_int(data.get_damage_dealt()).is_greater_equal(3)


func test_weapon_decrease_condition() -> void:
	var data = WeaponData.new()
	data.condition = 10
	data.max_condition = 10
	data.decrease_condition(4)
	assert_int(data.condition).is_equal(6)


func test_weapon_decrease_below_zero_clamps() -> void:
	var data = WeaponData.new()
	data.condition = 3
	data.max_condition = 10
	data.decrease_condition(10)
	assert_int(data.condition).is_equal(0)


func test_shield_data_defaults() -> void:
	var data = ShieldData.new()
	data.name = "Test Shield"
	data.condition = 15
	data.max_condition = 15
	assert_str(data.name).is_equal("Test Shield")


func test_shield_decrease_condition() -> void:
	var data = ShieldData.new()
	data.condition = 10
	data.max_condition = 10
	data.decrease_condition(3)
	assert_int(data.condition).is_equal(7)


func test_furniture_data_defaults() -> void:
	var data = FurnitureData.new()
	data.name = "Table"
	data.throw_rotation_speed = 2.0
	data.throw_movement_speed = 8.0
	assert_str(data.name).is_equal("Table")
	assert_float(data.throw_rotation_speed).is_equal(2.0)


func test_configure_four_weapon_slots_and_activate() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	var sword := _make_weapon("Slot Sword", 2.0)
	var axe := _make_weapon("Slot Axe", 3.0)
	assert_bool(eq.configure_weapon_slot(0, sword, true)).is_true()
	assert_bool(eq.configure_weapon_slot(3, axe, true)).is_true()
	assert_int(eq.weapon_slots.size()).is_equal(4)
	assert_int(eq.active_weapon_slot).is_equal(3)
	assert_str(eq.weapon_data.name).is_equal("Slot Axe")
	assert_str(eq.get_weapon_slot_label(0)).is_equal("Slot Sword")
	assert_str(eq.get_weapon_slot_label(3)).is_equal("Slot Axe")


func test_cycle_weapon_slot_skips_empty_slots() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	eq.configure_weapon_slot(0, _make_weapon("First", 2.0), true)
	eq.configure_weapon_slot(2, _make_weapon("Third", 4.0), false)
	assert_bool(eq.cycle_weapon_slot(1)).is_true()
	assert_int(eq.active_weapon_slot).is_equal(2)
	assert_str(eq.weapon_data.name).is_equal("Third")
	assert_float(abs(eq.weapon_reach_raycast.target_position.z)).is_equal_approx(4.0, 0.01)
	assert_bool(eq.cycle_weapon_slot(1)).is_true()
	assert_int(eq.active_weapon_slot).is_equal(0)


func test_equip_weapon_uses_first_empty_slot() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	eq.configure_weapon_slot(0, _make_weapon("Existing", 2.0), true)
	eq.equip_weapon(_make_weapon("Pickup", 3.0))
	assert_int(eq.active_weapon_slot).is_equal(1)
	assert_str(eq.get_weapon_slot_label(1)).is_equal("Pickup")


func test_shield_weapondata_uses_same_hand_slots() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	var shield := _make_shield_weapon("Buckler")
	assert_bool(eq.configure_weapon_slot(2, shield, true)).is_true()
	assert_int(eq.active_weapon_slot).is_equal(2)
	assert_str(eq.get_weapon_slot_label(2)).is_equal("Buckler")
	assert_bool(eq.has_hand_equipment()).is_true()
	assert_bool(eq.has_shield()).is_true()
	assert_bool(eq.has_weapon()).is_false()
	assert_object(eq.get_active_shield_data()).is_not_null()


func test_armor_slots_store_runtime_armor_and_sum_stats() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	var light := _make_armor("Leather", 2, 3.0, 0.98)
	var heavy := _make_armor("Plate", 5, -2.0, 0.88)
	assert_bool(eq.configure_armor_slot("body", light)).is_true()
	assert_bool(eq.configure_armor_slot("head", heavy)).is_true()
	assert_str(eq.get_armor_slot_label("body")).is_equal("Leather")
	assert_int(eq.get_armor_defense()).is_equal(7)
	assert_float(eq.get_armor_move_speed_mult()).is_equal_approx(0.8624, 0.0001)


func test_hand_slots_reject_armor() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	assert_bool(eq.configure_weapon_slot(0, _make_armor("Leather", 2, 3.0), true)).is_false()


func test_legacy_tres_weapon_without_tags_is_hand_equipment() -> void:
	# 回归测试：.tres 文件没有 item_tag/equipment_category（默认空字符串），
	# 不应被 _is_hand_equipment 拒绝
	var data := WeaponData.new()
	data.name = "Legacy Sword"
	data.condition = 20
	data.max_condition = 20
	data.damage_min = 3
	data.damage_max = 5
	data.reach = 3.0
	assert_str(data.item_tag).is_empty()
	assert_str(data.equipment_category).is_empty()
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	assert_bool(eq.configure_weapon_slot(0, data, true)).is_true()
	assert_str(eq.weapon_data.name).is_equal("Legacy Sword")


func test_equip_weapon_returns_true_for_valid_weapon() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	assert_bool(eq.equip_weapon(_make_weapon("Sword", 2.0))).is_true()
	assert_str(eq.weapon_data.name).is_equal("Sword")


func test_equip_weapon_returns_false_for_armor() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	assert_bool(eq.equip_weapon(_make_armor("Plate", 5, -2.0))).is_false()
	assert_object(eq.weapon_data).is_null()


func test_equip_weapon_returns_true_for_legacy_tres() -> void:
	# 回归测试：拾取 .tres 武器（无 item_tag）应返回 true
	var data := WeaponData.new()
	data.name = "Axe"
	data.condition = 25
	data.max_condition = 25
	data.damage_min = 4
	data.damage_max = 5
	data.reach = 4.0
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	_prepare_weapon_equipment(eq)
	assert_bool(eq.equip_weapon(data)).is_true()
	assert_str(eq.weapon_data.name).is_equal("Axe")


func test_player_mouse_wheel_routes_to_weapon_slot_cycle() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("MOUSE_BUTTON_WHEEL_UP")).is_true()
	assert_bool(source.contains("MOUSE_BUTTON_WHEEL_DOWN")).is_true()
	assert_bool(source.contains("equipment.cycle_weapon_slot")).is_true()


func _prepare_weapon_equipment(eq: EquipmentComponent) -> void:
	eq.weapon_placeholder = Node3D.new()
	eq.weapon_reach_raycast = RayCast3D.new()
	eq.weapon_spawn_position = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.weapon_reach_raycast)
	eq.add_child(eq.weapon_spawn_position)


func _make_weapon(label: String, reach: float) -> WeaponData:
	var data := WeaponData.new()
	data.id = label.to_lower()
	data.name = label
	data.item_tag = "weapon"
	data.equipment_category = "weapons"
	data.condition = 10
	data.max_condition = 10
	data.damage_min = 1
	data.damage_max = 3
	data.reach = reach
	return data


func _make_shield_weapon(label: String) -> WeaponData:
	var data := _make_weapon(label, 1.0)
	data.item_tag = "shield"
	data.weapon_class = "shield"
	data.equipment_category = "shields"
	data.shield_phys_def = 1
	return data


func _make_armor(label: String, phys_def: int, evade: float, move_speed_mult: float = 1.0) -> WeaponData:
	var data := WeaponData.new()
	data.id = label.to_lower()
	data.name = label
	data.item_tag = "armor_light"
	data.equipment_category = "armor_light"
	data.armor_slot = "body"
	data.armor_phys_def = phys_def
	data.armor_move_speed_mult = move_speed_mult
	data.condition = 10
	data.max_condition = 10
	return data
