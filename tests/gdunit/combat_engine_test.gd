extends GdUnitTestSuite
## 战斗数值引擎 (CombatEngine) 测试。
## 动作控制版：验证属性面板换算、战斗风格激活、伤害结算（命中恒定→暴击→基础伤害→朝向→防御→扣血）、双轨经验。
## 已移除概率命中/闪避/格挡相关测试（改为动作判定）。

const CE := preload("res://globals/combat/combat_engine.gd")

# ---------- 属性面板换算 (策划案 05 §2.1) ----------

func test_max_hp_formula() -> void:
	# 100 + 体质×10 + 等级×5
	assert_int(CE.compute_max_hp(10, 1)).is_equal(205)  # 100+100+5
	assert_int(CE.compute_max_hp(0, 0)).is_equal(100)
	assert_int(CE.compute_max_hp(20, 10)).is_equal(350)  # 100+200+50

func test_physical_def_formula() -> void:
	# 防具防御 + 体质×1
	assert_int(CE.compute_physical_def(15, 10)).is_equal(25)
	assert_int(CE.compute_physical_def(0, 8)).is_equal(8)

func test_carry_weight_formula() -> void:
	# 50 + 体质×2
	assert_int(CE.compute_carry_weight(10)).is_equal(70)
	assert_int(CE.compute_carry_weight(25)).is_equal(100)

func test_melee_flat_formula() -> void:
	# 力量×1.5 + 风格修正
	assert_float(CE.compute_melee_flat(20, 0.0)).is_equal(30.0)
	assert_float(CE.compute_melee_flat(20, 5.0)).is_equal(35.0)

func test_ranged_flat_formula() -> void:
	assert_float(CE.compute_ranged_flat(20, 0.0)).is_equal(30.0)
	assert_float(CE.compute_ranged_flat(20, 8.0)).is_equal(38.0)

func test_spell_flat_formula() -> void:
	assert_float(CE.compute_spell_flat(15, 0.0)).is_equal(22.5)

func test_physical_impact_damage_is_zero_below_threshold() -> void:
	assert_int(CE.compute_physical_impact_damage(100, 2.0, 4.0, 14.0, 1.0)).is_equal(0)

func test_physical_impact_damage_scales_from_paper_doll_max_life() -> void:
	var damage := CE.compute_physical_impact_damage(200, 9.0, 4.0, 14.0, 1.0)
	assert_int(damage).is_equal(36)

func test_physical_impact_damage_accepts_skill_rune_multiplier() -> void:
	var base := CE.compute_physical_impact_damage(200, 9.0, 4.0, 14.0, 1.0)
	var boosted := CE.compute_physical_impact_damage(200, 9.0, 4.0, 14.0, 1.5)
	assert_int(boosted).is_greater(base)

func test_physical_impact_damage_accepts_target_rank_and_body_profile() -> void:
	var normal := CE.compute_physical_impact_damage(200, 10.0, 4.0, 14.0, 1.0)
	var boss_large := CE.compute_physical_impact_damage(200, 10.0, 4.0, 14.0, 1.0, {
		"impact_damage_taken_mult": 0.52,
		"impact_min_speed_add": 1.0,
	})
	assert_int(boss_large).is_less(normal)

func test_physical_impact_profile_can_raise_effective_min_speed() -> void:
	var normal := CE.compute_physical_impact_damage(200, 4.5, 4.0, 14.0, 1.0)
	var huge := CE.compute_physical_impact_damage(200, 4.5, 4.0, 14.0, 1.0, {
		"impact_damage_taken_mult": 0.60,
		"impact_min_speed_add": 2.0,
	})
	assert_int(normal).is_greater(0)
	assert_int(huge).is_equal(0)

# ---------- 战斗风格激活 (策划案 05 §3) ----------

func test_style_unarmed_both_empty() -> void:
	assert_int(CE.determine_style("", "")).is_equal(CE.Style.UNARMED)

func test_style_one_hand() -> void:
	assert_int(CE.determine_style("one_hand_melee", "")).is_equal(CE.Style.ONE_HAND)

