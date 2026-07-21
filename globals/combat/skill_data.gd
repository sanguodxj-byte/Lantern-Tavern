extends Node
## 技能与领悟系统（autoload: SkillData）。
## 策划案《15-技能与领悟系统》ARPG 化数据层。
## 已移除回合制专属概念：
##   回合动作消耗 → ARPG 主动技能的施法前摇/后摇（秒）
##   冷却 N 回合 → 冷却 N 秒
##   击退 N 格   → 击退 N 米（沿攻击向量施加冲量）
##   持续 N 回合 → 持续 N 秒（buff/debuff 计时）
##   射程 N 格   → 射程 N 米（3D 空间距离）
##   扇形/直线 N 格 → 扇形半径/直线长度 N 米
## 所有数值对齐策划案原值，仅做单位换算：1 回合 ≈ 1 秒，1 格 ≈ 1.5 米。

# 单位换算常量（策划案 1 回合 = 1 秒；1 网格格 = 1.5 米）
const TICK_TO_SECOND: float = 1.0
const CELL_TO_METER: float = 1.5

# ============================================================================
# 1. 双轨领悟阶梯门槛（策划案 §1.1）
# ============================================================================

enum SkillTier { T1, T2, T3 }

# 领悟门槛：[武器熟练度等级, 主属性点数]
const UNLOCK_THRESHOLD: Dictionary = {
	SkillTier.T1: {"proficiency": 3, "attr": 15},
	SkillTier.T2: {"proficiency": 8, "attr": 35},
	SkillTier.T3: {"proficiency": 15, "attr": 70},
}

# ============================================================================
# 2. 10 战斗流派 + 30 技能大表（策划案 §2）
# 注：策划案标题写"11 大流派 33 技能"，但 §2 正文仅详列 10 流派（A-J）× 3 阶 = 30 技能。
# 第 11 流派数据未给出，待策划补全后再扩为 11/33。
# ============================================================================

enum School {
	ONE_HAND_SWORD,   # A 单手剑
	TWO_HAND_SWORD,   # B 双手大剑
	TWO_HAND_AXE,     # C 双手斧
	WAR_HAMMER,       # D 战锤
	SPEAR,            # E 长枪
	LONGBOW,          # F 长弓
	LIGHT_CROSSBOW,   # G 轻弩
	ENCHANT_WAND,     # H 附魔法杖
	GRIMOIRE,         # I 魔导书
	UNARMED,          # J 徒手
	# 策划案 §2 标题称"11 大流派"，但正文仅列 10 流派（A-J）。
	# 第 11 流派数据待策划补全后追加枚举值与对应 SKILLS/SCHOOL_MAIN_ATTR/SCHOOL_WEAPON_MEDIUM 条目。
}

# 主攻属性映射（策划案 §2 各流派"主攻属性"标注）
const SCHOOL_MAIN_ATTR: Dictionary = {
	School.ONE_HAND_SWORD: ["str", "dex"],     # 力量/敏捷均可
	School.TWO_HAND_SWORD: ["str"],
	School.TWO_HAND_AXE: ["str"],
	School.WAR_HAMMER: ["str"],
	School.SPEAR: ["str", "dex"],
	School.LONGBOW: ["dex"],
	School.LIGHT_CROSSBOW: ["dex"],
	School.ENCHANT_WAND: ["mag"],
	School.GRIMOIRE: ["mag"],
	School.UNARMED: ["str", "agi"],
}

# 释放媒介：对应装备槽武器类型 id（与 CombatEngine.determine_style 输入同源）
const SCHOOL_WEAPON_MEDIUM: Dictionary = {
	School.ONE_HAND_SWORD: "one_hand_melee",
	School.TWO_HAND_SWORD: "two_hand",
	School.TWO_HAND_AXE: "two_hand",
	School.WAR_HAMMER: "two_hand",
	School.SPEAR: "two_hand",
	School.LONGBOW: "longbow",
	School.LIGHT_CROSSBOW: "crossbow",
	School.ENCHANT_WAND: "wand",
	School.GRIMOIRE: "grimoire",
	School.UNARMED: "",  # 徒手：双手空置
}

