extends Node
## 战斗数值引擎（autoload: CombatEngine）。
## 3D ARPG 实时战斗数值骨架（动作控制版）。
##
## 本文件现分为两部分：
##  A. 属性面板 / 进度换算（6 大主属性、攻速/移速、双轨经验）—— 仍由本 autoload 直接承载。
##  B. 伤害结算（命中→暴击→基础伤害→朝向→防御→扣血 + 物理冲量）—— 已剥离至
##     DamageResolver（res://globals/combat/damage_resolver.gd）。本文件仅做外观层委托与
##     类型别名，保证既有调用方（CombatBridge / SkillRuntime / 各测试）无需改动。
##
## 设计约束：DamageResolver 自包含、不反向 preload 本文件，避免 autoload 循环依赖。

# DamageResolver：伤害结算组件（自包含，无反向依赖）
const DR := preload("res://globals/combat/damage_resolver.gd")

# ---- 类型别名（保持 CE.AttackInput / CE.DamageResult / CE.Style / CE.STYLE_META 可用）----
const Style = DR.Style
const STYLE_META = DR.STYLE_META
const AttackInput = DR.AttackInput
const Defender = DR.Defender
const DamageResult = DR.DamageResult

# ============================================================================
# 1. 6 大主属性
# ============================================================================

enum Attr { STR, DEX, MAG, CON, AGI, PER }

# 属性升级门槛（策划案 05 §5.1：累积经验达门槛 +1）
const ATTR_UPGRADE_THRESHOLD: int = 100

# 基础攻击间隔（秒）与移动速度（米/秒），ARPG 实时基准
const BASE_ATTACK_INTERVAL: float = 1.0
const BASE_MOVE_SPEED: float = 5.0

# ============================================================================
# 2. 属性面板换算公式（策划案 05 §2.1，ARPG 化）
# ============================================================================

## 最大生命值 = 100 + 体质×10 + 角色等级×5
static func compute_max_hp(constitution: int, level: int) -> int:
	return 100 + constitution * 10 + level * 5

## 物理防御 = 防具防御 + 体质×1
static func compute_physical_def(armor_def: int, constitution: int) -> int:
	return armor_def + constitution

## 负重上限 = 50 + 体质×2
static func compute_carry_weight(constitution: int) -> int:
	return 50 + constitution * 2

## 攻击间隔（秒）= 基础间隔 / 风格攻速倍率 / 敏捷加成
## ARPG 实时：敏捷越高攻速越快
static func compute_attack_interval(style: int, dex_val: int) -> float:
	var style_mult: float = STYLE_META[style].get("attack_speed_mult", 1.0)
	var dex_mult: float = 1.0 + dex_val * 0.005  # 每点敏捷 +0.5% 攻速
	return BASE_ATTACK_INTERVAL / (style_mult * dex_mult)

## 移动速度（米/秒）= 基础速度 × 风格移速倍率 × 灵巧加成
static func compute_move_speed(style: int, agility: int) -> float:
	var style_mult: float = STYLE_META[style].get("move_speed_mult", 1.0)
	var agi_mult: float = 1.0 + agility * 0.003  # 每点灵巧 +0.3% 移速
	return BASE_MOVE_SPEED * style_mult * agi_mult

# ============================================================================
# 3. 战斗风格自动激活（委托 DamageResolver）
# ============================================================================

static func determine_style(main_hand: String, off_hand: String) -> int:
	return DR.determine_style(main_hand, off_hand)

# ============================================================================
# 4. 伤害结算相关（委托 DamageResolver）
# ============================================================================

## 近战伤害修正 = 力量×1.5 + 风格与熟练度修正
static func compute_melee_flat(str_val: int, style_bonus: float = 0.0) -> float:
	return DR.compute_melee_flat(str_val, style_bonus)

## 远程伤害修正 = 敏捷×1.5 + 武器与熟练度修正
static func compute_ranged_flat(dex_val: int, proficiency_bonus: float = 0.0) -> float:
	return DR.compute_ranged_flat(dex_val, proficiency_bonus)

## 法术伤害修正 = 魔力×1.5 + 武器与熟练度修正
static func compute_spell_flat(mag_val: int, proficiency_bonus: float = 0.0) -> float:
	return DR.compute_spell_flat(mag_val, proficiency_bonus)

## 被动撞击伤害（由物理速度换算为纸娃娃最大生命百分比伤害）
static func compute_physical_impact_damage(max_life: int, impact_speed: float, min_speed: float = 4.0, full_speed: float = 14.0, damage_mult: float = 1.0, target_profile: Dictionary = {}) -> int:
	return DR.compute_physical_impact_damage(max_life, impact_speed, min_speed, full_speed, damage_mult, target_profile)

## 执行伤害结算（命中→暴击→基础伤害→朝向→防御→扣血 + 实时击退）
## 详见 DamageResolver.resolve_attack（含物理冲量倍率处理）
static func resolve_attack(attack: AttackInput, defender: Defender, attacker_forward: Vector3 = Vector3(0, 0, -1)) -> DamageResult:
	return DR.resolve_attack(attack, defender, attacker_forward)

# ============================================================================
# 5. 双轨经验（策划案 05 §5.1，实时版：无回合，按动作累积）
# ============================================================================

## 主属性经验累积。返回 (new_exp, leveled_up)
static func accumulate_attr_exp(current_exp: int, gain: int) -> Dictionary:
	var new_exp: int = current_exp + gain
	if new_exp >= ATTR_UPGRADE_THRESHOLD:
		return {"exp": new_exp - ATTR_UPGRADE_THRESHOLD, "leveled_up": true}
	return {"exp": new_exp, "leveled_up": false}
