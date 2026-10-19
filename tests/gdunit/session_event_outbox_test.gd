extends GdUnitTestSuite

## A1（架构审查 P0）接缝测试：SessionRoot.session_event 必须被 NetworkManager 接线为
## 会话内异步事件的单一出口（含节流/RPC 下发）。
##
## 覆盖（通过公开行为断言，不读源码字符串）：
##   * broadcast_player_combat_state / tick_enemy_combat → NetworkManager.event_dispatched 恰好一次；
##   * session_event 直发事件（despawned / command_rejected）到达 event_dispatched 恰好一次；
##   * 命令返回路径已下发的事件（despawned / session_snapshot / spell_resolved）不得重复下发
##     ——同一逻辑事件必须恰好一次（回归门禁：一旦 NetworkManager 重复调用 dispatch 即失败）。
##
## 测试共享 autoload 单例（/root/GameState.player_resolver），before_test/after_test 恢复现场。

const NETWORK_MANAGER := preload("res://globals/core/network_manager.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PC := preload("res://globals/core/player_context.gd")

var _gs: Node = null

func before_test() -> void:
	_gs = get_node_or_null("/root/GameState")

func after_test() -> void:
	# 共享 autoload 单例：复位到文档默认（Callable()），避免跨测试悬挂会话闭包。
	if _gs != null and is_instance_valid(_gs):
		_gs.player_resolver = Callable()
	_gs = null

## 构造一个「已 host 语义」的 NetworkManager：入树 + _ensure_session 建会话 + init_server。
## 入树以复刻生产 autoload 环境（_ensure_session 需 get_node("/root/GameState")）。
## headless 无真实 peer → _dispatch_event 仅 emit event_dispatched 信号（单测观测通道）。
func _make_host_manager() -> NETWORK_MANAGER:
	var manager: NETWORK_MANAGER = NETWORK_MANAGER.new()
	add_child(manager)
	manager._ensure_session()
	manager.session.init_server()
	return manager

func _count_kind(dispatched: Array, kind: String) -> int:
	var n := 0
	for ev in dispatched:
		if String(ev.get("event", ev.get("type", ""))) == kind:
			n += 1
	return n

# ---------------------------------------------------------------------------
# 异步事件（仅经 session_event 出口）必须到达 event_dispatched —— 修复前 RED
# ---------------------------------------------------------------------------

func test_broadcast_player_combat_state_dispatched_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager.session.broadcast_player_combat_state(1)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_COMBAT_STATE)) \
		.override_failure_message("broadcast_player_combat_state 必须经 session_event 出口下发恰好一次").is_equal(1)

func test_tick_enemy_combat_dispatches_combat_state_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager.session.set_player_position(1, Vector3.ZERO)
	manager.session.set_entity(1001, {"kind": "enemy", "current_life": 100, "max_life": 100, "position": Vector3.ZERO, "next_attack_at": 0.0})
	var attacks: int = manager.session.tick_enemy_combat(1.0)
	assert_int(attacks).is_equal(1)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_COMBAT_STATE)) \
		.override_failure_message("tick_enemy_combat 造成的战斗状态事件必须下发恰好一次").is_equal(1)

func test_session_event_despawned_on_leave_dispatched_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager.session.handle_peer_left(1)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_DESPAWNED)) \
		.override_failure_message("handle_peer_left 的 despawned 必须经 session_event 出口下发恰好一次").is_equal(1)

func test_session_event_despawned_on_disconnect_dispatched_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager.session.handle_peer_disconnected(1, 0.0)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_DESPAWNED)) \
		.override_failure_message("handle_peer_disconnected 的 despawned 必须经 session_event 出口下发恰好一次").is_equal(1)

func test_session_event_command_rejected_dispatched_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	# 非法协议版本 → on_command 走 _reject → session_event(EVT_COMMAND_REJECTED) → 必须下发一次
	manager.session.on_command(1, {"type": NP.CMD_INTERACT, "protocol_version": 99})
	assert_int(_count_kind(dispatched, NP.EVT_COMMAND_REJECTED)) \
		.override_failure_message("命令拒绝事件必须经 session_event 出口下发恰好一次").is_equal(1)

