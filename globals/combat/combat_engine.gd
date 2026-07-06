extends Node
## 战斗数值引擎（autoload: CombatEngine）。
## 3D ARPG 实时战斗数值骨架（动作控制版）。
## 承载策划案《05-战斗系统》中与实时战斗兼容的部分：
## 1. 6 大属性面板换算（HP/防御/负重/伤害修正/攻速/移速）
## 2. 5 战斗风格自动激活与数值修正
## 3. 伤害结算算法（命中→暴击→基础伤害→朝向→防御→扣血）
## 4. 实时向量化击退（米/秒）与秒数状态计时
## 已移除：行动 Tick、网格格数击退、回合数 CD/眩晕、读条蓄力回合。
## 已移除：闪避率（命中改为动作判定，hitbox 接触即命中）、格挡率（格挡改为动作控制）。

# ============================================================================
# 1. 6 大主属性
# ============================================================================

enum Attr { STR, DEX, MAG, CON, AGI, PER }

# 属性升级门槛（策划案 05 §5.1：累积经验达门槛 +1）
const ATTR_UPGRADE_THRESHOLD: int = 100

# ============================================================================
# 2. 战斗风格（ARPG 实时版：移除回合制 Tick，新增攻速/移速修正）
# ============================================================================

enum Style { ONE_HAND, ONE_HAND_SHIELD, TWO_HAND, DUAL_WIELD, UNARMED, RANGED, SPELL }

const STYLE_META: Dictionary = {
	Style.ONE_HAND: {
		"name": "单手风格", "hit_bonus": 10.0,
		"attack_speed_mult": 1.0, "move_speed_mult": 1.0,
	},
	Style.ONE_HAND_SHIELD: {
		"name": "单手持盾风格", "hit_bonus": 0.0,
		"block_damage_reduce": 0.15,
		"attack_speed_mult": 0.95, "move_speed_mult": 0.95,
	},
	Style.TWO_HAND: {
		"name": "双手风格", "hit_bonus": 0.0,
		"damage_mult": 1.0, "knockback_force": 4.0,  # 米/秒
		"attack_speed_mult": 0.85, "move_speed_mult": 0.9,
	},
	Style.DUAL_WIELD: {
		"name": "双持风格", "hit_bonus": -10.0,
		"offhand_damage_pct": 0.6,
		"attack_speed_mult": 1.2, "move_speed_mult": 1.0,
	},
	Style.UNARMED: {
		"name": "徒手风格", "hit_bonus": 0.0,
		"attack_speed_mult": 1.3, "move_speed_mult": 1.1,
	},
	Style.RANGED: {
		"name": "远程风格", "hit_bonus": 0.0,
		"attack_speed_mult": 0.9, "move_speed_mult": 0.95,
	},
	Style.SPELL: {
		"name": "法术风格", "hit_bonus": 0.0,
		"attack_speed_mult": 0.9, "move_speed_mult": 0.95,
	},
}

# 基础攻击间隔（秒）与移动速度（米/秒），ARPG 实时基准
const BASE_ATTACK_INTERVAL: float = 1.0
const BASE_MOVE_SPEED: float = 5.0

# ============================================================================
# 3. 属性面板换算公式（策划案 05 §2.1，ARPG 化）
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

## 近战伤害修正 = 力量×1.5 + 风格与熟练度修正
static func compute_melee_flat(str_val: int, style_bonus: float = 0.0) -> float:
	return str_val * 1.5 + style_bonus

## 远程伤害修正 = 敏捷×1.5 + 武器与熟练度修正
static func compute_ranged_flat(dex_val: int, proficiency_bonus: float = 0.0) -> float:
	return dex_val * 1.5 + proficiency_bonus

## 法术伤害修正 = 魔力×1.5 + 武器与熟练度修正
static func compute_spell_flat(mag_val: int, proficiency_bonus: float = 0.0) -> float:
	return mag_val * 1.5 + proficiency_bonus

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
# 4. 战斗风格自动激活（策划案 05 §3）
# ============================================================================

## 根据主手/副手装备判定战斗风格
static func determine_style(main_hand: String, off_hand: String) -> int:
	if main_hand == "" and off_hand == "":
		return Style.UNARMED
	if main_hand == "one_hand_melee" and off_hand == "one_hand_melee":
		return Style.DUAL_WIELD
	if main_hand == "one_hand_melee" and off_hand == "shield":
		return Style.ONE_HAND_SHIELD
	if main_hand == "two_hand" and off_hand == "":
		return Style.TWO_HAND
	if (main_hand == "longbow" or main_hand == "crossbow") and off_hand == "":
		return Style.RANGED
	if (main_hand == "wand" or main_hand == "grimoire") and off_hand == "":
		return Style.SPELL
	if main_hand == "one_hand_melee" and off_hand == "":
		return Style.ONE_HAND
	return Style.UNARMED

