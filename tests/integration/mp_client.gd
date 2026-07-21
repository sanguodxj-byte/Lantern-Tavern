extends Node
## 集成测试——客户端进程（真实 ENet）。
## 由 tools/run_integration_test.sh 在服务器就绪后启动：
##   godot --headless tests/integration/mp_client.tscn
## 流程：join(127.0.0.1) → 轮询 CONNECTED → send_spawn（携带单人存档摘要占位 + 稳定 guid）
## → 等待服务器下发 rpc_server_spawned（写入 reconnect_token）→ 写 client_ok.txt → 退出。
## 仅地牢范围：客户端进入地牢只继承各自存档（此处用空 save_state 占位，继承逻辑已由单测覆盖）。

const PORT := 17391
const ADDR := "127.0.0.1"

var _result_dir := ""

func _ready() -> void:
	await get_tree().process_frame
	_result_dir = OS.get_environment("ITEST_DIR")
	if _result_dir == "":
		_result_dir = "D:/123/Lantern Tavern/.tmp_ittest"
	var err := NetworkManager.join(ADDR, PORT)
	if err != OK:
		_write("client_ok.txt", "FAIL join err=%d" % err)
		get_tree().quit()
		return
	# 等待 ENet 连接完成（最多 ~7s）
	var connected := false
	for i in range(420):
		await get_tree().process_frame
		if _is_connected():
			connected = true
			break
	if not connected:
		_write("client_ok.txt", "FAIL not_connected")
		get_tree().quit()
		return
	# 连接已建立：确保 local_peer_id 已同步为 ENet 分配的真实 id
	NetworkManager.local_peer_id = NetworkManager.multiplayer.get_unique_id()
	# 上送生成请求（空 save_state 占位 + 稳定身份 guid）
	var save_state := {}
	NetworkManager.send_spawn(save_state, "client_guid_001")
	# 等待服务器确认（rpc_server_spawned 写入 reconnect_token，最多 ~7s）
	for i in range(420):
		await get_tree().process_frame
		if NetworkManager.reconnect_token != "":
			break
	if NetworkManager.reconnect_token != "":
		_write("client_ok.txt", "OK token=%s" % NetworkManager.reconnect_token)
	else:
		_write("client_ok.txt", "FAIL no_spawned")
	get_tree().quit()

func _is_connected() -> bool:
	var mp = NetworkManager.multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return false
	return mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _write(name: String, content: String) -> void:
	var f := FileAccess.open(_result_dir + "/" + name, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()
