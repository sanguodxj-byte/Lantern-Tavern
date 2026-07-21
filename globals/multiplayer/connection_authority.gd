extends RefCounted
## ConnectionAuthority（docs/25 §13）—— 服务器权威的 peer 连接生命周期管理。
##
## 纯逻辑、无场景树依赖：由 SessionRoot / NetworkManager 在收到 SceneMultiplayer 的
## peer_connected / peer_disconnected / 心跳超时 事件时调用。本模块只裁决「状态与重连令牌」，
## 不持有玩家具体数据（PlayerContext 由 SessionRoot 维护，断线保留期仍保留）。
##
## 每 peer 状态机：
##   ONLINE  --(断线 / 心跳超时)--> GRACE（保留私有状态、发重连 token、广播 player_despawned）
##   GRACE   --(重连且 token 有效)--> ONLINE（恢复、重置序列、下发 session_snapshot）
##   GRACE   --(超过保留期 / 主动离开)--> 已清理（注销 PlayerContext）
##
## 关键参数（§13.1）：断线保留 = 重连 token 有效期 = 60s；心跳超时 = 15s（服务器判定掉线）。
## §14.2：peer_id 每次连接会变，重连身份用外部传入的 player_guid 锚定，不用 peer_id 作永久 ID。

const NP := preload("res://globals/multiplayer/network_protocol.gd")

const STATUS_ONLINE := "online"
const STATUS_GRACE := "grace"
const STATUS_LEFT := "left"

const GRACE_PERIOD := 60.0          # 断线保留 + 重连 token 有效期（秒）
const HEARTBEAT_TIMEOUT := 15.0     # 服务器判定 peer 掉线的心跳超时（秒）
const SECRET := "lt_conn_v1"        # 重连 token 派生盐（服务器私有，仅用于派生，不传输）

var _peers: Dictionary = {}         # peer_id -> {status, disconnect_time, token, token_expiry, last_seen, player_guid}
var _guid_to_peer: Dictionary = {}  # player_guid -> 当前 peer_id（§14.2 稳定身份索引，重连时按 guid 反查旧条目）
var host_peer_id: int = 1           # 房主（§13.1：房主断线第一版直接结束房间）

func _init() -> void:
	_peers = {}
	_guid_to_peer = {}

## 稳定身份：peer_id 每次连接会变（§14.2），这里用外部传入的 player_guid 作为重连身份锚。
func register_online(peer_id: int, player_guid: String, now: float) -> void:
	_peers[peer_id] = {
		"status": STATUS_ONLINE,
		"disconnect_time": -1.0,
		"token": "",
		"token_expiry": -1.0,
		"last_seen": now,
		"player_guid": player_guid,
	}
	if player_guid != "":
		_guid_to_peer[player_guid] = peer_id

## 是否已存在该 peer 的 GRACE 条目（用于判断连接事件是否可能是「重连」）。
func has_grace_entry(peer_id: int) -> bool:
	return _peers.has(peer_id) and _peers[peer_id]["status"] == STATUS_GRACE

func get_status(peer_id: int) -> String:
	if not _peers.has(peer_id):
		return ""
	return _peers[peer_id]["status"]

func is_online(peer_id: int) -> bool:
	return get_status(peer_id) == STATUS_ONLINE

## 当前所有 ONLINE（已连接、未断线）的 peer_id 列表。供服务器在 tick 中扫描心跳超时。
func online_peer_ids() -> Array:
	var out: Array = []
	for pid in _peers.keys():
		if _peers[pid]["status"] == STATUS_ONLINE:
			out.append(int(pid))
	return out

func get_player_guid(peer_id: int) -> String:
	if not _peers.has(peer_id):
		return ""
	return _peers[peer_id]["player_guid"]

## 在玩家上线（spawn）时预签发重连 token 并存储，使断线/重连期间 token 保持稳定。
## 客户端在 spawn 时即收到该 token；后续断线重连沿用同一 token（on_disconnect 复用已存 token，
## 不再重新派生），避免「spawn 时给的 token」与「断线时生成的 token」不一致导致重连失败。
## 返回签发的 token（peer 未登记则返回 ""）。
func issue_token(peer_id: int, now: float) -> String:
	if not _peers.has(peer_id):
		return ""
	var p: Dictionary = _peers[peer_id]
	p["token"] = generate_token(peer_id, now)
	p["token_expiry"] = now + GRACE_PERIOD
	return p["token"]

## 断线（peer_disconnected 事件 / 心跳超时）：进入 GRACE，发重连 token，保留状态。
## 返回 {token, was_tracked}。peer 未登记则 was_tracked=false。
## token 优先复用 spawn 时已签发的稳定 token（若已签发），否则当场派生。
func on_disconnect(peer_id: int, now: float) -> Dictionary:
	if not _peers.has(peer_id):
		return {"token": "", "was_tracked": false}
	var p: Dictionary = _peers[peer_id]
	p["status"] = STATUS_GRACE
	p["disconnect_time"] = now
	if String(p["token"]) == "":
		p["token"] = generate_token(peer_id, now)
	p["token_expiry"] = now + GRACE_PERIOD
	p["last_seen"] = now
	return {"token": p["token"], "was_tracked": true}

## 主动离开（不再重连）：直接标记 LEFT（调用方应立即注销 PlayerContext）。
func on_leave(peer_id: int) -> bool:
	if not _peers.has(peer_id):
		return false
	_peers[peer_id]["status"] = STATUS_LEFT
	return true

## 心跳（客户端定期 ping）：刷新 last_seen。
func touch(peer_id: int, now: float) -> void:
	if _peers.has(peer_id):
		_peers[peer_id]["last_seen"] = now

