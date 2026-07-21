extends GdUnitTestSuite

const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

var _captured: Array = []
var _received: bool = false
var _room_ended: bool = false

func _capture(e: Dictionary) -> void:
	_captured.append(e)

func _mark_received(_e: Dictionary) -> void:
	_received = true

func _mark_room_ended() -> void:
	_room_ended = true

## 服务器生成：创建权威 PlayerContext、签发稳定重连 token、并继承单人存档摘要。
func test_server_spawn_creates_context_and_token_and_inherits_save() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	var save_state := {"materials": {"iron": 3}}
	var res: Dictionary = nm._server_handle_spawn(2, save_state, "guid_2")
	assert_object(res["ctx"]).is_not_null()
	assert_str(res["token"]).is_not_empty()
	assert_bool(nm.session.registry.has_peer(2)).is_true()
	# 继承存档：服务器把客户端单人存档摘要应用到联机上下文（地牢继承存档状态）
	assert_int(nm.session.registry.get_context(2).inventory.materials.get("iron", 0)).is_equal(3)
	nm.free()

## 命令路由：服务器权威处理 input_frame，产生 player_snapshot 事件并积分出权威位置。
func test_server_command_routing_dispatches_event_and_integrates_movement() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	var res_spawn: Dictionary = nm._server_handle_spawn(2, {}, "g2")
	assert_object(res_spawn["ctx"]).is_not_null()
	nm.event_dispatched.connect(_capture)
	var cmd := {
		"type": NP.CMD_INPUT,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": nm.session.world.world_revision,
		"sequence": 1,
		"move": [1.0, 0.0],
		"sprint": false,
		"look_yaw": 0.0,
	}
	var res: Dictionary = nm._server_handle_command(2, cmd)
	assert_bool(res["success"]).is_true()
	assert_int(_captured.size()).is_equal(1)
	assert_str(_captured[0]["event"]).is_equal(NP.EVT_PLAYER_SNAPSHOT)
	# 权威位置由服务器积分（绝不信任客户端自报坐标）
	var pos: Vector3 = nm.session._live_state[2]["position"]
	assert_float(pos.x).is_greater(0.0)
	nm.free()

## 重连：断线进入 GRACE，持 token 重连恢复 ONLINE 并下发会话快照。
func test_reconnect_restores_online_state_and_sends_snapshot() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm._server_handle_spawn(3, {}, "g3")
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	assert_str(nm.session.connection_auth.get_status(3)).is_equal("grace")
	nm.event_dispatched.connect(_capture)
	var res: Dictionary = nm._server_handle_resume(3, dis["token"])
	assert_bool(res["success"]).is_true()
	assert_str(nm.session.connection_auth.get_status(3)).is_equal("online")
	var found_snap := false
	for e in _captured:
		if e.get("event", "") == NP.EVT_SESSION_SNAPSHOT:
			found_snap = true
	assert_bool(found_snap).is_true()
	nm.free()

## 真实代码路径证明：经 NetworkManager._server_handle_resume（即客户端 RPC 最终调用的服务器入口），
## 用【新】peer_id + 稳定 guid 完成重连，旧 peer_id 的全部权威状态（inventory/位置）接管到新 peer_id。
func test_reconnect_with_new_peer_id_through_network_manager() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	# 旧 peer=3，带稳定 guid 与可见 inventory（模拟出征拾取）。
	nm._server_handle_spawn(3, {"materials": {"iron_ore": 2}}, "g3")
	nm.session.set_player_position(3, Vector3(4, 0, 5))
	var dis: Dictionary = nm.session.handle_peer_disconnected(3, nm.session.current_time)
	assert_str(nm.session.connection_auth.get_status(3)).is_equal("grace")
	nm.event_dispatched.connect(_capture)
	# 重连分配新 peer_id=9（模拟 ENet 重连），携带同一 guid。
	var res: Dictionary = nm._server_handle_resume(9, dis["token"], "g3")
	assert_bool(res["success"]).is_true()
	assert_str(nm.session.connection_auth.get_status(9)).is_equal("online")
	# 旧 peer=3 已清空，新 peer=9 接管同一 ctx 与状态（不丢、不串号）。
	assert_bool(nm.session.registry.has_peer(3)).is_false()
	assert_bool(nm.session.registry.has_peer(9)).is_true()
	assert_int(nm.session.registry.get_context(9).inventory.materials.get("iron_ore", 0)).is_equal(2)
	var pos = nm.session._live_state[9]["position"]
	assert_float(pos.x).is_equal(4.0)
	assert_float(pos.z).is_equal(5.0)
	# 会话快照下发给新 peer_id。
	var found_snap := false
	for e in _captured:
		if e.get("event", "") == NP.EVT_SESSION_SNAPSHOT:
			found_snap = true
	assert_bool(found_snap).is_true()
	nm.free()

## 重连 token 过期（超过 60s 保留期）应被拒绝。
func test_expired_grace_token_rejected() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm._server_handle_spawn(4, {}, "g4")
	var dis: Dictionary = nm.session.handle_peer_disconnected(4, nm.session.current_time)
	nm.session.current_time = 100.0  # 远超 GRACE_PERIOD(60s)
	var res: Dictionary = nm._server_handle_resume(4, dis["token"])
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal(NP.ERR_RECONNECT_TOKEN_EXPIRED)
	nm.free()

## 房主（peer 1）断线应触发房间结束。
func test_host_disconnect_ends_room() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm._server_handle_spawn(1, {}, "host")
	assert_bool(nm.session.connection_auth.should_end_room_on_disconnect(1)).is_true()
	nm.room_ended.connect(_mark_room_ended)
	nm._server_on_peer_disconnected(1)
	assert_bool(_room_ended).is_true()
	nm.free()

## 服务器 tick 推进时间并清理 GRACE 超时的玩家。
func test_tick_cleans_expired_grace() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm._server_handle_spawn(5, {}, "g5")
	nm.session.handle_peer_disconnected(5, nm.session.current_time)  # t=0 进入 GRACE
	assert_bool(nm.session.registry.has_peer(5)).is_true()
	nm.session.current_time = 100.0  # 超过 GRACE_PERIOD
	nm.tick(0.0)
	assert_bool(nm.session.registry.has_peer(5)).is_false()
	nm.free()

## 客户端应用服务器下发的会话快照（重连/落后追平）。
func test_client_applies_session_snapshot() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_client()
	nm.event_received.connect(_mark_received)
	var snap := {"world_revision": 7, "current_space": "dungeon", "run_seed": 123}
	nm._apply_event({"event": NP.EVT_SESSION_SNAPSHOT, "snapshot": snap})
	assert_int(nm.session.world.world_revision).is_equal(7)
	assert_str(nm.session.world.current_space).is_equal("dungeon")
	assert_bool(_received).is_true()
	nm.free()

## 命令在 GRACE 保留期（非 CMD_RESUME）被拒绝。
func test_command_rejected_during_grace() -> void:
	var nm := NETWORK_MANAGER.new()
	nm._ensure_session()
	nm.session.init_server()
	nm._server_handle_spawn(6, {}, "g6")
	nm.session.handle_peer_disconnected(6, nm.session.current_time)  # 进入 GRACE
	var cmd := {
		"type": NP.CMD_INPUT,
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": nm.session.world.world_revision,
		"sequence": 1,
		"move": [1.0, 0.0],
	}
	var res: Dictionary = nm._server_handle_command(6, cmd)
	assert_bool(res["success"]).is_false()
	assert_str(res["error_code"]).is_equal(NP.ERR_INVALID_STATE)
	nm.free()