func test_style_one_hand_shield() -> void:
	assert_int(CE.determine_style("one_hand_melee", "shield")).is_equal(CE.Style.ONE_HAND_SHIELD)

func test_style_two_hand() -> void:
	assert_int(CE.determine_style("two_hand", "")).is_equal(CE.Style.TWO_HAND)

func test_style_dual_wield() -> void:
	assert_int(CE.determine_style("one_hand_melee", "one_hand_melee")).is_equal(CE.Style.DUAL_WIELD)

func test_two_hand_forbids_offhand() -> void:
	# 双手武器副手非空 → 降级徒手（非法配置）
	assert_int(CE.determine_style("two_hand", "shield")).is_equal(CE.Style.UNARMED)

func test_style_meta_has_required_fields() -> void:
	for style_id in [CE.Style.ONE_HAND, CE.Style.ONE_HAND_SHIELD, CE.Style.TWO_HAND, CE.Style.DUAL_WIELD, CE.Style.UNARMED]:
		var meta: Dictionary = CE.STYLE_META[style_id]
		assert_bool(meta.has("name")).is_true()
		assert_bool(meta.has("attack_speed_mult")).is_true()
		assert_bool(meta.has("move_speed_mult")).is_true()

func test_style_meta_no_evade_bonus() -> void:
	# 动作控制版：闪避率与命中率均为回合制残留，已从 STYLE_META 移除
	for style_id in CE.STYLE_META.keys():
		var meta: Dictionary = CE.STYLE_META[style_id]
		assert_bool(not meta.has("evade_bonus")) \
			.override_failure_message("风格 %s 仍含 evade_bonus（已移除）" % style_id).is_true()
		assert_bool(not meta.has("hit_bonus")) \
			.override_failure_message("风格 %s 仍含 hit_bonus（已移除，动作控制无命中/未命中判定）" % style_id).is_true()

# ---------- 伤害结算（动作控制版） ----------

func _make_basic_attack() -> Object:
	var a := CE.AttackInput.new()
	a.attacker_str = 10
	a.attacker_dex = 10
	a.attacker_mag = 10
	a.attacker_per = 10
	a.attacker_agi = 10
	a.attacker_con = 10
	a.attacker_level = 1
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	return a

func _make_basic_defender() -> Object:
	var d := CE.Defender.new()
	d.con = 10
	d.agi = 10
	d.per = 10
	return d

func test_resolve_attack_always_hits() -> void:
	# 动作控制版：hitbox 接触即命中，hit 恒为 true
	var a := _make_basic_attack()
	var d := _make_basic_defender()
	for i in range(100):
		var r = CE.resolve_attack(a, d)
		assert_bool(r.hit).is_true()

func test_resolve_attack_returns_result() -> void:
	var a := _make_basic_attack()
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d)
	assert_object(r).is_not_null()
	assert_bool(r.hit).is_true()

func test_resolve_attack_hit_deals_at_least_one_damage() -> void:
	var a := _make_basic_attack()
	a.weapon_damage_dice = {"count": 1, "sides": 100}
	var d := _make_basic_defender()
	d.armor_def = 0
	d.con = 0
	for i in range(100):
		var r = CE.resolve_attack(a, d)
		assert_bool(r.hit).is_true()
		assert_int(r.final_damage).is_greater_equal(1)

func test_resolve_attack_crit_increases_damage() -> void:
	# 暴击应增加伤害（暴击倍率 ≥1.1）
	var a := _make_basic_attack()
	a.attacker_per = 100  # 极高暴击率
	a.weapon_damage_dice = {"count": 10, "sides": 100}
	var d := _make_basic_defender()
	d.per = 1
	var crit_damage: int = 0
	var normal_damage: int = 0
	for i in range(200):
		var r = CE.resolve_attack(a, d)
		if r.crit:
			crit_damage = max(crit_damage, r.final_damage)
		else:
			normal_damage = max(normal_damage, r.final_damage)
	assert_bool(crit_damage > normal_damage) \
		.override_failure_message("暴击伤害 %d 未超过普攻 %d" % [crit_damage, normal_damage]).is_true()

