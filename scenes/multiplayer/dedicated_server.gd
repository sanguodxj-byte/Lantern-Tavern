extends Node
## DedicatedServer —— 无头专用服务器入口（⑫）。
##
## 与 listen-server（房主也是玩家，MultiplayerSession.host_room）不同：专用服务器
## 【本身不是玩家】——不 spawn_self、不构建可见地牢/本地 Player、不渲染。它只：
##   1. 起 ENet 服务器（NetworkManager.host）；
##   2. 常驻 MultiplayerSceneBridge（服务器侧转发 avatar / player_snapshot 给客户端）；
##   3. 首个玩家 spawn 后触发出征（服务器权威 seed + 广播 dungeon_layout + 生成权威实体）；
##   4. 晚到玩家接入时追平（重播 layout + 实体 + 会话快照）；
##   5. 每帧驱动 NetworkManager.tick（服务器时钟 / 断线清理 / 快照节流 flush / 心跳超时）；
##   6. 全部玩家离开后可选自动关服（idle 空闲超时）。
##
## 权威地牢仅需 layout（seed→出生点）来放置权威实体；移动为纯数学积分
## （MovementAuthority.integrate_position）不依赖碰撞几何，故用 build_authority_only 跳过场景几何。
##
## 启动（headless）：
##   Godot --headless --path <proj> scenes/multiplayer/dedicated_server.tscn
## 参数（环境变量优先，其次命令行 --key=value）：
##   DS_PORT（默认 54321）/ DS_MAX_PLAYERS（默认 8）/ DS_IDLE_SHUTDOWN_SEC（默认 0=不自动关服）。
##
## 不声明 class_name：遵循本项目联机脚本约定；经场景挂载运行。

