extends GdUnitTestSuite

# Tests for ShieldData and FurnitureData resources

# ── ShieldData ───────────────────────────────────────────────────────────

func test_shield_defaults() -> void:
	var s := ShieldData.new()
	s.name = "Buckler"
	s.condition = 20
	s.max_condition = 20
	assert_str(s.name).is_equal("Buckler")
	assert_int(s.condition).is_equal(20)
	assert_int(s.max_condition).is_equal(20)


func test_shield_decrease_condition() -> void:
	var s := ShieldData.new()
	s.condition = 15
	s.max_condition = 15
	s.decrease_condition(5)
	assert_int(s.condition).is_equal(10)


func test_shield_decrease_clamps_to_zero() -> void:
	var s := ShieldData.new()
	s.condition = 10
	s.max_condition = 10
	s.decrease_condition(20)
	assert_int(s.condition).is_equal(0)


func test_shield_decrease_negative_raises() -> void:
	var s := ShieldData.new()
	s.condition = 10
	s.max_condition = 10
	s.decrease_condition(-5)
	# clampi(10-(-5)=15, 0, 10) → capped at max_condition=10
	assert_int(s.condition).is_equal(10)


func test_shield_condition_never_exceeds_max() -> void:
	var s := ShieldData.new()
	s.condition = 10
	s.max_condition = 10
	s.decrease_condition(-5)
	assert_int(s.condition).is_equal(10)  # clamps to max_condition


func test_shield_glb_mesh_null_by_default() -> void:
	var s := ShieldData.new()
	assert_object(s.glb_mesh).is_null()


# ── FurnitureData ────────────────────────────────────────────────────────

func test_furniture_defaults() -> void:
	var f := FurnitureData.new()
	f.name = "Wooden Table"
	f.throw_rotation_speed = 2.5
	f.throw_movement_speed = 8.0
	assert_str(f.name).is_equal("Wooden Table")
	assert_float(f.throw_rotation_speed).is_equal(2.5)
	assert_float(f.throw_movement_speed).is_equal(8.0)


func test_furniture_glb_mesh_null_by_default() -> void:
	var f := FurnitureData.new()
	assert_object(f.glb_mesh).is_null()
	assert_object(f.glb_fragments_mesh).is_null()


func test_furniture_can_set_all_fields() -> void:
	var f := FurnitureData.new()
	f.name = "Iron Bench"
	f.throw_rotation_speed = 3.0
	f.throw_movement_speed = 6.0
	assert_str(f.name).is_equal("Iron Bench")
	assert_float(f.throw_rotation_speed).is_equal(3.0)
	assert_float(f.throw_movement_speed).is_equal(6.0)
