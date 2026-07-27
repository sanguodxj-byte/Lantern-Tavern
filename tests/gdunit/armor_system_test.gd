extends GdUnitTestSuite
## 护甲体系单元测试（策划案《35-护甲体系》）
## 覆盖：ArmorResolver 结算管线、ArmorProficiency 熟练度被动、DamageResolver 集成。
## 参考表 §3.2（k=8）验证百分比减伤公式。

const AR := preload("res://globals/combat/armor_resolver.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")
const CB := preload("res://globals/combat/combat_bridge.gd")

# ============================================================================
# 每测试前后重置 ArmorProficiency autoload 状态
# ============================================================================

func before_test() -> void:
	AR.clear_snapshot_cache()
	_reset_armor_proficiency()

func after_test() -> void:
	AR.clear_snapshot_cache()
	_reset_armor_proficiency()

func _reset_armor_proficiency() -> void:
	var ap: Node = _get_armor_proficiency()
	if ap != null:
		ap.reset()

func _get_armor_proficiency() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	var ap: Node = tree.root.get_node_or_null("ArmorProficiency")
	if ap != null:
		ap.reset()
	return ap

# ============================================================================
# §3.1 物理百分比减伤公式（k=8）
# ============================================================================

func test_mitigation_normal_attack() -> void:
	# 重甲 vs 普攻：def=80, base=50 → mit≈16.7%, final≈42
	var input := AR.ResolveInput.new()
	input.base_damage = 50.0
	input.total_phys_def = 70.0  # 80 total with con=10
	input.con = 10
	var result := AR.resolve(input)
	# mit = 80 / (80 + 8*50) = 80/480 = 0.16667
	assert_float(result.physical_mitigation).is_equal_approx(0.16667, 0.001)
	# post_mit = 50 * (1 - 0.16667) = 41.67 → round = 42
	assert_int(result.final_damage).is_equal(42)

func test_mitigation_small_damage() -> void:
	# 重甲 vs 小伤：def=80, base=20 → mit=33.3%, final=13
	var input := AR.ResolveInput.new()
	input.base_damage = 20.0
	input.total_phys_def = 70.0  # 80 total with con=10
	input.con = 10
	var result := AR.resolve(input)
	# mit = 80 / (80 + 8*20) = 80/240 = 0.3333
	assert_float(result.physical_mitigation).is_equal_approx(0.3333, 0.001)
	assert_int(result.final_damage).is_equal(13)

func test_mitigation_boss_damage() -> void:
	# 任意甲 vs Boss 巨伤：def=60, base=200 → mit≈3.6%, final≈193
	var input := AR.ResolveInput.new()
	input.base_damage = 200.0
	input.total_phys_def = 50.0  # 60 total with con=10
	input.con = 10
	var result := AR.resolve(input)
	# mit = 60 / (60 + 8*200) = 60/1660 = 0.03614
	assert_float(result.physical_mitigation).is_equal_approx(0.03614, 0.001)
	assert_int(result.final_damage).is_equal(193)

func test_mitigation_high_def() -> void:
	# 高甲 vs 普攻：def=120, base=50 → mit≈23.1%, final=38
	var input := AR.ResolveInput.new()
	input.base_damage = 50.0
	input.total_phys_def = 110.0  # 120 total with con=10
	input.con = 10
	var result := AR.resolve(input)
	# mit = 120 / (120 + 8*50) = 120/520 = 0.23077
	assert_float(result.physical_mitigation).is_equal_approx(0.23077, 0.001)
	assert_int(result.final_damage).is_equal(38)

func test_mitigation_cap_90_percent() -> void:
	# 极高防御 + 低伤害 → 减伤封顶 90%
	var input := AR.ResolveInput.new()
	input.base_damage = 10.0
	input.total_phys_def = 1000.0
	input.con = 10
	var result := AR.resolve(input)
	# mit = 1010 / (1010 + 80) = 0.9264... → capped at 0.90
	assert_float(result.physical_mitigation).is_equal(0.90)
	# post_mit = 10 * 0.1 = 1.0
	assert_int(result.final_damage).is_equal(1)