# ============================================================================
# 5. 伤害结算（ARPG 动作控制版）
# ============================================================================

class AttackInput:
	var attacker_str: int = 10
	var attacker_dex: int = 10
	var attacker_mag: int = 10
	var attacker_per: int = 10
	var attacker_agi: int = 10
	var attacker_con: int = 10
	var attacker_level: int = 1
	var weapon_hit_bonus: float = 0.0
	var weapon_damage_dice: Dictionary = {"count": 1, "sides": 6}
	var weapon_damage_flat: float = 0.0
	var weapon_damage_mult: float = 1.0
	var crit_bonus: float = 0.0
	var crit_damage_bonus: float = 0.0
	var base_damage_bonus_percent: float = 0.0
	var ignore_def_percent: float = 0.0
	var ignore_block: bool = false
	var force_crit: bool = false
	var lifesteal_percent: float = 0.0
	var bonus_stun_duration: float = 0.0
	var style: int = Style.ONE_HAND
	var attack_type: String = "melee"  # melee / ranged / spell
	var is_backstab: bool = false
	var is_sideswipe: bool = false
	var knockback_force: float = 2.0  # 基础击退力（米/秒），双手风格在结算时叠加

class Defender:
	var con: int = 10
	var agi: int = 10
	var per: int = 10
	var armor_def: int = 0
	# has_shield 保留为信息字段（UI/桥接层使用），resolve_attack 不再据此做概率格挡
	var has_shield: bool = false

# ARPG 实时结算结果
class DamageResult:
	# 动作控制：hitbox 接触即命中，hit 恒为 true
	var hit: bool = true
	var crit: bool = false
	var raw_damage: float = 0.0
	var final_damage: int = 0
	var attack_type: String = "melee"
	# blocked / block_reduced 保留用于受击方状态机判定（由 try_receive_hit_result 设置）
	var blocked: bool = false
	var block_reduced: float = 0.0
	# ignores_block：穿透类攻击可绕过格挡状态（从 AttackInput.ignore_block 传递）
	var ignores_block: bool = false
	var lifesteal_amount: int = 0
	# ARPG 实时：击退为作用力（米/秒），由物理引擎施加冲量
	var knockback_impulse: Vector3 = Vector3.ZERO
	var knockback_force: float = 0.0
	# ARPG 实时：眩晕为秒数（非回合数）
	var stun_duration: float = 0.0
	var crit_roll: int = 0
	var physical_impact_enabled: bool = false
	var physical_impact_damage_mult: float = 1.0
	var physical_impact_min_speed: float = 4.0
	var physical_impact_full_speed: float = 14.0

## 被动撞击伤害：由物理速度换算为纸娃娃最大生命百分比伤害。
## min_speed 以下无伤；full_speed 及以上达到 30% 最大生命基础伤害。
## target_profile 可传入:
## - impact_damage_taken_mult: 精英/Boss/体型对撞击百分比伤害的承伤倍率
## - impact_min_speed_add: 大体型单位开始受撞击伤害所需的额外速度
static func compute_physical_impact_damage(max_life: int, impact_speed: float, min_speed: float = 4.0, full_speed: float = 14.0, damage_mult: float = 1.0, target_profile: Dictionary = {}) -> int:
	var taken_mult := float(target_profile.get("impact_damage_taken_mult", 1.0))
	var adjusted_min_speed := min_speed + float(target_profile.get("impact_min_speed_add", 0.0))
	var adjusted_full_speed := maxf(full_speed + float(target_profile.get("impact_min_speed_add", 0.0)), adjusted_min_speed + 0.001)
	if max_life <= 0 or impact_speed < adjusted_min_speed or damage_mult <= 0.0 or taken_mult <= 0.0:
		return 0
	var span: float = maxf(adjusted_full_speed - adjusted_min_speed, 0.001)
	var ratio: float = clampf((impact_speed - adjusted_min_speed) / span, 0.0, 1.0)
	var damage_pct: float = 0.06 + ratio * 0.24
	return maxi(1, int(round(float(max_life) * damage_pct * damage_mult * taken_mult)))