# 33 技能定义（ARPG 化字段）
# 字段说明：
#   id          技能 id（中文键，对齐策划案）
#   school      所属流派
#   tier        阶位
#   name        中文名
#   type        active 主动 / passive 被动
#   damage_mult 伤害倍率（相对基础攻击力）
#   (命中率 hit_bonus 已移除：动作控制模型无命中/未命中判定，原字段为回合制残留)
#   cooldown    冷却时间（秒）
#   cast_time   施法前摇（秒），被动为 0
#   range_m     射程/作用半径（米）
#   aoe_shape   形状：none / cone / line / circle
#   aoe_radius  AoE 半径（米）
#   knockback_m 击退距离（米）
#   stun_sec    眩晕持续（秒）
#   buff_sec    buff/debuff 持续（秒）
#   buff_type   buff 类型 id（如 def_up / evade_up / def_down / slow / lifesteal）
#   buff_value  buff 数值（百分比或点数，按 buff_type 解释）
#   ignore_def  无视物理防御百分比(%)
#   ignore_block 无视盾牌格挡（bool）
#   lifesteal   吸血百分比(%)
#   desc        策划案原效果描述（保留原文便于核对）
const SKILLS: Array = [
	# ===== A. 单手剑流派 =====
	{
		"id": "防御姿态", "school": School.ONE_HAND_SWORD, "tier": SkillTier.T1,
		"name": "防御姿态 / Defensive Stance", "type": "active",
		"damage_mult": 0.0, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 0.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "def_and_evade_up", "buff_value": {"def": 4, "evade": 5},
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "3 秒内物防 +4，闪避 +5%",
	},
	{
		"id": "精准刺击", "school": School.ONE_HAND_SWORD, "tier": SkillTier.T2,
		"name": "精准刺击 / Precision Thrust", "type": "active",
		"damage_mult": 1.0, "cooldown": 4.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "命中 +25%，命中即暴击",
	},
	{
		"id": "招架反击", "school": School.ONE_HAND_SWORD, "tier": SkillTier.T3,
		"name": "招架反击 / Riposte", "type": "passive",
		"damage_mult": 0.8, "cooldown": 0.0, "cast_time": 0.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "riposte_chance", "buff_value": 40,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "闪避/格挡后 40% 概率免费反击 80% 基础攻击力",
	},
	# ===== B. 双手大剑流派 =====
	{
		"id": "顺劈斩", "school": School.TWO_HAND_SWORD, "tier": SkillTier.T1,
		"name": "顺劈斩 / Cleave", "type": "active",
		"damage_mult": 0.85, "cooldown": 4.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "cone", "aoe_radius": 4.5,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "前方扇形 3 米内敌人 85% 伤害",
	},
	{
		"id": "过顶重击", "school": School.TWO_HAND_SWORD, "tier": SkillTier.T2,
		"name": "过顶重击 / Heavy Overhead", "type": "active",
		"damage_mult": 2.2, "cooldown": 6.0, "cast_time": 2.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 20.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "蓄力 1 秒，220% 伤害，无视 20% 物防",
	},
	{
		"id": "不屈重斩", "school": School.TWO_HAND_SWORD, "tier": SkillTier.T3,
		"name": "不屈重斩 / Unyielding Strike", "type": "active",
		"damage_mult": 1.5, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 30.0,
		"desc": "150% 伤害 + 30% 吸血",
	},
	# ===== C. 双手斧流派 =====
	{
		"id": "破甲斩", "school": School.TWO_HAND_AXE, "tier": SkillTier.T1,
		"name": "破甲斩 / Sunder", "type": "active",
		"damage_mult": 1.1, "cooldown": 4.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "def_down", "buff_value": 6,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "110% 伤害 + 3 秒内物防 -6",
	},
	{
		"id": "斩首", "school": School.TWO_HAND_AXE, "tier": SkillTier.T2,
		"name": "斩首 / Decapitate", "type": "active",
		"damage_mult": 1.6, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "execute_threshold", "buff_value": 35,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "目标 HP < 35% 时基础伤害 ×1.6",
	},
	{
		"id": "旋风斩", "school": School.TWO_HAND_AXE, "tier": SkillTier.T3,
		"name": "旋风斩 / Whirlwind", "type": "active",
		"damage_mult": 1.2, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 2.25, "aoe_shape": "circle", "aoe_radius": 2.25,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 15.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "周围 1.5 米内 120% 伤害，无视 15% 物防",
	},
	# ===== D. 战锤流派 =====
	{
		"id": "震荡打击", "school": School.WAR_HAMMER, "tier": SkillTier.T1,
		"name": "震荡打击 / Concussive Blow", "type": "active",
		"damage_mult": 0.9, "cooldown": 4.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 2.0, "buff_sec": 0.0,
		"buff_type": "collide_damage", "buff_value": 30,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "90% 伤害 + 2 秒眩晕（仅踢击/冲撞有击退）",
	},
	{
		"id": "颅骨粉碎", "school": School.WAR_HAMMER, "tier": SkillTier.T2,
		"name": "颅骨粉碎 / Skullcracker", "type": "active",
		"damage_mult": 1.0, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "crit_vs_stunned", "buff_value": {"crit_rate": 30, "crit_dmg": 25},
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "对眩晕/立足不稳目标暴击率 +30%、暴击伤害 +25%",
	},
	{
		"id": "震地击", "school": School.WAR_HAMMER, "tier": SkillTier.T3,
		"name": "震地击 / Earthshaker", "type": "active",
		"damage_mult": 1.1, "cooldown": 9.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "line", "aoe_radius": 4.5,
		"knockback_m": 0.0, "stun_sec": 1.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "前方直线 3 米 110% 伤害 + 必眩晕 1 秒",
	},
	# ===== E. 长枪流派 =====
	{
		"id": "突刺", "school": School.SPEAR, "tier": SkillTier.T1,
		"name": "突刺 / Lunge", "type": "active",
		"damage_mult": 1.05, "cooldown": 3.0, "cast_time": 1.0,
		"range_m": 3.0, "aoe_shape": "line", "aoe_radius": 3.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "直线 2 米单体 105% 伤害 + 命中 +10%",
	},
	{
		"id": "横扫击", "school": School.SPEAR, "tier": SkillTier.T2,
		"name": "横扫击 / Sweeping Strike", "type": "active",
		"damage_mult": 0.8, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "cone", "aoe_radius": 4.5,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "slow", "buff_value": 20,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "前方扇形 3 米 80% 伤害 + 减速 3 秒",
	},
	{
		"id": "贯穿刺击", "school": School.SPEAR, "tier": SkillTier.T3,
		"name": "贯穿刺击 / Impale", "type": "active",
		"damage_mult": 1.8, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 3.0, "aoe_shape": "line", "aoe_radius": 3.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": true, "lifesteal": 0.0,
		"desc": "2 米单体 180% 伤害 + 命中 +15% + 无视盾牌格挡",
	},
	# ===== F. 长弓流派 =====
	{
		"id": "瞄准射击", "school": School.LONGBOW, "tier": SkillTier.T1,
		"name": "瞄准射击 / Aimed Shot", "type": "active",
		"damage_mult": 0.95, "cooldown": 3.0, "cast_time": 1.0,
		"range_m": 6.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "射程 4 米，95% 远程伤害 + 命中 +30%",
	},
	{
		"id": "压制齐射", "school": School.LONGBOW, "tier": SkillTier.T2,
		"name": "压制齐射 / Suppressing Volley", "type": "active",
		"damage_mult": 0.7, "cooldown": 6.0, "cast_time": 1.0,
		"range_m": 6.0, "aoe_shape": "circle", "aoe_radius": 3.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "evade_down", "buff_value": 10,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "2x2 米区域 70% 伤害 + 闪避 -10% 持续 3 秒",
	},
	{
		"id": "贯穿射击", "school": School.LONGBOW, "tier": SkillTier.T3,
		"name": "贯穿射击 / Piercing Shot", "type": "active",
		"damage_mult": 1.6, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 7.5, "aoe_shape": "line", "aoe_radius": 7.5,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "pierce_falloff", "buff_value": 15,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "直线 5 米穿透，每穿一敌伤害 -15%",
	},
	# ===== G. 轻弩流派 =====
	{
		"id": "双发连射", "school": School.LIGHT_CROSSBOW, "tier": SkillTier.T1,
		"name": "双发连射 / Double Tap", "type": "active",
		"damage_mult": 0.6, "cooldown": 4.0, "cast_time": 1.0,
		"range_m": 6.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "double_hit", "buff_value": 2,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "同目标两发，各 60% 伤害独立判定命中暴击",
	},
	{
		"id": "刺钩弩箭", "school": School.LIGHT_CROSSBOW, "tier": SkillTier.T2,
		"name": "刺钩弩箭 / Barbed Bolt", "type": "active",
		"damage_mult": 1.1, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 6.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 2.0,
		"buff_type": "slow", "buff_value": 30,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "110% 伤害 + 2 秒减速 30%（仅踢击/冲撞有击退）",
	},
	{
		"id": "弩箭齐射", "school": School.LIGHT_CROSSBOW, "tier": SkillTier.T3,
		"name": "弩箭齐射 / Volley of Bolts", "type": "active",
		"damage_mult": 1.3, "cooldown": 8.0, "cast_time": 2.0,
		"range_m": 4.5, "aoe_shape": "cone", "aoe_radius": 4.5,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "装填 1 秒，前方 3 米扇形 130% 伤害 + 命中 +10%",
	},
	# ===== H. 附魔法杖流派 =====
	{
		"id": "元素弹", "school": School.ENCHANT_WAND, "tier": SkillTier.T1,
		"name": "元素弹 / Elemental Bolt", "type": "active",
		"damage_mult": 1.0, "cooldown": 2.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "射程 3 米，100% 法术伤害",
	},
	{
		"id": "寒冰新星", "school": School.ENCHANT_WAND, "tier": SkillTier.T2,
		"name": "寒冰新星 / Frost Nova", "type": "active",
		"damage_mult": 0.8, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 2.25, "aoe_shape": "circle", "aoe_radius": 2.25,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 2.0,
		"buff_type": "ground_ice", "buff_value": 30,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "周围 1.5 米 80% 法术伤害 + 地面冰冻 2 秒（减速 30%）",
	},
	{
		"id": "雷暴术", "school": School.ENCHANT_WAND, "tier": SkillTier.T3,
		"name": "雷暴术 / Thunderstorm", "type": "active",
		"damage_mult": 1.5, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "circle", "aoe_radius": 4.5,
		"knockback_m": 0.0, "stun_sec": 1.0, "buff_sec": 0.0,
		"buff_type": "stun_chance", "buff_value": 30,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "3 米内 3x3 米区域 150% 法术伤害 + 30% 概率眩晕 1 秒",
	},
	# ===== I. 魔导书流派 =====
	{
		"id": "魔力涌动", "school": School.GRIMOIRE, "tier": SkillTier.T1,
		"name": "魔力涌动 / Mana Surge", "type": "passive",
		"damage_mult": 0.0, "cooldown": 0.0, "cast_time": 0.0,
		"range_m": 0.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "spell_damage_up", "buff_value": 5,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "副手魔导书时法术伤害 +5%",
	},
	{
		"id": "防护结界", "school": School.GRIMOIRE, "tier": SkillTier.T2,
		"name": "防护结界 / Ward Barrier", "type": "active",
		"damage_mult": 0.0, "cooldown": 6.0, "cast_time": 1.0,
		"range_m": 0.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "damage_absorb", "buff_value": 20,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "吸收最大 HP 20% 伤害，持续 3 秒",
	},
	{
		"id": "迟缓术", "school": School.GRIMOIRE, "tier": SkillTier.T3,
		"name": "迟缓术 / Slow", "type": "active",
		"damage_mult": 0.0, "cooldown": 10.0, "cast_time": 1.0,
		"range_m": 4.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "slow_and_haste", "buff_value": {"slow_target": 30, "haste_self": 20},
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "目标 3 秒减速 30%，自身 3 秒加速 20%",
	},
	# ===== J. 徒手流派 =====
	{
		"id": "刺拳", "school": School.UNARMED, "tier": SkillTier.T1,
		"name": "刺拳 / Jab", "type": "active",
		"damage_mult": 1.0, "cooldown": 2.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "双手空置，100% 伤害 + 命中 +10%（仅踢击/冲撞有击退）",
	},
	{
		"id": "关节锁", "school": School.UNARMED, "tier": SkillTier.T2,
		"name": "关节锁 / Joint Lock", "type": "active",
		"damage_mult": 0.9, "cooldown": 5.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 3.0,
		"buff_type": "root_and_dmg_down", "buff_value": {"root": true, "dmg_down": 20},
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "90% 伤害 + 3 秒内移动力归 0 且攻击伤害 -20%",
	},
	{
		"id": "碎骨重拳", "school": School.UNARMED, "tier": SkillTier.T3,
		"name": "碎骨重拳 / Skullbreaker Punch", "type": "active",
		"damage_mult": 1.8, "cooldown": 8.0, "cast_time": 1.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "blocked_kb_bonus", "buff_value": 50,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"desc": "180% 伤害（仅踢击/冲撞有击退）",
	},
]

