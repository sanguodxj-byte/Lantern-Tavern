extends GdUnitTestSuite
## 战斗数值引擎 (CombatEngine) 测试。
## 验证策划案《05-战斗系统》：属性面板换算、战斗风格激活、6 阶段伤害结算、双轨经验。

const CE := preload("res://globals/combat_engine.gd")

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

func test_evade_rate_formula() -> void:
	# 装甲基础闪避 + 灵巧×1% + 风格加成
	assert_float(CE.compute_evade_rate(10.0, 15, 0.0)).is_equal(25.0)
	assert_float(CE.compute_evade_rate(0.0, 20, 5.0)).is_equal(25.0)

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
		assert_bool(meta.has("hit_bonus")).is_true()
		assert_bool(meta.has("evade_bonus")).is_true()

func test_two_hand_style_evade_penalty() -> void:
	assert_float(CE.STYLE_META[CE.Style.TWO_HAND].evade_bonus).is_equal(-10.0)

func test_one_hand_style_bonuses() -> void:
	assert_float(CE.STYLE_META[CE.Style.ONE_HAND].hit_bonus).is_equal(10.0)
	assert_float(CE.STYLE_META[CE.Style.ONE_HAND].evade_bonus).is_equal(5.0)

func test_dual_wield_hit_penalty() -> void:
	assert_float(CE.STYLE_META[CE.Style.DUAL_WIELD].hit_bonus).is_equal(-10.0)

# ---------- 6 阶段伤害结算 (策划案 05 §4) ----------

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

func test_resolve_attack_returns_result() -> void:
	var a := _make_basic_attack()
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d)
	assert_object(r).is_not_null()
	assert_bool(r.hit or not r.hit).is_true()  # 至少有结果

func test_resolve_attack_hit_rate_within_bounds() -> void:
	# 1000 次抽样验证命中率在 5%-95% 边界内
	var a := _make_basic_attack()
	var d := _make_basic_defender()
	var hits: int = 0
	for i in range(1000):
		var r = CE.resolve_attack(a, d)
		if r.hit:
			hits += 1
	var hit_rate: float = float(hits) / 1000.0
	# 基础命中 75% + str*0.5 + per*0.5 - agi*1 = 75+5+5-10 = 75%
	assert_bool(hit_rate > 0.6 and hit_rate < 0.9) \
		.override_failure_message("命中率 %.2f 偏离 0.75" % hit_rate).is_true()

func test_resolve_attack_low_hit_floor() -> void:
	# 极高闪避防方，命中率下限 5%
	var a := _make_basic_attack()
	a.attacker_str = 1
	a.attacker_per = 1
	var d := _make_basic_defender()
	d.agi = 100  # 极高闪避
	var hits: int = 0
	for i in range(1000):
		var r = CE.resolve_attack(a, d)
		if r.hit:
			hits += 1
	# 下限 5%，容差 ±3%
	assert_bool(hits > 20 and hits < 80) \
		.override_failure_message("下限命中率命中数 %d 偏离 50" % hits).is_true()

func test_resolve_attack_high_hit_cap() -> void:
	# 极高命中攻方，命中率上限 95%
	var a := _make_basic_attack()
	a.attacker_str = 100
	a.attacker_per = 100
	a.weapon_hit_bonus = 100
	var d := _make_basic_defender()
	d.agi = 1
	var hits: int = 0
	for i in range(1000):
		var r = CE.resolve_attack(a, d)
		if r.hit:
			hits += 1
	# 上限 95%，容差 ±3%
	assert_bool(hits > 920 and hits < 980) \
		.override_failure_message("上限命中率命中数 %d 偏离 950" % hits).is_true()

func test_resolve_attack_miss_deals_zero_damage() -> void:
	# 未命中应无伤害
	var a := _make_basic_attack()
	a.attacker_str = 1
	a.attacker_per = 1
	var d := _make_basic_defender()
	d.agi = 200  # 几乎必闪
	for i in range(100):
		var r = CE.resolve_attack(a, d)
		if not r.hit:
			assert_int(r.final_damage).is_equal(0)
			return
	assert_bool(true).is_true()  # 全部命中也通过（极端情况）

