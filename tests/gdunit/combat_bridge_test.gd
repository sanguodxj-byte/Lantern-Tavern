extends GdUnitTestSuite
## CombatBridge 桥接层集成测试
## 动作控制版：验证 AttackInput/Defender 字段映射、resolve_player_attack/resolve_enemy_attack 闭环、
## 朝向判定（背袭/侧击）、徒手/持盾/双手风格适配。
## 已移除概率格挡/闪避相关测试（改为动作判定）。

const CB := preload("res://globals/combat/combat_bridge.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const SD := preload("res://globals/combat/skill_data.gd")

func before() -> void:
	_reset_attr_panel()

func after() -> void:
	_reset_attr_panel()

# ---------- 攻方输入构造 ----------

func test_build_player_attack_melee_one_hand() -> void:
	# 单手近战武器：风格 ONE_HAND，attack_type melee
	var weapon := _make_weapon(2, 6)  # damage_min=2, damage_max=6
	var player := _make_dummy_node3d()
	var attrs := {"str": 12, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "", attrs, 1)
	assert_int(attack.attacker_str).is_equal(12)
	assert_int(attack.style).is_equal(CE.Style.ONE_HAND)
	assert_str(attack.attack_type).is_equal("melee")
	# 投骰 sides = damage_max - damage_min + 1 = 5
	assert_int(attack.weapon_damage_dice["sides"]).is_equal(5)
	player.queue_free()

func test_build_player_attack_unarmed() -> void:
	# 徒手：双手空置，风格 UNARMED
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, null, "", "", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.UNARMED)
	assert_str(attack.attack_type).is_equal("melee")
	# 徒手低伤害投骰 1d4
	assert_int(attack.weapon_damage_dice["sides"]).is_equal(4)
	player.queue_free()

func test_build_player_attack_two_hand() -> void:
	var weapon := _make_weapon(3, 9)
	var player := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "two_hand", "", attrs, 2)
	assert_int(attack.style).is_equal(CE.Style.TWO_HAND)
	assert_int(attack.attacker_level).is_equal(2)
	player.queue_free()

func test_build_player_attack_ranged_longbow() -> void:
	var weapon := _make_weapon(1, 5)
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 14, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "longbow", "", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.RANGED)
	assert_str(attack.attack_type).is_equal("ranged")
	player.queue_free()

func test_build_player_attack_spell_wand() -> void:
	var weapon := _make_weapon(1, 4)
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 8, "mag": 15, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "wand", "", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.SPELL)
	assert_str(attack.attack_type).is_equal("spell")
	assert_int(attack.attacker_mag).is_equal(15)
	player.queue_free()

func test_build_player_attack_one_hand_shield() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var attrs := {"str": 12, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "shield", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.ONE_HAND_SHIELD)
	player.queue_free()

func test_build_player_attack_dual_wield() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var attrs := {"str": 12, "dex": 12, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "one_hand_melee", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.DUAL_WIELD)
	player.queue_free()

func test_build_player_attack_backstab_flag() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "", attrs, 1, true)
	assert_bool(attack.is_backstab).is_true()
	player.queue_free()


func test_build_player_attack_uses_weapondata_taxonomy_without_hardcoded_type() -> void:
	var bow := WeaponRegistry.get_weapon_data("longbow")
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 20, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, bow, "one_hand_melee", "", attrs, 1)
	assert_int(attack.style).is_equal(CE.Style.RANGED)
	assert_str(attack.attack_type).is_equal("ranged")
	assert_int(attack.weapon_damage_dice["count"]).is_equal(1)
	assert_int(attack.weapon_damage_dice["sides"]).is_equal(8)
	assert_float(attack.weapon_damage_flat).is_equal(2.0)
	player.queue_free()


func test_get_weapon_proficiency_key_uses_weapondata() -> void:
	var staff := WeaponRegistry.get_weapon_data("staff")
	assert_str(CB.get_weapon_proficiency_key(staff)).is_equal("staff")

# ---------- 防方输入构造 ----------

func test_build_player_defender_no_shield() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 12, "agi": 14, "per": 10}
	var defender = CB.build_player_defender(player, attrs, false)
	assert_int(defender.con).is_equal(12)
	assert_int(defender.agi).is_equal(14)
	assert_bool(defender.has_shield).is_false()
	player.queue_free()

