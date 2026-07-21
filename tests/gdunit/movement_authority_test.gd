extends GdUnitTestSuite

# Phase 4（docs/25 §6.2）：MovementAuthority 服务器移动权威。
# 服务器采样 input_frame，从输入积分出权威位置（绝不信任客户端坐标），产出 player_snapshot。
# 复用 per-peer 严格递增序列防重放。

const MovementAuthority := preload("res://globals/multiplayer/movement_authority.gd")
const CV := preload("res://globals/multiplayer/command_validator.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

const SERVER_REV := 100

func _live(peer_id: int = 1, alive: bool = true, pos: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"peer_id": peer_id, "is_alive": alive, "position": pos}

func _frame(seq: int, move: Array, world_rev: int = SERVER_REV, sprint: bool = false) -> Dictionary:
	return {
		"protocol_version": NP.PROTOCOL_VERSION,
		"world_revision": world_rev,
		"client_tick": 1000 + seq,
		"sequence": seq,
		"move": move,
		"look_yaw": 1.2,
		"look_pitch": -0.1,
		"jump": false,
		"sprint": sprint,
	}

func test_validate_rejects_bad_protocol() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	var f := _frame(1, [0.0, -1.0]); f["protocol_version"] = 99
	assert_str(ma.validate_input_frame(f, _live(), SERVER_REV, tr)).is_equal("INVALID_PROTOCOL")

func test_validate_rejects_wrong_world_revision() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	assert_str(ma.validate_input_frame(_frame(1, [0.0, -1.0], SERVER_REV + 1), _live(), SERVER_REV, tr)).is_equal("INVALID_WORLD_REVISION")

func test_validate_rejects_dead_player() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	assert_str(ma.validate_input_frame(_frame(1, [0.0, -1.0]), _live(1, false), SERVER_REV, tr)).is_equal("PLAYER_NOT_ALIVE")

func test_validate_rejects_non_array_move() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	var f := _frame(1, [0.0, -1.0]); f["move"] = "forward"
	assert_str(ma.validate_input_frame(f, _live(), SERVER_REV, tr)).is_equal("INVALID_STATE")

func test_validate_rejects_unnormalized_move() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	# 模长 > 1（客户端未归一化，可能用于速度作弊）
	assert_str(ma.validate_input_frame(_frame(1, [1.0, 1.0]), _live(), SERVER_REV, tr)).is_equal("INVALID_STATE")

func test_validate_rejects_out_of_range_component() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	assert_str(ma.validate_input_frame(_frame(1, [2.0, 0.0]), _live(), SERVER_REV, tr)).is_equal("INVALID_STATE")

func test_sequence_strictly_increasing_accepted_then_replay_rejected() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	assert_str(ma.validate_input_frame(_frame(1, [0.0, -1.0]), _live(), SERVER_REV, tr)).is_equal("")
	assert_str(ma.validate_input_frame(_frame(1, [0.0, -1.0]), _live(), SERVER_REV, tr)).is_equal("INVALID_SEQUENCE")
	# 更大序列恢复接受
	assert_str(ma.validate_input_frame(_frame(2, [0.0, -1.0]), _live(), SERVER_REV, tr)).is_equal("")

func test_invalid_move_does_not_consume_sequence() -> void:
	# 静态校验（move 越界）应在消费序列号之前，故后续合法帧仍可用同一序列号。
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	var bad := _frame(7, [2.0, 0.0])
	assert_str(ma.validate_input_frame(bad, _live(), SERVER_REV, tr)).is_equal("INVALID_STATE")
	# 序列号 7 未被消费，合法帧可继续
	assert_str(ma.validate_input_frame(_frame(7, [1.0, 0.0]), _live(), SERVER_REV, tr)).is_equal("")

func test_integrate_moves_in_input_direction() -> void:
	var ma = auto_free(MovementAuthority.new())
	var old := Vector3(0, 0, 0)
	var dt := 0.1
	# move=[0,-1] 对应 -Z 前进
	var new_pos: Vector3 = ma.integrate_position(old, Vector2(0.0, -1.0), dt, MovementAuthority.BASE_SPEED)
	assert_float(new_pos.x).is_equal_approx(0.0, 1e-4)
	assert_float(new_pos.z).is_equal_approx(-MovementAuthority.BASE_SPEED * dt, 1e-4)
	assert_float(new_pos.y).is_equal_approx(0.0, 1e-4)

func test_sprint_increases_distance() -> void:
	var ma = auto_free(MovementAuthority.new())
	var dt := 0.1
	var walk: Vector3 = ma.integrate_position(Vector3.ZERO, Vector2(1.0, 0.0), dt, MovementAuthority.BASE_SPEED)
	var run: Vector3 = ma.integrate_position(Vector3.ZERO, Vector2(1.0, 0.0), dt, MovementAuthority.BASE_SPEED * MovementAuthority.SPRINT_MULT)
	assert_float(run.x).is_greater(walk.x)

func test_resolve_produces_player_snapshot_event() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	var live := _live(1, true, Vector3(0, 0, 0))
	var out: Dictionary = ma.resolve_input_frame(_frame(1, [0.0, -1.0], SERVER_REV, false), live, SERVER_REV, tr)
	assert_bool(out["success"]).is_true()
	assert_str(out["event"]["event"]).is_equal(NP.EVT_PLAYER_SNAPSHOT)
	assert_int(int(out["event"]["peer_id"])).is_equal(1)
	assert_float(float(out["event"]["position"].z)).is_equal_approx(-MovementAuthority.BASE_SPEED * MovementAuthority.DEFAULT_TICK_DT, 1e-4)
	assert_float(float(out["event"]["look_yaw"])).is_equal_approx(1.2, 1e-4)

func test_resolve_rejects_dead_player_with_error_event() -> void:
	var ma = auto_free(MovementAuthority.new())
	var tr = CV.SequenceTracker.new()
	var out: Dictionary = ma.resolve_input_frame(_frame(1, [0.0, -1.0]), _live(1, false), SERVER_REV, tr)
	assert_bool(out["success"]).is_false()
	assert_str(out["error_code"]).is_equal("PLAYER_NOT_ALIVE")
