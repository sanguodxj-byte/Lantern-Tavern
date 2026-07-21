extends GdUnitTestSuite

# Tests for Data Resources: WeaponData, ShieldData, FurnitureData

func test_weapon_data_defaults() -> void:
	var w = WeaponData.new()
	w.name = "Short Sword"
	w.condition = 30
	w.max_condition = 30
	w.damage_min = 2
	w.damage_max = 5
	w.reach = 2.5

	assert_str(w.name).is_equal("Short Sword")
	assert_int(w.condition).is_equal(30)
	assert_int(w.max_condition).is_equal(30)
	assert_int(w.damage_min).is_equal(2)
	assert_int(w.damage_max).is_equal(5)
	assert_float(w.reach).is_equal(2.5)


func test_weapon_data_carries_armor_move_speed_multiplier() -> void:
	var w = WeaponData.new()
	w.equipment_category = "armor_heavy"
	w.armor_move_speed_mult = 0.88

	assert_float(w.armor_move_speed_mult).is_equal(0.88)


func test_weapon_get_damage_dealt_in_range() -> void:
	var w = WeaponData.new()
	w.damage_min = 3
	w.damage_max = 8
	for _i in 100:
		var dmg = w.get_damage_dealt()
		assert_bool(dmg >= 3 and dmg <= 8) \
			.override_failure_message("Damage %d out of range [3,8]" % dmg) \
			.is_true()


func test_weapon_decrease_condition_clamps() -> void:
	var w = WeaponData.new()
	w.condition = 10
	w.max_condition = 10

	w.decrease_condition(3)
	assert_int(w.condition).is_equal(7)

	w.decrease_condition(10)
	assert_int(w.condition).is_equal(0) # clamped

	w.decrease_condition(-5)
	assert_int(w.condition).is_equal(5)


func test_shield_data_defaults() -> void:
	var s = ShieldData.new()
	s.name = "Buckler"
	s.condition = 20
	s.max_condition = 20

	assert_str(s.name).is_equal("Buckler")
	assert_int(s.condition).is_equal(20)


func test_shield_decrease_condition_clamps() -> void:
	var s = ShieldData.new()
	s.condition = 15
	s.max_condition = 15

	s.decrease_condition(5)
	assert_int(s.condition).is_equal(10)

	s.decrease_condition(20)
	assert_int(s.condition).is_equal(0)


func test_furniture_data_defaults() -> void:
	var f = FurnitureData.new()
	f.name = "Wooden Table"
	f.throw_rotation_speed = 2.5
	f.throw_movement_speed = 8.0

	assert_str(f.name).is_equal("Wooden Table")
	assert_float(f.throw_rotation_speed).is_equal(2.5)
	assert_float(f.throw_movement_speed).is_equal(8.0)