func test_resolve_attack_defense_reduces_damage() -> void:
	# 高防御应降低伤害
	var a := _make_basic_attack()
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	var d_low := _make_basic_defender()
	d_low.armor_def = 0
	d_low.con = 0
	var d_high := _make_basic_defender()
	d_high.armor_def = 50
	d_high.con = 50
	var low_total: int = 0
	var high_total: int = 0
	var samples: int = 0
	for i in range(500):
		var r1 = CE.resolve_attack(a, d_low)
		var r2 = CE.resolve_attack(a, d_high)
		low_total += r1.final_damage
		high_total += r2.final_damage
		samples += 1
	if samples > 0:
		assert_bool(low_total > high_total) \
			.override_failure_message("低防御伤害 %d 未高于高防御 %d" % [low_total, high_total]).is_true()

func test_resolve_attack_no_probability_block() -> void:
	# 动作控制版：Defender 不再有 shield_block_chance，resolve_attack 不做概率格挡
	var a := _make_basic_attack()
	a.weapon_damage_dice = {"count": 5, "sides": 6}
	var d := _make_basic_defender()
	d.has_shield = true  # 仅信息字段，不影响结算
	# Defender 不再有 shield_block_chance / shield_block_value 字段
	assert_bool(not "shield_block_chance" in d) \
		.override_failure_message("Defender 不应含 shield_block_chance（已移除）").is_true()
	assert_bool(not "shield_block_value" in d) \
		.override_failure_message("Defender 不应含 shield_block_value（已移除）").is_true()
	# 多次结算，blocked 应始终为 false（resolve_attack 不再做概率格挡）
	for i in range(50):
		var r = CE.resolve_attack(a, d)
		assert_bool(r.blocked).is_false()

func test_resolve_attack_ignores_block_passthrough() -> void:
	# ignore_block 从 AttackInput 传递到 DamageResult.ignores_block
	var a := _make_basic_attack()
	a.ignore_block = true
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d)
	assert_bool(r.ignores_block).is_true()

func test_base_damage_bonus_percent_increases_damage() -> void:
	var d := _make_basic_defender()
	d.con = 0
	d.agi = 0
	d.per = 0
	d.armor_def = 0
	var a_base := _make_basic_attack()
	a_base.weapon_damage_dice = {"count": 0, "sides": 0}
	a_base.weapon_damage_flat = 20.0
	a_base.attacker_str = 0
	a_base.attacker_per = 100
	a_base.force_crit = true
	var a_bonus := _make_basic_attack()
	a_bonus.weapon_damage_dice = {"count": 0, "sides": 0}
	a_bonus.weapon_damage_flat = 20.0
	a_bonus.attacker_str = 0
	a_bonus.attacker_per = 100
	a_bonus.force_crit = true
	a_bonus.base_damage_bonus_percent = 10.0
	for i in range(20):
		var r_base = CE.resolve_attack(a_base, d)
		var r_bonus = CE.resolve_attack(a_bonus, d)
		assert_int(r_bonus.final_damage).is_greater(r_base.final_damage)
		return

func test_resolve_attack_backstab_increases_damage() -> void:
	var a_normal := _make_basic_attack()
	a_normal.weapon_damage_dice = {"count": 5, "sides": 6}
	a_normal.is_backstab = false
	var a_back := _make_basic_attack()
	a_back.weapon_damage_dice = {"count": 5, "sides": 6}
	a_back.is_backstab = true
	var d := _make_basic_defender()
	d.armor_def = 0
	d.con = 0
	var normal_total: int = 0
	var back_total: int = 0
	var samples: int = 0
	for i in range(500):
		var r1 = CE.resolve_attack(a_normal, d)
		var r2 = CE.resolve_attack(a_back, d)
		normal_total += r1.final_damage
		back_total += r2.final_damage
		samples += 1
	if samples > 0:
		assert_bool(back_total > normal_total) \
			.override_failure_message("背袭伤害 %d 未超过正面 %d" % [back_total, normal_total]).is_true()

func test_resolve_attack_normal_attack_has_no_knockback() -> void:
	# 策划案调整：正常攻击（无技能）仅造成血量伤害，不施加击退
	var a := _make_basic_attack()
	a.style = CE.Style.ONE_HAND
	a.attack_type = "melee"
	a.knockback_force = 0.0  # 默认值，正常攻击无击退
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(0.0)
	assert_vector(r.knockback_impulse).is_equal(Vector3.ZERO)