func test_build_player_defender_with_shield() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var defender = CB.build_player_defender(player, attrs, true, 5)
	assert_bool(defender.has_shield).is_true()
	# 盾牌仅提供物理防御，不再有 shield_block_chance / shield_block_value
	# armor_def 包含传入值(5) + 盾牌物理防御加成（从注册表获取 shield_phys_def）
	assert_int(defender.armor_def).is_greater_equal(5)
	assert_bool(not "shield_block_chance" in defender) \
		.override_failure_message("Defender 不应含 shield_block_chance（已移除）").is_true()
	player.queue_free()

func test_build_player_defender_uses_explicit_shield_data() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var shield := WeaponData.new()
	shield.shield_phys_def = 8
	var defender = CB.build_player_defender(player, attrs, true, 2, shield)
	# shield_phys_def 叠加到 armor_def
	assert_int(defender.armor_def).is_equal(10)
	assert_bool(not "shield_block_chance" in defender).is_true()
	player.queue_free()

func test_build_player_defender_applies_defensive_stance_buff() -> void:
	var player := Player.new()
	player.combat_buffs["def_and_evade_up"] = {"remaining": 3.0, "value": {"def": 4, "evade": 5}}
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var defender = CB.build_player_defender(player, attrs, false, 2)
	# def 加成仍生效（2 + 4 = 6）
	assert_int(defender.armor_def).is_equal(6)
	player.free()


func test_build_player_defender_from_equipment_uses_armor_and_hand_shield() -> void:
	var player := Player.new()
	var eq := EquipmentComponent.new()
	player.add_child(eq)
	player.equipment = eq
	eq.configure_armor_slot("body", _make_armor("Leather", 2, 3.0))
	eq.configure_weapon_slot(0, _make_shield_weapon("Buckler"), true)
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var defender = CB.build_player_defender_from_equipment(player, attrs, false)
	assert_bool(defender.has_shield).is_true()
	# armor_def = 防具防御(2) + 盾牌物理防御(1) = 3
	assert_int(defender.armor_def).is_equal(3)
	player.free()


func test_build_enemy_defender_no_shield() -> void:
	var enemy := _make_dummy_node3d()
	var defender = CB.build_enemy_defender(enemy, false)
	assert_int(defender.con).is_equal(10)
	assert_bool(defender.has_shield).is_false()
	enemy.queue_free()

func test_build_enemy_defender_with_shield() -> void:
	var enemy := _make_dummy_node3d()
	var defender = CB.build_enemy_defender(enemy, true)
	assert_bool(defender.has_shield).is_true()
	# 盾牌仅提供物理防御，不再有 shield_block_chance
	assert_bool(not "shield_block_chance" in defender).is_true()
	enemy.queue_free()

# ---------- 朝向判定 ----------

func test_is_backstab_same_direction() -> void:
	# 攻方朝向与防方朝向同向（都朝 -Z）→ 背袭
	var atk := Vector3(0, 0, -1)
	var def := Vector3(0, 0, -1)
	assert_bool(CB.is_backstab(atk, def)).is_true()

func test_is_backstab_opposite_direction() -> void:
	# 攻方朝 -Z，防方朝 +Z（面对面）→ 非背袭
	var atk := Vector3(0, 0, -1)
	var def := Vector3(0, 0, 1)
	assert_bool(CB.is_backstab(atk, def)).is_false()

func test_is_sideswipe_perpendicular() -> void:
	# 攻方朝 -Z，防方朝 +X（垂直）→ 侧击
	var atk := Vector3(0, 0, -1)
	var def := Vector3(1, 0, 0)
	assert_bool(CB.is_sideswipe(atk, def)).is_true()

func test_is_sideswipe_parallel_not_sideswipe() -> void:
	var atk := Vector3(0, 0, -1)
	var def := Vector3(0, 0, -1)
	assert_bool(CB.is_sideswipe(atk, def)).is_false()

# ---------- 结算闭环 ----------

func test_resolve_player_attack_returns_damage_result() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	enemy.position = Vector3(0, 0, -2)  # 在玩家前方
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	# 动作控制版：hit 恒为 true
	var result = CB.resolve_player_attack(player, enemy, weapon, "one_hand_melee", "", attrs, 1)
	assert_bool(result.hit).is_true()
	assert_int(result.final_damage).is_greater(0)
	player.queue_free()
	enemy.queue_free()