const DungeonSessionControllerClass := preload("res://scenes/multiplayer/dungeon_session_controller.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

const DEFAULT_PORT := 54321
const DEFAULT_MAX_PLAYERS := 8

var _bridge: Node = null
var _controller: Node = null
var _seed: int = 0
var _expedition_started: bool = false
var _port: int = DEFAULT_PORT
var _max_players: int = DEFAULT_MAX_PLAYERS
## 空闲（无玩家）自动关服秒数；0 表示永不自动关服。
var _idle_shutdown_sec: float = 0.0
var _idle_timer: float = 0.0
var _had_players: bool = false

func _ready() -> void:
	_parse_args()
	_ensure_bridge()
	var err := NetworkManager.host(_port, _max_players)
	if err != OK:
		push_error("[DedicatedServer] host failed on port %d (err=%d)" % [_port, err])
		_log("HOST FAILED port=%d err=%d" % [_port, err])
		return
	# 专用服务器本身不是玩家：不 spawn_self。
	if not NetworkManager.peer_authorized.is_connected(_on_peer_authorized):
		NetworkManager.peer_authorized.connect(_on_peer_authorized)
	if not NetworkManager.peer_left.is_connected(_on_peer_left):
		NetworkManager.peer_left.connect(_on_peer_left)
	_log("READY port=%d max_players=%d idle_shutdown=%.0fs" % [_port, _max_players, _idle_shutdown_sec])
	print("========================================")
	print(" Lantern Tavern — Dedicated Server")
	print("   listening on port %d (max %d players)" % [_port, _max_players])
	print("   waiting for players...")
	print("========================================")

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_host:
		return
	NetworkManager.tick(delta)
	_tick_idle_shutdown(delta)

# ---------------------------------------------------------------------------
# 玩家接入 / 离开
# ---------------------------------------------------------------------------

## 一个玩家权威 spawn 完成：首个玩家触发出征；后续（晚到）玩家追平真实场景。
func _on_peer_authorized(peer_id: int, _ctx) -> void:
	_had_players = true
	_idle_timer = 0.0
	if not _expedition_started:
		_start_expedition()
	else:
		_replay_for_late_join(peer_id)
	_log("PLAYER JOINED peer=%d total=%d" % [peer_id, NetworkManager.peer_count()])
	print("[DedicatedServer] player joined: peer=%d (total online=%d)" % [peer_id, _online_player_count()])

func _on_peer_left(peer_id: int) -> void:
	_log("PLAYER LEFT peer=%d remaining=%d" % [peer_id, _online_player_count()])
	print("[DedicatedServer] player left: peer=%d (remaining=%d)" % [peer_id, _online_player_count()])

# ---------------------------------------------------------------------------
# 出征（首个玩家触发）：服务器权威 seed → 广播 layout → 权威实体
# ---------------------------------------------------------------------------
func _start_expedition() -> void:
	var evt: Dictionary = NetworkManager.start_expedition()
	if evt.is_empty():
		push_warning("[DedicatedServer] start_expedition returned empty event")
		return
	_seed = int(evt.get("seed", 0))
	_controller = DungeonSessionControllerClass.new()
	_controller.name = "DungeonAuthority"
	add_child(_controller)
	# 仅权威地牢状态（无可见几何、无本地 Player）。
	_controller.build_authority_only(_seed)
	if _controller.has_method("spawn_server_entities"):
		_controller.spawn_server_entities()
	_expedition_started = true
	_log("EXPEDITION seed=%d fp=%s" % [_seed, _controller.layout_fingerprint()])
	print("[DedicatedServer] expedition started: seed=%d" % _seed)

## 晚到玩家追平：重播当前 layout + 全部权威实体 + 完整会话快照。
## （avatar 的重播由 MultiplayerSceneBridge._on_peer_authorized 处理，无需在此重复。）
func _replay_for_late_join(peer_id: int) -> void:
	var nm: Node = NetworkManager
	if nm.session != null and nm.session.dungeon_auth != null:
		nm._dispatch_event(nm.session.dungeon_auth.make_layout_event(), 0)
	if nm.has_method("rebroadcast_entities"):
		nm.rebroadcast_entities()
	if nm.session != null and nm.has_method("rpc_server_event"):
		var snap_evt := {
			"event": NP.EVT_SESSION_SNAPSHOT, "peer_id": peer_id,
			"snapshot": nm.session.build_session_snapshot(),
		}
		nm.rpc_server_event.rpc_id(peer_id, snap_evt)

# ---------------------------------------------------------------------------
# 空闲自动关服
# ---------------------------------------------------------------------------
func _tick_idle_shutdown(delta: float) -> void:
	if _idle_shutdown_sec <= 0.0:
		return
	if not _had_players:
		return  # 从未有玩家进来，不触发（避免刚启动就关）
	if _online_player_count() > 0:
		_idle_timer = 0.0
		return
	_idle_timer += delta
	if _idle_timer >= _idle_shutdown_sec:
		_log("IDLE SHUTDOWN after %.0fs with no players" % _idle_shutdown_sec)
		print("[DedicatedServer] idle shutdown (no players for %.0fs)" % _idle_shutdown_sec)
		NetworkManager.disconnect_session()
		get_tree().quit(0)

## 当前在线玩家数（专用服务器不含自身，故 peer_count 即玩家数）。
func _online_player_count() -> int:
	# peer_contexts 含服务器为每个连接的 peer 建的槽位；专用服务器自身不 spawn 玩家，
	# 但 host() 会 _register_peer(local_peer_id=1)。故减去服务器自身槽位。
	var c: int = NetworkManager.peer_count()
	var peers: Array = NetworkManager.connected_peers()
	if peers.has(NetworkManager.local_peer_id):
		c -= 1
	return max(c, 0)

# ---------------------------------------------------------------------------
# 桥接层 / 参数 / 日志
# ---------------------------------------------------------------------------

## 确保 MultiplayerSceneBridge 常驻（服务器侧转发 avatar / 快照给客户端）。
## 优先用场景内嵌节点；缺失则运行时补建。
func _ensure_bridge() -> void:
	_bridge = get_node_or_null("MultiplayerSceneBridge")
	if _bridge == null:
		_bridge = get_node_or_null("/root/MultiplayerSceneBridge")
	if _bridge == null:
		var scene: PackedScene = load("res://globals/multiplayer/multiplayer_scene_bridge.tscn")
		if scene != null:
			_bridge = scene.instantiate()
			_bridge.name = "MultiplayerSceneBridge"
			add_child(_bridge)

func _parse_args() -> void:
	_port = _read_int_arg("DS_PORT", "port", DEFAULT_PORT)
	_max_players = _read_int_arg("DS_MAX_PLAYERS", "max-players", DEFAULT_MAX_PLAYERS)
	_idle_shutdown_sec = float(_read_int_arg("DS_IDLE_SHUTDOWN_SEC", "idle-shutdown", 0))

## 读整型参数：环境变量优先，其次命令行 --key=value，最后默认值。
func _read_int_arg(env_name: String, cli_key: String, default_value: int) -> int:
	var env_val: String = OS.get_environment(env_name)
	if env_val != "" and env_val.is_valid_int():
		return int(env_val)
	for arg in OS.get_cmdline_user_args():
		var prefix := "--%s=" % cli_key
		if arg.begins_with(prefix):
			var v: String = arg.substr(prefix.length())
			if v.is_valid_int():
				return int(v)
	return default_value

## 结构化日志：写 DS_LOG_DIR/dedicated.log（集成测试用）+ stdout。
func _log(line: String) -> void:
	var dir: String = OS.get_environment("DS_LOG_DIR")
	if dir == "":
		return
	var f := FileAccess.open(dir + "/dedicated.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(dir + "/dedicated.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