# ---------------------------------------------------------------------------
# 回归门禁：命令返回路径也下发的事件不得重复（同一逻辑事件恰好一次）
# ---------------------------------------------------------------------------

func test_server_handle_leave_dispatches_despawned_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager._server_handle_leave(1)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_DESPAWNED)) \
		.override_failure_message("_server_handle_leave 的 despawned 不得重复下发").is_equal(1)

func test_server_on_peer_disconnected_dispatches_despawned_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	manager._server_on_peer_disconnected(1)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_DESPAWNED)) \
		.override_failure_message("_server_on_peer_disconnected 的 despawned 不得重复下发").is_equal(1)

func test_server_handle_resume_dispatches_snapshot_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	var token: String = String(manager.session.handle_peer_disconnected(1, 0.0).get("token", ""))
	manager.session.current_time = 5.0
	manager._server_handle_resume(1, token, "peer_1")
	assert_int(_count_kind(dispatched, NP.EVT_SESSION_SNAPSHOT)) \
		.override_failure_message("_server_handle_resume 的 session_snapshot 不得重复下发").is_equal(1)

func test_server_handle_command_spell_resolved_dispatched_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	_spawn_caster(manager.session)
	_bind_caster(manager.session)
	var r: Dictionary = manager._server_handle_command(1, _cast_command(manager.session))
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(_count_kind(dispatched, NP.EVT_SPELL_RESOLVED)) \
		.override_failure_message("spell_resolved 经命令返回路径与 session_event 不得重复下发").is_equal(1)

# ---------------------------------------------------------------------------
# A4（架构审查 P1）：buff 过期必须发布战斗状态事件（expire_buffs 返回被清除的 buff id 列表）
# ---------------------------------------------------------------------------

func test_buff_expiry_publishes_combat_state_exactly_once() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	var ctx: PC = manager.session.registry.get_context(1)
	ctx.buffs["spell_power"] = 1  # 过期时刻已过（now_ms=1000 >= 1）
	manager.session.tick_player_buffs(1000)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_COMBAT_STATE)) \
		.override_failure_message("buff 过期必须经 session_event 出口下发战斗状态事件恰好一次").is_equal(1)
	# 权威 buff 已被清除（事件是真实状态变更的发布，不是空发）。
	assert_bool(not ctx.buffs.has("spell_power")).is_true()

func test_no_buff_expiry_publishes_no_combat_state_event() -> void:
	var manager: NETWORK_MANAGER = auto_free(_make_host_manager())
	var dispatched: Array = []
	manager.event_dispatched.connect(func(ev: Dictionary): dispatched.append(ev))
	manager.session.handle_spawn_request(1)
	var ctx: PC = manager.session.registry.get_context(1)
	ctx.buffs["spell_power"] = 4611686018427387903  # 未来很久，不会过期
	manager.session.tick_player_buffs(1000)
	assert_int(_count_kind(dispatched, NP.EVT_PLAYER_COMBAT_STATE)) \
		.override_failure_message("无 buff 过期时不得下发战斗状态事件").is_equal(0)

# ---------------------------------------------------------------------------
# 辅助：施法成功场景（复用 spell_session_atomicity_test 的装配）
# ---------------------------------------------------------------------------

func _spawn_caster(s, peer_id: int = 1) -> void:
	var spell_state := {
		"spell_loadout": {"slot_runes": [["ember", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]},
		"spell_mana": 100,
		"spell_max_mana": 100,
		"spell_runtime": {},
	}
	var save_state := {
		"loadout": {"weapon_slots": ["grimoire", "", "", ""], "armor_slots": {}, "active_weapon_slot": 0},
		"spell_state": spell_state,
	}
	s.handle_spawn_request(peer_id, save_state, "caster_%d" % peer_id)

func _bind_caster(s, peer_id: int = 1) -> Node3D:
	var caster := Node3D.new()
	caster.name = "Caster%d" % peer_id
	add_child(caster)
	s.bind_player_entity(peer_id, caster)
	return caster

func _cast_command(s, slot_index: int = 0, sequence: int = 1) -> Dictionary:
	return {
		"type": NP.CMD_CAST_SPELL,
		"slot_index": slot_index,
		"protocol_version": 1,
		"world_revision": s.world.world_revision,
		"sequence": sequence,
	}