func test_min_damage_floor() -> void:
	# 极高防御 + 元素抗性 + 里程碑减免 → 最终伤害不低于 1
	var input := AR.ResolveInput.new()
	input.base_damage = 5.0
	input.total_phys_def = 500.0
	input.con = 10
	input.fire_res = 10
	input.flat_reduce = 10
	input.element_type = "fire"
	var result := AR.resolve(input)
	assert_int(result.final_damage).is_equal(1)

# ============================================================================
# §3.3 品质系数 / 材质倍率 / 稀有度系数
# ============================================================================

func test_quality_coefficients() -> void:
	assert_float(AR.get_quality_coefficient("EXCELLENT")).is_equal(1.0)
	assert_float(AR.get_quality_coefficient("SERVICEABLE")).is_equal(0.9)
	assert_float(AR.get_quality_coefficient("WORN")).is_equal(0.75)
	assert_float(AR.get_quality_coefficient("DECREPIT")).is_equal(0.5)
	assert_float(AR.get_quality_coefficient("DESTROYED")).is_equal(0.0)
	# 未知品质安全降级
	assert_float(AR.get_quality_coefficient("UNKNOWN")).is_equal(1.0)

func test_material_multipliers() -> void:
	assert_float(AR.get_material_multiplier("wood")).is_equal(0.90)
	assert_float(AR.get_material_multiplier("iron")).is_equal(1.0)
	assert_float(AR.get_material_multiplier("steel")).is_equal(1.05)
	assert_float(AR.get_material_multiplier("meteoric")).is_equal(1.10)
	assert_float(AR.get_material_multiplier("mithril")).is_equal(1.15)
	assert_float(AR.get_material_multiplier("adamantite")).is_equal(1.20)

func test_rarity_coefficients() -> void:
	assert_float(AR.get_rarity_coefficient("INFERIOR")).is_equal(0.85)
	assert_float(AR.get_rarity_coefficient("COMMON")).is_equal(1.0)
	assert_float(AR.get_rarity_coefficient("SUPERIOR")).is_equal(1.03)
	assert_float(AR.get_rarity_coefficient("RARE")).is_equal(1.06)
	assert_float(AR.get_rarity_coefficient("EPIC")).is_equal(1.10)
	assert_float(AR.get_rarity_coefficient("ARTIFACT")).is_equal(1.15)

# ============================================================================
# §3.3 有效物理防御 = base × quality × material × rarity
# ============================================================================

func test_effective_phys_def_full() -> void:
	# base=10, EXCELLENT(1.0) × steel(1.05) × RARE(1.06) = 10 × 1.0 × 1.05 × 1.06 = 11.13
	var armor := _make_armor_piece(10, "EXCELLENT", "steel", "RARE")
	var eff := AR.get_effective_phys_def(armor)
	assert_float(eff).is_equal_approx(11.13, 0.01)

func test_effective_phys_def_decrepit() -> void:
	# base=20, DECREPIT(0.5) × iron(1.0) × COMMON(1.0) = 20 × 0.5 = 10
	var armor := _make_armor_piece(20, "DECREPIT", "iron", "COMMON")
	var eff := AR.get_effective_phys_def(armor)
	assert_float(eff).is_equal(10.0)

func test_effective_phys_def_null() -> void:
	assert_float(AR.get_effective_phys_def(null)).is_equal(0.0)

func test_effective_element_res_with_quality() -> void:
	# base_res=10, WORN(0.75) → 10 × 0.75 = 7.5 → round = 8
	var armor := _make_armor_piece(0, "WORN", "iron", "COMMON")
	armor.armor_fire_res = 10
	var res := AR.get_effective_element_res(armor, "fire")
	assert_int(res).is_equal(8)

