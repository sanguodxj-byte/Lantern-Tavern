extends GdUnitTestSuite
## 状态效果系统（StatusEffectSystem）测试套件。
## 覆盖：施加/刷新/过期/DoT伤害/速度修正/防御修正/闪避修正/受击增伤。

const SES := preload("res://globals/combat/status_effect_system.gd")

## 模拟敌人（仅包含 SES 所需的属性与方法）
class MockEnemy:
	extends Node
	var combat_debuffs: Dictionary = {}
	var health: MockHealth

class MockHealth:
	extends Node
	var current_life: int = 100
	var max_life: int = 100
	var _is_dead: bool = false
	func take_damage(dmg: int) -> void:
		current_life = maxi(0, current_life - dmg)
		if current_life <= 0:
			_is_dead = true
	func is_dead() -> bool:
		return _is_dead
	func heal(amount: int) -> void:
		current_life = mini(max_life, current_life + amount)

func _make_enemy() -> MockEnemy:
	var e := MockEnemy.new()
	e.health = MockHealth.new()
	e.add_child(e.health)
	return auto_free(e)

# ---------- 施加与刷新 ----------

func test_apply_status_adds_to_combat_debuffs() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_burn", 3.0)
	assert_bool(e.combat_debuffs.has("se_burn")).is_true()
	assert_float(float(e.combat_debuffs["se_burn"]["remaining"])).is_equal_approx(3.0, 0.01)

func test_apply_status_refresh_takes_longer_duration() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_burn", 2.0)
	SES.apply_status(e, "se_burn", 5.0)
	assert_float(float(e.combat_debuffs["se_burn"]["remaining"])).is_equal_approx(5.0, 0.01)

func test_apply_status_with_custom_value() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_slow", 3.0, 0.3)
	assert_float(float(e.combat_debuffs["se_slow"]["value"])).is_equal_approx(0.3, 0.01)

func test_apply_status_null_enemy_does_not_crash() -> void:
	SES.apply_status(null, "se_burn", 3.0)
	assert_bool(true).is_true()

# ---------- 过期与清除 ----------

func test_process_tick_removes_expired_status() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_burn", 1.0)
	SES.process_tick(e, 1.5)
	assert_bool(e.combat_debuffs.has("se_burn")).is_false()

func test_process_tick_decrements_remaining() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_slow", 5.0, 0.5)
	SES.process_tick(e, 1.0)
	assert_float(float(e.combat_debuffs["se_slow"]["remaining"])).is_equal_approx(4.0, 0.01)

func test_clear_all_statuses_only_removes_se_prefix() -> void:
	var e := _make_enemy()
	e.combat_debuffs = {"se_burn": {"remaining": 3.0}, "slow": {"remaining": 2.0, "value": 30}}
	SES.clear_all_statuses(e)
	assert_bool(e.combat_debuffs.has("se_burn")).is_false()
	assert_bool(e.combat_debuffs.has("slow")).is_true()

# ---------- DoT 伤害 ----------

func test_dot_tick_deals_damage() -> void:
	var e := _make_enemy()
	e.health.current_life = 50
	e.health.max_life = 50
	SES.apply_status(e, "se_burn", 5.0)
	# burn: 4 dps, tick_interval=1.0
	SES.process_tick(e, 1.0)
	assert_int(e.health.current_life).is_equal(46)

func test_dot_with_custom_dps() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_poison", 5.0, 10.0)
	# custom dps=10, tick_interval=1.0
	SES.process_tick(e, 1.0)
	assert_int(e.health.current_life).is_equal(90)

func test_dot_does_not_tick_before_interval() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_choke", 5.0, 2.0)
	# choke: tick_interval=1.5
	SES.process_tick(e, 1.0)
	assert_int(e.health.current_life).is_equal(100)

# ---------- 速度修正 ----------

func test_speed_multiplier_no_status() -> void:
	var e := _make_enemy()
	assert_float(SES.get_speed_multiplier(e)).is_equal_approx(1.0, 0.01)

func test_speed_multiplier_slow() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_slow", 3.0, 0.5)
	assert_float(SES.get_speed_multiplier(e)).is_equal_approx(0.5, 0.01)

func test_speed_multiplier_ensnare_is_zero() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_ensnare", 3.0)
	assert_float(SES.get_speed_multiplier(e)).is_equal_approx(0.0, 0.01)

