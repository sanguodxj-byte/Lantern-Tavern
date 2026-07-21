extends GdUnitTestSuite

## SessionRoot 编排器测试（docs/25 §3.2 / §21 步骤 3）。
## 覆盖：子对象构建、生成注册（两个独立 PlayerContext）、命令路由、
## 交互拾取端到端、战斗结算、断线清理、快照回放、权威掉落确定性。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const CV := preload("res://globals/multiplayer/command_validator.gd")

func _make_server() -> SR:
	var s: SR = SR.new()
	s.init_server()
	return s

# ---------------------------------------------------------------------------
# 构建 / 初始化
# ---------------------------------------------------------------------------

func test_subobjects_built_in_init() -> void:
	var s: SR = auto_free(SR.new())
	assert_object(s.registry).is_not_null()
	assert_object(s.world).is_not_null()
	assert_object(s.router).is_not_null()
	assert_object(s.validator).is_not_null()
	assert_object(s.interaction_auth).is_not_null()
	assert_object(s.combat_auth).is_not_null()
	assert_object(s.loot_auth).is_not_null()

func test_init_server_wires_authorities() -> void:
	var s: SR = auto_free(_make_server())
	assert_bool(s.is_server).is_true()
	assert_bool(s.router.has_handler(NP.CMD_INTERACT)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_PICKUP)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_ATTACK)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_INPUT)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_EXPEDITION)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_REQUEST_LAYOUT)).is_true()

# ---------------------------------------------------------------------------
# 玩家生成 / 注册（垂直切片：两个 PlayerContext）
# ---------------------------------------------------------------------------

func test_register_two_players_two_contexts() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_spawn_request(2)
	assert_int(s.registry.peer_count()).is_equal(2)
	var c1 = s.registry.get_context(1)
	var c2 = s.registry.get_context(2)
	assert_int(c1.get_instance_id()).is_not_equal(c2.get_instance_id())
	assert_bool(s.registry.is_spawned(1)).is_true()
	assert_bool(s.registry.is_spawned(2)).is_true()

func test_handle_spawn_request_creates_independent_state() -> void:
	var s: SR = auto_free(_make_server())
	var c1 = s.handle_spawn_request(1)
	var c2 = s.handle_spawn_request(2)
	# 两个上下文的属性容器必须彼此独立（per-peer 隔离）
	c1.attributes.accumulate_attr("str", 999)
	assert_int(c1.attributes.get_attr("str")).is_not_equal(c2.attributes.get_attr("str"))

func test_spawn_request_on_client_returns_null() -> void:
	var s: SR = auto_free(SR.new())
	s.init_client()
	assert_object(s.handle_spawn_request(1)).is_null()

# ---------------------------------------------------------------------------
# 命令入口 / 权限边界
# ---------------------------------------------------------------------------

func test_on_command_rejects_non_server() -> void:
	var s: SR = auto_free(SR.new())
	s.init_client()
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INTERACT, "protocol_version": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PERMISSION_DENIED)

func test_on_command_rejects_wrong_protocol() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INTERACT, "protocol_version": 99})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_PROTOCOL)

func test_on_command_rejects_dead_player() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_alive(1, false)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INTERACT, "protocol_version": 1, "world_revision": s.world.world_revision})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PLAYER_NOT_ALIVE)

func test_on_command_rejects_forbidden_trusted_field() -> void:
	# Phase 2.3: 任何携带「服务器权威字段」的命令一律被拒（GLITCH/秒杀/无限资源根防）。
	# 验证多个被禁字段均触发拒绝，且拒绝码为 PERMISSION_DENIED（而非协议/序列等其它原因）。
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	for f in CV.FORBIDDEN_TRUSTED_FIELDS:
		var cmd := {"type": NP.CMD_INPUT, f: 1, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1}
		var r: Dictionary = s.on_command(1, cmd)
		assert_bool(r["success"]).is_false()
		assert_str(r["error_code"]).is_equal(NP.ERR_PERMISSION_DENIED)

func test_init_server_wires_phase2_authorities() -> void:
	var s: SR = auto_free(_make_server())
	# Phase 2 新增的 5 个命令处理器均已注册（与既有处理器并列）。
	assert_bool(s.router.has_handler(NP.CMD_SKILL)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_EQUIP)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_DROP)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_SAVE)).is_true()
	assert_bool(s.router.has_handler(NP.CMD_LEAVE)).is_true()