# ============================================================================
# §4 元素抗性 / 魔法减伤 / 击退抗性
# ============================================================================

func test_element_resistance_fire() -> void:
	# base=100, no phys_def, fire_res=20, element=fire
	var input := AR.ResolveInput.new()
	input.base_damage = 100.0
	input.con = 0
	input.fire_res = 20
	input.element_type = "fire"
	var result := AR.resolve(input)
	# post_mit = 100 (no phys def), post_elem = 100 - 20 = 80
	assert_int(result.element_absorbed).is_equal(20)
	assert_int(result.final_damage).is_equal(80)

func test_element_resistance_no_match() -> void:
	# 元素类型不匹配时，对应抗性不生效
	var input := AR.ResolveInput.new()
	input.base_damage = 100.0
	input.con = 0
	input.fire_res = 20
	input.ice_res = 15
	input.element_type = "ice"
	var result := AR.resolve(input)
	# fire_res 不生效，ice_res=15 生效
	assert_int(result.element_absorbed).is_equal(15)
	assert_int(result.final_damage).is_equal(85)

func test_magic_resistance_spell() -> void:
	# spell damage 100, magic_res_percent=30 → 100 × (1 - 30/100) = 70
	var input := AR.ResolveInput.new()
	input.base_damage = 100.0
	input.con = 0
	input.attack_type = "spell"
	input.total_magic_res_percent = 30.0
	var result := AR.resolve(input)
	assert_float(result.magic_mitigation).is_equal(30.0)
	assert_int(result.final_damage).is_equal(70)

func test_magic_resistance_cap_75() -> void:
	# magic_res_percent=100 → capped at 75
	var input := AR.ResolveInput.new()
	input.base_damage = 100.0
	input.con = 0
	input.attack_type = "spell"
	input.total_magic_res_percent = 100.0
	var result := AR.resolve(input)
	assert_float(result.magic_mitigation).is_equal(75.0)
	assert_int(result.final_damage).is_equal(25)

func test_magic_resistance_non_spell_ignored() -> void:
	# 非法术攻击不触发魔法减伤
	var input := AR.ResolveInput.new()
	input.base_damage = 100.0
	input.con = 0
	input.attack_type = "melee"
	input.total_magic_res_percent = 50.0
	var result := AR.resolve(input)
	assert_float(result.magic_mitigation).is_equal(0.0)
	assert_int(result.final_damage).is_equal(100)

func test_knockback_resistance() -> void:
	var snap := AR.ArmorSnapshot.new()
	snap.total_knockback_res = 0.5
	# 基础击退 10, 抗性 0.5 → 有效击退 5
	var effective := AR.resolve_knockback(10.0, snap)
	assert_float(effective).is_equal(5.0)

func test_knockback_resistance_full() -> void:
	var snap := AR.ArmorSnapshot.new()
	snap.total_knockback_res = 1.0
	# 完全免疫
	var effective := AR.resolve_knockback(10.0, snap)
	assert_float(effective).is_equal(0.0)

func test_knockback_resistance_null() -> void:
	# null snapshot → 原样返回
	var effective := AR.resolve_knockback(10.0, null)
	assert_float(effective).is_equal(10.0)

# ============================================================================
# §5 穿透 / 无视防御
# ============================================================================

func test_ignore_def_percent() -> void:
	# def=80, 50% 穿透 → effective def = 40
	var input := AR.ResolveInput.new()
	input.base_damage = 50.0
	input.total_phys_def = 70.0  # +con=80
	input.con = 10
	input.ignore_def_percent = 50.0
	var result := AR.resolve(input)
	# eff_def = 80 × (1 - 0.5) = 40
	# mit = 40 / (40 + 8*50) = 40/440 = 0.0909
	assert_float(result.effective_def).is_equal(40.0)
	assert_float(result.physical_mitigation).is_equal_approx(0.0909, 0.001)