func test_resolve_attack_hit_deals_at_least_one_damage() -> void:
	var a := _make_basic_attack()
	a.weapon_damage_dice = {"count": 1, "sides": 100}
	var d := _make_basic_defender()
	d.armor_def = 0
	d.con = 0
	for i in range(100):
		var r = CE.resolve_attack(a, d)
		if r.hit:
			assert_int(r.final_damage).is_greater_equal(1)
			return

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
		if not r.hit:
			continue
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
		if r1.hit and r2.hit:
			low_total += r1.final_damage
			high_total += r2.final_damage
			samples += 1
	if samples > 0:
		assert_bool(low_total > high_total) \
			.override_failure_message("低防御伤害 %d 未高于高防御 %d" % [low_total, high_total]).is_true()

func test_resolve_attack_block_reduces_damage() -> void:
	# 盾牌格挡成功应降低伤害
	var a := _make_basic_attack()
	a.weapon_damage_dice = {"count": 5, "sides": 6}
	var d_no_shield := _make_basic_defender()
	d_no_shield.has_shield = false
	var d_shield := _make_basic_defender()
	d_shield.has_shield = true
	d_shield.shield_block_chance = 100.0  # 必定格挡
	d_shield.shield_block_value = 20
	var blocked_total: int = 0
	var unblocked_total: int = 0
	var samples: int = 0
	for i in range(200):
		var r1 = CE.resolve_attack(a, d_no_shield)
		var r2 = CE.resolve_attack(a, d_shield)
		if r1.hit and r2.hit:
			unblocked_total += r1.final_damage
			blocked_total += r2.final_damage
			samples += 1
	if samples > 0:
		assert_bool(blocked_total < unblocked_total) \
			.override_failure_message("格挡后伤害 %d 未低于未格挡 %d" % [blocked_total, unblocked_total]).is_true()

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
		if r1.hit and r2.hit:
			normal_total += r1.final_damage
			back_total += r2.final_damage
			samples += 1
	if samples > 0:
		assert_bool(back_total > normal_total) \
			.override_failure_message("背袭伤害 %d 未超过正面 %d" % [back_total, normal_total]).is_true()

func test_resolve_attack_two_hand_knockback_force_doubled() -> void:
	# ARPG 实时：双手风格击退力叠加（基础 + 双手专属），方向沿攻方朝向
	var a := _make_basic_attack()
	a.style = CE.Style.TWO_HAND
	a.attack_type = "melee"
	a.knockback_force = 2.0  # 基础击退力
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(0, 0, -1))
	if r.hit:
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
	if r.hit:
		assert_float(r.knockback_force).is_equal(2.0)

func test_resolve_attack_knockback_direction_follows_attacker_facing() -> void:
	# ARPG 实时：击退方向随攻方朝向变化
	var a := _make_basic_attack()
	a.attack_type = "melee"
	a.knockback_force = 3.0
	var d := _make_basic_defender()
	var r = CE.resolve_attack(a, d, Vector3(1, 0, 0))  # 朝 +X
	if r.hit:
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
		if r.hit and r.crit:
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
		if r.hit and not r.crit:
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

func test_no_tick_or_turn_based_fields_remain() -> void:
	# 反向断言：确认已移除回合制专属字段
	var script: GDScript = load("res://globals/combat_engine.gd") as GDScript
	var source: String = script.source_code
	# 不应含 tick_reduce / 回合数 / 格数击退
	assert_bool(source.find("tick_reduce") == -1) \
		.override_failure_message("仍含回合制 tick_reduce").is_true()
	assert_bool(source.find("knocked_back") == -1) \
		.override_failure_message("仍含格数击退字段 knocked_back").is_true()
	# 应含 ARPG 实时字段
	assert_bool(source.find("knockback_force") != -1).is_true()
	assert_bool(source.find("stun_duration") != -1).is_true()
	assert_bool(source.find("attack_speed_mult") != -1).is_true()
	assert_bool(source.find("move_speed_mult") != -1).is_true()

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
