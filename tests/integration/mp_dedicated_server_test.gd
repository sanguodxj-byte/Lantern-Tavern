extends Node3D
## ⑫ Dedicated Server 集成测试（真实 ENet，双进程）。
##
## 与 listen-server（mp_dungeon_test）不同：本测试 SERVER 角色加载的是真正的
##【无头专用服务器】scenes/multiplayer/dedicated_server.tscn —— 它本身【不是玩家】，
## 不 spawn 本地 Player、不渲染、不构建可见几何；只负责 host + 常驻桥接层 + 首个玩家
## 接入时触发出征 + 每帧 tick 服务器时钟/快照节流/断线清理。
##
## 验证范围（⑫ 垂直切片）：
##   1. 专用服务器启动、监听、无报错（自身非玩家）；
##   2. 真实客户端 join → send_spawn → 收到重连 token；
##   3. 客户端用服务器权威 seed 确定性重建地牢（收到 dungeon_layout，指纹非 none）；
##   4. 服务器权威敌人实体经桥接层复制到客户端（entity_spawned → 可见节点）；
##   5. 客户端输入 → CMD_INPUT → 服务器积分权威位置 → player_snapshot 回传 →
##      本地 Player 被服务器驱动移动（证明专用服务器的“输入→权威→广播”闭环成立）。
##
## 角色：
##   ITEST_ROLE=server  → 实例化 DedicatedServer（专用服务器进程）
##   ITEST_ROLE=client  → 连专用服务器、spawn、验证上述切片

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const DedicatedServerScene := preload("res://scenes/multiplayer/dedicated_server.tscn")

const ROLE_SERVER := "server"
const ROLE_CLIENT := "client"
const MOVE_THRESHOLD := 0.5
const CANDIDATE_PORTS := [30021, 30023, 30027, 30101, 30137]

var _role: String = ""
var _itdir: String = ""
var _bridge: Node = null
var _controller: Node = null
var _local_player: Node = null
var _driver: Node = null
var _seed: int = 0
var _ds: Node = null
var _snapshot_count: int = 0
var _host_peer: int = 1
var _server_port: int = 0

func _ready() -> void:
	_role = OS.get_environment("ITEST_ROLE")
	_itdir = OS.get_environment("ITEST_DIR")
	if _itdir == "":
		_itdir = "D:/123/Lantern Tavern/.tmp_itest_dedsrv"
	_bridge = get_node_or_null("MultiplayerSceneBridge")
	if _bridge == null:
		var b: Node = preload("res://globals/multiplayer/multiplayer_scene_bridge.tscn").instantiate()
		b.name = "MultiplayerSceneBridge"
		add_child(b)
		_bridge = b
	if _role == ROLE_SERVER:
		_run_server()
	else:
		_run_client()

# ---------------------------------------------------------------------------
# Server 角色：装载真正的无头专用服务器
# ---------------------------------------------------------------------------
func _run_server() -> void:
	_ds = DedicatedServerScene.instantiate()
	_ds.name = "DedicatedServer"
	add_child(_ds)
	# 等待专用服务器 host 完成并写出 READY（_ready 内 host 失败后不会写 ready）。
	for i in range(300):
		await get_tree().process_frame
		if NetworkManager.is_host:
			break
	if not NetworkManager.is_host:
		_write("ds_ready.txt", "FAIL host not active")
		return
	_server_port = NetworkManager.session_port
	_write("ds_ready.txt", "OK port=%d" % _server_port)
	# 等待首个客户端接入 → 出征；把服务器权威 seed + 地牢指纹落地，供客户端跨进程比对。
	for i in range(1200):
		await get_tree().process_frame
		if _ds != null and _ds.get("_expedition_started") and _ds.get("_controller") != null:
			var c: Node = _ds.get("_controller")
			if c != null and c.layout_fingerprint() != "none":
				_write("ds_seed.txt", "%d|%s" % [int(_ds.get("_seed")), c.layout_fingerprint()])
				break
	# 持续运行直到客户端完成（客户端写 client_ok.txt / client_fail.txt 后退出），
	# 或超时（约 120s）保底。专用服务器须比客户端活得更久，否则客户端连接会掉。
	for i in range(7200):
		await get_tree().process_frame
		if _read("client_ok.txt") != "" or _read("client_fail.txt") != "":
			break
	_write("ds_done.txt", "server ran to completion")