# ============================================================================
# 3. 6 大主属性里程碑被动（策划案 §3）
# ============================================================================

enum AttrMilestone { T1, T2, T3 }  # 5 / 15 / 30 点

const MILESTONE_THRESHOLD: Dictionary = {
	AttrMilestone.T1: 5,
	AttrMilestone.T2: 15,
	AttrMilestone.T3: 30,
}

# 6 属性 × 3 阶 = 18 个里程碑被动
# 字段：attr / tier / id / name / type / effect_type / value / desc
const ATTR_MILESTONES: Array = [
	# ===== 力量 STR =====
	{"attr": "str", "tier": AttrMilestone.T1, "id": "震退", "name": "震退 / Knockback",
		"type": "passive", "effect_type": "kb_chance", "value": 15,
		"desc": "近战命中 15% 概率击退 1 米；撞墙追加自防 20% 碰撞伤害"},
	{"attr": "str", "tier": AttrMilestone.T2, "id": "重力击", "name": "重力击 / Heavy Stride",
		"type": "passive", "effect_type": "melee_dmg_up", "value": 5,
		"desc": "近战伤害 +5%，暴击必触发击退"},
	{"attr": "str", "tier": AttrMilestone.T3, "id": "蛮力负荷", "name": "蛮力负荷 / Brute Load",
		"type": "passive", "effect_type": "carry_and_twohand_dmg", "value": {"carry": 15, "dmg": 5},
		"desc": "负重 +15，双手武器基础伤害倍率 +5%"},
	# ===== 敏捷 DEX =====
	{"attr": "dex", "tier": AttrMilestone.T1, "id": "跳跃", "name": "跳跃 / Leap",
		"type": "active", "effect_type": "leap", "value": 1.5,
		"desc": "主动跳跃 1 米，越过地形裂隙；CD 3 秒"},
	{"attr": "dex", "tier": AttrMilestone.T2, "id": "神射手", "name": "神射手 / Sharpshooter",
		"type": "passive", "effect_type": "ranged_crit_up", "value": 10,
		"desc": "长弓/轻弩远程暴击率 +10%（动作化替代命中率）"},
	{"attr": "dex", "tier": AttrMilestone.T3, "id": "穿透打击", "name": "穿透打击 / Penetrating Strike",
		"type": "passive", "effect_type": "ranged_dmg_up", "value": 12,
		"desc": "远程伤害 +12%（动作化替代无视物防）"},
	# ===== 灵巧 AGI =====
	{"attr": "agi", "tier": AttrMilestone.T1, "id": "侧垫步", "name": "侧垫步 / Sidestep",
		"type": "passive", "effect_type": "dodge_chance", "value": 10,
		"desc": "受近战攻击 10% 概率侧闪免伤；CD 5 秒"},
	{"attr": "agi", "tier": AttrMilestone.T2, "id": "轻捷之行", "name": "轻捷之行 / Fleet Foot",
		"type": "passive", "effect_type": "move_cost_down", "value": 10,
		"desc": "移动消耗 -10%（移速 +10%）"},
	{"attr": "agi", "tier": AttrMilestone.T3, "id": "虚实避让", "name": "虚实避让 / Elusive",
		"type": "passive", "effect_type": "evade_up", "value": 6,
		"desc": "基础闪避率 +6%"},
	# ===== 体质 CON =====
	{"attr": "con", "tier": AttrMilestone.T1, "id": "强健体魄", "name": "强健体魄 / Fortitude",
		"type": "passive", "effect_type": "max_hp_up", "value": 20,
		"desc": "最大 HP +20"},
	{"attr": "con", "tier": AttrMilestone.T2, "id": "厚实皮肤", "name": "厚实皮肤 / Thick Skin",
		"type": "passive", "effect_type": "dmg_reduce_flat", "value": 2,
		"desc": "每次受击最终扣血 -2（最低 1）"},
	{"attr": "con", "tier": AttrMilestone.T3, "id": "复苏之息", "name": "复苏之息 / Recovery Breath",
		"type": "passive", "effect_type": "inn_rest_heal", "value": 25,
		"desc": "夜晚酒馆休息额外恢复 25% 最大 HP"},
	# ===== 魔力 MAG =====
	{"attr": "mag", "tier": AttrMilestone.T1, "id": "魔力凝息", "name": "魔力凝息 / Mana Focus",
		"type": "passive", "effect_type": "cd_reset_chance", "value": 10,
		"desc": "释放法杖/魔导书技能 10% 概率冷却清零"},
	{"attr": "mag", "tier": AttrMilestone.T2, "id": "元素护壳", "name": "元素护壳 / Elemental Aegis",
		"type": "passive", "effect_type": "spell_dmg_reduce_flat", "value": 4,
		"desc": "受法术伤害最终扣血 -4"},
	{"attr": "mag", "tier": AttrMilestone.T3, "id": "魔力涌流", "name": "魔力涌流 / Mana Surge",
		"type": "passive", "effect_type": "spell_crit_up", "value": 8,
		"desc": "所有魔法主动技能暴击率 +8%"},
	# ===== 感知 PER =====
	{"attr": "per", "tier": AttrMilestone.T1, "id": "警觉", "name": "警觉 / Alertness",
		"type": "passive", "effect_type": "view_and_trap", "value": {"view": 1, "trap": 20},
		"desc": "视野 +1 米，发现陷阱/暗门概率 +20%"},
	{"attr": "per", "tier": AttrMilestone.T2, "id": "弱点洞察", "name": "弱点洞察 / Find Weakness",
		"type": "passive", "effect_type": "crit_up", "value": 5,
		"desc": "基础暴击率 +5%"},
	{"attr": "per", "tier": AttrMilestone.T3, "id": "直觉闪避", "name": "直觉闪避 / Intuitive Evade",
		"type": "passive", "effect_type": "negate_flank", "value": 100,
		"desc": "侧击/背袭不再享有额外伤害加成（命中由动作判定，不计入）"},
]