func test_injected_handler_routing() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(7)
	var called := {"hit": false}
	s.register_authority("custom_cmd", func(cmd, ctx):
		called["hit"] = true
		return {"success": true, "event": {"event": "custom_ok"}, "error_code": ""})
	var r: Dictionary = s.on_command(7, {"type": "custom_cmd", "protocol_version": 1, "world_revision": s.world.world_revision})
	assert_bool(called["hit"]).is_true()
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal("custom_ok")

# ---------------------------------------------------------------------------
# 交互 / 拾取（端到端：服务器权威）
# ---------------------------------------------------------------------------

func test_interaction_pickup_end_to_end() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	s.set_player_position(1, Vector3.ZERO)
	s.set_entity(9001, {"item_id": "goblin_tooth", "item_kind": "material", "amount": 2, "position": Vector3.ZERO, "consumed": false})
	var cmd := {"type": NP.CMD_PICKUP, "target_entity_id": 9001, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_INTERACTION_RESULT)
	assert_int(ctx.inventory.to_dict()["materials"].get("goblin_tooth", 0)).is_equal(2)
	# 实体已被拾取并从权威注册表移除：重复请求必须被拒（实体已不存在 → INVALID_TARGET，服务器权威非客户端自判）。
	# 注意：首次拾取会移除实体→bump world_revision；真实客户端已学到新 revision，故第二次用当前 revision 上送以越过校验门。
	var r2: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 9001,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r2["success"]).is_false()
	assert_str(r2["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

func test_interaction_pickup_out_of_range() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_position(1, Vector3(0, 0, 10))
	s.set_entity(9002, {"item_id": "gold", "item_kind": "material", "amount": 1, "position": Vector3.ZERO, "consumed": false})
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 9002, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_OUT_OF_RANGE)

# ---------------------------------------------------------------------------
# 战斗结算（服务器权威）
# ---------------------------------------------------------------------------

func test_combat_handler_resolves_damage() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_entity(4312, {"con": 10, "agi": 10, "per": 10, "armor_def": 0, "current_life": 100, "max_life": 100})
	var cmd := {"type": NP.CMD_ATTACK, "attack_type": "melee", "target_hint": 4312, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	var evt: Dictionary = r["event"]
	assert_str(evt["event"]).is_equal(NP.EVT_COMBAT_RESOLVED)
	assert_int(evt["damage"]).is_greater(0)
	assert_int(evt["defender_entity_id"]).is_equal(4312)
	# 重复 sequence 应被拒（防重放）
	var r2: Dictionary = s.on_command(1, cmd)
	assert_bool(r2["success"]).is_false()
	assert_str(r2["error_code"]).is_equal(NP.ERR_INVALID_SEQUENCE)

# ---------------------------------------------------------------------------
# 移动同步（Phase 4：服务器采样输入帧，从输入积分权威位置）
# ---------------------------------------------------------------------------

func test_input_frame_updates_server_position() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_position(1, Vector3(0, 0, 0))
	var cmd := {"type": NP.CMD_INPUT, "move": [0.0, -1.0], "look_yaw": 0.5, "look_pitch": 0.0,
		"sprint": false, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_PLAYER_SNAPSHOT)
	assert_int(int(r["event"]["peer_id"])).is_equal(1)
	# 服务器从输入积分位置，不信客户端自报坐标
	var expected_z: float = -4.0 * (1.0 / 30.0)
	assert_float(float(s._live_state[1]["position"].z)).is_equal_approx(expected_z, 1e-4)
	assert_float(float(r["event"]["position"].z)).is_equal_approx(expected_z, 1e-4)

func test_input_frame_sprint_covers_more_distance() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_position(1, Vector3(0, 0, 0))
	var walk := {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1}
	var run := {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": true, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2}
	var rw: Dictionary = s.on_command(1, walk)
	var rr: Dictionary = s.on_command(1, run)
	assert_float(float(rr["event"]["position"].x)).is_greater(float(rw["event"]["position"].x))

# ---------------------------------------------------------------------------
# 实体复制权威（Phase 9：服务器维护实体表并产出复制事件）
# ---------------------------------------------------------------------------

func test_entity_spawn_despawn_update_produces_events() -> void:
	var s: SR = auto_free(_make_server())
	var sp: Dictionary = s.set_entity(9001, {"kind": "enemy", "hp": 30})
	assert_str(sp["event"]["event"]).is_equal(NP.EVT_ENTITY_SPAWNED)
	assert_bool(s.get_entity(9001).is_empty()).is_false()
	var up: Dictionary = s.update_entity(9001, {"hp": 12})
	assert_str(up["event"]["event"]).is_equal(NP.EVT_ENTITY_SNAPSHOT)
	assert_int(int(s.get_entity(9001)["hp"])).is_equal(12)
	var dp: Dictionary = s.remove_entity(9001)
	assert_str(dp["event"]["event"]).is_equal(NP.EVT_ENTITY_DESPAWNED)
	assert_bool(s.get_entity(9001).is_empty()).is_true()

# ---------------------------------------------------------------------------
# 地牢 seed/layout 同步（Phase 7：服务器权威出征 + 客户端布局声明校验）
# ---------------------------------------------------------------------------

func test_start_expedition_broadcasts_layout() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var captured := {"evt": {}}
	s.session_event.connect(func(e): captured["evt"] = e)
	var cmd := {"type": NP.CMD_EXPEDITION, "seed": 777, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["type"]).is_equal(NP.EVT_DUNGEON_LAYOUT)
	assert_int(r["event"]["seed"]).is_equal(777)
	# 广播事件已通过 session_event 发出
	assert_str(captured["evt"].get("type", "")).is_equal(NP.EVT_DUNGEON_LAYOUT)

func test_layout_request_matching_seed_ok() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.on_command(1, {"type": NP.CMD_EXPEDITION, "seed": 777, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_REQUEST_LAYOUT, "seed": 777,
		"layout_version": NP.DUNGEON_LAYOUT_VERSION, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["type"]).is_equal(NP.EVT_DUNGEON_LAYOUT)

func test_layout_request_wrong_seed_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.on_command(1, {"type": NP.CMD_EXPEDITION, "seed": 777, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_REQUEST_LAYOUT, "seed": 999,
		"layout_version": NP.DUNGEON_LAYOUT_VERSION, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_DUNGEON_SEED_MISMATCH)

func test_dungeon_state_in_reconnect_snapshot() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.on_command(1, {"type": NP.CMD_EXPEDITION, "seed": 777, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	var snap: Dictionary = s.build_session_snapshot()
	assert_int(snap["dungeon"]["seed"]).is_equal(777)
	# 新会话从快照恢复
	var s2: SR = auto_free(_make_server())
	s2.apply_session_snapshot(snap)
	assert_int(s2.dungeon_auth.seed).is_equal(777)
	assert_bool(s2.dungeon_auth.active).is_true()

# ---------------------------------------------------------------------------
# 继承存档状态（联机仅地牢：进入地牢时只带入各自单人存档）
# ---------------------------------------------------------------------------

func test_spawn_inherits_save_state() -> void:
	var s: SR = auto_free(_make_server())
	var save_state := {
		"materials": {"rat_tail": 5, "iron_ore": 2},
		"loadout": {"weapon_slots": ["iron_sword", "", "", ""], "armor_slots": {"head": "leather_cap"}}
	}
	var ctx = s.handle_spawn_request(1, save_state)
	# 存档材料已继承到联机上下文背包（服务器可信数据，非客户端自报）
	assert_int(ctx.inventory.materials.get("rat_tail", 0)).is_equal(5)
	assert_int(ctx.inventory.materials.get("iron_ore", 0)).is_equal(2)
	# 存档装备已继承到 loadout
	assert_str(ctx.loadout.get_weapon_slot(0)).is_equal("iron_sword")
	assert_str(ctx.loadout.get_armor_slot("head")).is_equal("leather_cap")

func test_spawn_without_save_state_uses_defaults() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	# 无存档：使用默认空上下文（不崩溃、属性已按 init_defaults 初始化）
	assert_int(ctx.attributes.get_attr("str")).is_equal(5)
	assert_bool(ctx.inventory.materials.is_empty()).is_true()

# ---------------------------------------------------------------------------
# 断线清理
# ---------------------------------------------------------------------------

func test_unregister_player_cleans_up() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_entity(9001, {"item_id": "x", "consumed": false})
	s.unregister_player(1)
	assert_bool(s.registry.has_peer(1)).is_false()
	assert_bool(s._live_state.has(1)).is_false()

# ---------------------------------------------------------------------------
# 连接生命周期（§13 断线保留 / 重连 / 心跳超时）
# ---------------------------------------------------------------------------

func test_disconnect_keeps_context_in_grace() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var res: Dictionary = s.handle_peer_disconnected(1, 0.0)
	# 发放重连 token，且 PlayerContext 在保留期内仍保留（未注销）
	assert_str(res["token"]).is_not_equal("")
	assert_str(s.connection_auth.get_status(1)).is_equal("grace")
	assert_bool(s.registry.has_peer(1)).is_true()
	assert_bool(s._live_state.has(1)).is_true()

func test_resume_delivers_snapshot_and_reregisters() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_position(1, Vector3(3, 0, 4))
	var tok: String = s.handle_peer_disconnected(1, 0.0)["token"]
	s.current_time = 5.0
	var cmd := {"type": NP.CMD_RESUME, "token": tok, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_SESSION_SNAPSHOT)
	assert_bool(r["event"].has("snapshot")).is_true()
	# 重连后重新在线（沿用保留期内的同一上下文）
	assert_str(s.connection_auth.get_status(1)).is_equal("online")
	assert_bool(s.registry.has_peer(1)).is_true()
	assert_str(s.connection_auth.get_player_guid(1)).is_equal("peer_1")

func test_resume_with_wrong_token_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_peer_disconnected(1, 0.0)
	# 携带稳定 guid（客户端 spawn 时即持有），token 错误 → 命中 GRACE 条目但校验失败。
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_RESUME, "token": "bogus", "player_guid": "peer_1", "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_RECONNECT_TOKEN_INVALID)
	assert_str(s.connection_auth.get_status(1)).is_equal("grace")

func test_resume_after_grace_expiry_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var tok: String = s.handle_peer_disconnected(1, 0.0)["token"]
	s.current_time = 61.0  # 超过 60s 保留期
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_RESUME, "token": tok, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_RECONNECT_TOKEN_EXPIRED)

func test_commands_blocked_during_grace() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_peer_disconnected(1, 0.0)
	# GRACE 期内普通命令（除重连）一律拒绝
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [0, 1], "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_STATE)

## 关键 D1 bug 修复验证：重连时 ENet 分配【新】peer_id，旧 peer_id 的 inventory/位置/状态
## 必须沿稳定 player_guid 接管到新 peer_id，不丢、不串号。
func test_resume_with_new_peer_id_migrates_state_keeping_inventory_and_position() -> void:
	var s: SR = auto_free(_make_server())
	# 旧 peer=3 携带可见状态：位置 (7,0,8)，背包含 3 个 iron_ore（模拟出征拾取）。
	s.handle_spawn_request(3, {"materials": {"iron_ore": 3}}, "player_alpha")
	s.set_player_position(3, Vector3(7, 0, 8))
	var tok: String = s.handle_peer_disconnected(3, 0.0)["token"]
	# 模拟 ENet 重连分配了全新 peer_id=9（旧 3 已不可达）。
	s.current_time = 5.0
	var cmd := {
		"type": NP.CMD_RESUME, "token": tok, "player_guid": "player_alpha",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0,
	}
	var r: Dictionary = s.on_command(9, cmd)
	assert_bool(r["success"]).is_true()
	# 1) 旧 peer_id=3 已不再承载任何状态（被迁移清除，不串号）。
	assert_bool(s.registry.has_peer(3)).is_false()
	assert_bool(s._live_state.has(3)).is_false()
	assert_str(s.connection_auth.get_status(3)).is_equal("")
	assert_str(s.connection_auth.get_player_guid(3)).is_equal("")
	# 2) 新 peer_id=9 接管了同一 PlayerContext（同一实例 id，不重建）。
	assert_bool(s.registry.has_peer(9)).is_true()
	var ctx9 = s.registry.get_context(9)
	assert_object(ctx9).is_not_null()
	# 3) inventory/位置连续（重连不丢状态）。
	assert_int(ctx9.inventory.materials.get("iron_ore", 0)).is_equal(3)
	var pos = s._live_state[9]["position"]
	assert_float(pos.x).is_equal(7.0)
	assert_float(pos.y).is_equal(0.0)
	assert_float(pos.z).is_equal(8.0)
	# 4) 在线态恢复，guid 仍锚定到新 peer_id。
	assert_str(s.connection_auth.get_status(9)).is_equal("online")
	assert_str(s.connection_auth.get_player_guid(9)).is_equal("player_alpha")
	assert_bool(s.registry.is_spawned(9)).is_true()

## 新 peer_id 重连 + 错 token → 仍按 guid 命中 GRACE 但校验失败（不串号、不接管）。
func test_resume_with_new_peer_id_wrong_token_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(3, {}, "player_alpha")
	s.handle_peer_disconnected(3, 0.0)
	var r: Dictionary = s.on_command(9, {"type": NP.CMD_RESUME, "token": "bad", "player_guid": "player_alpha", "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_RECONNECT_TOKEN_INVALID)
	# 旧 peer 仍在 GRACE，新 peer 未建立任何状态（未被串号接管）。
	assert_str(s.connection_auth.get_status(3)).is_equal("grace")
	assert_bool(s.registry.has_peer(9)).is_false()

func test_grace_expiry_cleans_context() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_peer_disconnected(1, 0.0)
	# 推进超过保留期 → tick 清理 PlayerContext
	var cleaned: Array = s.tick_connections(61.0)
	assert_int(cleaned.size()).is_equal(1)
	assert_bool(s.registry.has_peer(1)).is_false()
	assert_bool(s._live_state.has(1)).is_false()

func test_host_disconnect_ends_room() -> void:
	var s: SR = auto_free(_make_server())
	s.connection_auth.host_peer_id = 1
	assert_bool(s.connection_auth.should_end_room_on_disconnect(1)).is_true()
	assert_bool(s.connection_auth.should_end_room_on_disconnect(2)).is_false()

func test_interaction_lock_released_on_disconnect() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_position(1, Vector3.ZERO)
	s.set_entity(9001, {"item_id": "goblin_tooth", "item_kind": "material", "amount": 2, "position": Vector3.ZERO, "consumed": false})
	s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 9001, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 0})
	# 拾取后持有交互锁
	assert_int(s.interaction_auth._interaction_locks.get(9001, -1)).is_equal(1)
	# 断线后交互锁被释放
	s.handle_peer_disconnected(1, 0.0)
	assert_bool(s.interaction_auth._interaction_locks.has(9001)).is_false()

# ---------------------------------------------------------------------------
# 快照 / 重连
# ---------------------------------------------------------------------------

func test_session_snapshot_roundtrip() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_spawn_request(2)
	s.world.transition_space("dungeon")
	s.set_entity(50, {"hp": 30})
	var snap: Dictionary = s.build_session_snapshot()
	var s2: SR = auto_free(SR.new())
	s2.init_client()
	s2.apply_session_snapshot(snap)
	assert_int(s2.world.world_revision).is_equal(s.world.world_revision)
	assert_str(s2.world.current_space).is_equal("dungeon")
	assert_int(s2.get_entity(50).get("hp", -1)).is_equal(30)

# ---------------------------------------------------------------------------
# 权威掉落（确定性，便于重连回放）
# ---------------------------------------------------------------------------

func test_server_roll_loot_deterministic() -> void:
	var s: SR = auto_free(_make_server())
	var table := {"goblin_tooth": {"kind": "material", "weight": 10, "min": 1, "max": 3}}
	var a: Dictionary = s.server_roll_loot(table, 12345)
	var b: Dictionary = s.server_roll_loot(table, 12345)
	assert_dict(a).is_equal(b)

# ---------------------------------------------------------------------------
# 出征结算（Phase ⑧）：只回写本次净获得，不重复累加基线、不丢失既有符文/装备
# ---------------------------------------------------------------------------

func test_extraction_settlement_returns_net_gain_only() -> void:
	var s: SR = auto_free(_make_server())
	# 进地牢时带入 baseline：材料 rat_tail=5（模拟已有单人存档物资）。
	var save_state := {
		"materials": {"rat_tail": 5},
		"loadout": {"weapon_slots": ["iron_sword", "", "", ""], "armor_slots": {}}
	}
	var ctx = s.handle_spawn_request(1, save_state)
	# 地牢中捡到 2 个 goblin_tooth。
	ctx.inventory.add_material("goblin_tooth", 2)
	# 结算：净获得应只有 goblin_tooth=2，不含 baseline 的 rat_tail=5（避免重复累加）。
	var settle: Dictionary = s._compute_settlement(1)
	assert_int(int((settle["materials"] as Dictionary).get("goblin_tooth", 0))).is_equal(2)
	assert_bool((settle["materials"] as Dictionary).has("rat_tail")).is_false()

func test_extraction_handler_emits_result_event() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	ctx.inventory.add_rune("ember_rune", 3)
	var cmd := {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_EXTRACTION_RESULT)
	assert_int(int((r["event"]["settlement"]["runes"] as Dictionary).get("ember_rune", 0))).is_equal(3)
	assert_int(int(r["event"]["peer_id"])).is_equal(1)

func test_extraction_settlement_zero_when_nothing_gathered() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var settle: Dictionary = s._compute_settlement(1)
	assert_bool((settle["materials"] as Dictionary).is_empty()).is_true()
	assert_bool((settle["runes"] as Dictionary).is_empty()).is_true()
	assert_bool((settle["equipment"] as Dictionary).is_empty()).is_true()

# ---------------------------------------------------------------------------
# Phase 5 结算幂等（存档信任边界）：重复 extract/save 不刷物品
# ---------------------------------------------------------------------------

func test_extract_first_time_not_already_settled() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1, {}, "player_alpha")
	ctx.inventory.add_material("goblin_tooth", 2)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_bool(bool(r["event"].get("already_settled", true))).is_false()
	assert_int(int((r["event"]["settlement"]["materials"] as Dictionary).get("goblin_tooth", 0))).is_equal(2)
	assert_bool(s.save_auth.is_settled("player_alpha")).is_true()

func test_repeat_extract_is_idempotent_and_flags_already_settled() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1, {}, "player_alpha")
	ctx.inventory.add_material("goblin_tooth", 2)
	s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	# 玩家试图再刷一次：即使背包又"变多"，重复结算必须被幂等拒绝、置 already_settled。
	ctx.inventory.add_material("goblin_tooth", 999)
	var r2: Dictionary = s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2})
	assert_bool(r2["success"]).is_true()
	assert_bool(bool(r2["event"]["already_settled"])).is_true()
	# 缓存结算仍是首次的净获得（2），不是被刷后的 1001。
	assert_int(int((r2["event"]["settlement"]["materials"] as Dictionary).get("goblin_tooth", 0))).is_equal(2)

func test_save_command_is_idempotent_with_extract() -> void:
	# CMD_SAVE 与 CMD_EXTRACT 共用同一结算账本：先 extract 再 save 应判定已结算。
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1, {}, "player_alpha")
	ctx.inventory.add_rune("ember_rune", 3)
	s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	var r2: Dictionary = s.on_command(1, {"type": NP.CMD_SAVE, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2})
	assert_bool(r2["success"]).is_true()
	assert_bool(bool(r2["event"]["already_settled"])).is_true()

func test_new_expedition_allows_fresh_settlement() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1, {}, "player_alpha")
	ctx.inventory.add_material("goblin_tooth", 2)
	s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(s.save_auth.is_settled("player_alpha")).is_true()
	# 开启新出征后账本重置，玩家可再结算一次（新 run 的净获得）。
	s.on_command(1, {"type": NP.CMD_EXPEDITION, "seed": 77, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2})
	assert_bool(s.save_auth.is_settled("player_alpha")).is_false()
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 3})
	assert_bool(bool(r["event"]["already_settled"])).is_false()

