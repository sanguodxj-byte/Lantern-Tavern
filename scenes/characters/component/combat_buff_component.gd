class_name CombatBuffComponent
extends RefCounted

## 战斗增益/减益管理器
## 从 player.gd 提取，负责 buff 的添加、衰减、查询和伤害吸收。
## 设计为 RefCounted（非 Node），由宿主（Player/Enemy）持有引用并在 _physics_process 中调用 tick()。
## 这样做的好处：不依赖场景树，可在单元测试中直接 new() 使用。

## 所有活跃 buff 的字典：{ buff_type: { "remaining": float, "value": Variant } }
var _buffs: Dictionary = {}


# ============================================================================
# 添加 / 查询
# ============================================================================

## 添加一个 buff。duration_sec <= 0 或空 type 将被忽略。
func add(buff_type: String, duration_sec: float, value: Variant) -> void:
	if buff_type == "" or duration_sec <= 0.0:
		return
	_buffs[buff_type] = {"remaining": duration_sec, "value": value}

## 该 buff 类型当前是否活跃
func has(buff_type: String) -> bool:
	return _buffs.has(buff_type)

## 获取 buff 的 value 字段（无则返回 null）
func get_value(buff_type: String) -> Variant:
	if not _buffs.has(buff_type):
		return null
	return _buffs[buff_type].get("value", null)


# ============================================================================
# 战斗属性查询（玩家 buff 专用）
# ============================================================================

## 防御加成（def_and_evade_up buff 的 def 字段）
func get_defense_bonus() -> int:
	var bonus := 0
	if _buffs.has("def_and_evade_up"):
		var value = _buffs["def_and_evade_up"].get("value", {})
		if typeof(value) == TYPE_DICTIONARY:
			bonus += int(value.get("def", 0))
	return bonus

## 闪避加成（def_and_evade_up buff 的 evade 字段）
func get_evade_bonus() -> float:
	var bonus := 0.0
	if _buffs.has("def_and_evade_up"):
		var value = _buffs["def_and_evade_up"].get("value", {})
		if typeof(value) == TYPE_DICTIONARY:
			bonus += float(value.get("evade", 0.0))
	return bonus

## 移速乘数（slow_and_haste buff 的 haste_self 字段）
func get_speed_multiplier() -> float:
	var mult := 1.0
	if _buffs.has("slow_and_haste"):
		var value = _buffs["slow_and_haste"].get("value", {})
		if typeof(value) == TYPE_DICTIONARY:
			mult *= 1.0 + float(value.get("haste_self", 0.0)) / 100.0
	return mult


# ============================================================================
# 伤害吸收（一次性消费 buff）
# ============================================================================

## 消费 damage_absorb buff，按最大生命值百分比吸收伤害。
## 返回吸收后的剩余伤害。吸收后该 buff 被移除。
func consume_damage_absorb(damage: int, max_life: int) -> int:
	if not _buffs.has("damage_absorb"):
		return damage
	var buff: Dictionary = _buffs["damage_absorb"]
	var absorb_percent := float(buff.get("value", 0.0))
	var absorb_amount := int(round(max_life * absorb_percent / 100.0))
	var reduced := maxi(damage - absorb_amount, 0)
	_buffs.erase("damage_absorb")
	return reduced


# ============================================================================
# 每帧 tick（由宿主在 _physics_process 中调用）
# ============================================================================

## 推进所有 buff 的剩余时间，过期则移除
func tick(delta: float) -> void:
	for buff_type in _buffs.keys():
		var buff: Dictionary = _buffs[buff_type]
		var remaining := float(buff.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			_buffs.erase(buff_type)
		else:
			buff["remaining"] = remaining
			_buffs[buff_type] = buff


# ============================================================================
# 兼容性接口
# ============================================================================

## 返回内部字典引用（供旧代码直接访问，如测试中的 player.combat_buffs["key"] = value）
func get_buffs_dict() -> Dictionary:
	return _buffs
