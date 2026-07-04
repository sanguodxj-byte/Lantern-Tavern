extends GdUnitTestSuite
## MilestoneEffects 里程碑被动效果测试
## 验证：18 个被动效果函数在解锁/未解锁状态下的修正值

const ME := preload("res://globals/milestone_effects.gd")
var AP

func before() -> void:
	AP = Engine.get_main_loop().root.get_node("AttrPanel")
	if AP:
		AP.reset()

func after() -> void:
	AP = Engine.get_main_loop().root.get_node("AttrPanel")
	if AP:
		AP.reset()

# 辅助：强制解锁某里程碑（先确保 reset 干净再解锁）
func _unlock(milestone_id: String) -> void:
	if AP:
		AP.reset()
		AP.unlocked_milestones.append(milestone_id)

# ---------- 受击路径修正 ----------

func test_thick_skin_not_unlocked_no_change() -> void:
	if AP: AP.reset()
	assert_int(ME.apply_thick_skin(10)).is_equal(10)

func test_thick_skin_unlocked_reduces_2() -> void:
	_unlock("厚实皮肤")
	assert_int(ME.apply_thick_skin(10)).is_equal(8)

func test_thick_skin_floor_1() -> void:
	_unlock("厚实皮肤")
	assert_int(ME.apply_thick_skin(2)).is_equal(1)
	assert_int(ME.apply_thick_skin(1)).is_equal(1)

func test_elemental_aegis_not_spell_no_change() -> void:
	_unlock("元素护壳")
	assert_int(ME.apply_elemental_aegis(10, false)).is_equal(10)

func test_elemental_aegis_spell_reduces_4() -> void:
	_unlock("元素护壳")
	assert_int(ME.apply_elemental_aegis(10, true)).is_equal(6)

func test_elemental_aegis_floor_1() -> void:
	_unlock("元素护壳")
	assert_int(ME.apply_elemental_aegis(3, true)).is_equal(1)

func test_sidestep_not_melee_never_triggers() -> void:
	_unlock("侧垫步")
	for i in range(100):
		assert_bool(ME.try_sidestep(false)).is_false()

func test_sidestep_not_unlocked_never_triggers() -> void:
	# 显式 reset 确保未解锁状态
	if AP:
		AP.reset()
	for i in range(100):
		assert_bool(ME.try_sidestep(true)).is_false()

func test_sidestep_unlocked_can_trigger() -> void:
	_unlock("侧垫步")
	var triggered: bool = false
	for i in range(500):
		if ME.try_sidestep(true):
			triggered = true
			break
	assert_bool(triggered).is_true()

func test_negate_flank_bonus_not_unlocked() -> void:
	if AP: AP.reset()
	assert_bool(ME.negate_flank_bonus()).is_false()

func test_negate_flank_bonus_unlocked() -> void:
	_unlock("直觉闪避")
	assert_bool(ME.negate_flank_bonus()).is_true()

# ---------- 攻击路径修正 ----------

func test_heavy_stride_not_melee_no_change() -> void:
	_unlock("重力击")
	assert_int(ME.apply_heavy_stride(100, false)).is_equal(100)

func test_heavy_stride_unlocked_melee_5pct() -> void:
	_unlock("重力击")
	assert_int(ME.apply_heavy_stride(100, true)).is_equal(105)

func test_sharpshooter_not_ranged_no_change() -> void:
	_unlock("神射手")
	assert_float(ME.apply_sharpshooter(10.0, false)).is_equal(10.0)

func test_sharpshooter_unlocked_ranged_plus_10() -> void:
	_unlock("神射手")
	assert_float(ME.apply_sharpshooter(10.0, true)).is_equal(20.0)

func test_penetrating_strike_not_ranged_no_change() -> void:
	_unlock("穿透打击")
	assert_float(ME.apply_penetrating_strike(0.0, false)).is_equal(0.0)

func test_penetrating_strike_unlocked_ranged_10pct() -> void:
	_unlock("穿透打击")
	assert_float(ME.apply_penetrating_strike(0.0, true)).is_equal(10.0)

func test_penetrating_strike_keeps_higher_value() -> void:
	_unlock("穿透打击")
	assert_float(ME.apply_penetrating_strike(15.0, true)).is_equal(15.0)

func test_knockback_chance_not_melee_never() -> void:
	_unlock("震退")
	for i in range(100):
		assert_float(ME.try_knockback_chance(false)).is_equal(0.0)