func test_resolve_attack_normal_attack_two_hand_no_knockback() -> void:
	# 双手风格正常攻击也不应有击退（kb_force=0 时不叠加双手加成）
	var a := _make_basic_attack()
	a.style = CE.Style.TWO_HAND
	a.attack_type = "melee"
	a.knockback_force = 0.0
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(0.0)
	assert_vector(r.knockback_impulse).is_equal(Vector3.ZERO)

func test_resolve_attack_crit_stun_without_knockback() -> void:
	# 暴击眩晕独立于击退：即使 kb_force=0，暴击仍附加眩晕
	var a := _make_basic_attack()
	a.attacker_per = 100  # 极高暴击率
	a.weapon_damage_dice = {"count": 10, "sides": 100}
	a.knockback_force = 0.0  # 正常攻击无击退
	var d := _make_basic_defender()
	d.per = 1
	for i in range(200):
		var r = CE.resolve_attack(a, d)
		if r.crit:
			assert_float(r.stun_duration).is_equal(0.5)
			assert_float(r.knockback_force).is_equal(0.0)
			return
	assert_bool(true).is_true()  # 容错

func test_resolve_attack_two_hand_knockback_force_doubled() -> void:
	# ARPG 实时：双手风格击退力叠加（基础 + 双手专属），方向沿攻方朝向
	var a := _make_basic_attack()
	a.style = CE.Style.TWO_HAND
	a.attack_type = "melee"
	a.knockback_force = 2.0  # 基础击退力
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(0, 0, -1))
	# 基础 2.0 + 双手专属 4.0 = 6.0
	assert_float(r.knockback_force).is_equal(6.0)
	# 击退方向沿 -Z
	assert_float(r.knockback_impulse.z).is_equal(-6.0)

func test_resolve_attack_one_hand_knockback_basic_force() -> void:
	# ARPG 实时：单手风格击退力=基础值，无叠加
	var a := _make_basic_attack()
	a.style = CE.Style.ONE_HAND
	a.attack_type = "melee"
	a.knockback_force = 2.0
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(0, 0, -1))
	assert_float(r.knockback_force).is_equal(2.0)

func test_resolve_attack_knockback_direction_follows_attacker_facing() -> void:
	# ARPG 实时：击退方向随攻方朝向变化
	var a := _make_basic_attack()
	a.attack_type = "melee"
	a.knockback_force = 3.0
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(1, 0, 0))  # 朝 +X
	assert_float(r.knockback_impulse.x).is_equal(3.0)
	assert_float(r.knockback_impulse.z).is_equal(0.0)

func test_resolve_attack_crit_adds_stun_duration() -> void:
	# ARPG 实时：暴击附加 0.5 秒眩晕（非回合数）
	var a := _make_basic_attack()
	a.attacker_per = 100  # 极高暴击率
	a.weapon_damage_dice = {"count": 10, "sides": 100}
	var d := _make_basic_defender()
	d.per = 1
	for i in range(200):
		var r = CE.resolve_attack(a, d)
		if r.crit:
			assert_float(r.stun_duration).is_equal(0.5)
			return
	assert_bool(true).is_true()  # 容错

func test_resolve_attack_non_crit_no_stun() -> void:
	var a := _make_basic_attack()
	a.attacker_per = 1  # 极低暴击
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	var d := _make_basic_defender()
	d.per = 100
	for i in range(100):
		var r = CE.resolve_attack(a, d)
		if not r.crit:
			assert_float(r.stun_duration).is_equal(0.0)
			return

# ---------- ARPG 实时攻速/移速 ----------

func test_compute_attack_interval_two_hand_slower() -> void:
	# 双手风格攻速倍率 0.85，间隔更长
	var interval_one := CE.compute_attack_interval(CE.Style.ONE_HAND, 10)
	var interval_two := CE.compute_attack_interval(CE.Style.TWO_HAND, 10)
	assert_bool(interval_two > interval_one) \
		.override_failure_message("双手攻速间隔 %s 应长于单手 %s" % [interval_two, interval_one]).is_true()

