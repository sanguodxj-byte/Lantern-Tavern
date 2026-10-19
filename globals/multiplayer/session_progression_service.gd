class_name SessionProgressionService
extends RefCounted

## 成长命令编排服务（ADR-003 渐进拆分：SessionRoot 第四刀）。
## 从 SessionRoot 迁出 progression 命令族：level_up_choice / level_up_rune_candidates，
## 以及权威成长状态事件构造（progression_event）。
##
## 依赖约定：共享状态与保留 API 经 `_r` 访问——_ctx_peer/_seq_tracker、
## _reject/session_event、expedition_service._peer_guid。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const ProgressionAuthorityClass := preload("res://globals/multiplayer/progression_authority.gd")

var _r = null

func _init(root: Node) -> void:
	_r = root

## 客户端提交升级选择（CMD_LEVEL_UP_CHOICE，P1-4 权威收口）：校验 pending 升级合法性和
## 选择有效性后应用（六维 +1 或符文机会二选一），应用成功广播 EVT_PROGRESSION_CHANGED；
## 失败不消耗任何升级机会。客户端面板只发送意图，绝不直接修改服务器权威属性。
func handle_level_up_choice(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var intent := {
		"kind": String(command.get("kind", "")),
		"attr_key": String(command.get("attr_key", "")),
		"rune_id": String(command.get("rune_id", "")),
	}
	var res: Dictionary = ProgressionAuthorityClass.apply_level_up_choice(ctx.attributes, ctx.inventory, intent)
	if not bool(res.get("ok", false)):
		return _r.reject(String(res.get("error_code", NP.ERR_INVALID_TARGET)))
	var evt := progression_event(peer_id, ctx)
	_r.session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 客户端请求本次升级的符文候选：服务器按 player_guid 确定性掷出（重连/回放同一组），
## 经 EVT_PROGRESSION_RUNE_CANDIDATES 下发；候选锁定在权威 AttrPanel。
func handle_level_up_rune_candidates(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var candidates: Array = ProgressionAuthorityClass.roll_rune_candidates(ctx.attributes, _r.expedition_service._peer_guid(peer_id, ctx))
	if candidates.is_empty():
		return _r.reject(NP.ERR_INVALID_STATE)
	var evt := {
		"event": NP.EVT_PROGRESSION_RUNE_CANDIDATES,
		"peer_id": peer_id,
		"candidates": candidates,
	}
	_r.session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": ""}

## 权威成长状态事件（P1-4）：killer/选择者 peer 的等级/经验/待升级队列快照。
func progression_event(peer_id: int, ctx: PlayerContextClass) -> Dictionary:
	var attrs = ctx.attributes
	return {
		"event": NP.EVT_PROGRESSION_CHANGED,
		"peer_id": peer_id,
		"level": int(attrs.get_level()) if attrs != null else 1,
		"level_exp": int(attrs.level_exp) if attrs != null else 0,
		"threshold": int(attrs.get_level_upgrade_threshold()) if attrs != null else 100,
		"pending_level_choices": int(attrs.get_pending_level_choices()) if attrs != null else 0,
	}
