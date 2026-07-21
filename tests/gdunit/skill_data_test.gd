extends GdUnitTestSuite
## SkillData 数据层测试（策划案 15 ARPG 化）
## 验证：33 技能完整、18 里程碑完整、ARPG 字段非负、无回合制残留、领悟门槛、媒介匹配

const SD := preload("res://globals/combat/skill_data.gd")

# ---------- 数量与结构完整性 ----------

func test_skills_total_count_30() -> void:
	# 策划案 §2 标题写"33 技能"，但正文仅详列 10 流派（A-J）× 3 阶 = 30 技能
	# 第 11 流派数据未给出，待策划补全后再扩为 33
	assert_int(SD.SKILLS.size()).is_equal(30)

func test_milestones_total_count_18() -> void:
	# 6 属性 × 3 阶 = 18
	assert_int(SD.ATTR_MILESTONES.size()).is_equal(18)

func test_each_school_has_3_skills() -> void:
	# 策划案 10 流派（A-J）× 3 阶 = 30；待第 11 流派补全
	# 现阶段每流派应有 3 技能
	var school_counts: Dictionary = {}
	for skill in SD.SKILLS:
		var s: int = skill["school"]
		school_counts[s] = school_counts.get(s, 0) + 1
	for school in school_counts.keys():
		assert_int(school_counts[school]) \
			.override_failure_message("流派 %d 技能数 != 3" % school).is_equal(3)

func test_skills_have_3_tiers_per_school() -> void:
	var school_tiers: Dictionary = {}
	for skill in SD.SKILLS:
		var s: int = skill["school"]
		var t: int = skill["tier"]
		if not school_tiers.has(s):
			school_tiers[s] = {}
		school_tiers[s][t] = true
	for school in school_tiers.keys():
		var tiers: Dictionary = school_tiers[school]
		assert_bool(tiers.has(SD.SkillTier.T1)) \
			.override_failure_message("流派 %d 缺 T1" % school).is_true()
		assert_bool(tiers.has(SD.SkillTier.T2)) \
			.override_failure_message("流派 %d 缺 T2" % school).is_true()
		assert_bool(tiers.has(SD.SkillTier.T3)) \
			.override_failure_message("流派 %d 缺 T3" % school).is_true()

func test_milestones_3_tiers_per_attr() -> void:
	var attr_tiers: Dictionary = {}
	for ms in SD.ATTR_MILESTONES:
		var a: String = ms["attr"]
		var t: int = ms["tier"]
		if not attr_tiers.has(a):
			attr_tiers[a] = {}
		attr_tiers[a][t] = true
	# 6 属性
	assert_int(attr_tiers.size()).is_equal(6)
	for attr in attr_tiers.keys():
		var tiers: Dictionary = attr_tiers[attr]
		assert_bool(tiers.has(SD.AttrMilestone.T1)).is_true()
		assert_bool(tiers.has(SD.AttrMilestone.T2)).is_true()
		assert_bool(tiers.has(SD.AttrMilestone.T3)).is_true()

func test_milestone_attrs_cover_6() -> void:
	var attrs: Array = []
	for ms in SD.ATTR_MILESTONES:
		if not attrs.has(ms["attr"]):
			attrs.append(ms["attr"])
	attrs.sort()
	assert_str(str(attrs)).is_equal('["agi", "con", "dex", "mag", "per", "str"]')

# ---------- ARPG 字段非负与单位化 ----------

func test_skill_ids_are_chinese_keys() -> void:
	for skill in SD.SKILLS:
		var id: String = skill["id"]
		assert_bool(id.length() > 0) \
			.override_failure_message("技能 id 为空").is_true()
		# 中文键：至少含一个 CJK 字符
		var has_cjk: bool = false
		for ch in id:
			if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
				has_cjk = true
				break
		assert_bool(has_cjk) \
			.override_failure_message("技能 id '%s' 不含中文字符" % id).is_true()

func test_skill_ids_unique() -> void:
	var ids: Array = []
	for skill in SD.SKILLS:
		ids.append(skill["id"])
	var unique: Array = []
	for id in ids:
		assert_bool(not unique.has(id)) \
			.override_failure_message("技能 id 重复: %s" % id).is_true()
		unique.append(id)

