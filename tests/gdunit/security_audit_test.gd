extends GdUnitTestSuite

## §17.4 安全审计测试套件（Phase 10 测试分层）。
## docs/25-联机总体方案.md §17.4 明确要求覆盖 10 类作弊/越权场景。此前这些断言散落在
## combat / movement / interaction / session 各套件中、从未汇集为一个显式的「安全基线」套件；
## 本文件把 10 类场景集中断言，作为所有权威硬化（Phase 1–9）的回归护栏。
##
## 每条用例都走【真实服务器权威路径】(SessionRoot.on_command / 各 Authority)，断言攻击被拒。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const CV := preload("res://globals/multiplayer/command_validator.gd")

func _make_server() -> SR:
	var s: SR = SR.new()
	s.init_server()
	return s

## 便捷：生成一个存活玩家并置于原点。
func _spawn_alive(s: SR, peer_id: int, pos := Vector3.ZERO) -> void:
	s.handle_spawn_request(peer_id)
	s.set_player_position(peer_id, pos)
	s.set_player_alive(peer_id, true)

# ---------------------------------------------------------------------------
# §17.4-1 客户端伪造 peer_id：命令内自报的 peer_id 字段【绝不被信任】，
# 服务器只按 RPC 层可信来源(on_command 的 peer_id 参数)归属命令。
# （RPC 层另有 rpc_client_command: sender != peer_id → return 的硬防线。）
# ---------------------------------------------------------------------------
func test_forged_peer_id_field_is_ignored() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	_spawn_alive(s, 2, Vector3(5, 0, 0))
	# peer 1 上送带伪造 "peer_id":2 的移动命令——应作用于 peer 1（可信参数），绝不动 peer 2。
	var before2: Vector3 = s._live_state[2]["position"]
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "peer_id": 2,
		"move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_true()
	# peer 2 权威位置未被 peer 1 的伪造命令改动。
	assert_vector(s._live_state[2]["position"]).is_equal(before2)

# ---------------------------------------------------------------------------
# §17.4-2 修改目标 entity_id：指向不存在实体的交互/攻击 → INVALID_TARGET。
# ---------------------------------------------------------------------------
func test_forged_target_entity_id_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 999999,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

# ---------------------------------------------------------------------------
# §17.4-3 重放旧 sequence：重复/回放的序列号 → INVALID_SEQUENCE。
# ---------------------------------------------------------------------------
func test_replayed_sequence_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	s.set_entity(4312, {"con": 10, "armor_def": 0, "current_life": 100, "max_life": 100, "position": Vector3.ZERO})
	var cmd := {"type": NP.CMD_ATTACK, "attack_type": "melee", "target_hint": 4312,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 7}
	var r1: Dictionary = s.on_command(1, cmd)
	assert_bool(r1["success"]).is_true()
	# 完全相同的命令（同 sequence）重放 → 拒绝。
	var r2: Dictionary = s.on_command(1, cmd)
	assert_bool(r2["success"]).is_false()
	assert_str(r2["error_code"]).is_equal(NP.ERR_INVALID_SEQUENCE)

# ---------------------------------------------------------------------------
# §17.4-4 使用旧 world_revision：服务器 bump 后仍用旧 revision 上送 → INVALID_WORLD_REVISION。
# ---------------------------------------------------------------------------
func test_stale_world_revision_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	s._bump_world()  # 服务器前进；客户端故意仍用旧 revision=0
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": 0, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_WORLD_REVISION)

# ---------------------------------------------------------------------------
# §17.4-5 发送异常移动输入（自报权威位置）：命令携带 "position" 权威字段 → PERMISSION_DENIED。
# 服务器只从客户端输入积分权威位置，绝不信任客户端自报坐标（防瞬移/穿墙）。
# ---------------------------------------------------------------------------
func test_forged_position_field_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [0.0, 0.0], "sprint": false,
		"position": Vector3(9999, 0, 9999),
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PERMISSION_DENIED)