## 心跳超时检测：若 ONLINE 且 now - last_seen > HEARTBEAT_TIMEOUT → 视为掉线。
## 返回是否触发了断线（调用方应据其结果走 on_disconnect 流程）。
func check_timeout(peer_id: int, now: float) -> bool:
	if not is_online(peer_id):
		return false
	return (now - float(_peers[peer_id]["last_seen"])) > HEARTBEAT_TIMEOUT

## 校验重连 token（§13.2）。返回 {ok, reason, player_guid}。
func validate_reconnect(peer_id: int, token: String, now: float) -> Dictionary:
	if not _peers.has(peer_id):
		return {"ok": false, "reason": NP.ERR_RECONNECT_PEER_UNKNOWN, "player_guid": ""}
	var p: Dictionary = _peers[peer_id]
	if p["status"] != STATUS_GRACE:
		return {"ok": false, "reason": NP.ERR_RECONNECT_TOKEN_INVALID, "player_guid": ""}
	if now > float(p["token_expiry"]):
		return {"ok": false, "reason": NP.ERR_RECONNECT_TOKEN_EXPIRED, "player_guid": ""}
	if token != String(p["token"]):
		return {"ok": false, "reason": NP.ERR_RECONNECT_TOKEN_INVALID, "player_guid": ""}
	return {"ok": true, "reason": "", "player_guid": String(p["player_guid"])}

## 完成重连：校验通过后把 peer 从 GRACE 恢复为 ONLINE，刷新 last_seen。
## 返回 {ok, reason, player_guid}（失败原因同 validate_reconnect）。
func resume(peer_id: int, token: String, now: float) -> Dictionary:
	var res: Dictionary = validate_reconnect(peer_id, token, now)
	if not res["ok"]:
		return res
	_peers[peer_id]["status"] = STATUS_ONLINE
	_peers[peer_id]["last_seen"] = now
	return res

## 按稳定身份 player_guid 反查处于 GRACE 的条目，返回其【旧 peer_id】；无则 0。
func find_grace_peer_by_guid(player_guid: String) -> int:
	if player_guid == "" or not _guid_to_peer.has(player_guid):
		return 0
	var pid: int = int(_guid_to_peer[player_guid])
	if not _peers.has(pid):
		return 0
	if _peers[pid]["status"] != STATUS_GRACE:
		return 0
	return pid

## 按重连 token 反查 GRACE 条目（token 全局唯一，作 guid 缺失时的兜底锚定，
## 也保证即便客户端遗忘了 guid，仅凭 token 也能定位断线保留条目）。
func find_grace_peer_by_token(token: String) -> int:
	for pid in _peers.keys():
		var p: Dictionary = _peers[pid]
		if p["status"] == STATUS_GRACE and String(p["token"]) == token:
			return int(pid)
	return 0

## 按 guid/token 校验重连（§14.2：身份锚定不依赖会变的 peer_id）。
## 返回 {ok, reason, player_guid, peer_id}（peer_id 为旧 peer_id，迁移目标）。
func validate_reconnect_by_guid(player_guid: String, token: String, now: float) -> Dictionary:
	var old_id: int = find_grace_peer_by_guid(player_guid)
	if old_id == 0:
		old_id = find_grace_peer_by_token(token)
	if old_id == 0:
		return {"ok": false, "reason": NP.ERR_RECONNECT_PEER_UNKNOWN, "player_guid": player_guid, "peer_id": 0}
	var p: Dictionary = _peers[old_id]
	if now > float(p["token_expiry"]):
		return {"ok": false, "reason": NP.ERR_RECONNECT_TOKEN_EXPIRED, "player_guid": player_guid, "peer_id": old_id}
	if token != String(p["token"]):
		return {"ok": false, "reason": NP.ERR_RECONNECT_TOKEN_INVALID, "player_guid": player_guid, "peer_id": old_id}
	return {"ok": true, "reason": "", "player_guid": player_guid, "peer_id": old_id}

## 重连接管：把 GRACE 条目从旧 peer_id 迁移到新 peer_id（ENet 重连分配新 peer_id）。
## 迁移后旧键删除、新键承载同一状态，_guid_to_peer 同步指向新 peer_id。
func migrate_peer(old_peer_id: int, new_peer_id: int) -> void:
	if old_peer_id == new_peer_id:
		return
	if not _peers.has(old_peer_id):
		return
	var entry: Dictionary = _peers[old_peer_id]
	_peers.erase(old_peer_id)
	_peers[new_peer_id] = entry
	var guid: String = String(entry.get("player_guid", ""))
	if guid != "":
		_guid_to_peer[guid] = new_peer_id

## 推进时间：返回所有 GRACE 超时（now - disconnect_time > GRACE_PERIOD）应被清理的 peer_id 列表。
func collect_expired_grace(now: float) -> Array:
	var out: Array = []
	for pid in _peers.keys():
		var p: Dictionary = _peers[pid]
		if p["status"] == STATUS_GRACE and (now - float(p["disconnect_time"])) > GRACE_PERIOD:
			out.append(int(pid))
	return out

## 房主断线（§13.1）：第一版直接结束房间。返回是否应结束房间。
func should_end_room_on_disconnect(peer_id: int) -> bool:
	return peer_id == host_peer_id

## 派生重连 token（确定性、服务器私有盐）。测试可用同一输入复现以断言。
func generate_token(peer_id: int, salt: float) -> String:
	return ("%d|%f|%s" % [peer_id, salt, SECRET]).sha256_text()