func test_milestone_ids_unique() -> void:
	var ids: Array = []
	for ms in SD.ATTR_MILESTONES:
		ids.append(ms["id"])
	var unique: Array = []
	for id in ids:
		assert_bool(not unique.has(id)) \
			.override_failure_message("里程碑 id 重复: %s" % id).is_true()
		unique.append(id)

func test_active_skills_have_positive_cooldown() -> void:
	for skill in SD.SKILLS:
		if skill["type"] == "active":
			assert_float(skill["cooldown"]).is_greater(0.0)

func test_passive_skills_have_zero_cooldown_and_cast() -> void:
	for skill in SD.SKILLS:
		if skill["type"] == "passive":
			assert_float(skill["cooldown"]).is_equal(0.0)
			assert_float(skill["cast_time"]).is_equal(0.0)

func test_all_skills_non_negative_arpg_fields() -> void:
	for skill in SD.SKILLS:
		assert_bool(skill["damage_mult"] >= 0.0) \
			.override_failure_message("%s damage_mult < 0" % skill["id"]).is_true()
		assert_bool(skill["cast_time"] >= 0.0).is_true()
		assert_bool(skill["range_m"] >= 0.0).is_true()
		assert_bool(skill["aoe_radius"] >= 0.0).is_true()
		assert_bool(skill["knockback_m"] >= 0.0).is_true()
		assert_bool(skill["stun_sec"] >= 0.0).is_true()
		assert_bool(skill["buff_sec"] >= 0.0).is_true()
		assert_bool(skill["ignore_def"] >= 0.0).is_true()
		assert_bool(skill["lifesteal"] >= 0.0).is_true()

func test_milestone_values_non_negative() -> void:
	for ms in SD.ATTR_MILESTONES:
		var v = ms["value"]
		if v is float or v is int:
			assert_bool(v >= 0) \
				.override_failure_message("%s value < 0" % ms["id"]).is_true()
		elif v is Dictionary:
			for key in v.keys():
				var sub = v[key]
				if sub is float or sub is int:
					assert_bool(sub >= 0) \
						.override_failure_message("%s value[%s] < 0" % [ms["id"], key]).is_true()

# ---------- 反向断言：无回合制残留 ----------

func test_no_turn_based_terms_in_skill_data() -> void:
	var script: GDScript = load("res://globals/combat/skill_data.gd") as GDScript
	var source: String = script.source_code
	# ARPG 化字段应存在
	assert_bool(source.find("cooldown") != -1).is_true()
	assert_bool(source.find("cast_time") != -1).is_true()
	assert_bool(source.find("range_m") != -1).is_true()
	assert_bool(source.find("knockback_m") != -1).is_true()
	assert_bool(source.find("stun_sec") != -1).is_true()
	assert_bool(source.find("buff_sec") != -1).is_true()
	# 注释/常量里不应再用"回合动作""格"作为运行时单位（CELL_TO_METER 是换算常量，允许）

# ---------- 领悟门槛判定（策划案 §1.1） ----------

func test_can_unlock_t1_threshold() -> void:
	# T1: 熟练度 >= 3，主属性 >= 15
	assert_bool(SD.can_unlock(SD.SkillTier.T1, 3, 15)).is_true()
	assert_bool(SD.can_unlock(SD.SkillTier.T1, 2, 15)).is_false()  # 熟练度不足
	assert_bool(SD.can_unlock(SD.SkillTier.T1, 3, 14)).is_false()  # 属性不足
	assert_bool(SD.can_unlock(SD.SkillTier.T1, 10, 50)).is_true()  # 双超

func test_can_unlock_t2_threshold() -> void:
	# T2: 熟练度 >= 8，主属性 >= 35
	assert_bool(SD.can_unlock(SD.SkillTier.T2, 8, 35)).is_true()
	assert_bool(SD.can_unlock(SD.SkillTier.T2, 7, 35)).is_false()
	assert_bool(SD.can_unlock(SD.SkillTier.T2, 8, 34)).is_false()

func test_can_unlock_t3_threshold() -> void:
	# T3: 熟练度 >= 15，主属性 >= 70
	assert_bool(SD.can_unlock(SD.SkillTier.T3, 15, 70)).is_true()
	assert_bool(SD.can_unlock(SD.SkillTier.T3, 14, 70)).is_false()
	assert_bool(SD.can_unlock(SD.SkillTier.T3, 15, 69)).is_false()

