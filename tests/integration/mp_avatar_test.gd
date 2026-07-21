extends Node3D
## 双进程集成测试场景（共享：host 与 client 加载同一场景，靠 ITEST_ROLE 区分）。
## 验证：① 服务器经桥接层 rpc_spawn_avatar 真实生成远端 avatar 并复制到客户端；
##       ② 客户端收到 rpc_snapshot 后，avatar 按插值平滑移动。
## 仅地牢联机范围，不触碰单人流程。
##
## 说明：本 Godot 4.7 构建的 MultiplayerSpawner 因 SceneTree 无 .multiplayer 属性导致
## 内部 _setup_spawn 注册失败、复制不可靠，故桥接层改用显式 RPC 完成复制，见
## multiplayer_scene_bridge.gd 头部说明。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const NetworkManagerClass := preload("res://globals/core/network_manager.gd")

## 候选端口列表（按序尝试，避开本环境被占用/保留的端口，如 14567 被某进程占住）。
## 服务器取第一个可绑定的端口；客户端按同序连接，命中即停。
const CANDIDATE_PORTS := [28999, 29001, 29234, 29567, 14567]
const ROLE_HOST := "host"
const ROLE_CLIENT := "client"

var _role: String = ""
var _itdir: String = ""
var _bridge: Node = null
var _client_peer: int = 0

func _ready() -> void:
	_role = OS.get_environment("ITEST_ROLE")
	_itdir = OS.get_environment("ITEST_DIR")
	if _itdir == "":
		_itdir = "D:/123/Lantern Tavern/.tmp_ittest"
	# 以脚本方式挂载桥接场景（不依赖 .tscn 的 instance 元数据，避免 headless 下
	# “modified from inside an instance, but it has vanished” 的脆弱实例加载问题）。
	_bridge = get_node_or_null("MultiplayerSceneBridge")
	if _bridge == null:
		var b: Node = preload("res://globals/multiplayer/multiplayer_scene_bridge.tscn").instantiate()
		b.name = "MultiplayerSceneBridge"
		add_child(b)
		_bridge = b
	if _role == ROLE_HOST:
		_run_host()
	else:
		_run_client()

func _run_host() -> void:
	var bound := false
	for p in CANDIDATE_PORTS:
		var err := NetworkManager.host(p)
		if err == OK:
			_write("server_port.txt", str(p))
			bound = true
			break
		else:
			_write("host_fail_%d.txt" % p, "host err %d" % err)
	if not bound:
		_write("host_fail.txt", "all candidate ports failed")
		return
	_write("server_ready.txt", "ready")
	NetworkManager.peer_authorized.connect(_on_host_peer_authorized)

func _on_host_peer_authorized(peer_id: int, _ctx) -> void:
	# 远端 avatar 由桥接层（_on_peer_authorized）统一生成 + 广播；此处记录真实 peer_id 供诊断，
	# 并给客户端一个【服务器自身】的远端 avatar（peer 1）来显示，从而验证客户端复制路径。
	# （按架构，客户端不显示自己的 avatar——它用真实 Player 控制器；所以用它“看到服务器”来验证复制。）
	print("[TEST] host peer_authorized peer_id=", peer_id, " local_peer_id=", NetworkManager.local_peer_id)
	_write("server_peer.txt", str(peer_id))
	_client_peer = peer_id
	_write("server_ok.txt", "OK")
	# 让客户端显示服务器的远端 avatar（peer 1 = 房主），证明客户端复制 + 插值路径。
	if _bridge != null and _bridge.has_method("rpc_spawn_avatar"):
		_bridge.rpc_spawn_avatar.rpc(1, Vector3.ZERO)
	# 服务器侧驱动：沿 +X 推进“服务器 avatar”位置并广播快照（每步间隔若干帧）。
	for i in range(1, 16):
		if _bridge != null and _bridge.has_method("rpc_snapshot"):
			_bridge.rpc_snapshot.rpc(1, Vector3(float(i) * 0.12, 0.0, 0.0), 0.0)
		for k in range(5):
			await get_tree().process_frame

func _run_client() -> void:
	var connected := false
	for p in CANDIDATE_PORTS:
		NetworkManager.join("127.0.0.1", p)
		for i in range(300):
			await get_tree().process_frame
			if NetworkManager.local_peer_id != 0:
				connected = true
				break
		if connected:
			_write("client_port.txt", str(p))
			break
		# 该端口无服务器：断开后试下一个候选端口。
		NetworkManager.disconnect_session()
		await get_tree().process_frame
	if not connected:
		_write("client_ok.txt", "FAIL connect (no server on candidate ports)")
		return
	NetworkManager.send_spawn({}, "client_guid_001")
	var my_peer: int = NetworkManager.local_peer_id
	print("[TEST] client my_peer=", my_peer)
	# 客户端应显示【服务器(peer 1)】的远端 avatar（自己不显示，用真实 Player 控制器）。
	var remote_peer: int = 1
	var avatar_ok := false
	for i in range(600):
		await get_tree().process_frame
		if NetworkManager.reconnect_token != "" and _bridge.get_avatar(remote_peer) != null:
			avatar_ok = true
			break
	if not avatar_ok:
		_write("client_ok.txt", "FAIL avatar (token=%s av=%s)" % [NetworkManager.reconnect_token, _bridge.get_avatar(remote_peer) != null])
		return
	_write("client_avatar_ok.txt", "OK remote_peer=%d" % remote_peer)
	# 等待客户端 avatar 插值跟随服务器广播的快照（position.x 显著 > 0）。
	var moved := false
	for i in range(240):
		await get_tree().process_frame
		var av: Node3D = _bridge.get_avatar(remote_peer)
		var px: float = av.global_position.x if av != null else 0.0
		if px > 0.3:
			moved = true
			break
	var av: Node3D = _bridge.get_avatar(remote_peer)
	var px: float = av.global_position.x if av != null else 0.0
	if moved:
		_write("client_move_ok.txt", "OK x=%.3f" % px)
		_write("client_ok.txt", "OK avatar+move x=%.3f" % px)
	else:
		_write("client_move_fail.txt", "x=%.3f" % px)
		_write("client_ok.txt", "FAIL move x=%.3f" % px)

func _write(name: String, content: String) -> void:
	var f := FileAccess.open(_itdir + "/" + name, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()