func test_ignore_def_full() -> void:
	# 骷髅+锤被动：完全无视防御
	var input := AR.ResolveInput.new()
	input.base_damage = 50.0
	input.total_phys_def = 70.0
	input.con = 10
	input.ignore_def = true
	var result := AR.resolve(input)
	assert_float(result.effective_def).is_equal(0.0)
	assert_float(result.physical_mitigation).is_equal(0.0)
	assert_int(result.final_damage).is_equal(50)

# ============================================================================
# §4 护甲面板快照构建
# ============================================================================

func test_build_snapshot_empty() -> void:
	var eq := _MockEq.new()
	var snap := AR.build_snapshot(eq)
	assert_object(snap).is_not_null()
	assert_float(snap.total_phys_def).is_equal(0.0)
	assert_int(snap.total_fire_res).is_equal(0)
	assert_bool(snap.has_light).is_false()
	assert_bool(snap.has_heavy).is_false()

func test_build_snapshot_with_light_armor() -> void:
	var eq := _MockEq.new()
	eq.items.append(_make_armor_piece(5, "EXCELLENT", "iron", "COMMON", "light"))
	eq.items.append(_make_typed_armor(3, "light", 5, 0))
	var snap := AR.build_snapshot(eq)
	assert_bool(snap.has_light).is_true()
	assert_bool(snap.has_heavy).is_false()
	# phys_def = 5 (EXCELLENT × iron × COMMON) + 3 (EXCELLENT × iron × COMMON) = 8
	assert_float(snap.total_phys_def).is_equal(8.0)
	# fire_res = 5 (from second piece)
	assert_int(snap.total_fire_res).is_equal(5)

func test_build_snapshot_with_heavy_armor() -> void:
	var eq := _MockEq.new()
	var armor := _make_typed_armor(10, "heavy", 0, 10)
	armor.armor_knockback_res = 0.1
	eq.items.append(armor)
	var snap := AR.build_snapshot(eq)
	assert_bool(snap.has_heavy).is_true()
	assert_bool(snap.has_light).is_false()
	assert_float(snap.total_knockback_res).is_equal(0.1)

func test_build_snapshot_magic_res_cap() -> void:
	var eq := _MockEq.new()
	var armor1 := _make_typed_armor(0, "heavy", 0, 0)
	armor1.armor_magic_res_percent = 50.0
	var armor2 := _make_typed_armor(0, "heavy", 0, 0)
	armor2.armor_magic_res_percent = 50.0
	eq.items.append(armor1)
	eq.items.append(armor2)
	var snap := AR.build_snapshot(eq)
	# 50 + 50 = 100 → capped at 75
	assert_float(snap.total_magic_res_percent).is_equal(75.0)

func test_build_snapshot_null() -> void:
	var snap := AR.build_snapshot(null)
	assert_object(snap).is_not_null()
	assert_float(snap.total_phys_def).is_equal(0.0)

# ============================================================================
# §4.1 护甲快照缓存（性能优化：指纹命中 → O(1) 复用，装备变更 → 重建）
# ============================================================================

func test_snapshot_cache_hit_returns_same_object() -> void:
	# 同一装备组件 + 同一装备项 → 指纹相同 → 缓存命中 → 返回同一对象
	var eq := _MockEq.new()
	eq.items.append(_make_typed_armor(10, "heavy", 0, 0))
	var snap1 := AR.build_snapshot(eq)
	var snap2 := AR.build_snapshot(eq)
	# 缓存命中：两次返回同一个 ArmorSnapshot 对象（引用相等）
	assert_int(snap1.get_instance_id()).is_equal(snap2.get_instance_id())
	assert_float(snap2.total_phys_def).is_equal(10.0)

