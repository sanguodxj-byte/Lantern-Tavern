extends GdUnitTestSuite

# Tests for HealthComponent

func test_health_initial_state() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 100

	assert_int(health.current_life).is_equal(100)
	assert_int(health.max_life).is_equal(100)
	assert_bool(health.is_dead()).is_false()
	health.free()


func test_take_damage_reduces_life() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 100

	health.take_damage(30)
	assert_int(health.current_life).is_equal(70)
	assert_bool(health.is_dead()).is_false()
	health.free()


func test_take_damage_clamps_to_zero() -> void:
	var health = HealthComponent.new()
	health.max_life = 50
	health.current_life = 50

	health.take_damage(100)
	assert_int(health.current_life).is_equal(0)
	assert_bool(health.is_dead()).is_true()
	health.free()


func test_take_damage_does_not_exceed_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 100

	health.take_damage(-50)
	assert_int(health.current_life).is_equal(100)
	health.free()


func test_heal_restores_life_and_clamps_to_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 70

	health.heal(50)
	assert_int(health.current_life).is_equal(100)
	health.free()


func test_is_dead_at_zero() -> void:
	var health = HealthComponent.new()
	health.max_life = 10
	health.current_life = 0

	assert_bool(health.is_dead()).is_true()
	health.free()


# ── 权威镜像 setter（P1/A3 修复：set_max_life / set_current_life）──

func test_set_max_life_updates_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 100

	health.set_max_life(150)
	assert_int(health.max_life).is_equal(150)
	health.free()


func test_set_max_life_clamps_current_to_new_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100
	health.current_life = 100

	health.set_max_life(50)
	assert_int(health.max_life).is_equal(50)
	assert_int(health.current_life).is_equal(50)
	health.free()


func test_set_max_life_never_zero() -> void:
	var health = HealthComponent.new()
	health.set_max_life(0)
	assert_int(health.max_life).is_greater_equal(1)
	health.free()


func test_set_current_life_updates_within_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100

	health.set_current_life(70)
	assert_int(health.current_life).is_equal(70)
	health.free()


func test_set_current_life_clamps_to_max() -> void:
	var health = HealthComponent.new()
	health.max_life = 100

	health.set_current_life(150)
	assert_int(health.current_life).is_equal(100)
	health.free()


func test_set_current_life_clamps_to_zero() -> void:
	var health = HealthComponent.new()
	health.max_life = 100

	health.set_current_life(-5)
	assert_int(health.current_life).is_equal(0)
	health.free()