func test_speed_multiplier_fear_increases() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_fear", 3.0)
	assert_float(SES.get_speed_multiplier(e)).is_equal_approx(1.2, 0.01)

# ---------- 防御修正 ----------

func test_defense_penalty_no_status() -> void:
	var e := _make_enemy()
	assert_int(SES.get_defense_penalty(e)).is_equal(0)

func test_defense_penalty_armor_break() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_armor_break", 3.0, 8)
	assert_int(SES.get_defense_penalty(e)).is_equal(8)

func test_defense_penalty_sunder_is_large() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_sunder", 3.0)
	assert_int(SES.get_defense_penalty(e)).is_greater_equal(999)

# ---------- 闪避修正 ----------

func test_evade_penalty_no_status() -> void:
	var e := _make_enemy()
	assert_float(SES.get_evade_penalty(e)).is_equal_approx(0.0, 0.01)

func test_evade_penalty_blind() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_blind", 3.0)
	assert_float(SES.get_evade_penalty(e)).is_equal_approx(1.0, 0.01)

# ---------- 受击增伤 ----------

func test_incoming_damage_mult_no_status() -> void:
	var e := _make_enemy()
	assert_float(SES.get_incoming_damage_mult(e)).is_equal_approx(1.0, 0.01)

func test_incoming_damage_mult_blind() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_blind", 3.0)
	assert_float(SES.get_incoming_damage_mult(e)).is_equal_approx(1.25, 0.01)

func test_incoming_damage_mult_fear() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_fear", 3.0)
	assert_float(SES.get_incoming_damage_mult(e)).is_equal_approx(1.30, 0.01)

# ---------- 查询接口 ----------

func test_has_status() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_burn", 3.0)
	assert_bool(SES.has_status(e, "se_burn")).is_true()
	assert_bool(SES.has_status(e, "se_poison")).is_false()

func test_get_aura_type_mapping() -> void:
	assert_str(SES.get_aura_type("se_burn")).is_equal("burn")
	assert_str(SES.get_aura_type("se_poison")).is_equal("poison")
	assert_str(SES.get_aura_type("se_slow")).is_equal("slow")
	assert_str(SES.get_aura_type("se_blind")).is_equal("blind")
	assert_str(SES.get_aura_type("se_nonexistent")).is_empty()

func test_is_dot_status() -> void:
	assert_bool(SES.is_dot_status("se_burn")).is_true()
	assert_bool(SES.is_dot_status("se_poison")).is_true()
	assert_bool(SES.is_dot_status("se_corrupt")).is_true()
	assert_bool(SES.is_dot_status("se_choke")).is_true()
	assert_bool(SES.is_dot_status("se_slow")).is_false()

func test_get_active_statuses() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_burn", 3.0)
	SES.apply_status(e, "se_slow", 2.0, 0.5)
	var active := SES.get_active_statuses(e)
	assert_int(active.size()).is_equal(2)
	# 验证不包含非 se_ 前缀的 debuff
	e.combat_debuffs["slow"] = {"remaining": 2.0, "value": 30}
	active = SES.get_active_statuses(e)
	assert_int(active.size()).is_equal(2)

# ---------- 元素伤害加成 ----------

func test_elemental_damage_mult_wet_electric() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_wet", 3.0)
	assert_float(SES.get_elemental_damage_mult(e, "electric")).is_equal_approx(1.50, 0.01)

func test_elemental_damage_mult_wet_ice() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_wet", 3.0)
	assert_float(SES.get_elemental_damage_mult(e, "ice")).is_equal_approx(1.25, 0.01)

func test_elemental_damage_mult_no_wet() -> void:
	var e := _make_enemy()
	assert_float(SES.get_elemental_damage_mult(e, "electric")).is_equal_approx(1.0, 0.01)

# ---------- 暴击加成 ----------

func test_crit_bonus_blind() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_blind", 3.0)
	assert_float(SES.get_crit_bonus_vs_enemy(e)).is_equal_approx(0.10, 0.01)

func test_crit_bonus_fear() -> void:
	var e := _make_enemy()
	SES.apply_status(e, "se_fear", 3.0)
	assert_float(SES.get_crit_bonus_vs_enemy(e)).is_equal_approx(0.15, 0.01)

func test_crit_bonus_no_status() -> void:
	var e := _make_enemy()
	assert_float(SES.get_crit_bonus_vs_enemy(e)).is_equal_approx(0.0, 0.01)