# ---------------------------------------------------------------------------
# §17.4-6 超范围攻击：目标远超武器射程（徒手 2.5m）→ OUT_OF_RANGE。
# 服务器用权威位置(attacker=live_state, target=entity)做几何校验，绝不信任客户端。
# ---------------------------------------------------------------------------
func test_out_of_range_attack_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	s.set_entity(4312, {"con": 10, "armor_def": 0, "current_life": 100, "max_life": 100,
		"position": Vector3(100, 0, 0)})  # 远在 100m 外
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_ATTACK, "attack_type": "melee", "target_hint": 4312,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_OUT_OF_RANGE)

# ---------------------------------------------------------------------------
# §17.4-7 修改库存数量：命令携带 "inventory_delta" 权威字段 → PERMISSION_DENIED。
# ---------------------------------------------------------------------------
func test_forged_inventory_delta_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 1,
		"inventory_delta": {"gold": 99999},
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PERMISSION_DENIED)

# ---------------------------------------------------------------------------
# §17.4-8 重复拾取：同一掉落实体拾取两次，第二次实体已 despawn → INVALID_TARGET。
# ---------------------------------------------------------------------------
func test_duplicate_pickup_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_alive(s, 1, Vector3.ZERO)
	s.set_entity(9001, {"item_id": "gold", "item_kind": "material", "amount": 5,
		"position": Vector3.ZERO, "consumed": false})
	var r1: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 9001,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r1["success"]).is_true()
	# 首次拾取移除实体并 bump world_revision；第二次用当前 revision 上送以越过 revision 门，
	# 直击「实体已消失」判定 → INVALID_TARGET（证明无法靠重复请求刷物品）。
	var r2: Dictionary = s.on_command(1, {"type": NP.CMD_PICKUP, "target_entity_id": 9001,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2})
	assert_bool(r2["success"]).is_false()
	assert_str(r2["error_code"]).is_equal(NP.ERR_INVALID_TARGET)

# ---------------------------------------------------------------------------
# §17.4-9 未授权操作者：未生成/已死亡的 peer 发命令 → 拒绝（NOT_ALIVE/NOT_READY/INVALID_STATE）。
# 在线但未存活玩家不能行动（防「死亡仍输出」/未授权 actor 越权）。
# ---------------------------------------------------------------------------
func test_unauthorized_dead_actor_rejected() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.set_player_alive(1, false)  # 明确置为死亡
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PLAYER_NOT_ALIVE)

# ---------------------------------------------------------------------------
# §17.4-10 客户端直接调用服务器方法：非服务器会话上的 on_command / handle_spawn_request
# 一律拒绝（客户端不得越过服务器权威直接改状态）。
# ---------------------------------------------------------------------------
func test_client_side_command_denied() -> void:
	var s: SR = auto_free(SR.new())
	s.init_client()  # 客户端会话（非权威）
	var r: Dictionary = s.on_command(1, {"type": NP.CMD_INPUT, "move": [1.0, 0.0], "sprint": false,
		"protocol_version": 1, "world_revision": 0, "sequence": 1})
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PERMISSION_DENIED)
	# 客户端也不能生成权威玩家（返回 null）。
	assert_object(s.handle_spawn_request(1)).is_null()

# ---------------------------------------------------------------------------
# 补充：validate_no_trusted_fields 单元级——所有被禁字段逐一拒绝（穷举护栏）。
# ---------------------------------------------------------------------------
func test_all_forbidden_trusted_fields_rejected() -> void:
	for f in CV.FORBIDDEN_TRUSTED_FIELDS:
		var cmd := {"type": NP.CMD_INPUT}
		cmd[f] = 1
		assert_bool(CV.validate_no_trusted_fields(cmd)) \
			.override_failure_message("字段 '%s' 应被识别为服务器权威字段并拒绝" % f).is_false()
	# 合法标识符字段（target_hint / item_id / slot / skill_id）不应被误伤。
	assert_bool(CV.validate_no_trusted_fields({"type": NP.CMD_ATTACK, "target_hint": 42})).is_true()
