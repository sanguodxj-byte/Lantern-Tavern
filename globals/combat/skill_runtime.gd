extends Node
## 技能运行时系统（autoload: SkillRuntime）。
## 槽位结构：2 主动技能槽（F/G 键）+ 5 被动技能槽。
## F/G 槽：通用主动技能槽，可绑定动作技能或已领悟的武器主动技能。
## 被动槽：常驻被动技能（武器流派被动 + 属性里程碑被动），无需释放。
## 主动/被动槽均可镶嵌符文，符文会生成有效技能定义。

const SD := preload("res://globals/combat/skill_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")
const CE := preload("res://globals/combat/combat_engine.gd")
const MC := preload("res://globals/combat/momentum_context.gd")
const RD := preload("res://globals/combat/rune_data.gd")

# 槽位索引
const SLOT_F_ACTION: int = 0      # F 键：通用主动技能（保留旧名兼容）
const SLOT_G_WEAPON: int = 1      # G 键：通用主动技能（保留旧名兼容）
const SLOT_PASSIVE_1: int = 2     # 被动槽 1
const SLOT_PASSIVE_2: int = 3     # 被动槽 2
const SLOT_PASSIVE_3: int = 4     # 被动槽 3
const SLOT_PASSIVE_4: int = 5     # 被动槽 4
const SLOT_PASSIVE_5: int = 6     # 被动槽 5
const TOTAL_SLOTS: int = 7
const MAX_RUNES_PER_SLOT: int = 3
const MAX_RUNES_PER_PASSIVE_SLOT: int = 2

# 槽位类型
enum SlotType { F_ACTION, G_WEAPON, PASSIVE }

# ============================================================================
# 1. 运行时状态
# ============================================================================

# 槽位 → 技能 id（空字符串表示未绑定）
var slots: Array = ["", "", "", "", "", "", ""]

# 槽位 → 符文 id 列表
var slot_runes: Array = [[], [], [], [], [], [], []]

# 主动技能 CD 剩余秒数：技能 id → 剩余秒（0 = 可释放）
var cooldowns: Dictionary = {}

# 施法前摇剩余秒数：技能 id → 剩余秒
var cast_timers: Dictionary = {}

# 施法/动作已经过秒数：技能 id → 已经过秒
var cast_elapsed: Dictionary = {}

# release_on_start 技能已经触发效果，但仍处于可取消动作窗口
var released_while_casting: Dictionary = {}

# 正在施法的技能 id
var casting_skill: String = ""
var casting_slot: int = -1
var release_slot_context: Dictionary = {}

# 最近一次技能取消继承到的动量，下一次命中消费
var pending_momentum_context = null

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
## F/G 槽：接受动作技能，或已领悟武器主动技能
## 被动槽：仅接受被动技能（SkillData.SKILLS type=passive）
func bind_skill(slot_index: int, skill_id: String) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return false
	if skill_id == "":
		slots[slot_index] = ""
		slot_runes[slot_index] = []
		return true
	var slot_type: int = get_slot_type(slot_index)
	match slot_type:
		SlotType.F_ACTION, SlotType.G_WEAPON:
			if not _can_bind_active_skill(skill_id):
				return false
			slots[slot_index] = skill_id
			slot_runes[slot_index] = []
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
			slot_runes[slot_index] = []
			return true
	return false

func _can_bind_active_skill(skill_id: String) -> bool:
	if not AS.get_skill_by_id(skill_id).is_empty():
		return true
	var skill: Dictionary = SD.get_skill_by_id(skill_id)
	if skill.is_empty() or skill.get("type", "") != "active":
		return false
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("AttrPanel")
	return ap != null and ap.has_skill(skill_id)

## 解绑槽位
func unbind_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < TOTAL_SLOTS:
		slots[slot_index] = ""
		slot_runes[slot_index] = []

