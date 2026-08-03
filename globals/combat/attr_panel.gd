extends Node
## 玩家属性面板系统（autoload: AttrPanel）。
## 6 大主属性 + 角色等级 + 双轨经验持久化。
## 替换 CombatBridge 集成期的临时默认值（全 10 / 等级 1）。
## 策划案《05-战斗系统》§2.1 属性面板 + §5.1 双轨经验。

const CE := preload("res://globals/combat/combat_engine.gd")
const RD := preload("res://globals/combat/rune_data.gd")

signal experience_changed(level: int, current_exp: int, required_exp: int, gained_exp: int)
signal level_up_choices_changed(pending_count: int)
signal level_up_reward_resolved(reward_kind: String, reward_id: String)

# 6 大主属性 id（与 CombatEngine.Attr 枚举对应）
const ATTR_KEYS: Array = ["str", "dex", "mag", "con", "agi", "per"]

# ============================================================================
# 1. 持久化状态（save/load 兼容）
# ============================================================================

# 6 主属性当前值（引用类型，必须在 _init 内按实例独立初始化，
# 否则 GDScript 类级字面量会被所有实例共享 —— 联机 per-peer 隔离会被破坏）
var attrs: Dictionary
var attr_exp: Dictionary

# 角色等级 + 总经验
var level: int = 1
var level_exp: int = 0
## 每升一级产生一次，必须由玩家选择六维 +1 或三选一符文后才会消耗。
var pending_level_choices: int = 0
## 已进入符文分支时锁定的三个候选，避免通过重开界面反复刷新。
var pending_rune_candidates: Array[String] = []

# 武器熟练度（按武器类型 id 累积，达门槛解锁技能）
# 策划案 §1.1：T1 需 Lv3，T2 需 Lv8，T3 需 Lv15
var weapon_proficiency: Dictionary

# 已领悟技能 id 列表
var unlocked_skills: Array

# 已解锁里程碑被动 id 列表
var unlocked_milestones: Array

# 出身系统（docs/36-出身系统与涌现式Build.md）
# 已选出身 id（空字符串 = 未选出身 = 旧存档兼容，全 5 初始值）
var origin_id: String = ""

# 熟练度阶梯奖励 {weapon_type: [threshold, ...]}
# 阈值 20/40/60/80/100 分别解锁伤害/攻速/暴击/大师被动/终极加成
var proficiency_milestones: Dictionary = {}

# 熟练度硬上限
const PROFICIENCY_CAP: int = 100

# 熟练度阶梯阈值
const PROFICIENCY_MILESTONE_THRESHOLDS: Array = [20, 40, 60, 80, 100]

