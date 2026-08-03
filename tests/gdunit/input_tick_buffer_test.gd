extends GdUnitTestSuite

## SessionRoot 固定 tick 输入缓冲（架构审查 P0-2）：
##   * queue_input 只保留 per-peer 最新一帧（洪泛不累积）；
##   * consume_input_tick 每 tick 每 peer 恰消费一次（输入频率与权威位移解耦）；
##   * 相同输入在 30/60/120Hz 上送频率下产生相同的权威位移（频率无关性）；
##   * 被更新命令取代的旧序列帧静默跳过（不产生拒绝事件、不破坏序列）。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const MA := preload("res://globals/multiplayer/movement_authority.gd")

func _make_server() -> SR:
	var s: SR = SR.new()
	add_child(s)
	s.init_server()
	return s

func _input_cmd(s: SR, move_x: float, move_y: float, sequence: int) -> Dictionary:
	return {
		"type": NP.CMD_INPUT, "move": [move_x, move_y], "sprint": false,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": sequence,
	}

func test_queue_input_only_accepts_online_peer_on_server() -> void:
	var s: SR = auto_free(_make_server())
	assert_bool(s.queue_input(1, _input_cmd(s, 1.0, 0.0, 1))).is_false()  # 未 spawn
	s.handle_spawn_request(1)
	assert_bool(s.queue_input(1, _input_cmd(s, 1.0, 0.0, 1))).is_true()
	assert_int(s.pending_input_count()).is_equal(1)

func test_consume_input_tick_processes_one_frame_per_peer() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.handle_spawn_request(2)
	# 每个 peer 洪泛 10 帧 → 缓冲只保留最新一帧。
	for i in range(1, 11):
		s.queue_input(1, _input_cmd(s, 1.0, 0.0, i))
	for i in range(1, 11):
		s.queue_input(2, _input_cmd(s, 0.0, 1.0, i))
	assert_int(s.pending_input_count()).is_equal(2)
	# 一个 tick 消费：每 peer 恰好处理最新一帧（10 帧洪泛不产生 10 次位移）。
	var results: Array = s.consume_input_tick()
	assert_int(results.size()).is_equal(2)
	assert_int(s.pending_input_count()).is_equal(0)
	for item in results:
		assert_bool(bool(item["result"]["success"])).is_true()

func test_input_frequency_independence_30hz_vs_120hz() -> void:
	# 相同总时间内的权威位移必须只由服务器 tick 数决定，与客户端上送频率无关。
	var s1: SR = auto_free(_make_server())
	s1.handle_spawn_request(1)
	var s2: SR = auto_free(_make_server())
	s2.handle_spawn_request(1)
	var dt: float = SR.SERVER_TICK_DT
	var ticks: int = 10
	# 30Hz：每个 tick 恰一帧。
	for t in range(1, ticks + 1):
		s1.queue_input(1, _input_cmd(s1, 1.0, 0.0, t))
		s1.consume_input_tick()
	# 120Hz 洪泛：每个 tick 之间塞 4 帧，缓冲只保留最新。
	var seq: int = 0
	for t in range(1, ticks + 1):
		for _f in range(4):
			seq += 1
			s2.queue_input(1, _input_cmd(s2, 1.0, 0.0, seq))
		s2.consume_input_tick()
	var p1: Vector3 = s1._live_state[1]["position"]
	var p2: Vector3 = s2._live_state[1]["position"]
	var expect: float = MA.BASE_SPEED * dt * float(ticks)
	assert_float(p1.x).is_equal_approx(expect, 1e-4)
	# 关键：120Hz 洪泛的位移与 30Hz 一致（按 RPC 次数积分已根除）。
	assert_float(p2.x).is_equal_approx(p1.x, 1e-4)
	assert_float(p2.x).is_less(expect * 1.05)

func test_superseded_stale_frame_skipped_silently() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	# 帧 1 入缓冲，但攻击命令（seq=2）先被即时消费 → 帧 1 已成陈旧输入。
	s.queue_input(1, _input_cmd(s, 1.0, 0.0, 1))
	var atk := {"type": NP.CMD_SKILL, "skill_id": "x", "protocol_version": 1,
		"world_revision": s.world.world_revision, "sequence": 2}
	s.router.register_handler(NP.CMD_SKILL, func(cmd, ctx):
		s._seq_tracker.accept(1, int(cmd.get("sequence", 0)))
		return {"success": true, "event": {}, "error_code": ""})
	s.on_command(1, atk)
	var before: Vector3 = s._live_state[1]["position"]
	# 消费陈旧帧：不得报错、不得位移、不产生任何事件。
	var results: Array = s.consume_input_tick()
	assert_int(results.size()).is_equal(1)
	assert_bool(bool(results[0]["result"]["success"])).is_false()
	assert_str(results[0]["result"]["error_code"]).is_equal(NP.ERR_INVALID_SEQUENCE)
	assert_float(s._live_state[1]["position"].x).is_equal_approx(before.x, 1e-6)
	# 后续合法新帧（seq=3）仍可正常消费（序列未被陈旧帧锁死）。
	s.queue_input(1, _input_cmd(s, 1.0, 0.0, 3))
	s.consume_input_tick()
	assert_float(s._live_state[1]["position"].x).is_greater(before.x)

func test_input_buffer_cleared_on_peer_disconnect() -> void:
	var s: SR = auto_free(_make_server())
	s.handle_spawn_request(1)
	s.queue_input(1, _input_cmd(s, 1.0, 0.0, 1))
	s.handle_peer_left(1)
	# 已注销 peer 的 pending 输入不得再被消费（无 ctx 静默跳过）。
	var results: Array = s.consume_input_tick()
	assert_int(results.size()).is_equal(0)
	assert_int(s.pending_input_count()).is_equal(0)
