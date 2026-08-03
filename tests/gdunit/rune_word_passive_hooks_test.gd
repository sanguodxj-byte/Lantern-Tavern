extends GdUnitTestSuite
## 符文之语被动钩子（RuneWordPassiveHooks）测试套件。
## 覆盖：伤害倍率/闪避/受伤修正/tick被动/控制免疫/静态状态重置。

const RWPH := preload("res://globals/combat/rune_word_passive_hooks.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")

## 模拟玩家（支持 has_mechanism_passive 覆写）
class MockPlayer:
	extends Node3D
	var health: MockHealth
	var _passives: Dictionary = {}
	func has_mechanism_passive(id: String) -> bool:
		return _passives.has(id) and _passives[id]
	func set_passive(id: String, active: bool) -> void:
		_passives[id] = active

class MockHealth:
	extends Node
	var current_life: int = 100
	var max_life: int = 100
	func heal(amount: int) -> void:
		current_life = mini(max_life, current_life + amount)
	func take_damage(dmg: int) -> void:
		current_life = maxi(0, current_life - dmg)

## 模拟敌人
class MockEnemy:
	extends Node3D
	var combat_debuffs: Dictionary = {}
	var health: MockHealth

func _make_player() -> MockPlayer:
	var p := MockPlayer.new()
	p.health = MockHealth.new()
	p.add_child(p.health)
	return auto_free(p)

func _make_enemy() -> MockEnemy:
	var e := MockEnemy.new()
	e.health = MockHealth.new()
	e.add_child(e.health)
	return auto_free(e)

func before() -> void:
	RWPH.reset_static_state()

func after() -> void:
	RWPH.reset_static_state()

# ---------- 伤害倍率查询 ----------

func test_outgoing_damage_mult_no_passive() -> void:
	var p := _make_player()
	var e := _make_enemy()
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.0, 0.001)

func test_outgoing_damage_mult_vital_power_full_hp() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_vital_power", true)
	p.health.current_life = 100
	p.health.max_life = 100
	# 满血 +30%
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.30, 0.001)

func test_outgoing_damage_mult_vital_power_half_hp() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_vital_power", true)
	p.health.current_life = 50
	p.health.max_life = 100
	# 半血 +15%
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.15, 0.001)

func test_outgoing_damage_mult_brave_spell_low_hp() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_brave_spell", true)
	p.health.current_life = 20
	p.health.max_life = 100
	# 残血(20%) +40% * 0.8 = +32%
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.32, 0.001)

func test_outgoing_damage_mult_armor_pierce() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_armor_pierce", true)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.20, 0.001)

func test_outgoing_damage_mult_perfect_liberation() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_perfect_liberation", true)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.15, 0.001)

func test_outgoing_damage_mult_dreadful_destruction_with_fear() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_dreadful_destruction", true)
	SES.apply_status(e, "se_fear", 3.0)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.50, 0.001)

func test_outgoing_damage_mult_dreadful_destruction_without_fear() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_dreadful_destruction", true)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.0, 0.001)

func test_outgoing_damage_mult_karmic_justice_stacks() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_karmic_justice", true)
	# 第一次命中：1 层 → +5%
	RWPH.on_player_hit_enemy(p, e, Vector3.ZERO, 10)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.05, 0.001)
	# 第二次命中：2 层 → +10%
	RWPH.on_player_hit_enemy(p, e, Vector3.ZERO, 10)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.10, 0.001)

# ---------- 闪避检定 ----------

func test_try_dodge_no_passive() -> void:
	var p := _make_player()
	assert_bool(RWPH.try_dodge(p)).is_false()

func test_try_dodge_with_passive_returns_bool() -> void:
	var p := _make_player()
	p.set_passive("rune_word_dodge", true)
	# 20% 概率，运行多次验证不会崩溃且返回 bool
	for i in range(20):
		var result := RWPH.try_dodge(p)
		assert_bool(result is bool).is_true()

# ---------- 受伤修正 ----------

func test_on_player_take_damage_no_passive() -> void:
	var p := _make_player()
	var e := _make_enemy()
	assert_int(RWPH.on_player_take_damage(p, 30, e)).is_equal(30)

func test_on_player_take_damage_earth_armor() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_earth_armor", true)
	assert_int(RWPH.on_player_take_damage(p, 30, e)).is_equal(26)

func test_on_player_take_damage_earth_armor_floor_zero() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_earth_armor", true)
	assert_int(RWPH.on_player_take_damage(p, 2, e)).is_equal(0)

func test_on_player_take_damage_immortal_life() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_immortal_life", true)
	p.health.current_life = 5
	p.health.max_life = 100
	# 受到 10 点伤害，但生命值不会低于 1
	assert_int(RWPH.on_player_take_damage(p, 10, e)).is_equal(4)

