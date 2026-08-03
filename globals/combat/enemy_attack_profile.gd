class_name EnemyAttackProfile
extends RefCounted
## 敌人攻击动作配置中心：按"人形（武器）/ 非人形（身体）"两条线给出
## 攻击动画、前摇时长、命中窗口、突进距离等招式参数。
## 非人形每种怪物独立招式（slime 扑击 / spider 撕咬 / dragon 挥爪 / rock_golem 砸地）；
## 人形按武器流派区分节奏（匕首快、长矛先手、重武器慢而迟、盾击中速）。

const ANIMATION_FALLBACK_BODY := "claw_swipe"

# ============================================================================
# 1. 非人形身体攻击档案（attack_mode = "body"）
# ============================================================================
# 字段：animation 攻击动画 / windup 前摇秒 / hit_start..hit_end 命中窗口(0..1) /
#       lunge 突进速度(米/秒，0=原地攻击)。动画必须存在于对应 rig。
const BODY_PROFILES := {
	"slime": {
		"animation": "slash",        # 史莱姆贴地扑击
		"windup": 0.45,
		"hit_start": 0.30,
		"hit_end": 0.80,
		"lunge": 1.8,
	},
	"spider": {
		"animation": "claw_swipe",   # 蜘蛛抬身前探撕咬（先慢抬后快咬）
		"windup": 0.60,
		"hit_start": 0.50,
		"hit_end": 0.90,
		"lunge": 0.0,
	},
	"dragon": {
		"animation": "slash",        # 巨龙横向挥爪扫击
		"windup": 0.80,
		"hit_start": 0.45,
		"hit_end": 0.95,
		"lunge": 0.6,
	},
	"rock_golem": {
		"animation": "slash_heavy",  # 石魔像双拳砸地（慢起手、迟命中）
		"windup": 0.90,
		"hit_start": 0.50,
		"hit_end": 1.0,
		"lunge": 0.0,
	},
}

# ============================================================================
# 2. 人形武器攻击档案（attack_mode = "weapon"，按武器流派）
# ============================================================================
# 字段：windup 前摇秒 / hit_start..hit_end 命中窗口 / speed_scale 动画速度倍率
const WEAPON_PROFILES := {
	"dagger": {
		"windup": 0.30,
		"hit_start": 0.25,
		"hit_end": 0.70,
		"speed_scale": 1.15,
	},
	"spear": {
		"windup": 0.55,
		"hit_start": 0.20,   # 长矛先手：刺出即判定
		"hit_end": 0.65,
		"speed_scale": 1.0,
	},
	"heavy": {
		"windup": 0.70,
		"hit_start": 0.42,   # 重武器慢而迟：砸落才判定
		"hit_end": 0.95,
		"speed_scale": 0.9,
	},
	"shield": {
		"windup": 0.40,
		"hit_start": 0.30,
		"hit_end": 0.80,
		"speed_scale": 1.0,
	},
	"sword": {
		"windup": 0.50,
		"hit_start": 0.34,
		"hit_end": 0.86,
		"speed_scale": 1.0,
	},
}

# ============================================================================
# 3. 查询
# ============================================================================

## 归一化敌人类型 id：去除 elite_/boss_ 前缀（与 DungeonSpawner 的命名一致）。
static func normalize_type(enemy_type: String) -> String:
	var t := enemy_type.strip_edges()
	for prefix in ["elite_", "boss_"]:
		if t.begins_with(prefix):
			t = t.trim_prefix(prefix)
	return t

## 非人形身体攻击档案；未登记类型返回空字典（调用方回退默认招式）。
static func body_profile(enemy_type: String) -> Dictionary:
	return BODY_PROFILES.get(normalize_type(enemy_type), {})

## 人形武器攻击档案（按 PLAYER_ANIMATION_PROFILE 的武器分类镜像）。
static func weapon_profile(weapon: Variant) -> Dictionary:
	if weapon == null:
		return WEAPON_PROFILES["sword"]
	var item_tag := String(weapon.item_tag) if "item_tag" in weapon else ""
	var weapon_class := String(weapon.weapon_class).to_lower() if "weapon_class" in weapon else ""
	var skill_school := String(weapon.skill_school).to_lower() if "skill_school" in weapon else ""
	var weapon_id := String(weapon.id).to_lower() if "id" in weapon else ""
	var tags: Array = weapon.tags if "tags" in weapon else []
	if item_tag == "shield" or weapon_class == "shield":
		return WEAPON_PROFILES["shield"]
	if tags.has("dagger") or skill_school == "dagger":
		return WEAPON_PROFILES["dagger"]
	if tags.has("spear") or skill_school == "spear" or "spear" in weapon_class:
		return WEAPON_PROFILES["spear"]
	if skill_school in ["two_hand_axe", "war_hammer", "two_hand_sword"] \
			or tags.has("two_hand_axe") or tags.has("war_hammer") or tags.has("two_hand_sword") \
			or weapon_class == "two_hand":
		return WEAPON_PROFILES["heavy"]
	return WEAPON_PROFILES["sword"]

## 按敌人与武器解析完整攻击档案。
## 返回 { animation, windup, hit_start, hit_end, lunge?, speed_scale? }。
static func profile_for_enemy(enemy_type: String, weapon: Variant, is_body: bool) -> Dictionary:
	if is_body:
		var body := body_profile(enemy_type)
		if not body.is_empty():
			return body
		return {
			"animation": ANIMATION_FALLBACK_BODY,
			"windup": 0.5,
			"hit_start": 0.34,
			"hit_end": 0.86,
			"lunge": 0.0,
		}
	var weapon_profile_data := weapon_profile(weapon)
	return weapon_profile_data