# ---------------------------------------------------------------------------
# Client 角色：连专用服务器、spawn、验证切片
# ---------------------------------------------------------------------------
func _run_client() -> void:
	var port_str: String = OS.get_environment("DS_PORT")
	_server_port = int(port_str) if port_str.is_valid_int() else CANDIDATE_PORTS[0]
	var connected := false
	for p in CANDIDATE_PORTS:
		var try_port: int = _server_port if p == CANDIDATE_PORTS[0] else p
		NetworkManager.join("127.0.0.1", try_port)
		for i in range(300):
			await get_tree().process_frame
			if NetworkManager.local_peer_id != 0:
				connected = true
				break
		if connected:
			break
		NetworkManager.disconnect_session()
		await get_tree().process_frame
	if not connected:
		_write("client_ok.txt", "FAIL connect (no dedicated server on port %d)" % _server_port)
		return
	NetworkManager.event_received.connect(_on_client_event)
	NetworkManager.send_spawn({}, "dedsrv_client_guid")
	# 等待：重连 token + 收到 dungeon_layout 并构建完地牢 + 出现权威实体。
	var ready := false
	for i in range(900):
		await get_tree().process_frame
		if NetworkManager.reconnect_token != "" and _local_player != null \
				and _bridge.get_entity_node(1001) != null and _bridge.get_entity_node(1002) != null:
			ready = true
			break
	if not ready:
		_write("client_ok.txt", "FAIL setup (token=%s player=%s)" % [
			NetworkManager.reconnect_token, _local_player != null])
		return
	_write("client_ready.txt", "OK token received, dungeon built")
	# 断言 3：地牢指纹与专用服务器权威布局一致（跨进程确定性重建同一张图）。
	var ds_line: String = _read("ds_seed.txt")
	var client_line: String = "%d|%s" % [_seed, _controller.layout_fingerprint()]
	var fp_match: bool = (ds_line != "" and _controller != null and _controller.layout_fingerprint() != "none"
		and _host_dedicated_fingerprint() == _controller.layout_fingerprint())
	_write("client_dungeon.txt", "ds=%s client=%s fp_match=%s" % [ds_line, client_line, fp_match])
	# 断言 4：权威敌人实体已复制到客户端。
	var ent_ok := _bridge.get_entity_node(1001) != null and _bridge.get_entity_node(1002) != null
	var ent_count: int = _bridge.entity_count() if _bridge.has_method("entity_count") else 0
	_write("client_entities.txt", "ent_ok=%s count=%d" % [ent_ok, ent_count])
	# 断言 5：客户端持续向 +X 移动（override_move），服务器积分并经 player_snapshot 回传驱动本地 Player。
	# 注意：不因为“已移动”就提前 break——须持续计数玩家快照，证明专用服务器的下发循环稳定。
	var local_moved := false
	var moved_x: float = 0.0
	if _driver != null and is_instance_valid(_driver):
		_driver.override_move = Vector2(1.0, 0.0)
	for i in range(400):
		await get_tree().process_frame
		moved_x = _local_player.global_position.x if _local_player != null else 0.0
		if moved_x > MOVE_THRESHOLD:
			local_moved = true
	if _driver != null:
		_driver.override_move = Vector2.ZERO
	# 断言 5b：专用服务器把 player_snapshot 下发给了客户端（闭环核心证据）。
	var snapshot_ok := _snapshot_count > 5
	var ok_all := ent_ok and fp_match and local_moved and snapshot_ok
	_write("client_move.txt", "local_x=%.3f moved=%s snapshots=%d" % [moved_x, local_moved, _snapshot_count])
	if ok_all:
		_write("client_ok.txt", "OK local_x=%.3f fp_match=%s entities=%d snapshots=%d" % [
			moved_x, fp_match, ent_count, _snapshot_count])
	else:
		_write("client_fail.txt", "FAIL local_moved=%s fp_match=%s ent_ok=%s snapshots=%d" % [
			local_moved, fp_match, ent_ok, _snapshot_count])
		_write("client_ok.txt", "FAIL local_moved=%s fp_match=%s ent_ok=%s snapshots=%d" % [
			local_moved, fp_match, ent_ok, _snapshot_count])

func _on_client_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var kind: String = event.get("event", event.get("type", ""))
	if kind == NP.EVT_PLAYER_SNAPSHOT:
		_snapshot_count += 1
	if kind != NP.EVT_DUNGEON_LAYOUT:
		return
	if _local_player != null:
		return  # 已构建，忽略重复 layout
	_seed = int(event.get("seed", 0))
	_controller = preload("res://scenes/multiplayer/dungeon_session_controller.gd").new()
	_controller.name = "DungeonSession"
	add_child(_controller)
	_local_player = _controller.build_and_enter(_seed)
	_driver = _local_player.get_node_or_null("ClientCommandDriver")

## ds_seed.txt 格式 "seed|width|height|gridhash|spawncell"，提取首个 '|' 之后的完整指纹。
func _host_dedicated_fingerprint() -> String:
	var dl: String = _read("ds_seed.txt")
	if dl == "":
		return ""
	var parts: PackedStringArray = dl.split("|", true, 1)
	return parts[1] if parts.size() > 1 else ""

func _write(name: String, content: String) -> void:
	var f := FileAccess.open(_itdir + "/" + name, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _read(name: String) -> String:
	var f := FileAccess.open(_itdir + "/" + name, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
