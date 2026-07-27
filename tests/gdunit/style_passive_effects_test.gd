extends GdUnitTestSuite

## 17 项流派专精被动效果全量测试（doc21 §一 + doc31 §一）。
## 测试覆盖：
##   1. DamageResolver 流派被动结算（直接设置 AttackInput 字段）
##   2. CombatBridge 流派被动应用（通过 style_context 参数）
##   3. SkillRuntime 流派被动授予
##   4. skills.json 数据完整性
##   5. StylePassiveEffects 逻辑（通过 scene-tree 注册的 SkillRuntime）

const SPE := preload("res://globals/combat/style_passive_effects.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const CB := preload("res://globals/combat/combat_bridge.gd")
const SR := preload("res://globals/combat/skill_runtime.gd")

## 测试辅助：确保 SkillRuntime 在场景树中可用
## 如果已有 autoload 则返回它；否则创建临时实例并挂入树
func _ensure_sr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var existing: Node = tree.root.get_node_or_null("SkillRuntime")
	if existing != null:
		return existing
	var sr: Node = SR.new()
	sr.name = "SkillRuntime"
	tree.root.add_child(sr)
	# 标记为 auto_free 以便测试结束后自动清理
	auto_free(sr)
	return sr

# ============================================================================
# 1. DamageResolver 集成测试 — 看破弱点暴击倍率覆盖 ×2.0
# ============================================================================
func test_damage_resolver_weakpoint_crit_override() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 100.0
	attack.style_crit_mult_override = 2.0
	attack.force_crit = true
	attack.attacker_per = 0

	var defender := CE.Defender.new()
	defender.con = 0
	defender.per = 0

	var res := CE.resolve_attack(attack, defender)
	assert_bool(res.crit).is_true()
	# 100 × 2.0 = 200
	assert_int(res.final_damage).is_equal(200)

# ============================================================================
# 2. DamageResolver 集成测试 — 蓄势累积额外伤害
# ============================================================================
func test_damage_resolver_accumulation_bonus() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 100.0
	attack.style_accumulation_bonus = 50.0

	var defender := CE.Defender.new()
	defender.con = 0
	defender.armor_def = 0

	var res := CE.resolve_attack(attack, defender)
	# 100 + 50 = 150
	assert_int(res.final_damage).is_equal(150)

# ============================================================================
# 3. DamageResolver — 无流派被动修正时基线不受影响
# ============================================================================
func test_damage_resolver_no_style_passive_baseline() -> void:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 0
	attack.weapon_damage_dice = {"count": 0, "sides": 0}
	attack.weapon_damage_flat = 100.0
	attack.crit_bonus = -100.0  # 基线测试排除随机暴击（基础暴击率 5%，不压制会以 5% 概率 ×1.5 flake）

	var defender := CE.Defender.new()
	defender.con = 0
	defender.armor_def = 0

	var res := CE.resolve_attack(attack, defender)
	assert_int(res.final_damage).is_equal(100)

# ============================================================================
# 4. CombatBridge 集成测试 — style_context 应用流派被动效果
# ============================================================================

# 决斗者 +50% 攻击力、+50% 暴击率
func test_combat_bridge_style_context_duelist() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_onehand_duelist")
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {"is_target_locked": true})
	# 决斗者 +50% 攻击力
	assert_float(attack.base_damage_bonus_percent).is_equal(50.0)
	assert_float(attack.crit_bonus).is_equal(50.0)
	sr.mechanism_passives.clear()

# 双持交错挥砍：副手必暴
func test_combat_bridge_style_context_dual_cross_offhand() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_dual_cross_strike")
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {"is_combo_active": true, "is_offhand_attack": true})
	assert_bool(attack.force_crit).is_true()
	sr.mechanism_passives.clear()

# 双持交错挥砍：主手无视 50% 防御
func test_combat_bridge_style_context_dual_cross_mainhand() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_dual_cross_strike")
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {"is_combo_active": true, "is_offhand_attack": false})
	assert_float(attack.ignore_def_percent).is_equal(50.0)
	sr.mechanism_passives.clear()