func test_settlement_survives_reconnect_snapshot() -> void:
	# 已结算状态纳入重连快照：断线重连到新 server 实例后仍判定已结算，防绕过幂等。
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1, {}, "player_alpha")
	ctx.inventory.add_material("goblin_tooth", 2)
	s.on_command(1, {"type": NP.CMD_EXTRACT, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	var snap: Dictionary = s.build_session_snapshot()
	var s2: SR = auto_free(_make_server())
	s2.apply_session_snapshot(snap)
	assert_bool(s2.save_auth.is_settled("player_alpha")).is_true()

# ---------------------------------------------------------------------------
# Phase 2 命令处理器（服务器权威）
# ---------------------------------------------------------------------------

func test_handle_skill_rejects_unowned_skill() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	# 该玩家未绑定 "nonexistent_skill"，服务器不应信任客户端自报的技能。
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_SKILL, "skill_id": "nonexistent_skill",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

func test_handle_skill_accepts_owned_skill() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	# 在服务器权威上下文中绑定技能，再请求释放。
	ctx.skills.slots[ctx.skills.SLOT_F_ACTION] = "test_fireball"
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_SKILL, "skill_id": "test_fireball",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_SKILL_STATE_CHANGED)
	assert_str(r["event"]["skill_id"]).is_equal("test_fireball")
	assert_int(int(r["event"]["peer_id"])).is_equal(1)
	# 重复 sequence 应被拒（防重放）。
	var r2: Dictionary = s.on_command(1, {"type": NP.CMD_SKILL, "skill_id": "test_fireball",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r2["success"]).is_false()
	assert_str(r2["error_code"]).is_equal(NP.ERR_INVALID_SEQUENCE)

func test_handle_equip_rejects_item_not_owned() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_EQUIP, "item_id": "not_owned_sword",
		"slot": 0, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

func test_handle_equip_accepts_owned_item() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	# 物品必须真实存在于该玩家背包（服务器权威校验）。
	ctx.inventory.add_material("iron_ore", 1)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_EQUIP, "item_id": "iron_ore",
		"slot": 0, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_EQUIPMENT_CHANGED)
	# 装备槽位已更新（权威写入）。
	assert_str(ctx.loadout.get_weapon_slot(0)).is_equal("iron_ore")

func test_handle_drop_clamps_to_held_amount() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	ctx.inventory.add_material("gold", 2)
	# 客户端谎报 drop_amount=999，服务器夹紧到实际持有量 2，杜绝无限复制。
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_DROP, "item_id": "gold", "category": "material",
		"amount": 999, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_INVENTORY_CHANGED)
	# 背包仅剩 0 个；世界生成了 1 个持有量为 2 的掉落实体。
	assert_int(int(ctx.inventory.materials.get("gold", 0))).is_equal(0)
	var loot_id: int = -1
	for eid in s._entities.keys():
		if s._entities[eid].get("item_id", "") == "gold":
			loot_id = int(eid)
	assert_bool(loot_id >= 0).is_true()
	assert_int(int(s.get_entity(loot_id)["amount"])).is_equal(2)