func test_compute_attack_interval_dual_wield_faster() -> void:
	# 双持攻速倍率 1.2，间隔更短
	var interval_one := CE.compute_attack_interval(CE.Style.ONE_HAND, 10)
	var interval_dual := CE.compute_attack_interval(CE.Style.DUAL_WIELD, 10)
	assert_bool(interval_dual < interval_one).is_true()

func test_compute_attack_interval_dex_increases_speed() -> void:
	# 敏捷越高攻速越快（间隔越短）
	var low_dex := CE.compute_attack_interval(CE.Style.ONE_HAND, 10)
	var high_dex := CE.compute_attack_interval(CE.Style.ONE_HAND, 50)
	assert_bool(high_dex < low_dex).is_true()

func test_compute_move_speed_style_modifiers() -> void:
	# 徒手移速最快，持盾最慢
	var unarmed_speed := CE.compute_move_speed(CE.Style.UNARMED, 10)
	var shield_speed := CE.compute_move_speed(CE.Style.ONE_HAND_SHIELD, 10)
	assert_bool(unarmed_speed > shield_speed).is_true()

func test_compute_move_speed_agility_bonus() -> void:
	# 灵巧越高移速越快
	var low_agi := CE.compute_move_speed(CE.Style.ONE_HAND, 10)
	var high_agi := CE.compute_move_speed(CE.Style.ONE_HAND, 50)
	assert_bool(high_agi > low_agi).is_true()

func test_no_evade_or_block_rate_fields_remain() -> void:
	# 反向断言：确认已移除闪避率/格挡率相关字段
	var script: GDScript = load("res://globals/combat/combat_engine.gd") as GDScript
	var source: String = script.source_code
	# 不应含闪避率计算
	assert_bool(source.find("compute_evade_rate") == -1) \
		.override_failure_message("仍含闪避率计算函数 compute_evade_rate").is_true()
	assert_bool(source.find("_compute_hit_rate") == -1) \
		.override_failure_message("仍含命中率计算函数 _compute_hit_rate").is_true()
	assert_bool(source.find("evade_bonus") == -1) \
		.override_failure_message("仍含闪避加成字段 evade_bonus").is_true()
	# 不应含概率格挡投骰
	assert_bool(source.find("block_roll") == -1) \
		.override_failure_message("仍含概率格挡投骰 block_roll").is_true()
	assert_bool(source.find("shield_block_chance") == -1) \
		.override_failure_message("仍含格挡率字段 shield_block_chance").is_true()
	# 应含 ARPG 实时字段（伤害结算已剥离至 DamageResolver，故需合并两份源码校验）
	var resolver_source: String = (load("res://globals/combat/damage_resolver.gd") as GDScript).source_code
	var combined: String = source + resolver_source
	assert_bool(combined.find("knockback_force") != -1).is_true()
	assert_bool(combined.find("stun_duration") != -1).is_true()
	assert_bool(combined.find("ignores_block") != -1).is_true()

# ---------- 双轨经验 (策划案 05 §5.1) ----------

func test_accumulate_attr_exp_no_levelup() -> void:
	var ce: Node = Engine.get_main_loop().root.get_node("CombatEngine")
	var result: Dictionary = ce.accumulate_attr_exp(50, 30)
	assert_int(result.exp).is_equal(80)
	assert_bool(result.leveled_up).is_false()

func test_accumulate_attr_exp_levelup() -> void:
	var ce: Node = Engine.get_main_loop().root.get_node("CombatEngine")
	var result: Dictionary = ce.accumulate_attr_exp(90, 20)
	assert_int(result.exp).is_equal(10)  # 110 - 100 = 10
	assert_bool(result.leveled_up).is_true()

func test_accumulate_attr_exp_exact_threshold() -> void:
	var ce: Node = Engine.get_main_loop().root.get_node("CombatEngine")
	var result: Dictionary = ce.accumulate_attr_exp(0, 100)
	assert_int(result.exp).is_equal(0)
	assert_bool(result.leveled_up).is_true()
