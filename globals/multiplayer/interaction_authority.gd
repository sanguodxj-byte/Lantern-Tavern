extends RefCounted
## InteractionAuthority（docs/25 §11 / §5.2）—— 服务器端交互/拾取的权威裁决。
## 仅服务器调用；客户端只发送 request_interact / request_pickup 意图。
##
## 纯逻辑、无场景树依赖：实体与玩家状态以数据字典传入，便于单测。
##
## live（服务器维护的玩家权威状态，不可信客户端的字段）：
##   {"peer_id":int, "is_alive":bool, "position":Vector3}
## entities：Dictionary entity_id -> {"type","item_id","item_kind","amount","position","consumed"}
## 返回：{"success":bool, "target_entity_id":int, "inventory_delta":Dictionary,
##        "error_code":String, "event":Dictionary}
##
## 校验顺序（§11）：存活 → 目标存在 → 未被消费 → 距离 → 写入背包 → 标记消费。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const CommandValidator := preload("res://globals/multiplayer/command_validator.gd")

const INTERACT_RANGE := 2.5  # 米，拾取/交互最大距离

# 交互锁：entity_id -> peer_id。防止两名玩家同时占用同一实体（§13.1「释放交互锁」）。
# 实体被消费后锁仍保留，直到持有者断线时由 clear_locks_for 释放，或显式 release_lock。
var _interaction_locks: Dictionary = {}

func _init() -> void:
	_interaction_locks = {}

## 尝试获取某实体的交互锁（已被他人持有则返回 false）。
func acquire_lock(entity_id: int, peer_id: int) -> bool:
	if _interaction_locks.has(entity_id) and int(_interaction_locks[entity_id]) != peer_id:
		return false
	_interaction_locks[entity_id] = peer_id
	return true

## 释放某实体的交互锁。
func release_lock(entity_id: int) -> void:
	_interaction_locks.erase(entity_id)

## 释放某 peer 持有的全部交互锁（断线清理时调用，§13.1）。返回释放数量。
func clear_locks_for(peer_id: int) -> int:
	var released := 0
	for eid in _interaction_locks.keys():
		if int(_interaction_locks[eid]) == peer_id:
			_interaction_locks.erase(eid)
			released += 1
	return released

## 重连接管：把旧 peer_id 持有的全部交互锁改挂到新 peer_id（peer_id 会随重连变化）。
func migrate_locks(old_peer_id: int, new_peer_id: int) -> void:
	if old_peer_id == new_peer_id:
		return
	for eid in _interaction_locks.keys():
		if int(_interaction_locks[eid]) == old_peer_id:
			_interaction_locks[eid] = new_peer_id

func resolve_interaction(command: Dictionary, ctx: PlayerContext, live: Dictionary, entities: Dictionary) -> Dictionary:
	var empty := {"success": false, "target_entity_id": 0, "inventory_delta": {}, "error_code": "", "event": {}}
	if live == null or not bool(live.get("is_alive", false)):
		empty["error_code"] = NP.ERR_PLAYER_NOT_ALIVE
		return empty
	if not command.has("target_entity_id"):
		empty["error_code"] = NP.ERR_INVALID_TARGET
		return empty
	var eid: int = int(command["target_entity_id"])
	if not entities.has(eid):
		empty["error_code"] = NP.ERR_INVALID_TARGET
		return empty
	var ent: Dictionary = entities[eid]
	if bool(ent.get("consumed", false)):
		empty["error_code"] = NP.ERR_TARGET_ALREADY_CONSUMED
		return empty
	# 距离校验使用服务器权威的玩家位置，而非命令里客户端自报的位置
	var ppos: Vector3 = live.get("position", Vector3.ZERO)
	var epos: Vector3 = ent.get("position", Vector3.ZERO)
	if not CommandValidator.validate_range(ppos, epos, INTERACT_RANGE):
		empty["error_code"] = NP.ERR_OUT_OF_RANGE
		return empty
	# 原子写入背包
	var item_id: String = String(ent.get("item_id", ""))
	var kind: String = String(ent.get("item_kind", "material"))
	var amount: int = int(ent.get("amount", 1))
	var inv = ctx.inventory
	var ok: bool = false
	match kind:
		"material":
			ok = inv.add_material(item_id, amount)
		"rune":
			ok = inv.add_rune(item_id, amount)
		"equipment":
			ok = inv.add_equipment(item_id, amount)
		_:
			ok = inv.add_material(item_id, amount)
	if not ok:
		# 背包已满或物品非法
		empty["error_code"] = NP.ERR_INSUFFICIENT_RESOURCE
		return empty
	# 标记实体已被消费（服务器权威状态，后续请求将拿到 TARGET_ALREADY_CONSUMED）
	ent["consumed"] = true
	# 占用交互锁（释放由 clear_locks_for 在断线时统一处理，§13.1）
	acquire_lock(eid, int(live.get("peer_id", 0)))
	var delta := {item_id: amount}
	return {
		"success": true,
		"target_entity_id": eid,
		"inventory_delta": delta,
		"error_code": "",
		"event": {
			"event": NP.EVT_INTERACTION_RESULT,
			"sequence": int(command.get("sequence", 0)),
			"success": true,
			"target_entity_id": eid,
			"inventory_delta": delta,
		},
	}