func test_on_player_take_damage_terrible_rage() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_terrible_rage", true)
	# 狂暴：受伤 +15%
	assert_int(RWPH.on_player_take_damage(p, 100, e)).is_equal(115)

# ---------- 伤害减免 ----------

func test_get_damage_reduce_pct_no_passive() -> void:
	var p := _make_player()
	assert_float(RWPH.get_damage_reduce_pct(p)).is_equal_approx(0.0, 0.001)

func test_get_damage_reduce_pct_perfect_liberation() -> void:
	var p := _make_player()
	p.set_passive("rune_word_perfect_liberation", true)
	assert_float(RWPH.get_damage_reduce_pct(p)).is_equal_approx(0.15, 0.001)

# ---------- 控制免疫 ----------

func test_has_cc_immune_no_passive() -> void:
	var p := _make_player()
	assert_bool(RWPH.has_cc_immune(p)).is_false()

func test_has_cc_immune_with_passive() -> void:
	var p := _make_player()
	p.set_passive("rune_word_perfect_liberation", true)
	assert_bool(RWPH.has_cc_immune(p)).is_true()

func test_has_fear_immune_no_passive() -> void:
	var p := _make_player()
	assert_bool(RWPH.has_fear_immune(p)).is_false()

func test_has_fear_immune_with_passive() -> void:
	var p := _make_player()
	p.set_passive("rune_word_brave_spell", true)
	assert_bool(RWPH.has_fear_immune(p)).is_true()

# ---------- Tick 被动 ----------

func test_on_player_tick_holy_bonus_heals() -> void:
	var p := _make_player()
	p.set_passive("rune_word_holy_bonus", true)
	p.health.current_life = 50
	p.health.max_life = 100
	# 3 hp/sec → 1 sec tick
	RWPH.on_player_tick(p, 1.0)
	assert_int(p.health.current_life).is_equal(53)

func test_on_player_tick_immortal_life_heals() -> void:
	var p := _make_player()
	p.set_passive("rune_word_immortal_life", true)
	p.health.current_life = 50
	p.health.max_life = 100
	# 5 hp/sec → 1 sec tick
	RWPH.on_player_tick(p, 1.0)
	assert_int(p.health.current_life).is_equal(55)

func test_on_player_tick_no_passive_does_nothing() -> void:
	var p := _make_player()
	p.health.current_life = 50
	RWPH.on_player_tick(p, 1.0)
	assert_int(p.health.current_life).is_equal(50)

func test_on_player_tick_does_not_exceed_max() -> void:
	var p := _make_player()
	p.set_passive("rune_word_holy_bonus", true)
	p.health.current_life = 99
	p.health.max_life = 100
	RWPH.on_player_tick(p, 1.0)
	assert_int(p.health.current_life).is_equal(100)

# ---------- 空值安全 ----------

func test_on_player_hit_enemy_null_player() -> void:
	var e := _make_enemy()
	RWPH.on_player_hit_enemy(null, e, Vector3.ZERO, 10)
	assert_bool(true).is_true()

func test_on_player_hit_enemy_null_enemy() -> void:
	var p := _make_player()
	RWPH.on_player_hit_enemy(p, null, Vector3.ZERO, 10)
	assert_bool(true).is_true()

func test_on_player_take_damage_null_player() -> void:
	assert_int(RWPH.on_player_take_damage(null, 30, null)).is_equal(30)

func test_on_player_tick_null_player() -> void:
	RWPH.on_player_tick(null, 1.0)
	assert_bool(true).is_true()

func test_try_dodge_null_player() -> void:
	assert_bool(RWPH.try_dodge(null)).is_false()

func test_get_outgoing_damage_mult_null_player() -> void:
	var e := _make_enemy()
	assert_float(RWPH.get_outgoing_damage_mult(null, e)).is_equal_approx(1.0, 0.001)

# ---------- 静态状态重置 ----------

func test_reset_static_state_clears_karma() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_karmic_justice", true)
	RWPH.on_player_hit_enemy(p, e, Vector3.ZERO, 10)
	# 确认有层数
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_greater(1.0)
	# 重置
	RWPH.reset_static_state()
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.0, 0.001)

func test_on_enemy_killed_clears_karma_stack() -> void:
	var p := _make_player()
	var e := _make_enemy()
	p.set_passive("rune_word_karmic_justice", true)
	RWPH.on_player_hit_enemy(p, e, Vector3.ZERO, 10)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_greater(1.0)
	# 击杀后清除
	RWPH.on_enemy_killed(p, e, Vector3.ZERO)
	assert_float(RWPH.get_outgoing_damage_mult(p, e)).is_equal_approx(1.0, 0.001)
