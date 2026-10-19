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

## P1-2（0304 审查）：连接失败路径幂等释放 SessionRoot 与缓冲，防旧会话污染下次 join。
func test_connection_failure_releases_session_and_buffers() -> void:
	var manager := NETWORK_MANAGER.new()
	add_child(manager)
	manager._ensure_session()
	manager.session.init_server()
	manager.is_active = true
	manager.is_host = false
	manager.local_peer_id = 7
	manager.session_address = "127.0.0.1"
	manager.session_port = 54321
	manager.reconnect_token = "tok_abc"
	manager._snapshot_buffer["k"] = {"x": 1}
	manager._on_connection_failed()
	assert_object(manager.session).is_null()
	assert_bool(manager.is_active).is_false()
	assert_str(manager.reconnect_token).is_empty()
	assert_int(manager._snapshot_buffer.size()).is_equal(0)
	assert_int(manager.peer_count()).is_equal(0)
	# 下一次 _ensure_session() 返回全新实例（旧房间状态不泄漏）
	manager._ensure_session()
	var fresh: Node = manager.session
	assert_object(fresh).is_not_null()
	manager.end_session()
	manager.free()

## P1-2（0304 审查）：服务器掉线路径同样释放 SessionRoot 与缓冲。
func test_server_disconnected_releases_session() -> void:
	var manager := NETWORK_MANAGER.new()
	add_child(manager)
	manager._ensure_session()
	manager.session.init_server()
	manager.is_active = true
	manager.is_host = false
	manager.local_peer_id = 7
	manager.reconnect_token = "tok_xyz"
	manager._entity_update_buffer["k"] = {"e": 1}
	manager._on_server_disconnected()
	assert_object(manager.session).is_null()
	assert_bool(manager.is_active).is_false()
	assert_str(manager.reconnect_token).is_empty()
	assert_int(manager._entity_update_buffer.size()).is_equal(0)
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

# ============================================================================
# B1（架构审查 P0）：disconnect_session 必须彻底结束会话并释放全部状态，
# re-host 不得把旧房间的 registry/world_revision/entities 泄漏进下一房间。
# ============================================================================

var _gs: Node = null

func before_test() -> void:
	_gs = get_node_or_null("/root/GameState")

func after_test() -> void:
	# 共享 autoload 单例：复位到文档默认（Callable()），避免跨测试悬挂会话闭包。
	if _gs != null and is_instance_valid(_gs):
		_gs.player_resolver = Callable()
	_gs = null

## 复刻 host() 的会话创建语义（headless 测试不绑定真实 ENet 端口）：
##   入树（复刻生产 autoload 环境，供 _ensure_session 的 /root/GameState 查找）+ 建会话 + init_server。
func _host_session(manager: NETWORK_MANAGER) -> void:
	if not manager.is_inside_tree():
		add_child(manager)
	manager._ensure_session()
	manager.session.init_server()
	manager.is_active = true
	manager.is_host = true

func test_disconnect_frees_session_and_clears_buffers_and_resolver() -> void:
	var manager: NETWORK_MANAGER = NETWORK_MANAGER.new()
	_host_session(manager)
	manager.session.handle_spawn_request(1, {}, "player_b1")
	manager.session.set_entity(1001, {"kind": "enemy", "current_life": 10, "max_life": 10})
	manager._snapshot_buffer[1] = {"event": NP.EVT_PLAYER_SNAPSHOT, "peer_id": 1}
	manager._entity_update_buffer[1001] = {"event": NP.EVT_ENTITY_SNAPSHOT, "entity_id": 1001}
	manager._input_tick_accum = 0.5
	manager.disconnect_session()
	# 会话必须被置 null（SessionRoot 已释放/排队释放，不再被本管理器持有）。
	assert_object(manager.session).is_null()
	# 快照/实体缓冲与 tick 累积器必须清空。
	assert_bool(manager._snapshot_buffer.is_empty()).is_true()
	assert_bool(manager._entity_update_buffer.is_empty()).is_true()
	assert_float(manager._input_tick_accum).is_equal(0.0)
	# GameState.player_resolver 必须解除（不再引用旧会话）。
	if _gs != null:
		assert_bool(not (_gs.player_resolver as Callable).is_valid()) \
			.override_failure_message("disconnect_session 必须解除 GameState.player_resolver").is_true()
	manager.free()

func test_rehost_creates_fresh_session_without_old_state() -> void:
	var manager: NETWORK_MANAGER = NETWORK_MANAGER.new()
	_host_session(manager)
	manager.session.handle_spawn_request(1, {}, "player_b1")
	manager.session.set_entity(1001, {"kind": "enemy", "current_life": 10, "max_life": 10})
	manager.session._bump_world("dungeon")
	var old_id: int = manager.session.get_instance_id()
	manager.disconnect_session()
	assert_object(manager.session).is_null()
	# re-host：_ensure_session 必须创建全新 SessionRoot 实例。
	_host_session(manager)
	assert_bool(manager.session.get_instance_id() != old_id) \
		.override_failure_message("re-host 必须创建全新 SessionRoot，而非复用旧会话").is_true()
	# 旧房间的实体注册表 / 玩家 / 世界状态不得泄漏（新会话是全新 WorldState：revision 0 + 默认 space）。
	assert_bool(manager.session.all_entities().is_empty()) \
		.override_failure_message("新会话不得携带旧房间实体").is_true()
	assert_int(manager.session.registry.peer_count()) \
		.override_failure_message("新会话不得携带旧房间玩家").is_equal(0)
	assert_int(manager.session.world.world_revision) \
		.override_failure_message("新会话不得携带旧房间 world_revision").is_equal(0)
	assert_str(manager.session.world.current_space) \
		.override_failure_message("新会话世界状态须为全新默认（tavern）").is_equal("tavern")
	manager.free()