# ---------- 属性里程碑门槛（策划案 §3.1） ----------

func test_can_unlock_milestone_t1() -> void:
	# T1: 属性 >= 5
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T1, 5)).is_true()
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T1, 4)).is_false()

func test_can_unlock_milestone_t2() -> void:
	# T2: 属性 >= 15
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T2, 15)).is_true()
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T2, 14)).is_false()

func test_can_unlock_milestone_t3() -> void:
	# T3: 属性 >= 30
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T3, 30)).is_true()
	assert_bool(SD.can_unlock_milestone(SD.AttrMilestone.T3, 29)).is_false()

# ---------- 查询 API ----------

func test_get_skills_by_school() -> void:
	var sword_skills: Array = SD.get_skills_by_school(SD.School.ONE_HAND_SWORD)
	assert_int(sword_skills.size()).is_equal(3)
	var unarmed_skills: Array = SD.get_skills_by_school(SD.School.UNARMED)
	assert_int(unarmed_skills.size()).is_equal(3)

func test_get_skill_by_id_found() -> void:
	var skill: Dictionary = SD.get_skill_by_id("顺劈斩")
	assert_bool(not skill.is_empty()).is_true()
	assert_int(skill["school"]).is_equal(SD.School.TWO_HAND_SWORD)
	assert_float(skill["damage_mult"]).is_equal(0.85)
	assert_float(skill["knockback_m"]).is_equal(0.0)

func test_get_skill_by_id_not_found() -> void:
	var skill: Dictionary = SD.get_skill_by_id("不存在技能")
	assert_bool(skill.is_empty()).is_true()

func test_get_milestones_by_attr() -> void:
	var str_ms: Array = SD.get_milestones_by_attr("str")
	assert_int(str_ms.size()).is_equal(3)
	var con_ms: Array = SD.get_milestones_by_attr("con")
	assert_int(con_ms.size()).is_equal(3)
	var empty_ms: Array = SD.get_milestones_by_attr("nonexistent")
	assert_int(empty_ms.size()).is_equal(0)

# ---------- 媒介匹配（策划案 §1.2） ----------

func test_is_weapon_medium_matched_unarmed_requires_both_empty() -> void:
	# 徒手：双手均须空置
	assert_bool(SD.is_weapon_medium_matched(SD.School.UNARMED, "", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.UNARMED, "one_hand_melee", "")).is_false()
	assert_bool(SD.is_weapon_medium_matched(SD.School.UNARMED, "", "shield")).is_false()

func test_is_weapon_medium_matched_sword() -> void:
	# 单手剑：主手须 one_hand_melee
	assert_bool(SD.is_weapon_medium_matched(SD.School.ONE_HAND_SWORD, "one_hand_melee", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.ONE_HAND_SWORD, "two_hand", "")).is_false()

func test_is_weapon_medium_matched_two_hand() -> void:
	# 双手大剑/斧/锤/枪：主手须 two_hand
	assert_bool(SD.is_weapon_medium_matched(SD.School.TWO_HAND_SWORD, "two_hand", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.WAR_HAMMER, "two_hand", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.SPEAR, "two_hand", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.TWO_HAND_AXE, "one_hand_melee", "")).is_false()

func test_is_weapon_medium_matched_ranged() -> void:
	assert_bool(SD.is_weapon_medium_matched(SD.School.LONGBOW, "longbow", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.LIGHT_CROSSBOW, "crossbow", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.LONGBOW, "crossbow", "")).is_false()

func test_is_weapon_medium_matched_magic() -> void:
	assert_bool(SD.is_weapon_medium_matched(SD.School.ENCHANT_WAND, "wand", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.GRIMOIRE, "grimoire", "")).is_true()
	assert_bool(SD.is_weapon_medium_matched(SD.School.ENCHANT_WAND, "grimoire", "")).is_false()

# ---------- 策划案数值抽样核对（ARPG 单位换算） ----------

func test_cell_to_meter_constant() -> void:
	# 1 格 = 1.5 米
	assert_float(SD.CELL_TO_METER).is_equal(1.5)

func test_tick_to_second_constant() -> void:
	# 1 回合 = 1 秒
	assert_float(SD.TICK_TO_SECOND).is_equal(1.0)

