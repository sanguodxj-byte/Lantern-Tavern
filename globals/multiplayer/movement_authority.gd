extends RefCounted
## MovementAuthority（docs/25 §6.2）—— 服务器移动权威（Phase 4 逻辑层）。
##
## 设计基线：服务器采样客户端输入帧（input_frame），**从输入计算权威位置**，
## 绝不信任客户端自报的 position（防穿墙 / 速度作弊 / 瞬移 / 穿过敌人）。
## 复用 per-peer 严格递增 SequenceTracker（与攻击共用）以抵抗重放。
##
## 纯逻辑、无场景树依赖，全部方法可单测（docs/25 §17.1）。
## 实际 RPC 接线（SceneMultiplayer.rpc + MultiplayerSpawner）在编辑器/CI 联调，
## 本模块只负责“给定输入帧算出权威位置 + 产出 player_snapshot 事件”。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const CommandValidator := preload("res://globals/multiplayer/command_validator.gd")

## 每 tick 基础移动速度（米/秒）。服务器固定步长采样（见 SessionRoot.SERVER_TICK_DT）。
const BASE_SPEED := 4.0
const SPRINT_MULT := 1.6
## 默认每 tick 步长（秒），由调用方（服务器固定频率）传入，这里给个合理缺省。
const DEFAULT_TICK_DT := 1.0 / 30.0

## 校验 input_frame 合法性。返回 "" 表示通过，否则错误码。
## live：服务器维护的玩家状态 {"peer_id":int, "is_alive":bool, "position":Vector3}（不可信客户端字段）。
## seq_tracker：per-peer 严格递增序列（与攻击共用，防重放）。
## 注意：序列号消费（seq_tracker.accept）放在最后一步，仅在全部静态校验通过后才推进，
## 避免非法帧浪费序列号导致合法帧被判重放。
func validate_input_frame(command: Dictionary, live: Dictionary, server_rev: int, seq_tracker: CommandValidator.SequenceTracker) -> String:
	if not CommandValidator.validate_protocol(int(command.get("protocol_version", 0))):
		return NP.ERR_INVALID_PROTOCOL
	if not CommandValidator.validate_world_revision(int(command.get("world_revision", 0)), server_rev):
		return NP.ERR_INVALID_WORLD_REVISION
	if live == null or not bool(live.get("is_alive", false)):
		return NP.ERR_PLAYER_NOT_ALIVE
	var peer: int = int(live.get("peer_id", 0))
	if peer <= 0:
		return NP.ERR_PLAYER_NOT_READY
	# move 必须是两分量数值向量，分量在 [-1,1]，且模长 <= 1（客户端应已归一化）。
	var mv = command.get("move", null)
	if not (mv is Array) or mv.size() < 2:
		return NP.ERR_INVALID_STATE
	var mx: float = float(mv[0])
	var mz: float = float(mv[1])
	if not (mx >= -1.0 and mx <= 1.0 and mz >= -1.0 and mz <= 1.0):
		return NP.ERR_INVALID_STATE
	if mx * mx + mz * mz > 1.0 + 1e-6:
		return NP.ERR_INVALID_STATE
	# 静态校验全部通过后再消费序列号（防重放）。
	if not seq_tracker.accept(peer, int(command.get("sequence", 0))):
		return NP.ERR_INVALID_SEQUENCE
	return ""

## 从输入帧积分出新的权威位置（服务器计算，客户端位置不可信）。
## dir 取自 move 的 x/z，y 轴固定为 0（地面移动）；dt 为服务器固定步长。
func integrate_position(old_pos: Vector3, move_vec: Vector2, dt: float, speed: float) -> Vector3:
	if dt <= 0.0:
		return old_pos
	var dir := Vector3(move_vec.x, 0.0, move_vec.y)
	return old_pos + dir * speed * dt

## 处理一次 input_frame：校验 -> 积分 -> 产出 player_snapshot 事件。
## 返回 {"success":bool, "event":Dictionary, "error_code":String}。
func resolve_input_frame(command: Dictionary, live: Dictionary, server_rev: int, seq_tracker: CommandValidator.SequenceTracker, dt: float = DEFAULT_TICK_DT) -> Dictionary:
	var err: String = validate_input_frame(command, live, server_rev, seq_tracker)
	if err != "":
		return {"success": false, "event": {}, "error_code": err}
	var peer: int = int(live.get("peer_id", 0))
	var old_pos: Vector3 = live.get("position", Vector3.ZERO)
	var mv: Array = command.get("move", [0.0, 0.0])
	var move_vec := Vector2(float(mv[0]), float(mv[1]))
	var sprint: bool = bool(command.get("sprint", false))
	var speed: float = BASE_SPEED * (SPRINT_MULT if sprint else 1.0)
	var new_pos: Vector3 = integrate_position(old_pos, move_vec, dt, speed)
	var event := {
		"event": NP.EVT_PLAYER_SNAPSHOT,
		"peer_id": peer,
		"position": new_pos,
		"look_yaw": float(command.get("look_yaw", 0.0)),
		"look_pitch": float(command.get("look_pitch", 0.0)),
		"sequence": int(command.get("sequence", 0)),
	}
	return {"success": true, "event": event, "error_code": ""}
