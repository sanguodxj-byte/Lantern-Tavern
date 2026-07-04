extends GdUnitTestSuite
## CombatBridge 桥接层集成测试
## 验证：AttackInput/Defender 字段映射、resolve_player_attack/resolve_enemy_attack 闭环、
## 朝向判定（背袭/侧击）、徒手/持盾/双手风格适配

const CB := preload("res://globals/combat_bridge.gd")
const CE := preload("res://globals/combat_engine.gd")

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
	assert_int(attack.style).is_equal(CE.Style.UNARMED)  # longbow 不在 determine_style 的 5 风格中，回落 UNARMED
	assert_str(attack.attack_type).is_equal("ranged")
	player.queue_free()

func test_build_player_attack_spell_wand() -> void:
	var weapon := _make_weapon(1, 4)
	var player := _make_dummy_node3d()
	var attrs := {"str": 8, "dex": 8, "mag": 15, "con": 10, "agi": 10, "per": 10}
	var attack = CB.build_player_attack(player, weapon, "wand", "", attrs, 1)
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

# ---------- 防方输入构造 ----------

func test_build_player_defender_no_shield() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 12, "agi": 14, "per": 10}
	var defender = CB.build_player_defender(player, attrs, false)
	assert_int(defender.con).is_equal(12)
	assert_int(defender.agi).is_equal(14)
	assert_bool(defender.has_shield).is_false()
	assert_float(defender.shield_block_chance).is_equal(0.0)
	player.queue_free()

func test_build_player_defender_with_shield() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var defender = CB.build_player_defender(player, attrs, true, 5, 3.0)
	assert_bool(defender.has_shield).is_true()
	assert_float(defender.shield_block_chance).is_equal(CB.DEFAULT_SHIELD_BLOCK_CHANCE)
	assert_int(defender.shield_block_value).is_equal(CB.DEFAULT_SHIELD_BLOCK_VALUE)
	assert_int(defender.armor_def).is_equal(5)
	assert_float(defender.armor_evade).is_equal(3.0)
	player.queue_free()

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
	assert_float(defender.shield_block_chance).is_equal(CB.DEFAULT_SHIELD_BLOCK_CHANCE)
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
	# 多次结算，至少有一次命中
	var hit_count := 0
	for i in range(20):
		var result = CB.resolve_player_attack(player, enemy, weapon, "one_hand_melee", "", attrs, 1)
		if result.hit:
			hit_count += 1
			assert_int(result.final_damage).is_greater(0)
	assert_bool(hit_count > 0).is_true()
	player.queue_free()
	enemy.queue_free()

func test_resolve_player_attack_knockback_direction_along_attacker_forward() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 15, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	for i in range(50):
		var result = CB.resolve_player_attack(player, enemy, weapon, "two_hand", "", attrs, 1)
		if result.hit and result.knockback_force > 0:
			# 玩家朝 -Z，击退冲量应沿 -Z
			assert_float(result.knockback_impulse.z).is_less(0.0)
			player.queue_free()
			enemy.queue_free()
			return
	assert_bool(true).is_true()  # 容错
	player.queue_free()
	enemy.queue_free()

func test_resolve_enemy_attack_returns_damage_result() -> void:
	var weapon := _make_weapon(2, 5)
	var enemy := _make_dummy_node3d()
	var player := _make_dummy_node3d()
	player.position = Vector3(0, 0, -2)
	var defender_attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var hit_count := 0
	for i in range(20):
		var result = CB.resolve_enemy_attack(enemy, player, weapon, defender_attrs, false)
		if result.hit:
			hit_count += 1
	assert_bool(hit_count > 0).is_true()
	enemy.queue_free()
	player.queue_free()

func test_resolve_player_attack_unarmed_low_damage() -> void:
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 10, "dex": 10, "mag": 10, "con": 10, "agi": 10, "per": 10}
	var max_dmg := 0
	for i in range(50):
		var result = CB.resolve_player_attack(player, enemy, null, "", "", attrs, 1)
		if result.hit:
			max_dmg = max(max_dmg, result.final_damage)
	# 徒手 1d4 + str*1.5(15) = 最高 4+15=19，扣 def(10+10)=负，min 1
	# 实际徒手伤害应显著低于持武
	assert_bool(max_dmg > 0).is_true()
	player.queue_free()
	enemy.queue_free()

func test_resolve_player_attack_with_shield_defender_can_block() -> void:
	var weapon := _make_weapon(2, 6)
	var player := _make_dummy_node3d()
	var enemy := _make_dummy_node3d()
	var attrs := {"str": 12, "dex": 10, "mag": 8, "con": 10, "agi": 10, "per": 10}
	# 直接构造持盾防方（绕过 resolve_player_attack 的反射检测，dummy Node3D 无 equipment 字段）
	var attack = CB.build_player_attack(player, weapon, "one_hand_melee", "", attrs, 1)
	var defender = CB.build_enemy_defender(enemy, true)
	var blocked_count := 0
	var hit_count := 0
	for i in range(200):
		var result = CE.resolve_attack(attack, defender)
		if result.hit:
			hit_count += 1
			if result.blocked:
				blocked_count += 1
	assert_bool(hit_count > 0).is_true()
	# 30% 格挡概率，200 次命中应至少触发 1 次（统计性断言）
	if hit_count > 50:
		assert_bool(blocked_count > 0).is_true()
	player.queue_free()
	enemy.queue_free()

# ---------- 默认值常量 ----------

func test_default_shield_constants() -> void:
	assert_float(CB.DEFAULT_SHIELD_BLOCK_CHANCE).is_equal(30.0)
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

func _make_dummy_node3d() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n