# 看破弱点：暴击 ×2.0
func test_combat_bridge_style_context_weakpoint() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_ranged_weakpoint_sight")
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {"is_weakpoint_hit": true})
	assert_bool(attack.force_crit).is_true()
	assert_float(attack.style_crit_mult_override).is_equal(2.0)
	sr.mechanism_passives.clear()

# 蓄势累积伤害
func test_combat_bridge_style_context_accumulation() -> void:
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {"accumulation_bonus": 30.0})
	assert_float(attack.style_accumulation_bonus).is_equal(30.0)

# 空 style_context 不影响基线
func test_combat_bridge_empty_style_context() -> void:
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack := CB.build_player_attack(null, null, "", "", attrs, 1, false, {}, {})
	assert_float(attack.base_damage_bonus_percent).is_equal(0.0)
	assert_bool(attack.force_crit).is_false()
	assert_float(attack.style_crit_mult_override).is_equal(0.0)
	assert_float(attack.style_accumulation_bonus).is_equal(0.0)

# resolve_player_attack 传递 style_context：决斗者加成应提升伤害
func test_resolve_player_attack_passes_style_context() -> void:
	var sr: Node = _ensure_sr()
	var player := Node3D.new()
	add_child(player)
	auto_free(player)
	var enemy := Node3D.new()
	add_child(enemy)
	auto_free(enemy)
	var attrs := {"str": 20, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	# 基线：无被动、无 style_context
	var base_result := CB.resolve_player_attack(player, enemy, null, "", "", attrs, 1)
	# 授予决斗者 + 锁定目标
	sr.grant_mechanism_passive("passive_style_onehand_duelist")
	var buffed_result := CB.resolve_player_attack(
		player, enemy, null, "", "", attrs, 1, false, {}, {"is_target_locked": true}
	)
	assert_int(buffed_result.final_damage).is_greater(base_result.final_damage)
	sr.mechanism_passives.clear()

# ============================================================================
# 5. StylePassiveEffects 逻辑测试（通过场景树中的 SkillRuntime）
# ============================================================================

# 决斗者：锁定目标 +50% 攻击力
func test_duelist_buff_with_passive_locked() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_onehand_duelist")
	var res := SPE.apply_duelist_buff(true)
	assert_float(float(res["atk_bonus"])).is_equal(50.0)
	assert_float(float(res["crit_bonus"])).is_equal(50.0)
	sr.mechanism_passives.clear()

func test_duelist_buff_not_locked() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_onehand_duelist")
	var res := SPE.apply_duelist_buff(false)
	assert_float(float(res["atk_bonus"])).is_equal(0.0)
	sr.mechanism_passives.clear()

# 奥法之剑：满蓄力释放
func test_spellblade_cast() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_onehand_spellblade")
	assert_bool(SPE.should_spellblade_cast(true)).is_true()
	assert_bool(SPE.should_spellblade_cast(false)).is_false()
	sr.mechanism_passives.clear()

# 盾击：触发 + 压制窗口
func test_shield_bash_trigger() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_shield_bash")
	assert_bool(SPE.should_shield_bash(true, true)).is_true()
	assert_bool(SPE.should_shield_bash(false, true)).is_false()
	assert_bool(SPE.should_shield_bash(true, false)).is_false()
	assert_bool(SPE.should_shield_bash_suppress(0.2)).is_true()
	assert_bool(SPE.should_shield_bash_suppress(0.4)).is_false()
	sr.mechanism_passives.clear()

# 折射：100% 反射 + 耐久加倍
func test_reflect_attack() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_shield_refraction")
	assert_float(SPE.try_reflect_attack(true, true)).is_equal(1.0)
	assert_float(SPE.try_reflect_attack(false, true)).is_equal(0.0)
	assert_float(SPE.try_reflect_attack(true, false)).is_equal(0.0)
	assert_float(SPE.get_refraction_durability_mult()).is_equal(2.0)
	sr.mechanism_passives.clear()

# 蓄势：减伤 30% + 累积
func test_accumulation_reduce() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_twohand_accumulation")
	assert_int(SPE.apply_accumulation_damage_reduce(100, true)).is_equal(70)
	assert_int(SPE.apply_accumulation_damage_reduce(100, false)).is_equal(100)
	assert_float(SPE.get_accumulation_bonus(50.0)).is_equal(50.0)
	sr.mechanism_passives.clear()

# 重型挥舞：参数
func test_heavy_swing_params() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_twohand_heavy_swing")
	var params := SPE.get_heavy_swing_params()
	assert_float(float(params["arc_angle_deg"])).is_equal(120.0)
	assert_float(float(params["radius_mult"])).is_equal(1.3)
	sr.mechanism_passives.clear()

# 交错挥砍：连携逻辑
func test_dual_cross_combo_active() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_dual_cross_strike")
	assert_bool(SPE.is_combo_active(0.0, 0.3, "primary", "secondary")).is_true()
	assert_bool(SPE.is_combo_active(0.0, 0.3, "primary", "primary")).is_false()
	assert_bool(SPE.is_combo_active(0.0, 0.6, "primary", "secondary")).is_false()
	assert_bool(SPE.is_combo_on_cooldown(0.0, 2.0)).is_true()
	assert_bool(SPE.is_combo_on_cooldown(0.0, 3.5)).is_false()
	sr.mechanism_passives.clear()

# 十字返
func test_dual_cross_counter() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_dual_cross_counter")
	assert_bool(SPE.should_dual_cross_counter(true, true)).is_true()
	assert_bool(SPE.should_dual_cross_counter(false, true)).is_false()
	assert_bool(SPE.should_dual_cross_counter(true, false)).is_false()
	sr.mechanism_passives.clear()

# 暴风骤雨：CD 递减
func test_flurry_storm_cd_mult() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_unarmed_flurry_storm")
	assert_float(SPE.apply_flurry_storm_cd_mult(0)).is_equal_approx(1.0, 0.001)
	assert_float(SPE.apply_flurry_storm_cd_mult(1)).is_equal_approx(0.95, 0.001)
	assert_float(SPE.apply_flurry_storm_cd_mult(12)).is_equal_approx(0.4, 0.001)
	assert_float(SPE.apply_flurry_storm_cd_mult(20)).is_equal_approx(0.4, 0.001)
	sr.mechanism_passives.clear()

# 过肩摔：真实伤害
func test_over_shoulder_slam_damage() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_unarmed_over_shoulder_slam")
	assert_int(SPE.compute_over_shoulder_slam_damage(200, false)).is_equal(200)
	assert_int(SPE.compute_over_shoulder_slam_damage(200, true)).is_equal(50)
	sr.mechanism_passives.clear()

# 擒拿：HP ≤ 30% 触发
func test_grapple_trigger() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_unarmed_grapple")
	assert_bool(SPE.should_grapple(20.0, true)).is_true()
	assert_bool(SPE.should_grapple(50.0, true)).is_false()
	assert_bool(SPE.should_grapple(20.0, false)).is_false()
	sr.mechanism_passives.clear()

# 迅猛踢击
func test_swift_kick() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_unarmed_swift_kick")
	assert_bool(SPE.has_swift_kick()).is_true()
	sr.mechanism_passives.clear()

# 折箭术：偏转角度
func test_arrow_break_deflect() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_unarmed_arrow_break")
	var angle: float = SPE.try_arrow_break_deflect()
	assert_bool(abs(angle) >= 60.0 and abs(angle) <= 90.0).is_true()
	sr.mechanism_passives.clear()

# 看破弱点：暴击 ×2.0
func test_weakpoint_sight() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_ranged_weakpoint_sight")
	var res := SPE.apply_weakpoint_sight(true)
	assert_bool(bool(res["force_crit"])).is_true()
	assert_float(float(res["crit_mult_override"])).is_equal(2.0)
	sr.mechanism_passives.clear()

# 贯穿：递减
func test_piercing_falloff() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_ranged_piercing")
	assert_float(SPE.apply_piercing_falloff(0)).is_equal_approx(1.0, 0.001)
	assert_float(SPE.apply_piercing_falloff(1)).is_equal_approx(0.8, 0.001)
	assert_float(SPE.apply_piercing_falloff(5)).is_equal_approx(0.0, 0.001)
	sr.mechanism_passives.clear()

# 奥术护盾：蓝量转化
func test_arcane_barrier_shield() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_spell_arcane_barrier")
	assert_int(SPE.compute_arcane_barrier_shield(30)).is_equal(30)
	sr.mechanism_passives.clear()

# 元素环：5 秒持续
func test_elemental_ring_duration() -> void:
	var sr: Node = _ensure_sr()
	sr.grant_mechanism_passive("passive_style_spell_elemental_ring")
	assert_float(SPE.get_elemental_ring_duration()).is_equal(5.0)
	sr.mechanism_passives.clear()

# ============================================================================
# 6. SkillRuntime 流派被动授予测试
# ============================================================================

# 全部 17 项流派被动授予校验
func test_all_17_style_passives_grantable() -> void:
	var runtime: Node = auto_free(SR.new())
	var all_17 := [
		"passive_style_onehand_duelist",
		"passive_style_onehand_spellblade",
		"passive_style_shield_bash",
		"passive_style_shield_refraction",
		"passive_style_twohand_accumulation",
		"passive_style_twohand_heavy_swing",
		"passive_style_dual_cross_strike",
		"passive_style_dual_cross_counter",
		"passive_style_unarmed_flurry_storm",
		"passive_style_unarmed_over_shoulder_slam",
		"passive_style_unarmed_grapple",
		"passive_style_unarmed_swift_kick",
		"passive_style_unarmed_arrow_break",
		"passive_style_ranged_weakpoint_sight",
		"passive_style_ranged_piercing",
		"passive_style_spell_arcane_barrier",
		"passive_style_spell_elemental_ring",
	]
	for pid in all_17:
		runtime.grant_mechanism_passive(pid)
		assert_bool(runtime.has_mechanism_passive(pid)).is_true()

# ============================================================================
# 7. skills.json 数据完整性测试
# ============================================================================

func test_skills_json_has_17_style_passives() -> void:
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var txt := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(txt)
	assert_int(err).is_equal(OK)
	var skills_arr: Array = json.data["skills"]

	var style_ids: Array = []
	for skill in skills_arr:
		if String(skill.get("category", "")) == "STYLE":
			style_ids.append(String(skill["id"]))

	# 17 项流派被动全部存在
	var expected := [
		"passive_style_onehand_duelist",
		"passive_style_onehand_spellblade",
		"passive_style_shield_bash",
		"passive_style_shield_refraction",
		"passive_style_twohand_accumulation",
		"passive_style_twohand_heavy_swing",
		"passive_style_dual_cross_strike",
		"passive_style_dual_cross_counter",
		"passive_style_unarmed_flurry_storm",
		"passive_style_unarmed_over_shoulder_slam",
		"passive_style_unarmed_grapple",
		"passive_style_unarmed_swift_kick",
		"passive_style_unarmed_arrow_break",
		"passive_style_ranged_weakpoint_sight",
		"passive_style_ranged_piercing",
		"passive_style_spell_arcane_barrier",
		"passive_style_spell_elemental_ring",
	]
	for id in expected:
		assert_bool(style_ids.has(id)).is_true()
	assert_int(style_ids.size()).is_equal(17)

func test_skills_json_style_passives_have_effect_type() -> void:
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	var txt := file.get_as_text()
	file.close()
	var json := JSON.new()
	json.parse(txt)
	var skills_arr: Array = json.data["skills"]

	for skill in skills_arr:
		if String(skill.get("category", "")) == "STYLE":
			assert_bool(skill.has("effect_type")).is_true()
			assert_str(String(skill["effect_type"])).is_not_empty()

func test_skills_json_3_new_unarmed_passives_have_params() -> void:
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	var txt := file.get_as_text()
	file.close()
	var json := JSON.new()
	json.parse(txt)
	var skills_arr: Array = json.data["skills"]

	var new_ids := [
		"passive_style_unarmed_grapple",
		"passive_style_unarmed_swift_kick",
		"passive_style_unarmed_arrow_break",
	]
	for skill in skills_arr:
		var sid: String = String(skill.get("id", ""))
		if new_ids.has(sid):
			assert_bool(skill.has("effect_type")).is_true()
			assert_bool(skill.has("style_required")).is_true()
			assert_str(String(skill["style_required"])).is_equal("UNARMED")