# ============================================================================
# 4. 领悟门槛判定 API（策划案 §1.1）
# ============================================================================

## 判定某流派某阶技能是否满足领悟门槛。
## proficiency: 该武器熟练度等级；attr_val: 该流派主攻属性点数
static func can_unlock(tier: int, proficiency: int, attr_val: int) -> bool:
	var threshold: Dictionary = UNLOCK_THRESHOLD.get(tier, {})
	if threshold.is_empty():
		return false
	return proficiency >= threshold["proficiency"] and attr_val >= threshold["attr"]

## 判定某属性里程碑是否满足解锁门槛
static func can_unlock_milestone(tier: int, attr_val: int) -> bool:
	var threshold: int = MILESTONE_THRESHOLD.get(tier, 999)
	return attr_val >= threshold

# ============================================================================
# 5. 查询 API
# ============================================================================

## 按流派获取所有技能
static func get_skills_by_school(school: int) -> Array:
	var result: Array = []
	for skill in SKILLS:
		if skill["school"] == school:
			result.append(skill)
	return result

## 按技能 id 获取技能定义
static func get_skill_by_id(skill_id: String) -> Dictionary:
	for skill in SKILLS:
		if skill["id"] == skill_id:
			return skill
	return {}

## 按属性获取所有里程碑被动
static func get_milestones_by_attr(attr: String) -> Array:
	var result: Array = []
	for ms in ATTR_MILESTONES:
		if ms["attr"] == attr:
			result.append(ms)
	return result

## 判定武器媒介是否匹配（策划案 §1.2 搭载媒介硬性限制）
## main_hand / off_hand: 当前装备武器类型 id
## school: 流派
static func is_weapon_medium_matched(school: int, main_hand: String, off_hand: String) -> bool:
	var medium: String = SCHOOL_WEAPON_MEDIUM.get(school, "")
	if medium == "":
		# 徒手流派：双手均须空置
		return main_hand == "" and off_hand == ""
	return main_hand == medium
