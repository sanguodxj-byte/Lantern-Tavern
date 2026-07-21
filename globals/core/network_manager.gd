extends Node
## NetworkManager（autoload singleton，按 project.godot 注册名访问；不声明 class_name 避免与 autoload 同名冲突）

## 联机传输（SceneMultiplayer + ENet）+ 权威编排接入层。
## 服务器：拥有 SessionRoot 权威实例，RPC 接收客户端意图 → 调用 SessionRoot → 广播结果事件。
## 客户端：RPC 接收服务器事件 → 应用到本地 SessionRoot（仅缓存/插值，不作权威计算）。
##
## 设计基线见 docs/25-联机总体方案.md §3.2 / §6.2 / §13 / §19。
## 联机范围仅限地牢（出征）：玩家进入地牢只继承各自单人存档（save_state），见 SessionRoot.handle_spawn_request。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const SessionRootClass := preload("res://globals/multiplayer/session_root.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal lobby_updated()
## 服务器成功处理一条命令/事件并准备下发（headless 单测可监听以断言分发）。
signal event_dispatched(event: Dictionary)
## 客户端收到服务器事件（用于本地插值/UI；headless 单测可监听）。
signal event_received(event: Dictionary)
## 房主断线导致的房间结束（§13.1）。
signal room_ended()
## 服务器成功为一个 peer 建立权威 PlayerContext（spawn 完成）。表现层（MultiplayerSceneBridge）
## 监听此信号以生成该 peer 的远端 avatar 节点（MultiplayerSpawner 复制给客户端）。
signal peer_authorized(peer_id: int, context)

const DEFAULT_PORT: int = 54321
const MAX_PLAYERS: int = 4
const HOST_PEER_ID: int = 1

var is_active: bool = false
var is_host: bool = false
var local_peer_id: int = 0
var session_address: String = ""
var session_port: int = 0
var last_error: Error = OK

## 服务器权威会话（纯逻辑编排器）。单测可直接调用其方法；运行时由 host()/join() 初始化。
var session: SessionRootClass = null

## 客户端侧缓存的重连令牌（spawn 时由服务器下发）。
var reconnect_token: String = ""
## 客户端侧缓存的稳定身份（spawn 时由本端选定并上送，重连时随之回传供服务器锚定）。
var reconnect_player_guid: String = ""
var reconnect_peer_id: int = 0

## 旧版 peer 注册表（兼容 connected_peers()/peer_count() 等既有 API 与 lobby UI）。
var peer_contexts: Dictionary = {}

# ---------------------------------------------------------------------------
# 性能（⑪）：快照广播节流 + 网络统计
# ---------------------------------------------------------------------------
## 服务器广播 player_snapshot 的目标频率（Hz）。原始实现每收到一帧输入就广播一次
## （≈60Hz/人），对 2~4 人联机是带宽大户；限频到 30Hz 足以支撑直接应用式表现，
## 且输入积分仍按原始频率进行（权威位置精度不变，仅网络下发降频）。
const SNAPSHOT_BROADCAST_HZ := 30.0
## 每个 peer 最新待广播的 player_snapshot（key=peer_id），flush 时取最新一帧下发。
var _snapshot_buffer: Dictionary = {}
## 实体状态更新（高频 HP/位置）缓冲：按 entity_id 合并，仅保留最新一帧，在 tick 中按
## SNAPSHOT_BROADCAST_HZ 节流下发（reliable），消除战斗中无节制的即时广播。
var _entity_update_buffer: Dictionary = {}
var _snapshot_accum: float = 0.0
## 网络统计：{事件类型: RPC 下发次数}（仅真实联机时累计，用于压测观测）。
var _net_stats: Dictionary = {}
var _netstat_timer: float = 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------------------
# 会话生命周期（服务器/客户端）
# ---------------------------------------------------------------------------