func test_snapshot_cache_rebuild_on_equipment_change() -> void:
	# 装备项增删 → 指纹变化 → 重建快照（新对象，聚合值更新）
	var eq := _MockEq.new()
	eq.items.append(_make_typed_armor(10, "heavy", 0, 0))
	var snap1 := AR.build_snapshot(eq)
	# 新增一件护甲 → 指纹不同 → 缓存未命中 → 重建
	eq.items.append(_make_typed_armor(5, "heavy", 0, 0))
	var snap2 := AR.build_snapshot(eq)
	# 不同对象，且总防御更新为 10 + 5 = 15
	assert_int(snap1.get_instance_id()).is_not_equal(snap2.get_instance_id())
	assert_float(snap2.total_phys_def).is_equal(15.0)

func test_snapshot_cache_invalidate_forces_rebuild() -> void:
	# 显式失效后再次构建 → 产生新对象（而非缓存命中）
	var eq := _MockEq.new()
	eq.items.append(_make_typed_armor(10, "heavy", 0, 0))
	var snap1 := AR.build_snapshot(eq)
	AR.invalidate_snapshot_cache(eq)
	var snap2 := AR.build_snapshot(eq)
	assert_int(snap1.get_instance_id()).is_not_equal(snap2.get_instance_id())
	# 值仍正确（重建后聚合）
	assert_float(snap2.total_phys_def).is_equal(10.0)

func test_snapshot_cache_clear_all() -> void:
	# clear_snapshot_cache 清空全部条目，后续构建产生新对象
	var eq := _MockEq.new()
	eq.items.append(_make_typed_armor(10, "heavy", 0, 0))
	var snap1 := AR.build_snapshot(eq)
	AR.clear_snapshot_cache()
	var snap2 := AR.build_snapshot(eq)
	assert_int(snap1.get_instance_id()).is_not_equal(snap2.get_instance_id())
	assert_float(snap2.total_phys_def).is_equal(10.0)

func test_snapshot_cache_separate_per_equipment_component() -> void:
	# 不同装备组件实例 → 独立缓存条目 → 互不干扰
	var eq1 := _MockEq.new()
	eq1.items.append(_make_typed_armor(10, "heavy", 0, 0))
	var eq2 := _MockEq.new()
	eq2.items.append(_make_typed_armor(20, "heavy", 0, 0))
	var snap1 := AR.build_snapshot(eq1)
	var snap2 := AR.build_snapshot(eq2)
	assert_float(snap1.total_phys_def).is_equal(10.0)
	assert_float(snap2.total_phys_def).is_equal(20.0)
	# 再次构建 eq1 仍命中自身缓存
	var snap1_again := AR.build_snapshot(eq1)
	assert_int(snap1.get_instance_id()).is_equal(snap1_again.get_instance_id())

func test_snapshot_cache_null_eq_returns_empty() -> void:
	# null 装备组件 → 返回空快照（不缓存、不崩溃）
	var snap := AR.build_snapshot(null)
	assert_object(snap).is_not_null()
	assert_float(snap.total_phys_def).is_equal(0.0)

# ============================================================================
# §6 ArmorProficiency 熟练度系统
# ============================================================================

func test_proficiency_level_progression() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	# 初始等级 1
	assert_int(ap.get_level("light")).is_equal(1)
	assert_int(ap.get_level("heavy")).is_equal(1)
	# 10 exp → level 2
	ap.add_exp("light", 10)
	assert_int(ap.get_level("light")).is_equal(2)
	# 90 exp total → level 10 (T1 解锁)
	ap.add_exp("light", 80)  # total 90
	assert_int(ap.get_level("light")).is_equal(10)

func test_proficiency_perk_unlock_t1() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	assert_int(ap.get_exp("light")).is_equal(0)
	# Lv.9 → T1 未解锁
	ap.add_exp("light", 80)  # level 9
	assert_bool(ap.has_perk("light", "light_t1")).is_false()
	# Lv.10 → T1 解锁
	ap.add_exp("light", 10)  # total 90 exp, level 10
	assert_bool(ap.has_perk("light", "light_t1")).is_true()

