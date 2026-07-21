extends GdUnitTestSuite
## CombatBuffComponent 单元测试
## 验证从 player.gd 提取的战斗 buff 系统的完整功能

const CBC := preload("res://scenes/characters/component/combat_buff_component.gd")

# ============================================================================
# 1. 添加 / 查询
# ============================================================================

func test_add_buff_creates_entry() -> void:
	var buffs = CBC.new()
	buffs.add("def_and_evade_up", 3.0, {"def": 4, "evade": 5})
	assert_bool(buffs.has("def_and_evade_up")).is_true()

func test_add_ignores_empty_type() -> void:
	var buffs = CBC.new()
	buffs.add("", 3.0, 10)
	assert_bool(buffs.has("")).is_false()

func test_add_ignores_zero_duration() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 0.0, 10)
	assert_bool(buffs.has("test_buff")).is_false()

func test_add_ignores_negative_duration() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", -1.0, 10)
	assert_bool(buffs.has("test_buff")).is_false()

func test_get_value_returns_stored_value() -> void:
	var buffs = CBC.new()
	buffs.add("slow_and_haste", 5.0, {"slow_target": 30, "haste_self": 10})
	var value = buffs.get_value("slow_and_haste")
	assert_bool(value.has("slow_target")).is_true()

func test_get_value_returns_null_for_missing_buff() -> void:
	var buffs = CBC.new()
	assert_object(buffs.get_value("nonexistent")).is_null()

func test_has_returns_false_for_missing_buff() -> void:
	var buffs = CBC.new()
	assert_bool(buffs.has("nonexistent")).is_false()

# ============================================================================
# 2. 战斗属性查询
# ============================================================================

func test_get_defense_bonus_with_buff() -> void:
	var buffs = CBC.new()
	buffs.add("def_and_evade_up", 3.0, {"def": 4, "evade": 5})
	assert_int(buffs.get_defense_bonus()).is_equal(4)

func test_get_defense_bonus_without_buff() -> void:
	var buffs = CBC.new()
	assert_int(buffs.get_defense_bonus()).is_equal(0)

func test_get_evade_bonus_with_buff() -> void:
	var buffs = CBC.new()
	buffs.add("def_and_evade_up", 3.0, {"def": 4, "evade": 5.0})
	assert_float(buffs.get_evade_bonus()).is_equal(5.0)

func test_get_evade_bonus_without_buff() -> void:
	var buffs = CBC.new()
	assert_float(buffs.get_evade_bonus()).is_equal(0.0)

func test_get_speed_multiplier_with_haste() -> void:
	var buffs = CBC.new()
	buffs.add("slow_and_haste", 5.0, {"haste_self": 20.0})
	# 1.0 + 20/100 = 1.2
	assert_float(buffs.get_speed_multiplier()).is_equal_approx(1.2, 0.001)

func test_get_speed_multiplier_without_buff() -> void:
	var buffs = CBC.new()
	assert_float(buffs.get_speed_multiplier()).is_equal(1.0)

# ============================================================================
# 3. 伤害吸收
# ============================================================================

func test_consume_damage_absorb_reduces_damage() -> void:
	var buffs = CBC.new()
	buffs.add("damage_absorb", 10.0, 50.0)  # 50% of max life
	var reduced: int = buffs.consume_damage_absorb(30, 100)
	# absorb = 100 * 50 / 100 = 50, reduced = max(30 - 50, 0) = 0
	assert_int(reduced).is_equal(0)

func test_consume_damage_absorb_partial_absorb() -> void:
	var buffs = CBC.new()
	buffs.add("damage_absorb", 10.0, 25.0)  # 25% of max life
	var reduced: int = buffs.consume_damage_absorb(30, 100)
	# absorb = 100 * 25 / 100 = 25, reduced = max(30 - 25, 0) = 5
	assert_int(reduced).is_equal(5)

func test_consume_damage_absorb_removes_buff_after_use() -> void:
	var buffs = CBC.new()
	buffs.add("damage_absorb", 10.0, 50.0)
	buffs.consume_damage_absorb(30, 100)
	assert_bool(buffs.has("damage_absorb")).is_false()

func test_consume_damage_absorb_without_buff_returns_original() -> void:
	var buffs = CBC.new()
	var reduced: int = buffs.consume_damage_absorb(30, 100)
	assert_int(reduced).is_equal(30)

# ============================================================================
# 4. Tick 衰减
# ============================================================================

func test_tick_reduces_remaining_time() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 5.0, 10)
	buffs.tick(2.0)
	# 5.0 - 2.0 = 3.0 remaining
	assert_bool(buffs.has("test_buff")).is_true()

func test_tick_removes_expired_buff() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 3.0, 10)
	buffs.tick(3.0)
	assert_bool(buffs.has("test_buff")).is_false()

func test_tick_removes_buff_when_duration_exceeded() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 2.0, 10)
	buffs.tick(3.0)
	assert_bool(buffs.has("test_buff")).is_false()

func test_tick_handles_multiple_buffs() -> void:
	var buffs = CBC.new()
	buffs.add("buff_a", 5.0, 1)
	buffs.add("buff_b", 2.0, 2)
	buffs.tick(3.0)
	assert_bool(buffs.has("buff_a")).is_true()
	assert_bool(buffs.has("buff_b")).is_false()

func test_tick_with_zero_delta_does_nothing() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 5.0, 10)
	buffs.tick(0.0)
	assert_bool(buffs.has("test_buff")).is_true()

# ============================================================================
# 5. 兼容性接口
# ============================================================================

func test_get_buffs_dict_returns_reference() -> void:
	var buffs = CBC.new()
	buffs.add("test_buff", 5.0, 10)
	var dict: Dictionary = buffs.get_buffs_dict()
	assert_bool(dict.has("test_buff")).is_true()

func test_get_buffs_dict_modifications_affect_component() -> void:
	var buffs = CBC.new()
	var dict: Dictionary = buffs.get_buffs_dict()
	# Simulate direct dictionary access like combat_bridge_test.gd does
	dict["def_and_evade_up"] = {"remaining": 3.0, "value": {"def": 4, "evade": 5}}
	# The component should see the modification
	assert_bool(buffs.has("def_and_evade_up")).is_true()
	assert_int(buffs.get_defense_bonus()).is_equal(4)

# ============================================================================
# 6. Player 集成验证
# ============================================================================

func test_player_combat_buffs_property_delegates_to_component() -> void:
	var player := Player.new()
	# Direct dictionary access via the compatibility property
	player.combat_buffs["def_and_evade_up"] = {"remaining": 3.0, "value": {"def": 4, "evade": 5}}
	# Proxy method should return the value from the component
	assert_int(player.get_combat_defense_bonus()).is_equal(4)
	assert_float(player.get_combat_evade_bonus()).is_equal(5.0)
	player.free()

func test_player_add_combat_buff_delegates_to_component() -> void:
	var player := Player.new()
	player.add_combat_buff("slow_and_haste", 5.0, {"haste_self": 20.0})
	assert_float(player.get_combat_speed_multiplier()).is_equal_approx(1.2, 0.001)
	player.free()

func test_player_buffs_tick_via_physics_process_compatible() -> void:
	var player := Player.new()
	player.add_combat_buff("test_buff", 2.0, 42)
	# Manually tick (simulates what _physics_process does)
	player.buffs.tick(3.0)
	assert_bool(player.buffs.has("test_buff")).is_false()
	player.free()