## 确保 session 实例存在（headless 单测与运行时都可用；不依赖 _ready 是否在树中）。
func _ensure_session() -> void:
	if session == null:
		session = SessionRootClass.new()
		# world_revision 闭环：SessionRoot 在权威世界状态变更时经此把 EVT_WORLD_REVISION_CHANGED 下发到所有客户端。
		session.broadcast_event = _dispatch_world_event

## 服务器主导出：开启 ENet 服务器 + 初始化权威 SessionRoot。
func host(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> Error:
	if is_active:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535 or max_players < 1:
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		last_error = err
		return err
	if is_instance_valid(multiplayer):
		multiplayer.multiplayer_peer = peer
	is_active = true
	is_host = true
	local_peer_id = multiplayer.get_unique_id()
	session_address = "0.0.0.0"
	session_port = port
	last_error = OK
	_ensure_session()
	session.init_server()
	_register_peer(local_peer_id)
	lobby_updated.emit()
	return OK

## 客户端导出：连接 ENet 服务器 + 初始化本地（非权威）SessionRoot。
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if is_active:
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty() or port < 1 or port > 65535:
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = err
		return err
	if is_instance_valid(multiplayer):
		multiplayer.multiplayer_peer = peer
	is_active = true
	is_host = false
	local_peer_id = 0
	session_address = address.strip_edges()
	session_port = port
	last_error = OK
	_ensure_session()
	session.init_client()
	return OK

func disconnect_session() -> void:
	if is_instance_valid(multiplayer) and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	last_error = OK
	reconnect_token = ""
	reconnect_peer_id = 0
	peer_contexts.clear()
	lobby_updated.emit()

# ---------------------------------------------------------------------------
# Peer 注册表（兼容既有 API）
# ---------------------------------------------------------------------------

func register_peer_context(peer_id: int, ctx: PlayerContext) -> void:
	peer_contexts[peer_id] = ctx

func get_peer_context(peer_id: int) -> PlayerContext:
	return peer_contexts.get(peer_id, null)

func connected_peers() -> Array:
	var peers: Array[int] = []
	for peer_id in peer_contexts.keys():
		peers.append(int(peer_id))
	peers.sort()
	return peers

func peer_count() -> int:
	return peer_contexts.size()

func is_client() -> bool:
	return is_active and not is_host

func _register_peer(peer_id: int) -> void:
	if not peer_contexts.has(peer_id):
		peer_contexts[peer_id] = null

# ---------------------------------------------------------------------------
# ENet 信号回调（真实连接生命周期）
# ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	_register_peer(peer_id)
	peer_joined.emit(peer_id)
	lobby_updated.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_contexts.has(peer_id):
		peer_contexts.erase(peer_id)
		peer_left.emit(peer_id)
		lobby_updated.emit()
	# 服务器侧权威清理（断线保留 / 重连令牌 / 广播 despawned / 房主断线结束房间）
	_server_on_peer_disconnected(peer_id)

func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	connected_to_server.emit()

func _on_connection_failed() -> void:
	if is_instance_valid(multiplayer) and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	connection_failed.emit()

func _on_server_disconnected() -> void:
	is_active = false
	is_host = false
	local_peer_id = 0
	session_address = ""
	session_port = 0
	peer_contexts.clear()
	server_disconnected.emit()
	lobby_updated.emit()

# ---------------------------------------------------------------------------
# 服务器侧权威接缝（headless 单测可直接调用，绕过 RPC）
# ---------------------------------------------------------------------------

## 服务器处理一次玩家生成请求：创建权威 PlayerContext、签发稳定重连 token、广播 spawned。
## 返回 {"ctx":PlayerContext, "token":String, "peer_id":int}；非服务器或失败返回 {"ctx":null,...}。
func _server_handle_spawn(peer_id: int, save_state: Dictionary = {}, player_guid: String = "") -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {"ctx": null, "token": "", "peer_id": peer_id}
	var ctx: PlayerContextClass = session.handle_spawn_request(peer_id, save_state, player_guid)
	if ctx == null:
		return {"ctx": null, "token": "", "peer_id": peer_id}
	var token: String = session.connection_auth.issue_token(peer_id, session.current_time)
	var evt := {"event": NP.EVT_PLAYER_SPAWNED, "peer_id": peer_id}
	_dispatch_event(evt, peer_id)
	peer_authorized.emit(peer_id, ctx)
	return {"ctx": ctx, "token": token, "peer_id": peer_id}

## 服务器处理一条客户端命令：经 SessionRoot 权威裁决，成功后广播事件。
## 返回 SessionRoot.on_command 的结果字典。
func _server_handle_command(peer_id: int, command: Dictionary) -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {"success": false, "event": {}, "error_code": NP.ERR_PERMISSION_DENIED}
	var res: Dictionary = session.on_command(peer_id, command)
	if bool(res.get("success", false)) and res.has("event") and not res["event"].is_empty():
		_buffer_or_dispatch(res["event"])
	# 附带事件（如战斗致敌人扣血的 entity_snapshot / 死亡的 entity_despawned / 掉落的 entity_spawned）。
	if res.has("extra_events"):
		for ev in (res["extra_events"] as Array):
			if ev is Dictionary and not (ev as Dictionary).is_empty():
				_buffer_or_dispatch(ev)
	return res

## 区分“可节流快照”与“需即时下发的事件”：
##   * player_snapshot 在真实联机下缓冲，由 tick 按 SNAPSHOT_BROADCAST_HZ 统一下发（降带宽）；
##   * 其余事件（战斗/掉落/布局/重连快照等）保持即时下发，保证响应性；
##   * 单进程（无真实 peer）时快照也即时下发，避免破坏 headless 单测的信号监听。
func _buffer_or_dispatch(event: Dictionary) -> void:
	if event.get("event", "") == NP.EVT_PLAYER_SNAPSHOT and _has_real_peers():
		var pid: int = int(event.get("peer_id", 0))
		_snapshot_buffer[pid] = event
	else:
		_dispatch_event(event, 0)

func _has_real_peers() -> bool:
	return session != null and session.is_server and _can_rpc()

## 服务器处理客户端重连请求（CMD_RESUME）：校验 token（按 guid 锚定旧条目），
## 成功后把旧 peer_id 的全部状态接管到新 peer_id，并下发会话快照。
func _server_handle_resume(peer_id: int, token: String, player_guid: String = "") -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {"success": false, "event": {}, "error_code": NP.ERR_PERMISSION_DENIED}
	var command := {
		"type": NP.CMD_RESUME,
		"token": token,
		"player_guid": player_guid,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": session.world.world_revision,
	}
	var res: Dictionary = session.on_command(peer_id, command)
	if bool(res.get("success", false)) and res.has("event") and not res["event"].is_empty():
		_dispatch_event(res["event"], peer_id)
	return res

## 服务器收到心跳：刷新该 peer 最后活跃时间。
func _server_handle_heartbeat(peer_id: int) -> void:
	_ensure_session()
	if session.is_server:
		session.heartbeat(peer_id, session.current_time)

## 服务器处理客户端主动离开：立即清理。
func _server_handle_leave(peer_id: int) -> void:
	_ensure_session()
	if not session.is_server:
		return
	session.handle_peer_left(peer_id)
	_dispatch_event({"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}, peer_id)

## 服务器侧断线流程（ENet 掉线 / 心跳超时共用）：进入 GRACE、广播 despawned、房主断线结束房间。
func _server_on_peer_disconnected(peer_id: int) -> void:
	_ensure_session()
	if not session.is_server:
		return
	var res: Dictionary = session.handle_peer_disconnected(peer_id, session.current_time)
	if bool(res.get("was_tracked", false)):
		_dispatch_event({"event": NP.EVT_PLAYER_DESPAWNED, "peer_id": peer_id}, peer_id)
		if session.connection_auth.should_end_room_on_disconnect(peer_id):
			room_ended.emit()

## 广播一个服务器事件到所有客户端（有真实 peer 时走 RPC，否则仅本地发射 signal 供单测）。
func _dispatch_event(event: Dictionary, _source_peer: int) -> void:
	event_dispatched.emit(event)
	var can_rpc := session != null and session.is_server and _can_rpc()
	if can_rpc:
		var kind: String = event.get("event", event.get("type", "?"))
		_net_stats[kind] = int(_net_stats.get(kind, 0)) + 1
		rpc_server_event.rpc(event)

## 返回累计网络下发统计（{事件类型: 次数}），供 PerfMonitor HUD / 压测观测。
func get_net_stats() -> Dictionary:
	return _net_stats.duplicate()

func _can_rpc() -> bool:
	return is_instance_valid(multiplayer) and multiplayer.multiplayer_peer != null

## world_revision 闭环：SessionRoot 经 broadcast_event 钩子调用本方法，把 EVT_WORLD_REVISION_CHANGED
## 下发到所有客户端（含 RPC）。仅服务器需要广播；客户端（session.is_server=false）忽略，避免误 RPC 上送。
func _dispatch_world_event(event: Dictionary) -> void:
	if session == null or not session.is_server:
		return
	_dispatch_event(event, 0)

# ---------------------------------------------------------------------------
# 每帧推进（由地牢场景 _physics_process 调用）：服务器时钟 + 断线清理 + 心跳超时
# ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	if session == null or not session.is_server:
		return
	session.current_time += delta
	_flush_snapshots(delta)
	for pid in session.connection_auth.online_peer_ids():
		if session.connection_auth.check_timeout(pid, session.current_time):
			_server_on_peer_disconnected(pid)
	session.tick_connections(session.current_time)
	# 压测观测：每 5 秒服务器时间打印一次累计网络下发统计。
	_netstat_timer += delta
	if _netstat_timer >= 5.0:
		_netstat_timer = 0.0
		if not _net_stats.is_empty():
			print("[NETSTATS] ", _net_stats)

## 按 SNAPSHOT_BROADCAST_HZ 把缓冲的 player_snapshot 下发（最新一帧/peer）。
## 同时 emit event_dispatched（host 侧桥接层经此收到自身快照）与 RPC（远端客户端）。
func _flush_snapshots(delta: float) -> void:
	if _snapshot_buffer.is_empty() and _entity_update_buffer.is_empty():
		return
	_snapshot_accum += delta
	if _snapshot_accum < (1.0 / SNAPSHOT_BROADCAST_HZ):
		return
	_snapshot_accum = 0.0
	for pid in _snapshot_buffer.keys():
		var ev: Dictionary = _snapshot_buffer[pid]
		_snapshot_buffer.erase(pid)
		_dispatch_event(ev, int(ev.get("peer_id", 0)))
	# 实体状态更新：按 entity_id 合并后仅下发最新一帧（可靠，节流到 30Hz）。
	for eid in _entity_update_buffer.keys():
		var ev: Dictionary = _entity_update_buffer[eid]
		_entity_update_buffer.erase(eid)
		_dispatch_event(ev, 0)

# ---------------------------------------------------------------------------
# 客户端侧：接收服务器事件并应用
# ---------------------------------------------------------------------------

## 客户端应用一条服务器事件（headless 单测可直接调用）。
## 仅做本地缓存/插值数据落地；不作权威计算（权威在服务器）。
func _apply_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	_ensure_session()
	if not session.is_server and event.get("event", "") == NP.EVT_SESSION_SNAPSHOT:
		session.apply_session_snapshot(event.get("snapshot", {}))
	event_received.emit(event)

# ---------------------------------------------------------------------------
# 客户端 → 服务器 RPC（意图上送）
# ---------------------------------------------------------------------------

func send_spawn(save_state: Dictionary, player_guid: String) -> void:
	if not is_client():
		return
	reconnect_player_guid = player_guid
	rpc_client_spawn.rpc_id(HOST_PEER_ID, local_peer_id, save_state, player_guid)

func send_command(command: Dictionary) -> void:
	if not is_client():
		return
	rpc_client_command.rpc_id(HOST_PEER_ID, local_peer_id, command)

## 客户端/房主统一上送命令入口：
##   客户端 → RPC 上送服务器（send_command）；
##   房主（listen-server）自身也是玩家，直接走服务器权威路径，不经 RPC 回路。
## 返回 SessionRoot.on_command 的结果（房主路径）或空字典（客户端路径，结果经事件下发）。
func submit_command(command: Dictionary) -> Dictionary:
	if is_host:
		return _server_handle_command(local_peer_id, command)
	if is_client():
		send_command(command)
	return {}

## 房主为【自身 peer】建立权威 PlayerContext（联机地牢中房主也是玩家）。
## 等价于客户端的 send_spawn，但走服务器本地权威路径（不依赖 RPC）。
## 返回 {"ctx":PlayerContext, "token":String, "peer_id":int}。
func spawn_self(save_state: Dictionary = {}, player_guid: String = "") -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {"ctx": null, "token": "", "peer_id": local_peer_id}
	reconnect_player_guid = player_guid
	return _server_handle_spawn(local_peer_id, save_state, player_guid)

## 房主开启出征：服务器决定权威 seed，广播 dungeon_layout 给所有客户端。
## 客户端据此用相同 seed 确定性重建真实地牢。返回 layout 事件字典。
func start_expedition(seed_hint: int = -1) -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {}
	var evt: Dictionary = session.dungeon_auth.start_expedition(seed_hint)
	_dispatch_event(evt, 0)
	return evt

## 服务器权威生成一个实体（敌人/宝箱/门/掉落）并广播 entity_spawned 给所有客户端。
## data 建议字段：kind/position/current_life/max_life/label（由表现层 multiplayer_entity 消费）。
## 返回 SessionRoot.set_entity 结果（含 event）；非服务器返回空字典。
func server_spawn_entity(entity_id: int, data: Dictionary) -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {}
	var res: Dictionary = session.set_entity(entity_id, data)
	if bool(res.get("success", false)) and res.has("event") and not res["event"].is_empty():
		_dispatch_event(res["event"], 0)
	return res

## 服务器权威更新一个实体的部分字段（HP/位置...）并广播 entity_snapshot。
## 高频状态更新（战斗中频繁）在有真实 peer 时入 30Hz 节流缓冲（按 entity_id 合并，仅发最新一帧），
## 避免无节制的即时 reliable 广播推高消息率；单进程/无真实 peer 时仍即时下发，保持 headless 单测同步性。
func server_update_entity(entity_id: int, patch: Dictionary) -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {}
	var res: Dictionary = session.update_entity(entity_id, patch)
	if bool(res.get("success", false)) and res.has("event") and not res["event"].is_empty():
		var ev: Dictionary = res["event"]
		if _has_real_peers() and ev.get("event", "") == NP.EVT_ENTITY_SNAPSHOT:
			_entity_update_buffer[int(entity_id)] = ev
		else:
			_dispatch_event(ev, 0)
	return res

## 服务器权威移除一个实体并广播 entity_despawned。
func server_despawn_entity(entity_id: int) -> Dictionary:
	_ensure_session()
	if not session.is_server:
		return {}
	var res: Dictionary = session.remove_entity(entity_id)
	if bool(res.get("success", false)) and res.has("event") and not res["event"].is_empty():
		_dispatch_event(res["event"], 0)
	return res

## 实体对账（Phase 10 生产化）：用 EntitySyncAuthority.build_delta 计算把某客户端
## 【已知实体集 known】追平到服务器当前权威实体集所需的最小复制事件集并下发。
##   - known 为空 → 全量 entity_spawned（等价旧 rebroadcast_entities，向后兼容）。
##   - known 非空（重连/晚到快照携带该客户端已知实体）→ 只补 新增/变化，并 despawn 陈旧实体
##     （朴素重播无法清理客户端仍持有的陈旧实体，这是本方法相对 rebroadcast 的关键修复）。
## 返回下发的复制事件列表（测试断言用）。despawn 广播全体是安全的：build_delta 只在
## 「known 有而 server 无」时产 despawn，即该实体在服务器权威侧确已不存在→全体清理正确且幂等。
func reconcile_entities(known: Dictionary = {}) -> Array:
	_ensure_session()
	if not session.is_server:
		return []
	var events: Array = session.reconcile_entities(known)
	for ev in events:
		_dispatch_event(ev, 0)
	return events

## 向所有已连接客户端重播当前全部实体（entity_spawned），供晚到/重连客户端追平。
## 幂等：表现层 bridge 对已存在实体改走更新，不产生重复节点。
## Phase 10：委托 reconcile_entities({})（known 为空即全量 spawned），使 build_delta 成为唯一实体对账真相源。
func rebroadcast_entities() -> void:
	reconcile_entities({})

func send_resume() -> void:
	if not is_client() or local_peer_id <= 0 or reconnect_token == "":
		return
	rpc_client_resume.rpc_id(HOST_PEER_ID, local_peer_id, reconnect_token, reconnect_player_guid)

func send_heartbeat() -> void:
	if not is_client():
		return
	rpc_client_heartbeat.rpc_id(HOST_PEER_ID, local_peer_id)

func send_leave() -> void:
	if not is_client():
		return
	rpc_client_leave.rpc_id(HOST_PEER_ID, local_peer_id)

# ---------------------------------------------------------------------------
# RPC 定义
# ---------------------------------------------------------------------------

## 客户端 → 服务器：请求生成玩家（带入单人存档摘要 save_state 与稳定身份 player_guid）。
@rpc("any_peer", "call_remote", "reliable")
func rpc_client_spawn(peer_id: int, save_state: Dictionary, player_guid: String) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return  # 安全：peer 只能为自己生成
	var res: Dictionary = _server_handle_spawn(peer_id, save_state, player_guid)
	if res.get("ctx") != null:
		rpc_server_spawned.rpc_id(peer_id, peer_id, String(res.get("token", "")))

## 客户端 → 服务器：上送一条意图命令。
@rpc("any_peer", "call_remote", "reliable")
func rpc_client_command(peer_id: int, command: Dictionary) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_server_handle_command(peer_id, command)

## 客户端 → 服务器：重连请求（携带 spawn 时收到的重连 token + 稳定身份 guid）。
@rpc("any_peer", "call_remote", "reliable")
func rpc_client_resume(peer_id: int, token: String, player_guid: String = "") -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_server_handle_resume(peer_id, token, player_guid)

## 客户端 → 服务器：心跳。
@rpc("any_peer", "call_remote", "unreliable")
func rpc_client_heartbeat(peer_id: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_server_handle_heartbeat(peer_id)

## 客户端 → 服务器：主动离开（不再重连）。
@rpc("any_peer", "call_remote", "reliable")
func rpc_client_leave(peer_id: int) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_server_handle_leave(peer_id)

## 服务器 → 客户端：下发事件（玩家快照/交互结果/战斗结算/地牢布局/断线快照等）。
@rpc("authority", "call_remote", "reliable")
func rpc_server_event(event: Dictionary) -> void:
	_apply_event(event)

## 服务器 → 客户端：玩家生成确认 + 重连令牌（客户端据此缓存 token 供后续重连）。
@rpc("authority", "call_remote", "reliable")
func rpc_server_spawned(peer_id: int, token: String) -> void:
	reconnect_peer_id = peer_id
	reconnect_token = token