func test_proficiency_perk_unlock_t3() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	# Lv.60 → T3 解锁
	ap.add_exp("heavy", 590)  # level 60
	assert_bool(ap.has_perk("heavy", "heavy_t1")).is_true()
	assert_bool(ap.has_perk("heavy", "heavy_t2")).is_true()
	assert_bool(ap.has_perk("heavy", "heavy_t3")).is_true()

func test_proficiency_max_level_cap() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.add_exp("light", 99999)
	assert_int(ap.get_level("light")).is_equal(100)

func test_proficiency_heavy_t1_bonus() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("heavy", true)
	ap.add_exp("heavy", 90)  # Lv.10 → T1
	# T1: +2 flat
	var bonus: float = ap.get_heavy_phys_def_bonus(40.0)
	assert_float(bonus).is_equal(2.0)

func test_proficiency_heavy_t2_bonus() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("heavy", true)
	ap.add_exp("heavy", 290)  # Lv.30 → T2
	# T1(+2) + T2(+5% of 40=2) = 4
	var bonus: float = ap.get_heavy_phys_def_bonus(40.0)
	assert_float(bonus).is_equal(4.0)

func test_proficiency_heavy_t3_bonus() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("heavy", true)
	ap.add_exp("heavy", 590)  # Lv.60 → T3
	# T1(+2) + T2(+5% of 40=2) + T3(+10% of 40=4) = 8
	var bonus: float = ap.get_heavy_phys_def_bonus(40.0)
	assert_float(bonus).is_equal(8.0)

func test_proficiency_heavy_t3_knockback_immune() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("heavy", true)
	ap.add_exp("heavy", 590)  # Lv.60
	# T3: full immunity
	var res: float = ap.get_effective_knockback_res(0.1)
	assert_float(res).is_equal(1.0)

func test_proficiency_heavy_not_wearing() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("heavy", false)
	ap.add_exp("heavy", 590)  # Lv.60 but not wearing
	# 不穿重甲 → 无加成
	var bonus: float = ap.get_heavy_phys_def_bonus(40.0)
	assert_float(bonus).is_equal(0.0)
	var res: float = ap.get_effective_knockback_res(0.1)
	assert_float(res).is_equal(0.1)

func test_proficiency_light_t3_crit_reduction() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("light", true)
	ap.add_exp("light", 590)  # Lv.60 → T3
	assert_float(ap.get_crit_rate_reduction()).is_equal(5.0)

func test_proficiency_light_t2_flanking_reduction() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("light", true)
	ap.add_exp("light", 290)  # Lv.30 → T2
	assert_float(ap.get_flanking_damage_reduction()).is_equal(0.50)

func test_proficiency_light_dodge_tier_bonus() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("light", true)
	# T1
	ap.add_exp("light", 90)  # Lv.10
	assert_int(ap.get_dodge_tier_bonus()).is_equal(1)
	# T2
	ap.add_exp("light", 200)  # Lv.30
	assert_int(ap.get_dodge_tier_bonus()).is_equal(2)
	# T3
	ap.add_exp("light", 300)  # Lv.60
	assert_int(ap.get_dodge_tier_bonus()).is_equal(3)

func test_proficiency_on_hit_received() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.set_wearing("light", true)
	ap.set_wearing("heavy", true)
	# 普通受击 +1
	ap.on_hit_received(false)
	assert_int(ap.get_exp("light")).is_equal(1)
	assert_int(ap.get_exp("heavy")).is_equal(1)
	# 格挡受击 +2
	ap.on_hit_received(true)
	assert_int(ap.get_exp("light")).is_equal(3)
	assert_int(ap.get_exp("heavy")).is_equal(3)