func test_handle_drop_rejects_when_not_held() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_DROP, "item_id": "absent", "category": "material",
		"amount": 1, "protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

func test_handle_save_returns_settlement() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = s.handle_spawn_request(1)
	ctx.inventory.add_rune("ember_rune", 2)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_SAVE,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_EXTRACTION_RESULT)
	assert_bool(bool(r["event"].get("requested_save", false))).is_true()
	assert_int(int((r["event"]["settlement"]["runes"] as Dictionary).get("ember_rune", 0))).is_equal(2)

func test_handle_leave_cleans_up_context() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_LEAVE,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	# 离开后 PlayerContext 被立即清理（不再重连）。
	assert_bool(s.registry.has_peer(1)).is_false()
	assert_bool(s._live_state.has(1)).is_false()

# ---------------------------------------------------------------------------
# Phase 6：world_revision 闭环（结构性世界变更→递增→广播→远端客户端追平）
# ---------------------------------------------------------------------------

func test_world_revision_bumps_on_player_join() -> void:
	var s: SR = auto_free(_make_server())
	assert_int(s.world.world_revision).is_equal(0)
	s.handle_spawn_request(1)
	assert_int(s.world.world_revision).is_equal(1)
	s.handle_spawn_request(2)
	assert_int(s.world.world_revision).is_equal(2)

