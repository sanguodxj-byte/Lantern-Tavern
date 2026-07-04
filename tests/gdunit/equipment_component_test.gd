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