## 获取槽位技能 id
func get_slot_skill(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return ""
	return slots[slot_index]

func socket_rune(slot_index: int, rune_id: String) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return false
	if get_slot_skill(slot_index) == "":
		return false
	if not RD.has_rune(rune_id):
		return false
	var runes: Array = slot_runes[slot_index]
	if runes.size() >= get_rune_capacity(slot_index):
		return false
	runes.append(rune_id)
	slot_runes[slot_index] = runes
	return true

func get_rune_capacity(slot_index: int) -> int:
	return MAX_RUNES_PER_PASSIVE_SLOT if get_slot_type(slot_index) == SlotType.PASSIVE else MAX_RUNES_PER_SLOT

func unsocket_rune(slot_index: int, rune_index: int) -> bool:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return false
	var runes: Array = slot_runes[slot_index]
	if rune_index < 0 or rune_index >= runes.size():
		return false
	runes.remove_at(rune_index)
	slot_runes[slot_index] = runes
	return true

func get_slot_runes(slot_index: int) -> Array:
	if slot_index < 0 or slot_index >= TOTAL_SLOTS:
		return []
	return slot_runes[slot_index].duplicate()

func get_effective_slot_skill(slot_index: int) -> Dictionary:
	var skill_id := get_slot_skill(slot_index)
	if skill_id == "":
		return {}
	return RD.apply_runes(get_skill_definition(skill_id), get_slot_runes(slot_index))

func get_effective_skill_definition(skill_id: String) -> Dictionary:
	if release_slot_context.has(skill_id):
		var context_slot := int(release_slot_context[skill_id])
		if context_slot >= 0 and context_slot < TOTAL_SLOTS and slots[context_slot] == skill_id:
			return get_effective_slot_skill(context_slot)
	for i in range(TOTAL_SLOTS):
		if slots[i] == skill_id:
			return get_effective_slot_skill(i)
	return get_skill_definition(skill_id)

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
func can_release(skill_id: String, main_hand: String, off_hand: String) -> Dictionary:
	var skill: Dictionary = get_effective_skill_definition(skill_id)
	if skill.is_empty():
		return {"ok": false, "reason": "技能不存在"}
	var skill_type := String(skill.get("type", ""))
	if skill_type != "active" and skill_type != "action":
		return {"ok": false, "reason": "被动技能不可释放"}
	return _can_release_check(skill_id, skill, false, main_hand, off_hand)

## 通用释放校验：CD + 施法中
func _can_release_check(skill_id: String, skill: Dictionary, _need_medium: bool, _main_hand: String, _off_hand: String) -> Dictionary:
	var cd_remain: float = float(cooldowns.get(skill_id, 0.0))
	if cd_remain > 0.0:
		return {"ok": false, "reason": "冷却中", "cd_remain": cd_remain}
	if casting_skill != "":
		var elapsed := get_cast_elapsed(casting_skill)
		if can_cancel(casting_skill, skill_id, elapsed):
			return {"ok": true, "cancelled": true, "cancelled_from": casting_skill}
		return {"ok": false, "reason": "正在施法其他技能"}
	return {"ok": true}

## 开始释放技能
func start_release(skill_id: String, main_hand: String, off_hand: String, actor: Node = null, slot_index: int = -1) -> bool:
	var context_slot := slot_index if slot_index >= 0 else _find_slot_for_skill(skill_id)
	if context_slot >= 0:
		release_slot_context[skill_id] = context_slot
	var check: Dictionary = can_release(skill_id, main_hand, off_hand)
	if not check["ok"]:
		release_slot_context.erase(skill_id)
		return false
	# 确定技能定义来源（动作技能 or 武器技能）
	var skill: Dictionary = get_effective_skill_definition(skill_id)
	if bool(check.get("cancelled", false)):
		var cancelled_from := String(check.get("cancelled_from", ""))
		_prepare_momentum_context(cancelled_from, skill, actor)
		_interrupt_casting_skill(cancelled_from)
	var cast_time: float = float(skill.get("cast_time", 0.0))
	if cast_time > 0.0:
		casting_skill = skill_id
		casting_slot = context_slot
		cast_timers[skill_id] = cast_time
		cast_elapsed[skill_id] = 0.0
		if bool(skill.get("release_on_start", false)):
			released_while_casting[skill_id] = true
			_release_effect(skill_id, context_slot)
	else:
		_complete_release(skill_id, context_slot)
	return true

## 施法前摇完成
func _complete_release(skill_id: String, slot_index: int = -1) -> void:
	if casting_skill == skill_id:
		casting_skill = ""
		casting_slot = -1
	cast_timers.erase(skill_id)
	cast_elapsed.erase(skill_id)
	released_while_casting.erase(skill_id)
	release_slot_context.erase(skill_id)
	_release_effect(skill_id, slot_index)

func _release_effect(skill_id: String, slot_index: int = -1) -> void:
	var context_slot := slot_index if slot_index >= 0 else casting_slot
	if context_slot >= 0:
		release_slot_context[skill_id] = context_slot
	# 进入 CD
	var skill: Dictionary = get_effective_skill_definition(skill_id)
	var cd: float = float(skill.get("cooldown", 0.0))
	if cd > 0.0:
		cooldowns[skill_id] = cd
	# 里程碑被动：魔力凝息（MAG T1）10% 概率 CD 清零（仅 spell 流派技能）
	const ME := preload("res://globals/combat/milestone_effects.gd")
	var school: int = int(skill.get("school", -1))
	var is_spell_skill: bool = school == SD.School.ENCHANT_WAND or school == SD.School.GRIMOIRE
	if is_spell_skill and ME.try_mana_focus_cd_reset(true):
		cooldowns[skill_id] = 0.0
	skill_released.emit(skill_id)
	release_slot_context.erase(skill_id)

func _interrupt_casting_skill(skill_id: String) -> void:
	if skill_id == "":
		return
	if casting_skill == skill_id:
		casting_skill = ""
		casting_slot = -1
	cast_timers.erase(skill_id)
	cast_elapsed.erase(skill_id)
	released_while_casting.erase(skill_id)

func _prepare_momentum_context(cancelled_from: String, next_skill: Dictionary, actor: Node) -> void:
	pending_momentum_context = null
	if not bool(next_skill.get("inherit_momentum", false)):
		return
	if actor == null:
		return
	pending_momentum_context = MC.from_actor(actor, cancelled_from, get_skill_cancel_tag(cancelled_from))

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
		cast_elapsed[casting_skill] = float(cast_elapsed.get(casting_skill, 0.0)) + delta
		cast_remain -= delta
		if cast_remain <= 0.0:
			var sid := casting_skill
			if bool(released_while_casting.get(sid, false)):
				_interrupt_casting_skill(sid)
			else:
				_complete_release(sid, casting_slot)
		else:
			cast_timers[casting_skill] = cast_remain

## 获取技能 CD 剩余秒数
func get_cooldown_remain(skill_id: String) -> float:
	return float(cooldowns.get(skill_id, 0.0))

## 获取技能 CD 进度（0~1，1 = 就绪）
func get_cooldown_progress(skill_id: String) -> float:
	var skill: Dictionary = get_effective_skill_definition(skill_id)
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

## 获取技能动作/前摇已经过秒数
func get_cast_elapsed(skill_id: String) -> float:
	return float(cast_elapsed.get(skill_id, 0.0))

## 是否正在施法
func is_casting(skill_id: String) -> bool:
	return casting_skill == skill_id

## 技能定义统一查询
func get_skill_definition(skill_id: String) -> Dictionary:
	var skill: Dictionary = AS.get_skill_by_id(skill_id)
	if skill.is_empty():
		skill = SD.get_skill_by_id(skill_id)
	return skill

## 供取消系统使用的技能标签。动作技能优先使用显式字段，武器技能按流派归类。
func get_skill_cancel_tag(skill_id: String) -> String:
	var skill := get_skill_definition(skill_id)
	if skill.is_empty():
		return ""
	if skill.has("cancel_tag"):
		return String(skill["cancel_tag"])
	if skill.has("skill_family"):
		return String(skill["skill_family"])
	var school := int(skill.get("school", -1))
	if school == SD.School.LONGBOW or school == SD.School.LIGHT_CROSSBOW:
		return "ranged"
	if school == SD.School.ENCHANT_WAND or school == SD.School.GRIMOIRE:
		return "spell"
	if String(skill.get("buff_type", "")) == "def_and_evade_up" or String(skill.get("buff_type", "")) == "damage_absorb":
		return "block"
	if String(skill.get("type", "")) == "active":
		return "melee"
	return String(skill.get("type", ""))

## 判定 current_skill 是否能在 elapsed_sec 时打断进入 next_skill。
func can_cancel(current_skill: String, next_skill: String, elapsed_sec: float = -1.0) -> bool:
	if current_skill == "" or next_skill == "" or current_skill == next_skill:
		return false
	var current := get_effective_skill_definition(current_skill)
	var next := get_effective_skill_definition(next_skill)
	if current.is_empty() or next.is_empty():
		return false
	if elapsed_sec < 0.0:
		elapsed_sec = get_cast_elapsed(current_skill)
	var cancel_start := _get_cancel_start(current)
	var cancel_end := _get_cancel_end(current)
	if elapsed_sec < cancel_start or elapsed_sec > cancel_end:
		return false
	var allowed: Array = _get_cancel_into(current)
	if allowed.is_empty():
		return false
	var next_tag := get_skill_cancel_tag(next_skill)
	var next_family := String(next.get("skill_family", ""))
	var next_type := String(next.get("type", ""))
	return allowed.has(next_skill) or allowed.has(next_tag) or allowed.has(next_family) or allowed.has(next_type)

func _get_cancel_start(skill: Dictionary) -> float:
	if skill.has("cancel_start"):
		return float(skill["cancel_start"])
	if String(skill.get("type", "")) == "active":
		return minf(float(skill.get("cast_time", 0.0)) * 0.35, 0.35)
	return INF

func _get_cancel_end(skill: Dictionary) -> float:
	if skill.has("cancel_end"):
		return float(skill["cancel_end"])
	if String(skill.get("type", "")) == "active":
		return float(skill.get("cast_time", 0.0))
	return -INF

func _get_cancel_into(skill: Dictionary) -> Array:
	if skill.has("cancel_into"):
		return skill["cancel_into"]
	if String(skill.get("type", "")) == "active":
		return ["movement", "kick", "melee", "ranged", "spell", "block"]
	return []

func peek_momentum_context():
	return pending_momentum_context

func consume_momentum_context():
	var ctx = pending_momentum_context
	pending_momentum_context = null
	return ctx

# ============================================================================
# 6. 媒介判定辅助（供 UI 置灰）
# ============================================================================

## F/G 主动槽不再按武器媒介置灰。
func is_slot_medium_matched(slot_index: int, main_hand: String, off_hand: String) -> bool:
	var sid: String = get_slot_skill(slot_index)
	if sid == "":
		return false
	if is_active_slot(slot_index):
		return true
	var skill: Dictionary = get_skill_definition(sid)
	return not skill.is_empty()

# ============================================================================
# 7. 存档/读档
# ============================================================================

func serialize() -> Dictionary:
	return {
		"slots": slots.duplicate(),
		"slot_runes": slot_runes.duplicate(true),
		"cooldowns": cooldowns.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	if data.has("slots"):
		slots = data["slots"].duplicate()
	if data.has("cooldowns"):
		cooldowns = data["cooldowns"].duplicate()
	if data.has("slot_runes"):
		slot_runes = data["slot_runes"].duplicate(true)
		_ensure_slot_runes_shape()

func reset() -> void:
	slots = ["", "", "", "", "", "", ""]
	slot_runes = [[], [], [], [], [], [], []]
	cooldowns.clear()
	cast_timers.clear()
	cast_elapsed.clear()
	released_while_casting.clear()
	casting_skill = ""
	casting_slot = -1
	pending_momentum_context = null
	release_slot_context.clear()

func _find_slot_for_skill(skill_id: String) -> int:
	for i in range(TOTAL_SLOTS):
		if slots[i] == skill_id:
			return i
	return -1

func _ensure_slot_runes_shape() -> void:
	while slot_runes.size() < TOTAL_SLOTS:
		slot_runes.append([])
	if slot_runes.size() > TOTAL_SLOTS:
		slot_runes.resize(TOTAL_SLOTS)
	for i in range(TOTAL_SLOTS):
		if typeof(slot_runes[i]) != TYPE_ARRAY:
			slot_runes[i] = []
		var capacity := get_rune_capacity(i)
		if slot_runes[i].size() > capacity:
			slot_runes[i].resize(capacity)
