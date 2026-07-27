extends GdUnitTestSuite

const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_host_rejects_invalid_port_without_activation() -> void:
	var manager := NETWORK_MANAGER.new()
	var result := manager.host(0)
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_bool(manager.is_active).is_false()
	assert_int(manager.last_error).is_equal(ERR_INVALID_PARAMETER)
	manager.free()

func test_join_rejects_empty_address_without_activation() -> void:
	var manager := NETWORK_MANAGER.new()
	var result := manager.join("   ", 54321)
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_bool(manager.is_active).is_false()
	assert_int(manager.last_error).is_equal(ERR_INVALID_PARAMETER)
	manager.free()

func test_connected_peers_are_sorted_and_host_is_registered() -> void:
	var manager := NETWORK_MANAGER.new()
	manager._register_peer(7)
	manager._register_peer(2)
	manager._register_peer(1)
	assert_array(manager.connected_peers()).is_equal([1, 2, 7])
	assert_int(manager.peer_count()).is_equal(3)
	manager.free()

func test_disconnect_clears_session_metadata_and_contexts() -> void:
	var manager := NETWORK_MANAGER.new()
	manager._register_peer(1)
	manager.session_address = "127.0.0.1"
	manager.session_port = 54321
	manager.is_active = true
	manager.is_host = true
	manager.local_peer_id = 1
	manager.disconnect_session()
	assert_bool(manager.is_active).is_false()
	assert_bool(manager.is_host).is_false()
	assert_int(manager.local_peer_id).is_equal(0)
	assert_str(manager.session_address).is_empty()
	assert_int(manager.session_port).is_equal(0)
	assert_int(manager.peer_count()).is_equal(0)
	manager.free()

# ============================================================================
# 性能优化：高频事件走 unreliable 通道，关键事件走 reliable 通道
# ============================================================================

func test_is_high_frequency_event_identifies_snapshots() -> void:
	# player_snapshot / entity_snapshot 是高频低重要性事件 → true
	var manager := NETWORK_MANAGER.new()
	assert_bool(manager._is_high_frequency_event(NP.EVT_PLAYER_SNAPSHOT)).is_true()
	assert_bool(manager._is_high_frequency_event(NP.EVT_ENTITY_SNAPSHOT)).is_true()
	manager.free()

func test_is_high_frequency_event_rejects_critical_events() -> void:
	# 关键事件（生成/销毁/布局/重连）必须走 reliable → false
	var manager := NETWORK_MANAGER.new()
	assert_bool(manager._is_high_frequency_event(NP.EVT_PLAYER_SPAWNED)).is_false()
	assert_bool(manager._is_high_frequency_event(NP.EVT_PLAYER_DESPAWNED)).is_false()
	assert_bool(manager._is_high_frequency_event(NP.EVT_ENTITY_SPAWNED)).is_false()
	assert_bool(manager._is_high_frequency_event(NP.EVT_ENTITY_DESPAWNED)).is_false()
	manager.free()

func test_is_high_frequency_event_rejects_unknown() -> void:
	# 未知事件类型 → false（保守走 reliable）
	var manager := NETWORK_MANAGER.new()
	assert_bool(manager._is_high_frequency_event("unknown_event")).is_false()
	assert_bool(manager._is_high_frequency_event("")).is_false()
	manager.free()

func test_dispatch_event_emits_signal_without_rpc() -> void:
	# 无真实 peer 时（单进程/单测），_dispatch_event 仅 emit 信号，不走 RPC
	var manager := NETWORK_MANAGER.new()
	var received: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): received.append(ev))
	# session 为 null → can_rpc 为 false → 仅 emit
	manager._dispatch_event({"event": NP.EVT_PLAYER_SNAPSHOT, "peer_id": 1}, 1)
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["event"]).is_equal(NP.EVT_PLAYER_SNAPSHOT)
	manager.free()

func test_dispatch_event_high_freq_does_not_crash_without_session() -> void:
	# 无 session 时分发高频事件不应崩溃（仅 emit 信号）
	var manager := NETWORK_MANAGER.new()
	var received: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): received.append(ev))
	manager._dispatch_event({"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": 5}, 0)
	assert_int(received.size()).is_equal(1)
	manager.free()
