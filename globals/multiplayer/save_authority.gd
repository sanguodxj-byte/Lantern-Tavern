extends RefCounted

## SaveAuthority —— 存档信任边界 / 出征结算幂等权威（Phase 5）。
##
## 设计目标（docs/25 §14 + §17.4 安全测试「修改库存数量 / 重复拾取」）：
## 出征结算（extract / save）把玩家【本次净获得】写回其各自的单人存档。若客户端可以
## 重复发送 CMD_EXTRACT / CMD_SAVE，则每次都会再累加一次净获得 → 刷物品漏洞。
## 本权威以 **player_guid**（稳定身份，不随 peer_id 变化，§14.2）为主键维护
## 「本次出征是否已结算 + 已结算 settlement 快照」的账本，实现幂等：
##   - 首次结算：记录并返回真实 settlement（already_settled=false，桥接层落地写回存档）。
##   - 重复结算：返回同一缓存 settlement（already_settled=true，桥接层跳过写回）。
##
## 不声明 class_name，规避 headless 类注册 / .uid 问题；经 preload 访问：
##   const SaveAuthorityClass := preload("res://globals/multiplayer/save_authority.gd")
##
## 纯逻辑 RefCounted、无场景树依赖，可 headless 单测。
## 关联：globals/multiplayer/session_root.gd（结算入口）、
##       globals/multiplayer/multiplayer_scene_bridge.gd（结算落地）。

## 当前出征修订号（每次开新出征 bump，用于区分不同 run 的结算账本）。
var expedition_revision: int = 0

## 已结算账本：player_guid -> {"revision": int, "settlement": Dictionary}。
var _settled: Dictionary = {}

func _init() -> void:
	expedition_revision = 0
	_settled = {}

## 开始一次新出征：bump 修订号并清空结算账本（新 run 允许各玩家重新结算一次）。
## revision 可由 DungeonAuthority 的 layout_revision 传入以对齐；缺省则自增。
func begin_expedition(revision: int = -1) -> void:
	if revision >= 0:
		expedition_revision = revision
	else:
		expedition_revision += 1
	_settled.clear()

## 该 guid 在本次出征是否已结算过。
func is_settled(guid: String) -> bool:
	if guid == "":
		return false
	var rec: Dictionary = _settled.get(guid, {})
	return not rec.is_empty() and int(rec.get("revision", -1)) == expedition_revision

## 记录一次结算。返回 true 表示首次记录（应落地写回存档）；
## false 表示本次出征已结算过（幂等：不应重复写回）。
func mark_settled(guid: String, settlement: Dictionary) -> bool:
	if guid == "":
		return false
	if is_settled(guid):
		return false
	_settled[guid] = {
		"revision": expedition_revision,
		"settlement": settlement.duplicate(true),
	}
	return true

## 取某 guid 已结算的 settlement 快照（未结算返回空字典）。
func get_settlement(guid: String) -> Dictionary:
	var rec: Dictionary = _settled.get(guid, {})
	if rec.is_empty() or int(rec.get("revision", -1)) != expedition_revision:
		return {}
	return (rec.get("settlement", {}) as Dictionary).duplicate(true)

## 重连身份迁移：guid 不变，无需搬移账本（账本以 guid 为键，peer_id 变化不影响）。
## 保留此方法以对齐 session_root 的迁移调用约定（当前为 no-op，语义占位）。
func migrate_guid(_old_guid: String, _new_guid: String) -> void:
	pass

## 序列化供重连快照（§13.2）：使重连玩家无法通过「断线→重连→再结算」绕过幂等。
func serialize() -> Dictionary:
	return {
		"expedition_revision": expedition_revision,
		"settled": _settled.duplicate(true),
	}

func deserialize(data: Dictionary) -> void:
	if data == null:
		return
	expedition_revision = int(data.get("expedition_revision", 0))
	var s = data.get("settled", {})
	_settled = (s as Dictionary).duplicate(true) if s is Dictionary else {}
