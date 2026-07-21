extends Node
## 集成测试——服务器进程（真实 ENet）。
## 由 tools/run_integration_test.sh 以独立 Godot 进程启动：
##   godot --headless tests/integration/mp_host.tscn
## 流程：host() 开启 ENet 服务器 → 写 server_ready.txt 通知编排器可启动客户端 →
## 等待客户端连入并发起 spawn → 收到 EVT_PLAYER_SPAWNED 后校验权威 PlayerContext 已建立 → 写 server_ok.txt → 退出。
## 结果文件写入 ITEST_DIR（默认 project/.tmp_ittest）。

const PORT := 17391

var _result_dir := ""
var _got_spawn := false
var _spawn_peer := -1

func _ready() -> void:
	await get_tree().process_frame
	_result_dir = OS.get_environment("ITEST_DIR")
	if _result_dir == "":
		_result_dir = "D:/123/Lantern Tavern/.tmp_ittest"
	NetworkManager.event_dispatched.connect(_on_event)
	var err := NetworkManager.host(PORT)
	if err != OK:
		_write("server_ok.txt", "FAIL host err=%d" % err)
		get_tree().quit()
		return
	_write("server_ready.txt", "READY")
	# 等待客户端 spawn（最多 ~12s）
	for i in range(720):
		await get_tree().process_frame
		if _got_spawn:
			break
	if _got_spawn and NetworkManager.session != null \
			and NetworkManager.session.registry.has_peer(_spawn_peer) \
			and NetworkManager.session.registry.is_spawned(_spawn_peer):
		_write("server_ok.txt", "OK peer=%d" % _spawn_peer)
	else:
		var detail := "got=%s session=%s" % [_got_spawn, NetworkManager.session != null]
		if NetworkManager.session != null:
			detail += " peers=%s" % str(NetworkManager.session.registry.peer_ids())
		_write("server_ok.txt", "FAIL no_spawn %s" % detail)
	get_tree().quit()

func _on_event(ev: Dictionary) -> void:
	if ev.get("event", "") == "player_spawned":
		_got_spawn = true
		_spawn_peer = int(ev.get("peer_id", -1))

func _write(name: String, content: String) -> void:
	var f := FileAccess.open(_result_dir + "/" + name, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()