func test_proficiency_save_load() -> void:
	var ap := _get_armor_proficiency()
	if ap == null:
		return # ArmorProficiency autoload not available
	ap.add_exp("light", 100)
	ap.add_exp("heavy", 50)
	var saved: Dictionary = ap.to_dict()
	ap.reset()
	assert_int(ap.get_exp("light")).is_equal(0)
	ap.from_dict(saved)
	assert_int(ap.get_exp("light")).is_equal(100)
	assert_int(ap.get_exp("heavy")).is_equal(50)

# ============================================================================
# 集成测试：DamageResolver 使用 ArmorResolver 管线
# ============================================================================

func test_resolve_attack_with_snapshot() -> void:
	# 玩家穿着重甲，被敌人攻击
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.weapon_damage_mult = 1.0
	attack.attack_type = "melee"
	# 基础伤害 ≈ (3.5 + 0 + 15) × 1.0 = 18.5
	var defender := DR.Defender.new()
	defender.con = 10
	defender.armor_def = 20
	# 构建快照：total_phys_def = 20
	var snap := AR.ArmorSnapshot.new()
	snap.total_phys_def = 20.0
	defender.armor_snapshot = snap
	var result := DR.resolve_attack(attack, defender)
	assert_object(result).is_not_null()
	assert_int(result.final_damage).is_greater(0)
	# def = 20 + 10 = 30, mit = 30/(30+8*18.5) = 30/178 = 0.1685
	# post_mit = 18.5 * 0.8315 = 15.38 → 15
	# (base_damage may vary slightly due to rounding)

func test_resolve_attack_backward_compat() -> void:
	# 无快照时退化为 armor_def + con
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.weapon_damage_mult = 1.0
	attack.attack_type = "melee"
	var defender := DR.Defender.new()
	defender.con = 10
	defender.armor_def = 20
	# armor_snapshot = null → 用 armor_def 作为 total_phys_def
	var result := DR.resolve_attack(attack, defender)
	assert_object(result).is_not_null()
	assert_int(result.final_damage).is_greater(0)
	# def = 20 + 10 = 30, same as with snapshot

func test_resolve_attack_knockback_with_resistance() -> void:
	# 击退抗性 50% → 有效击退减半
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.attack_type = "melee"
	attack.knockback_force = 10.0
	attack.style = DR.Style.ONE_HAND  # 非 TWO_HAND，不加额外击退
	var defender := DR.Defender.new()
	defender.con = 10
	var snap := AR.ArmorSnapshot.new()
	snap.total_knockback_res = 0.5
	defender.armor_snapshot = snap
	var result := DR.resolve_attack(attack, defender, Vector3(1, 0, 0))
	# 有效击退 = 10 × 1.0 × (1 - 0.5) = 5.0
	assert_float(result.knockback_force).is_equal(5.0)

func test_resolve_attack_proficiency_phys_def_bonus() -> void:
	# 重甲熟练度 T1: +2 phys_def → 伤害更低
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.attack_type = "melee"
	attack.attacker_per = 10
	# 无加成
	var defender_no := DR.Defender.new()
	defender_no.con = 10
	var snap_no := AR.ArmorSnapshot.new()
	snap_no.total_phys_def = 20.0
	defender_no.armor_snapshot = snap_no
	# 有加成 (+2)
	var defender_bonus := DR.Defender.new()
	defender_bonus.con = 10
	var snap_bonus := AR.ArmorSnapshot.new()
	snap_bonus.total_phys_def = 20.0
	defender_bonus.armor_snapshot = snap_bonus
	defender_bonus.prof_phys_def_bonus = 2.0
	var result_no := DR.resolve_attack(attack, defender_no)
	var result_with := DR.resolve_attack(attack, defender_bonus)
	# 有加成时防御更高 → 伤害更低或相等
	assert_int(result_with.final_damage).is_less_equal(result_no.final_damage)

