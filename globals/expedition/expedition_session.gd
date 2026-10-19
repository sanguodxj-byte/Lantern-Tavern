class_name ExpeditionSession
extends RefCounted

## 远征会话连续性载体（架构审查 1215 C1/C2/C3，用户 G2 已拍板白名单）。
##
## 楼层场景（ProceduralDungeon）会在下楼时被销毁重建；本类作为独立于楼层场景的
## 远征状态边界，捕获「同一趟远征」必须跨层保留的状态，并在新层恢复。
##
## 跨层保留（G2 白名单）：
##   - 远征时钟/暗蚀：elapsed_minutes / threat_level / opened_doors / broken_doors
##     + 一次性决策标记（recommendation/overtime 已触发）
##   - 玩家资源：当前生命 / 法力 / 法术屏障盾 / 持久 buff（含剩余时长）
## 跨层清除（白名单外，不拷贝）：
##   - 攻击冷却、二段跳/格挡残影等战斗瞬态（player_combat_runtime 状态）
##   - 动画状态、场景引用（Node 引用一律不序列化）
## 装备/背包由 GameState 既有模型持有，本类不复制第二份真相。

var zone: int = 0
var floor: int = 1
var active: bool = false

## 压力状态快照（字段对齐 ExplorationPressure 实例字段）。
var pressure_state: Dictionary = {}

## 玩家过渡状态：current_life / max_life / spell_mana / spell_max_mana / shield / buffs。
## buffs 形如 { buff_type: { "remaining": float, "value": Variant } }（对齐 CombatBuffComponent）。
var player_transition_state: Dictionary = {}

const MAX_BUFF_TYPES := 32  # 防御：跨层 buff 数量上限，防止异常膨胀

## 清空为未激活初始态。
func clear() -> void:
	active = false
	zone = 0
	floor = 1
	pressure_state = {}
	player_transition_state = {}

## 从当前压力节点捕获远征时钟/暗蚀（节点可空；字段缺失时取 0 默认）。
func capture_pressure_from(pressure: Node) -> void:
	pressure_state = {}
	if pressure == null:
		return
	pressure_state["elapsed_minutes"] = int(_node_get(pressure, "elapsed_minutes", 0))
	pressure_state["threat_level"] = float(_node_get(pressure, "threat_level", 0.0))
	pressure_state["opened_doors"] = int(_node_get(pressure, "opened_doors", 0))
	pressure_state["broken_doors"] = int(_node_get(pressure, "broken_doors", 0))
	pressure_state["_recommendation_sent"] = bool(_node_get(pressure, "_recommendation_sent", false))
	pressure_state["_overtime_sent"] = bool(_node_get(pressure, "_overtime_sent", false))

## Object.get() 只接受 1 参数——包装带默认值的属性读取。
static func _node_get(node: Node, property: String, default_value: Variant) -> Variant:
	var value = node.get(property)
	return value if value != null else default_value

## 恢复压力到新层的 ExplorationPressure 实例（节点可空；不强制非空）。
func restore_pressure_to(pressure: Node) -> void:
	if pressure == null:
		return
	if pressure.has_method("import_snapshot"):
		pressure.import_snapshot(pressure_state)

## 从玩家节点捕获跨层保留的资源状态（玩家可空；组件经 has_method/has 防御性读取）。
func capture_player_from(player: Node) -> void:
	player_transition_state = {}
	if player == null:
		return
	if "health" in player and player.health != null:
		player_transition_state["current_life"] = int(_node_get(player.health, "current_life", 0))
		player_transition_state["max_life"] = int(_node_get(player.health, "max_life", 1))
	if "buffs" in player and player.buffs != null and player.buffs.has_method("get_buffs_dict"):
		var buffs: Dictionary = player.buffs.get_buffs_dict()
		var out: Dictionary = {}
		var count := 0
		for buff_type in buffs.keys():
			if count >= MAX_BUFF_TYPES:
				break
			var buff: Dictionary = buffs[buff_type]
			out[String(buff_type)] = {
				"remaining": float(buff.get("remaining", 0.0)),
				"value": buff.get("value", null),
			}
			count += 1
		if not out.is_empty():
			player_transition_state["buffs"] = out

## 恢复资源到新层玩家节点：生命 clamp 到新玩家 max_life，法力/盾回写权威 PlayerContext，
## buff 以剩余时长重新登记（瞬态战斗状态不恢复）。
func restore_player_to(player: Node) -> void:
	if player == null or player_transition_state.is_empty():
		return
	if "health" in player and player.health != null:
		var max_life := int(_node_get(player.health, "max_life", 1))
		var desired := int(_node_get(player.health, "current_life", 0))
		desired = int(player_transition_state.get("current_life", desired))
		player.health.set("current_life", clampi(desired, 0, max_life))
	if "buffs" in player and player.buffs != null and player.buffs.has_method("add"):
		var buffs: Dictionary = player_transition_state.get("buffs", {})
		for buff_type in buffs.keys():
			var buff: Dictionary = buffs[buff_type]
			player.buffs.add(String(buff_type), float(buff.get("remaining", 0.0)), buff.get("value", null))

## 序列化为可 JSON 化字典（仅 active 时携带数据）。
func to_dict() -> Dictionary:
	return {
		"zone": zone,
		"floor": floor,
		"active": active,
		"pressure_state": pressure_state.duplicate(true),
		"player_transition_state": _sanitize_for_json(player_transition_state),
	}

## 从存档字典恢复。旧存档无该键时保持默认未激活。
func from_dict(data: Dictionary) -> void:
	clear()
	if data.is_empty() or not bool(data.get("active", false)):
		return
	active = true
	zone = int(data.get("zone", 0))
	floor = int(data.get("floor", 1))
	if data.has("pressure_state") and data["pressure_state"] is Dictionary:
		pressure_state = (data["pressure_state"] as Dictionary).duplicate(true)
	if data.has("player_transition_state") and data["player_transition_state"] is Dictionary:
		player_transition_state = _sanitize_from_json(data["player_transition_state"] as Dictionary)

## JSON 化：buff value 可能含非 JSON 类型（如 Color/Vector3），仅保留基础类型。
static func _sanitize_for_json(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in state.keys():
		var value = state[key]
		if value is Dictionary:
			out[String(key)] = _sanitize_for_json(value as Dictionary)
		elif value is Array:
			var arr: Array = []
			for item in value:
				arr.append(item if _is_json_primitive(item) else str(item))
			out[String(key)] = arr
		elif _is_json_primitive(value):
			out[String(key)] = value
	return out

static func _sanitize_from_json(state: Dictionary) -> Dictionary:
	return _sanitize_for_json(state)

static func _is_json_primitive(value: Variant) -> bool:
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]
