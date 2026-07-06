extends Node
## 玩家属性面板系统（autoload: AttrPanel）。
## 6 大主属性 + 角色等级 + 双轨经验持久化。
## 替换 CombatBridge 集成期的临时默认值（全 10 / 等级 1）。
## 策划案《05-战斗系统》§2.1 属性面板 + §5.1 双轨经验。

const CE := preload("res://globals/combat/combat_engine.gd")

# 6 大主属性 id（与 CombatEngine.Attr 枚举对应）
const ATTR_KEYS: Array = ["str", "dex", "mag", "con", "agi", "per"]

# ============================================================================
# 1. 持久化状态（save/load 兼容）
# ============================================================================

# 6 主属性当前值
var attrs: Dictionary = {
	"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5
}

# 6 主属性累积经验（达 ATTR_UPGRADE_THRESHOLD 时 +1 属性）
var attr_exp: Dictionary = {
	"str": 0, "dex": 0, "mag": 0, "con": 0, "agi": 0, "per": 0
}

# 角色等级 + 总经验
var level: int = 1
var level_exp: int = 0

# 武器熟练度（按武器类型 id 累积，达门槛解锁技能）
# 策划案 §1.1：T1 需 Lv3，T2 需 Lv8，T3 需 Lv15
var weapon_proficiency: Dictionary = {}  # {"one_hand_melee": 0, "two_hand": 0, ...}

# 已领悟技能 id 列表
var unlocked_skills: Array = []

# 已解锁里程碑被动 id 列表
var unlocked_milestones: Array = []

# ============================================================================
# 2. 属性查询 API
# ============================================================================

## 获取 6 属性字典（供 CombatBridge.build_player_attack/defender 使用）
func get_player_attrs() -> Dictionary:
	return attrs.duplicate()

## 获取单属性值
func get_attr(attr_key: String) -> int:
	return int(attrs.get(attr_key, 0))

## 获取角色等级
func get_level() -> int:
	return level

## 获取武器熟练度等级
func get_proficiency(weapon_type: String) -> int:
	return int(weapon_proficiency.get(weapon_type, 0))

# ============================================================================
# 3. 双轨经验累积（策划案 §5.1）
# ============================================================================

## 主属性经验累积。gain > 0 时累积，达门槛自动 +1 属性并触发里程碑判定。
func accumulate_attr(attr_key: String, gain: int) -> bool:
	if not attrs.has(attr_key):
		return false
	var cur_exp: int = int(attr_exp.get(attr_key, 0))
	var result: Dictionary = CE.accumulate_attr_exp(cur_exp, gain)
	attr_exp[attr_key] = result["exp"]
	if result["leveled_up"]:
		attrs[attr_key] = int(attrs[attr_key]) + 1
		_check_milestone_unlock(attr_key)
		return true
	return false

## 武器熟练度累积。gain > 0 时累积，达门槛自动解锁对应技能。
func accumulate_proficiency(weapon_type: String, gain: int) -> void:
	var cur: int = int(weapon_proficiency.get(weapon_type, 0))
	weapon_proficiency[weapon_type] = cur + gain

## 角色等级经验累积（策划案未给具体阈值，暂用简化阶梯）
func accumulate_level_exp(gain: int) -> void:
	level_exp += gain
	var threshold: int = _level_upgrade_threshold(level)
	while level_exp >= threshold:
		level_exp -= threshold
		level += 1
		threshold = _level_upgrade_threshold(level)

## 角色升级经验阈值（简化：level × 100）
func _level_upgrade_threshold(lv: int) -> int:
	return lv * 100

# ============================================================================
# 4. 里程碑被动解锁判定（策划案 §3.1）
# ============================================================================

## 属性提升后检查是否解锁对应里程碑被动
func _check_milestone_unlock(attr_key: String) -> void:
	const SD := preload("res://globals/combat/skill_data.gd")
	var attr_val: int = int(attrs[attr_key])
	for ms in SD.ATTR_MILESTONES:
		if ms["attr"] != attr_key:
			continue
		if unlocked_milestones.has(ms["id"]):
			continue
		if SD.can_unlock_milestone(ms["tier"], attr_val):
			unlocked_milestones.append(ms["id"])
			print("[AttrPanel] 里程碑解锁: %s (属性 %s=%d)" % [ms["id"], attr_key, attr_val])

## 检查某里程碑被动是否已解锁
func has_milestone(milestone_id: String) -> bool:
	return unlocked_milestones.has(milestone_id)

## 获取某属性某阶里程碑被动定义（若已解锁）
func get_milestone(attr_key: String, tier: int) -> Dictionary:
	const SD := preload("res://globals/combat/skill_data.gd")
	for ms in SD.ATTR_MILESTONES:
		if ms["attr"] == attr_key and ms["tier"] == tier:
			if has_milestone(ms["id"]):
				return ms
	return {}