func test_world_revision_bumps_on_expedition() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.on_command(1, {"type": NP.CMD_EXPEDITION, "seed": 42,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_int(s.world.world_revision).is_greater(0)
	assert_str(s.world.current_space).is_equal("dungeon")

func test_world_revision_bumps_on_entity_spawn_and_despawn() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	var rev_after_join: int = s.world.world_revision
	# 新增实体→bump
	s.set_entity(1001, {"kind": "enemy", "current_life": 10, "max_life": 10})
	assert_int(s.world.world_revision).is_greater(rev_after_join)
	# 重播同一实体（已存在）→不 bump（避免晚到追平时 churn）
	var rev_before_replay: int = s.world.world_revision
	s.set_entity(1001, {"kind": "enemy", "current_life": 5, "max_life": 10})
	assert_int(s.world.world_revision).is_equal(rev_before_replay)
	# 移除实体→bump
	s.remove_entity(1001)
	assert_int(s.world.world_revision).is_greater(rev_before_replay)

func test_world_revision_broadcast_on_bump() -> void:
	var s: SR = auto_free(_make_server())
	var captured := []
	s.broadcast_event = func(e): captured.append(e)
	var rev := s._bump_world("dungeon")
	assert_int(rev).is_equal(1)
	assert_int(captured.size()).is_equal(1)
	var evt: Dictionary = captured[0]
	assert_str(evt.get("event", "")).is_equal(NP.EVT_WORLD_REVISION_CHANGED)
	assert_int(int(evt.get("world_revision", -1))).is_equal(1)
	assert_str(evt.get("current_space", "")).is_equal("dungeon")

func test_stale_world_revision_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_alive(1, true)
	s._bump_world()  # 服务器 world 前进到 1，但客户端仍用旧 revision=0 上送
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": 0, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_WORLD_REVISION)

func test_fresh_world_revision_accepted_after_bump() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_alive(1, true)
	s._bump_world()  # world=1
	# 客户端已通过 EVT_WORLD_REVISION_CHANGED 学到 rev=1，用最新 revision 上送→通过校验
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()

func test_world_revision_carried_in_session_snapshot() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s._bump_world("dungeon")
	var snap: Dictionary = s.build_session_snapshot()
	assert_int(int(snap.get("world_revision", -1))).is_equal(s.world.world_revision)
	# 新服务器实例应用快照后 world_revision 一致（重连追平）
	var s2: SR = SR.new()
	s2.init_server()
	s2.apply_session_snapshot(snap)
	assert_int(s2.world.world_revision).is_equal(s.world.world_revision)

# ---------------------------------------------------------------------------
# 实体对账 reconcile_entities（Phase 10 生产化：build_delta 进生产路径）
# ---------------------------------------------------------------------------

func test_reconcile_empty_known_is_full_spawn() -> void:
	# known 为空 → 全量 entity_spawned（等价旧 rebroadcast 行为）
	var s: SR = auto_free(_make_server())
	s.set_entity(1, {"kind": "enemy", "current_life": 10})
	s.set_entity(2, {"kind": "loot", "item_id": "gold"})
	var ev: Array = s.reconcile_entities({})
	assert_int(ev.size()).is_equal(2)
	for e in ev:
		assert_str(e["event"]).is_equal(NP.EVT_ENTITY_SPAWNED)

func test_reconcile_despawns_stale_client_entity() -> void:
	# 关键修复：客户端仍持有的陈旧实体（server 已无）必须收到 despawn——朴素 rebroadcast 做不到。
	var s: SR = auto_free(_make_server())
	s.set_entity(1, {"kind": "enemy", "current_life": 10})
	# 客户端 known 里有 99（server 无）+ 1（server 有，未变）
	var known := {1: {"kind": "enemy", "current_life": 10}, 99: {"kind": "enemy", "current_life": 5}}
	var ev: Array = s.reconcile_entities(known)
	# 1 未变→无事件；99 消失→despawn；共 1 个事件
	assert_int(ev.size()).is_equal(1)
	assert_str(ev[0]["event"]).is_equal(NP.EVT_ENTITY_DESPAWNED)
	assert_int(int(ev[0]["entity_id"])).is_equal(99)

func test_reconcile_snapshots_changed_and_spawns_new() -> void:
	var s: SR = auto_free(_make_server())
	s.set_entity(1, {"kind": "enemy", "current_life": 4})   # server 已扣血
	s.set_entity(3, {"kind": "loot", "item_id": "gem"})     # server 新增
	var known := {1: {"kind": "enemy", "current_life": 10}} # 客户端仍是满血、不知 3
	var ev: Array = s.reconcile_entities(known)
	var kinds := {}
	for e in ev:
		kinds[e["event"]] = int(e["entity_id"])
	assert_bool(kinds.has(NP.EVT_ENTITY_SNAPSHOT)).is_true()   # 1 变化→snapshot
	assert_int(kinds[NP.EVT_ENTITY_SNAPSHOT]).is_equal(1)
	assert_bool(kinds.has(NP.EVT_ENTITY_SPAWNED)).is_true()    # 3 新增→spawn
	assert_int(kinds[NP.EVT_ENTITY_SPAWNED]).is_equal(3)
	assert_int(ev.size()).is_equal(2)
