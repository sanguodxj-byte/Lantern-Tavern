extends Node
## 通用动作技能数据层（autoload: ActionSkills）。
## F 槽专用：无武器媒介限制，任何装备状态均可释放的动作技能。
## 策划案扩展：踢击/冲撞/抓取投掷/滑铲/战术滑步。
## 与 SkillData.SKILLS（武器流派技能，受媒介限制）分离。

# ============================================================================
# 1. 动作技能枚举与定义
# ============================================================================

enum ActionSkill {
	KICK,           # 踢击（项目已有，player_state_kicking.gd）
	CHARGE,         # 冲撞
	GRAB_THROW,     # 抓取/投掷
	SLIDE,          # 滑铲
	TACTICAL_STEP,  # 战术滑步
}

# 动作技能定义（ARPG 实时字段）
# 字段与 SkillData.SKILLS 对齐，但 school=-1 表示无流派媒介限制
const SKILLS: Array = [
	{
		"id": "踢击", "enum": ActionSkill.KICK,
		"name": "踢击 / Kick", "type": "action", "skill_family": "impact", "cancel_tag": "kick",
		"damage_mult": 0.5, "hit_bonus": 0.0, "cooldown": 2.0, "cast_time": 0.0,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 1.5, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"cancel_start": 0.0, "cancel_end": 0.25, "cancel_into": ["movement", "melee", "block"],
		"inherit_momentum": true, "momentum_damage_scale": 0.03,
		"momentum_knockback_scale": 0.08, "momentum_cap": 10.0,
		"physical_impact_enabled": true, "physical_impact_damage_mult": 1.0,
		"desc": "无武器限制的踢击，击退 1 米，可踢门/踢敌",
	},
	{
		"id": "冲撞", "enum": ActionSkill.CHARGE,
		"name": "冲撞 / Charge", "type": "action", "skill_family": "movement", "cancel_tag": "movement",
		"damage_mult": 0.8, "hit_bonus": 10.0, "cooldown": 5.0, "cast_time": 0.2,
		"range_m": 5.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"dash_speed_mps": 12.0,
		"knockback_m": 2.0, "stun_sec": 0.5, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"breaks_shield": true,
		"release_on_start": true, "cancel_start": 0.05, "cancel_end": 0.2,
		"cancel_into": ["kick", "melee", "block"],
		"inherit_momentum": false, "momentum_damage_scale": 0.0,
		"momentum_knockback_scale": 0.0, "momentum_cap": 10.0,
		"physical_impact_enabled": true, "physical_impact_damage_mult": 1.0,
		"desc": "向前冲撞 5 米，命中敌人击退 2 米 + 眩晕 0.5 秒",
	},
	{
		"id": "抓取投掷", "enum": ActionSkill.GRAB_THROW,
		"name": "抓取/投掷 / Grab & Throw", "type": "action", "skill_family": "grapple", "cancel_tag": "grapple",
		"damage_mult": 1.0, "hit_bonus": 5.0, "cooldown": 6.0, "cast_time": 0.4,
		"range_m": 1.5, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 3.0, "stun_sec": 1.0, "buff_sec": 0.0,
		"buff_type": "", "buff_value": 0,
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"cancel_start": 0.2, "cancel_end": 0.4, "cancel_into": ["movement", "block"],
		"inherit_momentum": true, "momentum_damage_scale": 0.02,
		"momentum_knockback_scale": 0.05, "momentum_cap": 8.0,
		"desc": "抓取前方敌人投掷出去，击退 3 米 + 眩晕 1 秒",
	},
	{
		"id": "滑铲", "enum": ActionSkill.SLIDE,
		"name": "滑铲 / Slide", "type": "action", "skill_family": "movement", "cancel_tag": "movement",
		"damage_mult": 0.0, "hit_bonus": 0.0, "cooldown": 4.0, "cast_time": 0.5,
		"range_m": 4.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "iframes", "buff_value": 0.5,  # 0.5 秒无敌帧
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"release_on_start": true, "cancel_start": 0.15, "cancel_end": 0.5,
		"cancel_into": ["kick", "melee", "block"],
		"inherit_momentum": false, "momentum_damage_scale": 0.0,
		"momentum_knockback_scale": 0.0, "momentum_cap": 10.0,
		"desc": "向前滑铲 4 米，滑行期间 0.5 秒无敌帧",
	},
	{
		"id": "战术滑步", "enum": ActionSkill.TACTICAL_STEP,
		"name": "战术滑步 / Tactical Step", "type": "action", "skill_family": "movement", "cancel_tag": "movement",
		"damage_mult": 0.0, "hit_bonus": 0.0, "cooldown": 3.0, "cast_time": 0.1,
		"range_m": 3.0, "aoe_shape": "none", "aoe_radius": 0.0,
		"knockback_m": 0.0, "stun_sec": 0.0, "buff_sec": 0.0,
		"buff_type": "dodge_frames", "buff_value": 0.3,  # 0.3 秒闪避帧
		"ignore_def": 0.0, "ignore_block": false, "lifesteal": 0.0,
		"release_on_start": true, "cancel_start": 0.05, "cancel_end": 0.25,
		"cancel_into": ["kick", "melee", "block"],
		"inherit_momentum": false, "momentum_damage_scale": 0.0,
		"momentum_knockback_scale": 0.0, "momentum_cap": 8.0,
		"desc": "短距离战术滑步 3 米，0.3 秒闪避帧",
	},
]

# ============================================================================
# 2. 查询 API
# ============================================================================

## 按技能 id 获取定义
static func get_skill_by_id(skill_id: String) -> Dictionary:
	for skill in SKILLS:
		if skill["id"] == skill_id:
			return skill
	return {}

## 按枚举获取定义
static func get_skill_by_enum(skill_enum: int) -> Dictionary:
	for skill in SKILLS:
		if skill["enum"] == skill_enum:
			return skill
	return {}

## 获取所有动作技能 id
static func get_all_skill_ids() -> Array:
	var ids: Array = []
	for skill in SKILLS:
		ids.append(skill["id"])
	return ids

## 动作技能总数
static func get_skill_count() -> int:
	return SKILLS.size()
