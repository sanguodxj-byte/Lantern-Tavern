class_name MilestoneEffects
## 6 属性里程碑被动效果实装（策划案《15-技能与领悟系统》§3）。
## 纯静态函数，读取 AttrPanel 解锁状态，返回效果修正值或触发副作用。
## 由 player.gd 受击/移动/休息路径调用。

# AttrPanel 是 autoload 单例，运行时通过引擎根节点取实例
static func _ap():
	return Engine.get_main_loop().root.get_node("AttrPanel")

# ============================================================================
# 1. 受击路径修正（策划案 §3.2 各属性里程碑）
# ============================================================================

## 厚实皮肤（CON T2）：每次受击最终扣血 -2（最低 1）
static func apply_thick_skin(damage: int) -> int:
	if _ap().has_milestone("厚实皮肤"):
		return maxi(damage - 2, 1)
	return damage

## 元素护壳（MAG T2）：受法术伤害最终扣血 -4
static func apply_elemental_aegis(damage: int, is_spell: bool) -> int:
	if is_spell and _ap().has_milestone("元素护壳"):
		return maxi(damage - 4, 1)
	return damage

## 侧垫步（AGI T1）：受近战攻击 10% 概率完全免伤
## 返回 true 表示触发侧闪，调用方应跳过伤害结算
static func try_sidestep(is_melee: bool) -> bool:
	if is_melee and _ap().has_milestone("侧垫步"):
		return randf() < 0.10
	return false

## 直觉闪避（PER T3）：侧击/背袭不再享有命中与伤害加成
## 返回 true 时调用方应取消朝向加成
static func negate_flank_bonus() -> bool:
	return _ap().has_milestone("直觉闪避")

# ============================================================================
# 2. 攻击路径修正
# ============================================================================

## 重力击（STR T2）：近战伤害投骰 +5%
static func apply_heavy_stride(damage: int, is_melee: bool) -> int:
	if is_melee and _ap().has_milestone("重力击"):
		return int(round(damage * 1.05))
	return damage

## 神射手（DEX T2）：长弓/轻弩远程命中率 +10%
static func apply_sharpshooter(hit_bonus: float, is_ranged: bool) -> float:
	if is_ranged and _ap().has_milestone("神射手"):
		return hit_bonus + 10.0
	return hit_bonus

## 穿透打击（DEX T3）：远程攻击 100% 概率无视 10% 物防
static func apply_penetrating_strike(ignore_def: float, is_ranged: bool) -> float:
	if is_ranged and _ap().has_milestone("穿透打击"):
		return maxf(ignore_def, 10.0)
	return ignore_def

## 震退（STR T1）：近战命中 15% 概率击退 1 米
## 返回 > 0 表示触发击退，值为击退米数
static func try_knockback_chance(is_melee: bool) -> float:
	if is_melee and _ap().has_milestone("震退"):
		if randf() < 0.15:
			return 1.5  # 1 格 = 1.5 米
	return 0.0

## 魔力涌流（MAG T3）：魔法技能暴击率 +8%
static func apply_mana_surge_crit(crit_rate: float, is_spell: bool) -> float:
	if is_spell and _ap().has_milestone("魔力涌流"):
		return crit_rate + 8.0
	return crit_rate

## 魔力凝息（MAG T1）：释放法杖/魔导书技能 10% 概率冷却清零
## 返回 true 表示触发冷却清零
static func try_mana_focus_cd_reset(is_spell_skill: bool) -> bool:
	if is_spell_skill and _ap().has_milestone("魔力凝息"):
		return randf() < 0.10
	return false

# ============================================================================
# 3. 移动路径修正
# ============================================================================

## 轻捷之行（AGI T2）：移速 +10%
## 由 AttrPanel.compute_move_speed_mult 已实装，此处提供直接查询
static func move_speed_multiplier() -> float:
	if _ap().has_milestone("轻捷之行"):
		return 1.10
	return 1.0

# ============================================================================
# 4. 休息/恢复路径
# ============================================================================

## 复苏之息（CON T3）：夜晚酒馆休息额外恢复 25% 最大 HP
## 返回额外恢复量（基于 max_hp）
static func inn_rest_extra_heal(max_hp: int) -> int:
	if _ap().has_milestone("复苏之息"):
		return int(round(max_hp * 0.25))
	return 0

# ============================================================================
# 5. 视野/探索路径
# ============================================================================

## 警觉（PER T1）：视野 +1 米，发现陷阱/暗门概率 +20%
## 返回 {"view_bonus": float, "trap_bonus": float}
static func alertness_bonus() -> Dictionary:
	if _ap().has_milestone("警觉"):
		return {"view_bonus": 1.5, "trap_bonus": 20.0}  # 1 格 = 1.5 米
	return {"view_bonus": 0.0, "trap_bonus": 0.0}

# ============================================================================
# 6. 通用暴击率修正
# ============================================================================

## 弱点洞察（PER T2）：基础暴击率 +5%
## 由 AttrPanel.compute_crit_rate 已实装，此处提供独立查询
static func crit_rate_bonus() -> float:
	if _ap().has_milestone("弱点洞察"):
		return 5.0
	return 0.0

# ============================================================================
# 7. 双手武器伤害修正
# ============================================================================

## 蛮力负荷（STR T3）：双手武器基础伤害倍率 +5%
## 返回伤害倍率增量（叠加到 weapon_damage_mult）
static func two_hand_damage_mult_bonus(is_two_hand: bool) -> float:
	if is_two_hand and _ap().has_milestone("蛮力负荷"):
		return 0.05
	return 0.0