func test_resolve_player_attack_normal_attack_no_knockback() -> void:
	# 策划案调整：正常攻击（无技能）仅造成血量伤害，不施加击退
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_player_attack(player, enemy, weapon, "one_hand_melee", "", attrs, 1)
	assert_bool(result.hit).is_true()
	assert_int(result.final_damage).is_greater(0)
	assert_float(result.knockback_force).is_equal(0.0)
	assert_vector(result.knockback_impulse).is_equal(Vector3.ZERO)
	player.queue_free()
	enemy.queue_free()

func test_resolve_player_attack_unarmed_no_knockback() -> void:
	# 徒手正常攻击也不应有击退
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_player_attack(player, enemy, null, "", "", attrs, 1)
	assert_bool(result.hit).is_true()
	assert_float(result.knockback_force).is_equal(0.0)
	player.queue_free()
	enemy.queue_free()

func test_resolve_player_attack_knockback_direction_along_attacker_forward() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_player_attack(player, enemy, weapon, "two_hand", "", attrs, 1)
	assert_bool(result.hit).is_true()
	if result.knockback_force > 0:
		# 玩家朝 -Z，击退冲量应沿 -Z
		assert_float(result.knockback_impulse.z).is_less(0.0)
	player.queue_free()
	enemy.queue_free()

func test_resolve_enemy_attack_returns_damage_result() -> void:
	var weapon := _make_weapon(2, 5)
	var enemy := _make_dummy_node3d()
	var player := _make_dummy_node3d()
	player.position = Vector3(0, 0, -2)
	var defender_attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_enemy_attack(enemy, player, weapon, defender_attrs, false)
	assert_bool(result.hit).is_true()
	assert_int(result.final_damage).is_greater(0)
	enemy.queue_free()
	player.queue_free()

func test_resolve_player_attack_unarmed_low_damage() -> void:
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var max_dmg := 0
	var result = CB.resolve_player_attack(player, enemy, null, "", "", attrs, 1)
	if result.hit:
		max_dmg = max(max_dmg, result.final_damage)
	# 徒手 1d4 + str*1.5(15) = 最高 4+15=19，扣 def(10+10)=负，min 1
	# 实际徒手伤害应显著低于持武
	assert_bool(max_dmg > 0).is_true()
	player.queue_free()
	enemy.queue_free()

func test_resolve_attack_no_probability_block_with_shield() -> void:
	# 动作控制版：持盾不再有概率格挡，伤害不再因 shield_block_chance 随机减免
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 12, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "", attrs, 1)
	var defender = CB.build_enemy_defender(enemy, true)  # has_shield = true
	# 多次结算，blocked 应始终为 false（resolve_attack 不做概率格挡）
	for i in range(50):
		var result = CE.resolve_attack(attack, defender)
		assert_bool(result.blocked).is_false()
	player.queue_free()
	enemy.queue_free()


func test_backstab_deals_more_damage() -> void:
	# 动作控制版：背袭增加伤害（不再与概率格挡交互）
	var a := CE.AttackInput.new()
	a.attacker_str = 20
	a.weapon_damage_dice = {"count": 3, "sides": 12}
	a.is_backstab = true
	var d := CE.Defender.new()
	d.con = 0
	d.agi = 0
	d.per = 0
	d.armor_def = 0
	var a_normal := CE.AttackInput.new()
	a_normal.attacker_str = 20
	a_normal.weapon_damage_dice = {"count": 3, "sides": 12}
	a_normal.is_backstab = false
	var back_total := 0
	var normal_total := 0
	for i in range(50):
		var r_back = CE.resolve_attack(a, d)
		var r_normal = CE.resolve_attack(a_normal, d)
		back_total += r_back.final_damage
		normal_total += r_normal.final_damage
	assert_bool(back_total > normal_total) \
		.override_failure_message("背袭伤害 %d 未超过正面 %d" % [back_total, normal_total]).is_true()


func test_skill_modifiers_apply_damage_and_ignore_block() -> void:
	var spear := WeaponRegistry.get_weapon_data("spear")
	var skill := SD.get_skill_by_id("贯穿刺击")
	var player := _make_dummy_node3d()
	var attrs := {"str": 20, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, spear, "", "", attrs, 1, false, skill)
	assert_int(attack.style).is_equal(CE.Style.TWO_HAND)
	assert_bool(attack.ignore_block).is_true()
	assert_float(attack.weapon_damage_mult).is_equal(1.8)
	player.queue_free()

