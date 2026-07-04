extends Node
## 技能运行时系统（autoload: SkillRuntime）。
## 槽位结构：2 主动技能槽（F/G 键）+ 5 被动技能槽。
## F 槽：通用动作技能（踢击/冲撞/抓取投掷/滑铲/战术滑步），无武器媒介限制。
## G 槽：武器流派主动技能（受媒介限制，策划案 §1.2）。
## 被动槽：常驻被动技能（武器流派被动 + 属性里程碑被动），无需释放。

const SD := preload("res://globals/skill_data.gd")
const AS := preload("res://globals/action_skills.gd")
const CE := preload("res://globals/combat_engine.gd")

# 槽位索引
const SLOT_F_ACTION: int = 0      # F 键：通用动作技能
const SLOT_G_WEAPON: int = 1      # G 键：武器流派主动技能
const SLOT_PASSIVE_1: int = 2     # 被动槽 1
const SLOT_PASSIVE_2: int = 3     # 被动槽 2
const SLOT_PASSIVE_3: int = 4     # 被动槽 3
const SLOT_PASSIVE_4: int = 5     # 被动槽 4
const SLOT_PASSIVE_5: int = 6     # 被动槽 5
const TOTAL_SLOTS: int = 7

# 槽位类型
enum SlotType { F_ACTION, G_WEAPON, PASSIVE }

# ============================================================================
# 1. 运行时状态
# ============================================================================

# 槽位 → 技能 id（空字符串表示未绑定）
var slots: Array = ["", "", "", "", "", "", ""]

# 主动技能 CD 剩余秒数：技能 id → 剩余秒（0 = 可释放）
var cooldowns: Dictionary = {}

# 施法前摇剩余秒数：技能 id → 剩余秒
var cast_timers: Dictionary = {}

# 正在施法的技能 id
var casting_skill: String = ""

signal skill_released(skill_id: String)

# ============================================================================
# 2. 槽位类型查询
# ============================================================================

## 获取槽位类型
func get_slot_type(slot_index: int) -> int:
	match slot_index:
		SLOT_F_ACTION:
			return SlotType.F_ACTION
		SLOT_G_WEAPON:
			return SlotType.G_WEAPON
		SLOT_PASSIVE_1, SLOT_PASSIVE_2, SLOT_PASSIVE_3, SLOT_PASSIVE_4, SLOT_PASSIVE_5:
			return SlotType.PASSIVE
		_:
			return -1

## 槽位是否为主动技能槽（可释放）
func is_active_slot(slot_index: int) -> bool:
	var t: int = get_slot_type(slot_index)
	return t == SlotType.F_ACTION or t == SlotType.G_WEAPON

# ============================================================================
# 3. 槽位绑定
# ============================================================================

## 绑定技能到槽位
## F 槽：仅接受动作技能（ActionSkills.SKILLS），无媒介限制
## G 槽：仅接受武器流派主动技能（SkillData.SKILLS type=active），受媒介限制
## 被动槽：仅接受被动技能（SkillData.SKILLS type=passive）
func bind_skill(slot_index: int, skill_id: String) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return false
	if skill_id == "":
		slots[slot_index] = ""
		return true
	var slot_type: int = get_slot_type(slot_index)
	match slot_type:
		SlotType.F_ACTION:
			# F 槽：动作技能，无媒介/领悟校验（动作技能默认可用）
			var action_skill: Dictionary = AS.get_skill_by_id(skill_id)
			if action_skill.is_empty():
				return false
			slots[slot_index] = skill_id
			return true
		SlotType.G_WEAPON:
			# G 槽：武器流派主动技能，校验已领悟
			var skill: Dictionary = SD.get_skill_by_id(skill_id)
			if skill.is_empty() or skill["type"] != "active":
				return false
			var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
			if ap == null or not ap.has_skill(skill_id):
				return false
			slots[slot_index] = skill_id
			return true
		SlotType.PASSIVE:
			# 被动槽：被动技能，校验已领悟
			var skill: Dictionary = SD.get_skill_by_id(skill_id)
			if skill.is_empty() or skill["type"] != "passive":
				return false
			var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
			if ap == null or not ap.has_skill(skill_id):
				return false
			slots[slot_index] = skill_id
			return true
	return false

## 解绑槽位
func unbind_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < TOTAL_SLOTS:
		slots[slot_index] = ""