## 执行伤害结算。
## 动作控制版：命中由 hitbox 物理碰撞决定（接触即命中），闪避率/格挡率已移除。
## 格挡由受击方状态机判定（BLOCKING 状态 → can_get_hurt() = false），
## 不再在 resolve_attack 内做概率格挡投骰。
## attacker_forward: 攻方朝向单位向量（用于计算击退方向），默认 -Z
static func resolve_attack(attack: AttackInput, defender: Defender, attacker_forward: Vector3 = Vector3(0, 0, -1)) -> DamageResult:
	var result := DamageResult.new()
	result.attack_type = attack.attack_type
	result.ignores_block = attack.ignore_block
	# 动作控制：hitbox 接触即命中，不再投骰命中率/闪避率
	result.hit = true
	# 阶段一：暴击判定
	var crit_rate: float = 5.0 + attack.attacker_per * 0.5 - defender.per * 0.5 + attack.crit_bonus
	crit_rate = maxf(crit_rate, 0.0)
	result.crit_roll = randi_range(1, 100)
	if attack.force_crit or result.crit_roll <= int(crit_rate):
		result.crit = true
	# 阶段二：风格与武器基础伤害计算
	var base_damage: float = _compute_base_damage(attack)
	if result.crit:
		var crit_mult: float = 1.5 + attack.attacker_per * 0.01 - defender.per * 0.01 + attack.crit_damage_bonus
		crit_mult = maxf(crit_mult, 1.1)
		base_damage *= crit_mult
	result.raw_damage = base_damage
	# 阶段三：朝向判定最终修正
	if attack.is_backstab:
		base_damage *= 1.5
	# 阶段四：防御力减免结算（格挡率已移除，格挡由状态机处理）
	var final_def: float = float(defender.armor_def + defender.con)
	if attack.ignore_def_percent > 0.0:
		final_def *= maxf(0.0, 1.0 - attack.ignore_def_percent / 100.0)
	var after_def: float = base_damage - final_def
	after_def = maxf(after_def, 1.0)
	# 阶段五：最终扣血 + 实时击退
	result.final_damage = maxi(int(round(after_def)), 1)
	if attack.lifesteal_percent > 0.0:
		result.lifesteal_amount = int(round(result.final_damage * attack.lifesteal_percent / 100.0))
	# ARPG 实时击退：双手风格击退力叠加，方向沿攻方朝向
	var kb_force: float = attack.knockback_force
	if attack.style == Style.TWO_HAND:
		kb_force += STYLE_META[Style.TWO_HAND].get("knockback_force", 4.0)
	if attack.attack_type == "melee" or attack.attack_type == "ranged":
		result.knockback_force = kb_force
		result.knockback_impulse = attacker_forward * kb_force
		# 暴击附加短时眩晕（秒，非回合）
		if result.crit:
			result.stun_duration = 0.5
		if attack.bonus_stun_duration > 0.0:
			result.stun_duration = maxf(result.stun_duration, attack.bonus_stun_duration)
	return result

## 阶段二：基础伤害 = (武器投骰 NdN + 伤害修正) × 最终伤害倍率
static func _compute_base_damage(attack: AttackInput) -> float:
	var dice_sum: int = 0
	var dice_count: int = int(attack.weapon_damage_dice.get("count", 1))
	var dice_sides: int = int(attack.weapon_damage_dice.get("sides", 6))
	for i in range(dice_count):
		if dice_sides > 0:
			dice_sum += randi_range(1, dice_sides)
	var stat_flat: float = 0.0
	match attack.attack_type:
		"melee":
			stat_flat = compute_melee_flat(attack.attacker_str)
			if attack.style == Style.UNARMED:
				stat_flat = attack.attacker_str + attack.attacker_agi
		"ranged":
			stat_flat = compute_ranged_flat(attack.attacker_dex)
		"spell":
			stat_flat = compute_spell_flat(attack.attacker_mag)
	var raw: float = (dice_sum + attack.weapon_damage_flat + stat_flat) * attack.weapon_damage_mult
	if attack.base_damage_bonus_percent != 0.0:
		raw *= 1.0 + attack.base_damage_bonus_percent / 100.0
	return maxf(raw, 1.0)

# ============================================================================
# 6. 双轨经验（策划案 05 §5.1，实时版：无回合，按动作累积）
# ============================================================================

## 主属性经验累积。返回 (new_exp, leveled_up)
static func accumulate_attr_exp(current_exp: int, gain: int) -> Dictionary:
	var new_exp: int = current_exp + gain
	if new_exp >= ATTR_UPGRADE_THRESHOLD:
		return {"exp": new_exp - ATTR_UPGRADE_THRESHOLD, "leveled_up": true}
	return {"exp": new_exp, "leveled_up": false}
