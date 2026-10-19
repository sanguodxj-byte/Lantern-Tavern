class_name SessionExpeditionService
extends RefCounted

## 出征/结算/存档编排服务（ADR-003 渐进拆分：SessionRoot 第一刀）。
## 从 SessionRoot 迁出 expedition lifecycle 命令族：
##   start（CMD_EXPEDITION / 生产入口）/ extract / save / baseline 结算。
## 持有 SessionRoot 引用访问共享状态容器；公共 API 由 SessionRoot 委托转发，
## 外部调用（NetworkManager.start_expedition、测试）保持完全兼容。
##
## 拆分原则（2251 审查 P1-1）：每步只搬方法族 + 对应测试，不改变行为语义；
## 本服务内的编辑不再触碰 SessionRoot 战斗/实体/复制代码。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const ExpeditionInventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const EquipmentLoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")

## SessionRoot 引用（构造注入；无类型以避免循环 preload，运行时动态访问其成员）。
## GDScript 对 Node 类型的静态成员解析会拒绝私有方法访问，故保持 Variant。
var _r = null

func _init(root: Node) -> void:
	_r = root

## 服务器权威存档 schema 版本（1122 审查 P1-3）：加载时未知未来版本硬拒绝。
const SERVER_SAVE_SCHEMA_VERSION := 1

# ============================================================================
# 出征唯一权威事务
# ============================================================================

## 出征唯一权威事务入口（1417 审查 P0-1）：生产入口（房主本地 MultiplayerSession）
## 与命令路由 CMD_EXPEDITION 共用同一事务，杜绝双实现路径：
##   1. dungeon_auth.start_expedition() 生成布局；
##   2. save_auth.begin_expedition() 以新 layout_revision 清空上轮结算账本；
##   3. _bump_world("dungeon") 推进空间与权威 world_revision 并广播；
##   4. 发布布局事件（session_event 由 NetworkManager 自动路由广播）。
func start_expedition_authoritatively(seed_hint: int = -1) -> Dictionary:
	if not _r.is_server:
		return {"success": false, "error_code": NP.ERR_INVALID_STATE, "event": {}}
	var evt: Dictionary = _r.dungeon_auth.start_expedition(seed_hint)
	# 新一轮出征必须重置结算账本（绑定 layout_revision），否则旧 run 的已结算
	# GUID 在新 run 中仍会被 is_settled() 判为已结算，重复奖励/丢档。
	_r.save_auth.begin_expedition(_r.dungeon_auth.layout_revision)
	_r.bump_world("dungeon")
	_r.session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 命令路由 handler（原 _handle_start_expedition）。