## 获取槽位技能 id
func get_slot_skill(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return ""
	return slots[slot_index]

## 获取所有已绑定的主动技能 id（F+G 槽）
func get_bound_active_skills() -> Array:
	var result: Array = []
	if slots[SLOT_F_ACTION] != "":
		result.append(slots[SLOT_F_ACTION])
	if slots[SLOT_G_WEAPON] != "":
		result.append(slots[SLOT_G_WEAPON])
	return result

## 获取所有已绑定的被动技能 id
func get_bound_passive_skills() -> Array:
	var result: Array = []
	for i in range(SLOT_PASSIVE_1, SLOT_PASSIVE_5 + 1):
		if slots[i] != "":
			result.append(slots[i])
	return result

# ============================================================================
# 4. 释放判定
# ============================================================================

## 判定主动技能是否可释放
## F 槽动作技能：无媒介限制
## G 槽武器技能：受媒介限制（策划案 §1.2）
func can_release(skill_id: String, main_hand: String, off_hand: String) -> Dictionary:
	# F 槽动作技能
	var action_skill: Dictionary = AS.get_skill_by_id(skill_id)
	if not action_skill.is_empty():
		return _can_release_check(skill_id, action_skill, false, main_hand, off_hand)
	# G 槽武器流派技能
	var skill: Dictionary = SD.get_skill_by_id(skill_id)
	if skill.is_empty():
		return {"ok": false, "reason": "技能不存在"}
	if skill["type"] != "active":
		return {"ok": false, "reason": "被动技能不可释放"}
	# 媒介判定
	var school: int = skill["school"]
	if not SD.is_weapon_medium_matched(school, main_hand, off_hand):
		return {"ok": false, "reason": "武器媒介不匹配", "grey": true}
	return _can_release_check(skill_id, skill, true, main_hand, off_hand)

## 通用释放校验：CD + 施法中
func _can_release_check(skill_id: String, skill: Dictionary, _need_medium: bool, _main_hand: String, _off_hand: String) -> Dictionary:
	var cd_remain: float = float(cooldowns.get(skill_id, 0.0))
	if cd_remain > 0.0:
		return {"ok": false, "reason": "冷却中", "cd_remain": cd_remain}
	if casting_skill != "":
		return {"ok": false, "reason": "正在施法其他技能"}
	return {"ok": true}

## 开始释放技能
func start_release(skill_id: String, main_hand: String, off_hand: String) -> bool:
	var check: Dictionary = can_release(skill_id, main_hand, off_hand)
	if not check["ok"]:
		return false
	# 确定技能定义来源（动作技能 or 武器技能）
	var skill: Dictionary = AS.get_skill_by_id(skill_id)
	if skill.is_empty():
		skill = SD.get_skill_by_id(skill_id)
	var cast_time: float = float(skill.get("cast_time", 0.0))
	if cast_time > 0.0:
		casting_skill = skill_id
		cast_timers[skill_id] = cast_time
	else:
		_complete_release(skill_id)
	return true

## 施法前摇完成
func _complete_release(skill_id: String) -> void:
	if casting_skill == skill_id:
		casting_skill = ""
	cast_timers.erase(skill_id)
	# 进入 CD
	var skill: Dictionary = AS.get_skill_by_id(skill_id)
	if skill.is_empty():
		skill = SD.get_skill_by_id(skill_id)
	var cd: float = float(skill.get("cooldown", 0.0))
	if cd > 0.0:
		cooldowns[skill_id] = cd
	# 里程碑被动：魔力凝息（MAG T1）10% 概率 CD 清零（仅 spell 流派技能）
	const ME := preload("res://globals/milestone_effects.gd")
	var school: int = int(skill.get("school", -1))
	var is_spell_skill: bool = school == SD.School.ENCHANT_WAND or school == SD.School.GRIMOIRE
	if is_spell_skill and ME.try_mana_focus_cd_reset(true):
		cooldowns[skill_id] = 0.0
	skill_released.emit(skill_id)

# ============================================================================
# 5. Tick 更新
# ============================================================================

func tick(delta: float) -> void:
	for sid in cooldowns.keys():
		var remain: float = float(cooldowns[sid])
		remain -= delta
		if remain <= 0.0:
			cooldowns.erase(sid)
		else:
			cooldowns[sid] = remain
	if casting_skill != "":
		var cast_remain: float = float(cast_timers.get(casting_skill, 0.0))
		cast_remain -= delta
		if cast_remain <= 0.0:
			_complete_release(casting_skill)
		else:
			cast_timers[casting_skill] = cast_remain

## 获取技能 CD 剩余秒数
func get_cooldown_remain(skill_id: String) -> float:
	return float(cooldowns.get(skill_id, 0.0))

## 获取技能 CD 进度（0~1，1 = 就绪）
func get_cooldown_progress(skill_id: String) -> float:
	var skill: Dictionary = AS.get_skill_by_id(skill_id)
	if skill.is_empty():
		skill = SD.get_skill_by_id(skill_id)
	if skill.is_empty():
		return 1.0
	var cd: float = float(skill.get("cooldown", 0.0))
	if cd <= 0.0:
		return 1.0
	var remain: float = float(cooldowns.get(skill_id, 0.0))
	return 1.0 - (remain / cd)

## 获取施法前摇剩余秒数
func get_cast_remain(skill_id: String) -> float:
	return float(cast_timers.get(skill_id, 0.0))

## 是否正在施法
func is_casting(skill_id: String) -> bool:
	return casting_skill == skill_id

# ============================================================================
# 6. 媒介判定辅助（供 UI 置灰）
# ============================================================================

## G 槽武器技能媒介判定（F 槽动作技能永远匹配）
func is_slot_medium_matched(slot_index: int, main_hand: String, off_hand: String) -> bool:
	var sid: String = get_slot_skill(slot_index)
	if sid == "":
		return false
	if slot_index == SLOT_F_ACTION:
		return true  # 动作技能无媒介限制
	var skill: Dictionary = SD.get_skill_by_id(sid)
	if skill.is_empty():
		return false
	return SD.is_weapon_medium_matched(skill["school"], main_hand, off_hand)

# ============================================================================
# 7. 存档/读档
# ============================================================================

func serialize() -> Dictionary:
	return {
		"slots": slots.duplicate(),
		"cooldowns": cooldowns.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	if data.has("slots"):
		slots = data["slots"].duplicate()
	if data.has("cooldowns"):
		cooldowns = data["cooldowns"].duplicate()

func reset() -> void:
	slots = ["", "", "", "", "", "", ""]
	cooldowns.clear()
	cast_timers.clear()
	casting_skill = ""