# ============================================================================
# 5. 技能领悟判定（策划案 §1.1）
# ============================================================================

## 检查并解锁所有满足门槛的技能。返回本次新解锁的技能 id 列表。
func check_skill_unlocks() -> Array:
	const SD := preload("res://globals/combat/skill_data.gd")
	var newly_unlocked: Array = []
	for skill in SD.SKILLS:
		if unlocked_skills.has(skill["id"]):
			continue
		var school: int = skill["school"]
		var tier: int = skill["tier"]
		# 主攻属性门槛：取该流派任一主攻属性满足即可
		var main_attrs: Array = SD.SCHOOL_MAIN_ATTR.get(school, [])
		var attr_ok: bool = false
		for ak in main_attrs:
			if int(attrs.get(ak, 0)) >= SD.UNLOCK_THRESHOLD[tier]["attr"]:
				attr_ok = true
				break
		if not attr_ok:
			continue
		# 武器熟练度门槛：取该流派媒介武器类型
		var medium: String = SD.SCHOOL_WEAPON_MEDIUM.get(school, "")
		if medium == "":
			# 徒手流派：用专门 "unarmed" 熟练度键
			medium = "unarmed"
		var prof: int = int(weapon_proficiency.get(medium, 0))
		if prof < SD.UNLOCK_THRESHOLD[tier]["proficiency"]:
			continue
		unlocked_skills.append(skill["id"])
		newly_unlocked.append(skill["id"])
		print("[AttrPanel] 技能领悟: %s" % skill["id"])
	return newly_unlocked

## 检查某技能是否已领悟
func has_skill(skill_id: String) -> bool:
	return unlocked_skills.has(skill_id)

# ============================================================================
# 6. 衍生面板数值（策划案 §2.1）
# ============================================================================

## 最大生命值 = 100 + 体质×10 + 等级×5（含里程碑"强健体魄" +20）
func compute_max_hp() -> int:
	var base: int = CE.compute_max_hp(int(attrs["con"]), level)
	if has_milestone("强健体魄"):
		base += 20
	return base

## 物理防御 = 防具防御 + 体质（防具暂 0）
func compute_physical_def() -> int:
	return CE.compute_physical_def(0, int(attrs["con"]))

## 负重上限 = 50 + 体质×2（含里程碑"蛮力负荷" +15）
func compute_carry_weight() -> int:
	var base: int = CE.compute_carry_weight(int(attrs["con"]))
	if has_milestone("蛮力负荷"):
		base += 15
	return base

## 基础闪避率（仅用于 UI 展示，战斗结算已移除闪避率机制）
## = 灵巧×1% + 里程碑"虚实避让" +6%
func compute_evade_rate() -> float:
	var base: float = int(attrs["agi"]) * 1.0
	if has_milestone("虚实避让"):
		base += 6.0
	return base

## 基础暴击率 = 5 + 感知×0.5（含里程碑"弱点洞察" +5%）
func compute_crit_rate() -> float:
	var base: float = 5.0 + int(attrs["per"]) * 0.5
	if has_milestone("弱点洞察"):
		base += 5.0
	return base

## 移动速度倍率（含里程碑"轻捷之行" +10%）
func compute_move_speed_mult() -> float:
	var mult: float = 1.0
	if has_milestone("轻捷之行"):
		mult += 0.10
	return mult

# ============================================================================
# 7. 存档/读档
# ============================================================================

## 序列化为字典（供 GameState 存档）
func serialize() -> Dictionary:
	return {
		"attrs": attrs.duplicate(),
		"attr_exp": attr_exp.duplicate(),
		"level": level,
		"level_exp": level_exp,
		"weapon_proficiency": weapon_proficiency.duplicate(),
		"unlocked_skills": unlocked_skills.duplicate(),
		"unlocked_milestones": unlocked_milestones.duplicate(),
	}

## 从字典恢复
func deserialize(data: Dictionary) -> void:
	if data.has("attrs"):
		attrs = data["attrs"].duplicate()
	if data.has("attr_exp"):
		attr_exp = data["attr_exp"].duplicate()
	if data.has("level"):
		level = int(data["level"])
	if data.has("level_exp"):
		level_exp = int(data["level_exp"])
	if data.has("weapon_proficiency"):
		weapon_proficiency = data["weapon_proficiency"].duplicate()
	if data.has("unlocked_skills"):
		unlocked_skills = data["unlocked_skills"].duplicate()
	if data.has("unlocked_milestones"):
		unlocked_milestones = data["unlocked_milestones"].duplicate()

## 重置为初始状态
func reset() -> void:
	attrs = {"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5}
	attr_exp = {"str": 0, "dex": 0, "mag": 0, "con": 0, "agi": 0, "per": 0}
	level = 1
	level_exp = 0
	weapon_proficiency = {}
	unlocked_skills = []
	unlocked_milestones = []