func test_resolve_attack_proficiency_crit_reduction() -> void:
	# 轻甲 T3: 被暴击率 -5%
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.attack_type = "melee"
	attack.attacker_per = 100  # 高 per → 高暴击率
	attack.crit_bonus = 50.0
	var defender := DR.Defender.new()
	defender.con = 10
	defender.per = 10
	defender.prof_crit_rate_reduction = 5.0  # T3 reduction
	# 暴击率 = 5 + 100*0.5 - 10*0.5 + 50 - 5 = 100 → 一定暴击（不减）
	# 即使 -5%，暴击率仍为 95%+，几乎一定暴击
	var result := DR.resolve_attack(attack, defender)
	assert_bool(result.crit).is_true()

func test_resolve_attack_proficiency_flanking_reduction() -> void:
	# 轻甲 T2: 背刺伤害加成降低 50%
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.attack_type = "melee"
	attack.is_backstab = true
	var defender_no_red := DR.Defender.new()
	defender_no_red.con = 10
	defender_no_red.per = 10
	var defender_with_red := DR.Defender.new()
	defender_with_red.con = 10
	defender_with_red.per = 10
	defender_with_red.prof_flanking_reduction = 0.5  # T2 reduction
	var result_no := DR.resolve_attack(attack, defender_no_red)
	var result_with := DR.resolve_attack(attack, defender_with_red)
	# 有侧身闪避时背刺伤害更低
	assert_int(result_with.final_damage).is_less(result_no.final_damage)

func test_resolve_attack_proficiency_knockback_immune() -> void:
	# 重甲 T3: 完全免疫击退
	var attack := DR.AttackInput.new()
	attack.attacker_str = 10
	attack.weapon_damage_dice = {"count": 1, "sides": 6}
	attack.attack_type = "melee"
	attack.knockback_force = 10.0
	attack.style = DR.Style.ONE_HAND
	var defender := DR.Defender.new()
	defender.con = 10
	defender.prof_knockback_immune = true
	var result := DR.resolve_attack(attack, defender)
	# 完全免疫击退 → knockback_force = 0
	assert_float(result.knockback_force).is_equal(0.0)

# ============================================================================
# CombatBridge 集成测试
# ============================================================================

func test_build_player_defender_with_snapshot() -> void:
	var player := _make_dummy_node3d()
	var attrs := {"con": 12, "agi": 10, "per": 10}
	var defender := CB.build_player_defender(player, attrs, false, 10, null, null)
	assert_int(defender.con).is_equal(12)
	assert_object(defender.armor_snapshot).is_null()
	player.queue_free()

func test_build_player_defender_from_equipment() -> void:
	# 使用 _MockEq 验证 build_snapshot 路径
	var eq := _MockEq.new()
	eq.items.append(_make_typed_armor(5, "light", 0, 0))
	var snap := AR.build_snapshot(eq)
	assert_float(snap.total_phys_def).is_equal(5.0)
	assert_bool(snap.has_light).is_true()

# ============================================================================
# 辅助类与函数
# ============================================================================

class _MockEq:
	var items: Array = []
	func get_equipped_armor_items() -> Array:
		return items

func _make_armor_piece(phys_def: int, quality: String, material: String, rarity_str: String, armor_type: String = "") -> WeaponData:
	var w := WeaponData.new()
	w.armor_phys_def = phys_def
	w.quality_tier = quality
	w.material_tier = material
	w.rarity = rarity_str
	w.armor_type = armor_type
	w.condition = 100
	w.max_condition = 100
	return w

func _make_typed_armor(phys_def: int, armor_type: String, fire_res: int, magic_res: float) -> WeaponData:
	var w := WeaponData.new()
	w.armor_phys_def = phys_def
	w.armor_type = armor_type
	w.armor_fire_res = fire_res
	w.armor_magic_res_percent = magic_res
	w.quality_tier = "EXCELLENT"
	w.material_tier = "iron"
	w.rarity = "COMMON"
	w.condition = 100
	w.max_condition = 100
	w.equipment_category = "armor_" + armor_type
	w.item_tag = "armor_" + armor_type
	return w

func _make_dummy_node3d() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n


