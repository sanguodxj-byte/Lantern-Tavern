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
## 性能优化：检测实际变化——若 partial 中所有字段值与当前值相同，跳过事件生成和 duplicate，
## 避免战斗中频繁但无实质变化的更新（如同 HP 被格挡不扣血）产生冗余网络广播。
func update_entity(entity_id: int, partial: Dictionary, entities: Dictionary) -> Dictionary:
	if not entities.has(entity_id):
		return {"success": false, "error_code": NP.ERR_INVALID_TARGET, "event": {}}
	var cur: Dictionary = entities[entity_id]
	var changed: bool = false
	for k in partial.keys():
		var new_val: Variant = partial[k]
		var cur_val: Variant = cur.get(k, null)
		# 类型安全比较：不同 typeof 视为变化（短路避免跨类型 != 崩溃）；
		# 同类型用 != 做值比较。typeof 是廉价类型标签读取，远比 duplicate()+RPC 开销低。
		if typeof(cur_val) != typeof(new_val) or cur_val != new_val:
			cur[k] = new_val
			changed = true
	if not changed:
		return {"success": true, "error_code": "", "event": {}}
	return {"success": true, "error_code": "", "event": {
		"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": entity_id, "data": cur.duplicate()}}

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
		# 类型安全比较：不同 typeof 视为不等（短路避免跨类型 != 崩溃）
		var av: Variant = a[k]
		var bv: Variant = b[k]
		if typeof(av) != typeof(bv) or av != bv:
			return false
	return true