# 每个实例独立的初始状态（避免类级字面量跨实例共享）
func _init() -> void:
	attrs = {"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5}
	attr_exp = {"str": 0, "dex": 0, "mag": 0, "con": 0, "agi": 0, "per": 0}
	weapon_proficiency = {}
	unlocked_skills = []
	unlocked_milestones = []
	origin_id = ""
	proficiency_milestones = {}

# ============================================================================
# 2. 属性查询 API
# ============================================================================

## 获取 6 属性字典（供 CombatBridge.build_player_attack/defender 使用）
func get_player_attrs() -> Dictionary:
	return attrs.duplicate()

## 获取单属性值
func get_attr(attr_key: String) -> int:
	return int(attrs.get(attr_key, 0))

## 显式初始化钩子（AttrPanel 无 _ready 依赖，此处仅建立/校验默认状态，
## 使 per-peer 实例与 autoload 行为一致）。联机工厂在 .new() 后调用。
func init_defaults() -> void:
	for k in ATTR_KEYS:
		if not attrs.has(k):
			attrs[k] = 5
		if not attr_exp.has(k):
			attr_exp[k] = 0

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
		_recompute_mechanism_passives()
		return true
	return false

## 武器熟练度累积。gain > 0 时累积，封顶 100，达阶梯阈值解锁奖励。
func accumulate_proficiency(weapon_type: String, gain: int) -> void:
	var cur: int = int(weapon_proficiency.get(weapon_type, 0))
	var new_val: int = mini(cur + gain, PROFICIENCY_CAP)
	weapon_proficiency[weapon_type] = new_val
	_check_proficiency_milestones(weapon_type, new_val)
	# 武器 tier 类机制被动（蓄力/完美格挡/快速装弹）依赖熟练度，重算授予
	_recompute_mechanism_passives()

## 检查并解锁熟练度阶梯奖励（20/40/60/80/100）
func _check_proficiency_milestones(weapon_type: String, val: int) -> void:
	if not proficiency_milestones.has(weapon_type):
		proficiency_milestones[weapon_type] = []
	var unlocked: Array = proficiency_milestones[weapon_type]
	for threshold in PROFICIENCY_MILESTONE_THRESHOLDS:
		if val >= threshold and not unlocked.has(threshold):
			unlocked.append(threshold)
			print("[AttrPanel] 熟练度阶梯解锁: %s @%d" % [weapon_type, threshold])

## 获取某武器类别的熟练度加成（供 CombatBridge 注入 AttackInput）
func get_proficiency_bonus(weapon_type: String) -> Dictionary:
	var unlocked: Array = proficiency_milestones.get(weapon_type, [])
	return {
		"damage_mult": 1.0 + (0.05 if unlocked.has(20) else 0.0) + (0.10 if unlocked.has(100) else 0.0),
		"attack_speed_mult": 1.0 + (0.05 if unlocked.has(40) else 0.0) + (0.05 if unlocked.has(100) else 0.0),
		"crit_bonus": 3.0 if unlocked.has(60) else 0.0,
		"master_passive": unlocked.has(80),
	}

## 检查某武器类别是否已解锁大师级被动（熟练度 ≥ 80）
func has_master_proficiency(weapon_type: String) -> bool:
	var unlocked: Array = proficiency_milestones.get(weapon_type, [])
	return unlocked.has(80)

## 角色等级经验累积。返回本次提升的等级数；溢出经验保留并可连续升级。
func accumulate_level_exp(gain: int) -> int:
	if gain <= 0:
		return 0
	level_exp += gain
	var levels_gained := 0
	var threshold: int = get_level_upgrade_threshold()
	while level_exp >= threshold:
		level_exp -= threshold
		level += 1
		levels_gained += 1
		pending_level_choices += 1
		threshold = get_level_upgrade_threshold()
	experience_changed.emit(level, level_exp, threshold, gain)
	if levels_gained > 0:
		level_up_choices_changed.emit(pending_level_choices)
	return levels_gained

## 角色升级经验阈值（简化：level × 100）
func _level_upgrade_threshold(lv: int) -> int:
	return lv * 100

func get_level_upgrade_threshold() -> int:
	return _level_upgrade_threshold(level)

func get_pending_level_choices() -> int:
	return pending_level_choices

## 选择六维之一直接 +1，并消耗一次待处理升级选择。
func choose_level_up_attribute(attr_key: String) -> bool:
	if pending_level_choices <= 0 or not pending_rune_candidates.is_empty() or not ATTR_KEYS.has(attr_key):
		return false
	attrs[attr_key] = int(attrs.get(attr_key, 0)) + 1
	_check_milestone_unlock(attr_key)
	check_skill_unlocks()
	_recompute_mechanism_passives()
	_consume_level_up_choice("attribute", attr_key)
	return true

## 进入符文分支后锁定三个互不重复的候选；同一次选择重复打开会返回同一组。
func begin_level_up_rune_choice(rng: RandomNumberGenerator = null) -> Array[String]:
	if pending_level_choices <= 0:
		return []
	if pending_rune_candidates.is_empty():
		var rolled_candidates := RD.roll_unique_rune_ids("chest", 3, rng)
		if rolled_candidates.size() == 3:
			pending_rune_candidates = rolled_candidates
	return pending_rune_candidates.duplicate()

## 领取一个候选符文。grant_callback 负责写入实际符文库存，失败时不消耗升级机会。
func choose_level_up_rune(rune_id: String, grant_callback: Callable) -> bool:
	if pending_level_choices <= 0 or not pending_rune_candidates.has(rune_id):
		return false
	if not grant_callback.is_valid() or not bool(grant_callback.call(rune_id, 1)):
		return false
	_consume_level_up_choice("rune", rune_id)
	return true

func _consume_level_up_choice(reward_kind: String, reward_id: String) -> void:
	pending_level_choices = maxi(0, pending_level_choices - 1)
	pending_rune_candidates.clear()
	level_up_reward_resolved.emit(reward_kind, reward_id)
	level_up_choices_changed.emit(pending_level_choices)

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

## 依据当前双轨阶梯重算机制类被动授予（doc21 §5/§7）。
## 跨 autoload 调用统一走节点查找，避免全局名解析不确定性。
func _recompute_mechanism_passives() -> void:
	var sr = Engine.get_main_loop().root.get_node_or_null("SkillRuntime")
	if sr != null and sr.has_method("recompute_mechanism_passives"):
		sr.recompute_mechanism_passives()

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
		# 领悟读取武器类别熟练度；单双手剑共享 sword，法杖使用 staff。
		var proficiency_key: String = SD.SCHOOL_PROFICIENCY_KEY.get(school, "")
		var prof: int = int(weapon_proficiency.get(proficiency_key, 0))
		if prof < SD.UNLOCK_THRESHOLD[tier]["proficiency"]:
			continue
		unlocked_skills.append(skill["id"])
		newly_unlocked.append(skill["id"])
		print("[AttrPanel] 技能领悟: %s" % skill["id"])
	# 技能领悟门槛同时依赖 属性+熟练度，可能新满足某机制被动阶梯，重算授予
	_recompute_mechanism_passives()
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
		"pending_level_choices": pending_level_choices,
		"pending_rune_candidates": pending_rune_candidates.duplicate(),
		"weapon_proficiency": weapon_proficiency.duplicate(),
		"unlocked_skills": unlocked_skills.duplicate(),
		"unlocked_milestones": unlocked_milestones.duplicate(),
		"origin_id": origin_id,
		"proficiency_milestones": proficiency_milestones.duplicate(true),
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
	pending_level_choices = maxi(0, int(data.get("pending_level_choices", 0)))
	pending_rune_candidates.clear()
	for raw_id in data.get("pending_rune_candidates", []):
		var rune_id := String(raw_id)
		if RD.has_rune(rune_id) and not pending_rune_candidates.has(rune_id):
			pending_rune_candidates.append(rune_id)
	if pending_level_choices <= 0:
		pending_rune_candidates.clear()
	if data.has("weapon_proficiency"):
		weapon_proficiency = data["weapon_proficiency"].duplicate()
	if data.has("unlocked_skills"):
		unlocked_skills = data["unlocked_skills"].duplicate()
	if data.has("unlocked_milestones"):
		unlocked_milestones = data["unlocked_milestones"].duplicate()
	# 出身系统字段（旧存档无此字段时默认空值，完全向后兼容）
	origin_id = String(data.get("origin_id", ""))
	if data.has("proficiency_milestones"):
		proficiency_milestones = data["proficiency_milestones"].duplicate(true)
	# 读档后按已恢复的属性/熟练度重算机制被动授予
	_recompute_mechanism_passives()

## 重置为初始状态
func reset() -> void:
	attrs = {"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5}
	attr_exp = {"str": 0, "dex": 0, "mag": 0, "con": 0, "agi": 0, "per": 0}
	level = 1
	level_exp = 0
	pending_level_choices = 0
	pending_rune_candidates.clear()
	weapon_proficiency = {}
	unlocked_skills = []
	unlocked_milestones = []
	origin_id = ""
	proficiency_milestones = {}
