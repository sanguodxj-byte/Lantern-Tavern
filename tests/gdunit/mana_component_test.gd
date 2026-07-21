extends GdUnitTestSuite

# Tests for ManaComponent

func test_mana_initial_state() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 100

	assert_int(mana.current_mana).is_equal(100)
	assert_int(mana.max_mana).is_equal(100)
	assert_float(mana.ratio()).is_equal_approx(1.0, 0.001)
	mana.free()


func test_mana_spend_success() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 80

	var ok := mana.spend(30)
	assert_bool(ok).is_true()
	assert_int(mana.current_mana).is_equal(50)
	mana.free()


func test_mana_spend_insufficient() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 20

	var ok := mana.spend(50)
	assert_bool(ok).is_false()
	assert_int(mana.current_mana).is_equal(20)
	mana.free()


func test_mana_spend_zero_or_negative() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 50

	assert_bool(mana.spend(0)).is_true()
	assert_bool(mana.spend(-10)).is_true()
	assert_int(mana.current_mana).is_equal(50)
	mana.free()


func test_mana_regen() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 50
	mana.regen_per_sec = 10.0

	mana.regen(1.0)  # 1秒回复10点
	assert_int(mana.current_mana).is_equal(60)
	mana.free()


func test_mana_regen_clamps_to_max() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 95
	mana.regen_per_sec = 20.0

	mana.regen(1.0)
	assert_int(mana.current_mana).is_equal(100)
	mana.free()


func test_mana_regen_at_max_does_nothing() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 100
	mana.regen_per_sec = 10.0

	mana.regen(1.0)
	assert_int(mana.current_mana).is_equal(100)
	mana.free()


func test_mana_restore() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 30

	mana.restore(40)
	assert_int(mana.current_mana).is_equal(70)

	mana.restore(100)
	assert_int(mana.current_mana).is_equal(100)
	mana.free()


func test_mana_set_max_clamps_current() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 80

	mana.set_max(50)
	assert_int(mana.max_mana).is_equal(50)
	assert_int(mana.current_mana).is_equal(50)

	mana.set_max(200)
	assert_int(mana.max_mana).is_equal(200)
	assert_int(mana.current_mana).is_equal(50)
	mana.free()


func test_mana_ratio() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 200
	mana.current_mana = 50

	assert_float(mana.ratio()).is_equal_approx(0.25, 0.001)

	mana.current_mana = 0
	assert_float(mana.ratio()).is_equal_approx(0.0, 0.001)
	mana.free()


func test_mana_regen_fractional_accumulation() -> void:
	var mana = ManaComponent.new()
	mana.max_mana = 100
	mana.current_mana = 50
	mana.regen_per_sec = 5.0

	# 0.3秒积累1.5，>= 1.0 所以+1，剩余0.5
	mana.regen(0.3)
	assert_int(mana.current_mana).is_equal(51)

	# 再0.3秒: 0.5+1.5=2.0，>= 1.0 所以+2
	mana.regen(0.3)
	assert_int(mana.current_mana).is_equal(53)
	mana.free()