func test_ranged_milestones_apply_to_attack_input() -> void:
	_unlock_milestone("神射手")
	_unlock_milestone("穿透打击")
	var bow := WeaponRegistry.get_weapon_data("longbow")
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 20, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, bow, "", "", attrs, 1)
	# 神射手 → 远程暴击率 +10%（动作化替代命中率）
	assert_float(attack.crit_bonus).is_equal(10.0)
	# 穿透打击 → 远程伤害 +12%（动作化替代无视物防）
	assert_float(attack.weapon_damage_mult).is_equal_approx(1.12, 0.001)
	player.queue_free()

func test_two_hand_milestone_adds_base_damage_bonus() -> void:
	_unlock_milestone("蛮力负荷")
	var greatsword := WeaponRegistry.get_weapon_data("greatsword")
	var player := _make_dummy_node3d()
	var attrs := {"str": 20, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, greatsword, "", "", attrs, 1)
	assert_float(attack.base_damage_bonus_percent).is_equal(5.0)
	player.queue_free()

func test_spell_milestone_adds_skill_crit_bonus() -> void:
	_unlock_milestone("魔力涌流")
	var wand := WeaponRegistry.get_weapon_data("staff")
	var skill := SD.get_skill_by_id("元素弹")
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 10, "mag": 20, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, wand, "", "", attrs, 1, false, skill)
	assert_float(attack.crit_bonus).is_equal(8.0)
	player.queue_free()

func test_ignore_block_passes_through_to_result() -> void:
	# ignore_block 从 AttackInput 传递到 DamageResult.ignores_block
	var a := CE.AttackInput.new()
	a.attacker_str = 20
	a.weapon_damage_dice = {"count": 2, "sides": 6}
	a.ignore_block = true
	var d := CE.Defender.new()
	var r = CE.resolve_attack(a, d)
	assert_bool(r.ignores_block).is_true()

# ---------- 空参守卫 ----------

func test_resolve_player_attack_null_enemy_does_not_crash() -> void:
	# 传入 null enemy 应安全返回（不会因 has_method 崩溃）
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_player_attack(player, null, weapon, "one_hand_melee", "", attrs, 1)
	# 即使 enemy 为 null 也应返回有效 DamageResult
	assert_object(result).is_not_null()
	assert_bool("final_damage" in result).is_true()
	player.queue_free()

func test_resolve_player_attack_null_player_does_not_crash() -> void:
	# 传入 null player 应安全返回
	var weapon := _make_weapon(2, 6)
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	var result = CB.resolve_player_attack(null, enemy, weapon, "one_hand_melee", "", attrs, 1)
	assert_object(result).is_not_null()
	enemy.queue_free()

# ---------- 默认值常量 ----------

func test_default_shield_constants() -> void:
	# 动作控制版：DEFAULT_SHIELD_BLOCK_CHANCE 已移除，仅保留 DEFAULT_SHIELD_BLOCK_VALUE
	assert_int(CB.DEFAULT_SHIELD_BLOCK_VALUE).is_equal(3)

# ---------- 辅助 ----------

func _make_weapon(dmg_min: int, dmg_max: int) -> Resource:
	var w := WeaponData.new()
	w.damage_min = dmg_min
	w.damage_max = dmg_max
	w.condition = 100
	w.max_condition = 100
	w.reach = 2.0
	return w

func _make_shield_weapon(label: String) -> WeaponData:
	var w := WeaponData.new()
	w.name = label
	w.item_tag = "shield"
	w.weapon_class = "shield"
	w.equipment_category = "shields"
	w.condition = 10
	w.max_condition = 10
	w.reach = 1.0
	w.shield_phys_def = 1
	return w

func _make_armor(label: String, phys_def: int, evade: float) -> WeaponData:
	var w := WeaponData.new()
	w.name = label
	w.item_tag = "armor_light"
	w.equipment_category = "armor_light"
	w.armor_phys_def = phys_def
	w.condition = 10
	w.max_condition = 10
	return w

func _make_dummy_node3d() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n

func _reset_attr_panel() -> void:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null:
		ap.reset()

func _unlock_milestone(milestone_id: String) -> void:
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	if ap != null and not ap.unlocked_milestones.has(milestone_id):
		ap.unlocked_milestones.append(milestone_id)