func test_knockback_chance_not_unlocked_never() -> void:
	if AP: AP.reset()
	for i in range(100):
		assert_float(ME.try_knockback_chance(true)).is_equal(0.0)

func test_knockback_chance_unlocked_can_trigger() -> void:
	_unlock("震退")
	var triggered: bool = false
	for i in range(500):
		if ME.try_knockback_chance(true) > 0:
			triggered = true
			break
	assert_bool(triggered).is_true()

func test_knockback_chance_value_is_1_5_meters() -> void:
	_unlock("震退")
	for i in range(500):
		var kb: float = ME.try_knockback_chance(true)
		if kb > 0:
			assert_float(kb).is_equal(1.5)
			return

func test_mana_surge_crit_not_spell_no_change() -> void:
	_unlock("魔力涌流")
	assert_float(ME.apply_mana_surge_crit(10.0, false)).is_equal(10.0)

func test_mana_surge_crit_unlocked_spell_plus_8() -> void:
	_unlock("魔力涌流")
	assert_float(ME.apply_mana_surge_crit(10.0, true)).is_equal(18.0)

func test_mana_focus_cd_reset_not_spell_never() -> void:
	_unlock("魔力凝息")
	for i in range(100):
		assert_bool(ME.try_mana_focus_cd_reset(false)).is_false()

func test_mana_focus_cd_reset_unlocked_can_trigger() -> void:
	_unlock("魔力凝息")
	var triggered: bool = false
	for i in range(500):
		if ME.try_mana_focus_cd_reset(true):
			triggered = true
			break
	assert_bool(triggered).is_true()

# ---------- 移动路径修正 ----------

func test_move_speed_multiplier_base() -> void:
	if AP: AP.reset()
	assert_float(ME.move_speed_multiplier()).is_equal(1.0)

func test_move_speed_multiplier_with_fleet_foot() -> void:
	_unlock("轻捷之行")
	assert_float(ME.move_speed_multiplier()).is_equal(1.10)

# ---------- 休息/恢复路径 ----------

func test_inn_rest_extra_heal_not_unlocked() -> void:
	if AP: AP.reset()
	assert_int(ME.inn_rest_extra_heal(200)).is_equal(0)

func test_inn_rest_extra_heal_unlocked_25pct() -> void:
	_unlock("复苏之息")
	assert_int(ME.inn_rest_extra_heal(200)).is_equal(50)

func test_inn_rest_extra_heal_rounding() -> void:
	_unlock("复苏之息")
	assert_int(ME.inn_rest_extra_heal(100)).is_equal(25)
	assert_int(ME.inn_rest_extra_heal(99)).is_equal(25)  # round(24.75)=25

# ---------- 视野/探索 ----------

func test_alertness_bonus_not_unlocked() -> void:
	if AP: AP.reset()
	var b: Dictionary = ME.alertness_bonus()
	assert_float(b["view_bonus"]).is_equal(0.0)
	assert_float(b["trap_bonus"]).is_equal(0.0)

func test_alertness_bonus_unlocked() -> void:
	_unlock("警觉")
	var b: Dictionary = ME.alertness_bonus()
	assert_float(b["view_bonus"]).is_equal(1.5)
	assert_float(b["trap_bonus"]).is_equal(20.0)

# ---------- 暴击率修正 ----------

func test_crit_rate_bonus_not_unlocked() -> void:
	if AP: AP.reset()
	assert_float(ME.crit_rate_bonus()).is_equal(0.0)

func test_crit_rate_bonus_unlocked() -> void:
	_unlock("弱点洞察")
	assert_float(ME.crit_rate_bonus()).is_equal(5.0)

# ---------- 双手武器伤害 ----------

func test_two_hand_damage_mult_bonus_not_two_hand() -> void:
	_unlock("蛮力负荷")
	assert_float(ME.two_hand_damage_mult_bonus(false)).is_equal(0.0)

func test_two_hand_damage_mult_bonus_not_unlocked() -> void:
	if AP: AP.reset()
	assert_float(ME.two_hand_damage_mult_bonus(true)).is_equal(0.0)

func test_two_hand_damage_mult_bonus_unlocked() -> void:
	_unlock("蛮力负荷")
	assert_float(ME.two_hand_damage_mult_bonus(true)).is_equal(0.05)