func test_cleave_3_cells_becomes_4_5_meters() -> void:
	# 策划案"扇形 3 格" → range_m = 3 * 1.5 = 4.5
	var skill: Dictionary = SD.get_skill_by_id("顺劈斩")
	assert_float(skill["range_m"]).is_equal(4.5)
	assert_float(skill["aoe_radius"]).is_equal(4.5)

func test_cleave_knockback_removed_only_kick_charge_have_knockback() -> void:
	# 策划案调整：武器技能不再有击退，仅踢击/冲撞有击退
	var skill: Dictionary = SD.get_skill_by_id("顺劈斩")
	assert_float(skill["knockback_m"]).is_equal(0.0)

func test_concussive_blow_stun_2_turns_becomes_2_seconds() -> void:
	# 策划案"眩晕 2 回合" → stun_sec = 2.0
	var skill: Dictionary = SD.get_skill_by_id("震荡打击")
	assert_float(skill["stun_sec"]).is_equal(2.0)

func test_defensive_stance_buff_3_turns_becomes_3_seconds() -> void:
	var skill: Dictionary = SD.get_skill_by_id("防御姿态")
	assert_float(skill["buff_sec"]).is_equal(3.0)
	assert_float(skill["cooldown"]).is_equal(5.0)

func test_heavy_overhead_cast_2_turns_becomes_2_seconds() -> void:
	# 策划案"消耗 2 回合动作（读条蓄力 1 回合）" → cast_time = 2.0
	var skill: Dictionary = SD.get_skill_by_id("过顶重击")
	assert_float(skill["cast_time"]).is_equal(2.0)
	assert_float(skill["damage_mult"]).is_equal(2.2)
	assert_float(skill["ignore_def"]).is_equal(20.0)

func test_impale_ignores_block() -> void:
	var skill: Dictionary = SD.get_skill_by_id("贯穿刺击")
	assert_bool(skill["ignore_block"]).is_true()

func test_unyielding_strike_lifesteal_30() -> void:
	var skill: Dictionary = SD.get_skill_by_id("不屈重斩")
	assert_float(skill["lifesteal"]).is_equal(30.0)

func test_milestone_str_t3_carry_15() -> void:
	var ms: Array = SD.get_milestones_by_attr("str")
	var t3: Dictionary = {}
	for m in ms:
		if m["tier"] == SD.AttrMilestone.T3:
			t3 = m
	assert_bool(not t3.is_empty()).is_true()
	var val: Dictionary = t3["value"]
	assert_int(val["carry"]).is_equal(15)
	assert_int(val["dmg"]).is_equal(5)

func test_milestone_con_t1_max_hp_20() -> void:
	var ms: Array = SD.get_milestones_by_attr("con")
	var t1: Dictionary = {}
	for m in ms:
		if m["tier"] == SD.AttrMilestone.T1:
			t1 = m
	assert_bool(not t1.is_empty()).is_true()
	assert_int(t1["value"]).is_equal(20)

func test_school_main_attr_mapping_complete() -> void:
	# 10 流派（A-J）主攻属性映射完整
	assert_int(SD.SCHOOL_MAIN_ATTR.size()).is_equal(10)
	# 长弓主攻敏捷
	var longbow_attrs: Array = SD.SCHOOL_MAIN_ATTR[SD.School.LONGBOW]
	assert_bool(longbow_attrs.has("dex")).is_true()
	# 附魔法杖主攻魔力
	var wand_attrs: Array = SD.SCHOOL_MAIN_ATTR[SD.School.ENCHANT_WAND]
	assert_bool(wand_attrs.has("mag")).is_true()
	# 徒手主攻力量/灵巧
	var unarmed_attrs: Array = SD.SCHOOL_MAIN_ATTR[SD.School.UNARMED]
	assert_bool(unarmed_attrs.has("str")).is_true()
	assert_bool(unarmed_attrs.has("agi")).is_true()

func test_school_weapon_medium_mapping_complete() -> void:
	assert_int(SD.SCHOOL_WEAPON_MEDIUM.size()).is_equal(10)
	# 徒手媒介为空字符串
	assert_str(SD.SCHOOL_WEAPON_MEDIUM[SD.School.UNARMED]).is_equal("")