## P1-4（0304 审查）：仅房主可经命令路由发起；已开始的 run 拒绝重复启动
## （不得重置当前 run 的结算账本）。服务器自身（dedicated）直调
## start_expedition_authoritatively，不走本路由。
func handle_start_expedition(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if _r.host_peer_id != 0 and peer_id != _r.host_peer_id:
		return _r.reject(NP.ERR_PERMISSION_DENIED)
	if _r.dungeon_auth.active:
		return _r.reject(NP.ERR_INVALID_STATE)
	var provided_seed: int = int(command.get("seed", -1))
	return start_expedition_authoritatively(provided_seed)

# ============================================================================
# 结算（extract / save 共用）
# ============================================================================

## 客户端请求保存（CMD_SAVE）：与结算共用收口，requested_save=true。
func handle_save(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	return settle_expedition(peer_id, ctx, true)

## 出征结算（CMD_EXTRACT，§Phase 5）：客户端完成出征后请求结算，服务器计算该玩家
## 【本次净获得】（当前背包 - 进地牢时的基线），经 EVT_EXTRACTION_RESULT 回传。
## 幂等由 SaveAuthority 收口，防止「重复发 CMD_EXTRACT 刷物品」（§17.4 安全测试）。
func handle_extract(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	return settle_expedition(peer_id, ctx, false)

## 结算收口（extract / save 共用）：以 player_guid 幂等锚定本次出征结算。
## 首次结算：计算净获得、记入 SaveAuthority、返回 already_settled=false。
## 重复结算：返回缓存 settlement、already_settled=true（杜绝刷物品）。
func settle_expedition(peer_id: int, ctx: PlayerContextClass, requested_save: bool) -> Dictionary:
	var guid: String = _peer_guid(peer_id, ctx)
	if _r.save_auth.is_settled(guid):
		var cached: Dictionary = _r.save_auth.get_settlement(guid)
		var evt_dup := {
			"event": NP.EVT_EXTRACTION_RESULT,
			"peer_id": peer_id,
			"settlement": cached,
			"already_settled": true,
			"requested_save": requested_save,
		}
		return {"success": true, "event": evt_dup, "error_code": ""}
	var settlement: Dictionary = compute_settlement(peer_id)
	# P0-2（1122 审查）：先持久化、成功后才 mark_settled 并返回成功。
	# 写盘失败（磁盘满/权限/rename 失败）→ SAVE_PERSIST_FAILED，不消耗幂等机会。
	if _r.server_save_repo != null:
		if not _r.server_save_repo.save_save(guid, build_server_save_state(ctx)):
			return _r.reject(NP.ERR_SAVE_PERSIST_FAILED)
	_r.save_auth.mark_settled(guid, settlement)
	var evt := {
		"event": NP.EVT_EXTRACTION_RESULT,
		"peer_id": peer_id,
		"settlement": settlement,
		"already_settled": false,
		"requested_save": requested_save,
	}
	return {"success": true, "event": evt, "error_code": ""}

# ============================================================================
# 存档快照 / 恢复 / 净获得计算
# ============================================================================

## 构建服务器存档仓快照（与 GameState.build_network_save_state 同构：
## materials(三类字典)/loadout/spell_state/attributes/skills，附 schema_version）。
func build_server_save_state(ctx: PlayerContextClass) -> Dictionary:
	var state := {
		"schema_version": SERVER_SAVE_SCHEMA_VERSION,
		"materials": ctx.inventory.materials.duplicate(),
		"loadout": ctx.loadout.to_dict(),
		"spell_state": ctx.serialize_spell_state(),
	}
	if ctx.attributes != null and ctx.attributes.has_method("serialize"):
		state["attributes"] = ctx.attributes.serialize()
	if ctx.skills != null and ctx.skills.has_method("serialize"):
		state["skills"] = ctx.skills.serialize()
	return state

## 把服务器存档摘要应用到新生成的 PlayerContext（spawn 恢复）。
## P1-3（1122 审查）：未知未来 schema 版本硬拒绝，不做部分恢复。
func apply_save_state(ctx: PlayerContextClass, inv: ExpeditionInventoryClass, lo: EquipmentLoadoutClass, save_state: Dictionary) -> void:
	if save_state.has("schema_version") and int(save_state["schema_version"]) > SERVER_SAVE_SCHEMA_VERSION:
		push_warning("[SessionRoot] 服务器存档 schema 版本 %d 高于当前支持 %d，拒绝恢复" % [int(save_state["schema_version"]), SERVER_SAVE_SCHEMA_VERSION])
		return
	if save_state.has("materials") and save_state["materials"] is Dictionary:
		inv.materials = save_state["materials"].duplicate()
	if save_state.has("loadout") and save_state["loadout"] is Dictionary:
		lo.from_dict(save_state["loadout"])
	if save_state.has("spell_state") and save_state["spell_state"] is Dictionary:
		ctx.deserialize_spell_state(save_state["spell_state"])
	# P1-4：统一 DungeonPlayerSnapshot——属性/熟练度/等级与技能装配随存档摘要恢复。
	if save_state.has("attributes") and save_state["attributes"] is Dictionary and ctx.attributes != null:
		ctx.attributes.deserialize(save_state["attributes"])
	if save_state.has("skills") and save_state["skills"] is Dictionary and ctx.skills != null:
		ctx.skills.deserialize(save_state["skills"])

## 取某 peer 的稳定身份 guid（优先 PlayerContext.player_guid，缺省按 peer_id 派生）。
func _peer_guid(peer_id: int, ctx: PlayerContextClass = null) -> String:
	if ctx != null and "player_guid" in ctx and String(ctx.player_guid) != "":
		return String(ctx.player_guid)
	var c: PlayerContextClass = _r.registry.get_context(peer_id)
	if c != null and "player_guid" in c and String(c.player_guid) != "":
		return String(c.player_guid)
	return "peer_%d" % peer_id

## 计算某 peer 的出征净获得 = 当前背包 - 进地牢基线，按 materials/runes/equipment 三类求正差值。
## 纯计算：不修改任何状态（1122 审查 P0-2 事务顺序的前提）。
func compute_settlement(peer_id: int) -> Dictionary:
	var ctx: PlayerContextClass = _r.registry.get_context(peer_id)
	if ctx == null or ctx.inventory == null:
		return {"materials": {}, "runes": {}, "equipment": {}, "attributes": {}}
	var cur: Dictionary = ctx.inventory.to_dict()
	var base: Dictionary = _r.inventory_baseline().get(peer_id, {"materials": {}, "runes": {}, "equipment": {}})
	var out: Dictionary = {"materials": {}, "runes": {}, "equipment": {}, "attributes": {}}
	for cat in ["materials", "runes", "equipment"]:
		var c: Dictionary = cur.get(cat, {})
		var b: Dictionary = base.get(cat, {})
		for k in c.keys():
			var delta: int = int(c[k]) - int(b.get(k, 0))
			if delta > 0:
				out[cat][k] = delta
	if ctx.attributes != null and ctx.attributes.has_method("serialize"):
		out["attributes"] = ctx.attributes.serialize()
	return out
