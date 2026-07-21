extends GdUnitTestSuite
## DamageResolver（伤害结算器组件）测试。
## 验证：
##  1) 组件自包含、可从 CombatEngine 外观层委托访问（CE.* 别名与包装函数）。
##  2) 物理冲量倍率（physical_impulse_multiplier）按 击退力 × 倍率 缩放冲量。
##  3) 法术伤害豁免物理冲量（倍率记录但不参与击退）。
##  4) compute_physical_impact_damage 在组件与外观层行为一致。
##  5) 既有「双手击退力叠加」等行为在默认倍率(1.0)下保持不变。

const DR := preload("res://globals/combat/damage_resolver.gd")
const CE := preload("res://globals/combat/combat_engine.gd")

# ---------- 构造辅助 ----------

static func _basic_attack() -> DR.AttackInput:
	var a := DR.AttackInput.new()
	a.attacker_str = 10
	a.attacker_dex = 10
	a.attacker_mag = 10
	a.attacker_per = 10
	a.attacker_agi = 10
	a.attacker_con = 10
	a.attacker_level = 1
	a.style = DR.Style.ONE_HAND
	a.attack_type = "melee"
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	return a

static func _basic_defender() -> DR.Defender:
	var d := DR.Defender.new()
	d.con = 10
	d.agi = 10
	d.per = 10
	d.armor_def = 0
	return d

# ---------- 1. 自包含 + 外观层委托 ----------

func test_component_is_self_contained_and_reachable_via_facade() -> void:
	# 组件直接可访问
	assert_object(DR).is_not_null()
	# 外观层别名可用（类型别名 + 委托函数）
	assert_object(CE.AttackInput.new()).is_not_null()
	assert_object(CE.DamageResult.new()).is_not_null()
	assert_int(CE.Style.TWO_HAND).is_equal(DR.Style.TWO_HAND)
	var r := CE.resolve_attack(_basic_attack(), _basic_defender(), Vector3(0, 0, -1))
	assert_object(r).is_not_null()
	assert_bool(r.hit).is_true()

func test_style_meta_and_determine_style_delegated() -> void:
	assert_int(CE.determine_style("two_hand", "")).is_equal(CE.Style.TWO_HAND)
	assert_float(float(CE.STYLE_META[CE.Style.TWO_HAND].get("knockback_force", 0.0))).is_equal(4.0)

# ---------- 2. 物理冲量倍率缩放 ----------

func test_physical_impulse_multiplier_scales_knockback_impulse() -> void:
	var a := _basic_attack()
	a.attack_type = "melee"
	a.knockback_force = 2.0
	a.physical_impulse_multiplier = 2.0  # 放大一倍冲量
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	# 最终冲量大小 = 2.0 × 2.0 = 4.0
	assert_float(r.knockback_force).is_equal(4.0)
	assert_float(r.knockback_impulse.z).is_equal(-4.0)
	assert_float(r.physical_impulse_multiplier).is_equal(2.0)

func test_physical_impulse_multiplier_less_than_one_shrinks_impulse() -> void:
	var a := _basic_attack()
	a.attack_type = "melee"
	a.knockback_force = 4.0
	a.physical_impulse_multiplier = 0.5
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(1, 0, 0))
	assert_float(r.knockback_force).is_equal(2.0)
	assert_float(r.knockback_impulse.x).is_equal(2.0)

func test_default_impulse_multiplier_keeps_legacy_behavior() -> void:
	# 默认倍率 1.0 不应改变既有数值
	var a := _basic_attack()
	a.attack_type = "melee"
	a.knockback_force = 3.0
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(3.0)
	assert_float(r.knockback_impulse.z).is_equal(-3.0)

# ---------- 3. 法术伤害豁免物理冲量 ----------

func test_spell_damage_exempts_physical_impulse() -> void:
	var a := _basic_attack()
	a.attack_type = "spell"
	a.knockback_force = 2.0
	a.physical_impulse_multiplier = 3.0  # 即便给了倍率，法术也不产生击退冲量
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_object(r.knockback_impulse).is_equal(Vector3.ZERO)
	assert_float(r.knockback_force).is_equal(0.0)
	# 倍率仍记录，便于下游读取（但不参与击退）
	assert_float(r.physical_impulse_multiplier).is_equal(3.0)

# ---------- 4. compute_physical_impact_damage 一致性 ----------

func test_physical_impact_damage_matches_between_component_and_facade() -> void:
	var via_dr := DR.compute_physical_impact_damage(200, 9.0, 4.0, 14.0, 1.5)
	var via_ce := CE.compute_physical_impact_damage(200, 9.0, 4.0, 14.0, 1.5)
	assert_int(via_dr).is_equal(via_ce)
	assert_int(via_dr).is_greater(0)

# ---------- 5. 回归：双手击退力叠加（默认倍率） ----------

func test_two_hand_knockback_still_stacks_with_default_multiplier() -> void:
	var a := _basic_attack()
	a.style = DR.Style.TWO_HAND
	a.attack_type = "melee"
	a.knockback_force = 2.0
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	# 基础 2.0 + 双手专属 4.0 = 6.0（默认倍率 1.0）
	assert_float(r.knockback_force).is_equal(6.0)
	assert_float(r.knockback_impulse.z).is_equal(-6.0)

# ---------- 6. 正常攻击无击退（策划案调整） ----------

func test_normal_attack_zero_knockback_produces_no_impulse() -> void:
	# 策划案调整：正常攻击 knockback_force 默认 0，不施加击退
	var a := _basic_attack()
	a.knockback_force = 0.0
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(0.0)
	assert_vector(r.knockback_impulse).is_equal(Vector3.ZERO)

func test_normal_attack_two_hand_zero_knockback_no_bonus() -> void:
	# kb_force=0 时不叠加双手击退加成
	var a := _basic_attack()
	a.style = DR.Style.TWO_HAND
	a.knockback_force = 0.0
	var d := _basic_defender()
	var r := DR.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(0.0)
	assert_vector(r.knockback_impulse).is_equal(Vector3.ZERO)

# ---------- 7. DTO 字段完备 ----------

func test_dto_carries_physical_impulse_multiplier_field() -> void:
	var a := DR.AttackInput.new()
	assert_float(a.physical_impulse_multiplier).is_equal(1.0)
	var r := DR.DamageResult.new()
	assert_float(r.physical_impulse_multiplier).is_equal(1.0)
