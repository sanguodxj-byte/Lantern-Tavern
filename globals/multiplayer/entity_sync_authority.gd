extends RefCounted
## EntitySyncAuthority（docs/25 §9 / §12.3）—— 服务器端实体（敌人/掉落/宝箱/门）复制权威。
##
## 服务器维护权威实体表，产生 entity_spawned / entity_snapshot / entity_despawned 事件，
## 供 SceneMultiplayer 下行到各客户端（真实 RPC 接线在场景/ENet 联调阶段）。
## 纯逻辑、可单测；实体状态以字典传入（与 InteractionAuthority 一致风格）。
##
## entities：Dictionary entity_id -> 实体状态字典（由调用方/服务器持有）。
## 返回结构：{"success":bool, "error_code":String, "event":Dictionary}

const NP := preload("res://globals/multiplayer/network_protocol.gd")

## 生成实体：写入 entities，返回 entity_spawned 事件。已存在则返回失败（避免重复生成）。
func spawn_entity(entity_id: int, data: Dictionary, entities: Dictionary) -> Dictionary:
	if entities.has(entity_id):
		return {"success": false, "error_code": NP.ERR_INVALID_STATE, "event": {}}
	entities[entity_id] = data.duplicate()
	return {"success": true, "error_code": "", "event": {
		"event": NP.EVT_ENTITY_SPAWNED, "entity_id": entity_id, "data": data.duplicate()}}

## 销毁实体：从 entities 移除，返回 entity_despawned 事件。不存在则返回失败。
func despawn_entity(entity_id: int, entities: Dictionary) -> Dictionary:
	if not entities.has(entity_id):
		return {"success": false, "error_code": NP.ERR_INVALID_TARGET, "event": {}}
	entities.erase(entity_id)
	return {"success": true, "error_code": "", "event": {
		"event": NP.EVT_ENTITY_DESPAWNED, "entity_id": entity_id}}

## 更新实体部分字段：合并进 entities，返回 entity_snapshot 事件（含完整当前状态）。
func update_entity(entity_id: int, partial: Dictionary, entities: Dictionary) -> Dictionary:
	if not entities.has(entity_id):
		return {"success": false, "error_code": NP.ERR_INVALID_TARGET, "event": {}}
	for k in partial.keys():
		entities[entity_id][k] = partial[k]
	return {"success": true, "error_code": "", "event": {
		"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": entity_id, "data": entities[entity_id].duplicate()}}

## 复制增量：对比客户端已知状态 prev 与服务器当前状态 curr，
## 产出一组复制事件，使客户端从 prev 平滑过渡到 curr。
## prev / curr：Dictionary entity_id -> 实体状态（用于比较是否变化）。
## 返回 Array[Dictionary]（事件列表），顺序：先处理新增/变化，再处理消失。
func build_delta(prev: Dictionary, curr: Dictionary) -> Array:
	var events: Array = []
	for eid in curr.keys():
		var cur: Dictionary = curr[eid]
		if not prev.has(eid):
			events.append({"event": NP.EVT_ENTITY_SPAWNED, "entity_id": int(eid), "data": cur.duplicate()})
		elif not _equal(prev[eid], cur):
			events.append({"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": int(eid), "data": cur.duplicate()})
	for eid in prev.keys():
		if not curr.has(eid):
			events.append({"event": NP.EVT_ENTITY_DESPAWNED, "entity_id": int(eid)})
	return events

func _equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		if typeof(a[k]) != typeof(b[k]):
			return false
		if a[k] != b[k]:
			return false
	return true
