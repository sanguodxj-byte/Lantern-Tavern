extends GdUnitTestSuite

## ConnectionAuthority（§13 断线/重连）纯逻辑单测。

const CA := preload("res://globals/multiplayer/connection_authority.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func _make() -> CA:
	return auto_free(CA.new())

# ---------------------------------------------------------------------------
# token 派生
# ---------------------------------------------------------------------------

func test_token_is_deterministic() -> void:
	var ca := _make()
	var a: String = ca.generate_token(1, 0.0)
	var b: String = ca.generate_token(1, 0.0)
	assert_str(a).is_equal(b)
	assert_int(a.length()).is_greater(0)

func test_token_depends_on_peer_and_salt() -> void:
	var ca := _make()
	assert_str(ca.generate_token(1, 0.0)).is_not_equal(ca.generate_token(2, 0.0))
	assert_str(ca.generate_token(1, 0.0)).is_not_equal(ca.generate_token(1, 5.0))

# ---------------------------------------------------------------------------
# 注册 / 状态
# ---------------------------------------------------------------------------

func test_register_online_sets_status() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	assert_str(ca.get_status(1)).is_equal(CA.STATUS_ONLINE)
	assert_bool(ca.is_online(1)).is_true()
	assert_str(ca.get_player_guid(1)).is_equal("player_001")

func test_unknown_peer_has_empty_status() -> void:
	var ca := _make()
	assert_str(ca.get_status(99)).is_equal("")
	assert_bool(ca.is_online(99)).is_false()

# ---------------------------------------------------------------------------
# 断线 → GRACE
# ---------------------------------------------------------------------------

func test_disconnect_moves_to_grace_and_issues_token() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	var res: Dictionary = ca.on_disconnect(1, 0.0)
	assert_bool(res["was_tracked"]).is_true()
	assert_str(res["token"]).is_not_equal("")
	assert_str(ca.get_status(1)).is_equal(CA.STATUS_GRACE)
	# token 有效期 = 断线时刻 + 60s
	assert_float(ca._peers[1]["token_expiry"]).is_equal_approx(60.0, 0.001)

func test_disconnect_unknown_peer_not_tracked() -> void:
	var ca := _make()
	var res: Dictionary = ca.on_disconnect(42, 0.0)
	assert_bool(res["was_tracked"]).is_false()
	assert_str(res["token"]).is_equal("")

# ---------------------------------------------------------------------------
# 重连校验
# ---------------------------------------------------------------------------

func test_resume_with_valid_token_succeeds() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	var tok: String = ca.on_disconnect(1, 0.0)["token"]
	var res: Dictionary = ca.resume(1, tok, 5.0)
	assert_bool(res["ok"]).is_true()
	assert_str(res["player_guid"]).is_equal("player_001")
	assert_str(ca.get_status(1)).is_equal(CA.STATUS_ONLINE)

func test_resume_with_wrong_token_rejected() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	ca.on_disconnect(1, 0.0)
	var res: Dictionary = ca.resume(1, "not-the-token", 5.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_TOKEN_INVALID)

func test_resume_with_expired_token_rejected() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	var tok: String = ca.on_disconnect(1, 0.0)["token"]
	# 超过 GRACE_PERIOD(60s) → 过期
	var res: Dictionary = ca.resume(1, tok, 61.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_TOKEN_EXPIRED)

func test_resume_within_grace_window_ok() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	var tok: String = ca.on_disconnect(1, 0.0)["token"]
	# 正好在 60s 内（边界含）
	var res: Dictionary = ca.resume(1, tok, 59.9)
	assert_bool(res["ok"]).is_true()

func test_resume_unknown_peer_rejected() -> void:
	var ca := _make()
	var res: Dictionary = ca.resume(7, "tok", 0.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_PEER_UNKNOWN)

func test_resume_online_peer_invalid() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	# 仍在 ONLINE（未断线）却发来 token → 视为非法
	var res: Dictionary = ca.resume(1, "tok", 0.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_TOKEN_INVALID)

# ---------------------------------------------------------------------------
# 稳定身份索引（§14.2）：按 guid/token 反查 GRACE 条目，绕过会变的 peer_id
# ---------------------------------------------------------------------------

func test_find_grace_peer_by_guid_returns_old_peer() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	ca.on_disconnect(3, 0.0)
	# 重连时 ENet 分配了新 peer_id，但 guid 仍锚定旧条目
	assert_int(ca.find_grace_peer_by_guid("player_alpha")).is_equal(3)
	# 未知 guid → 0
	assert_int(ca.find_grace_peer_by_guid("nope")).is_equal(0)

func test_find_grace_peer_by_token_returns_old_peer() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	var tok: String = ca.on_disconnect(3, 0.0)["token"]
	# 即便客户端遗失 guid，仅凭 token 也能定位 GRACE 条目
	assert_int(ca.find_grace_peer_by_token(tok)).is_equal(3)
	assert_int(ca.find_grace_peer_by_token("bogus")).is_equal(0)

func test_validate_reconnect_by_guid_succeeds_with_new_peer() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	var tok: String = ca.on_disconnect(3, 0.0)["token"]
	# 重连用新 peer_id（9），以 guid 锚定旧条目
	var res: Dictionary = ca.validate_reconnect_by_guid("player_alpha", tok, 5.0)
	assert_bool(res["ok"]).is_true()
	assert_int(res["peer_id"]).is_equal(3)

func test_validate_reconnect_by_guid_wrong_token_rejected() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	ca.on_disconnect(3, 0.0)
	var res: Dictionary = ca.validate_reconnect_by_guid("player_alpha", "bad", 5.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_TOKEN_INVALID)

func test_validate_reconnect_by_guid_expired_rejected() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	var tok: String = ca.on_disconnect(3, 0.0)["token"]
	var res: Dictionary = ca.validate_reconnect_by_guid("player_alpha", tok, 61.0)
	assert_bool(res["ok"]).is_false()
	assert_str(res["reason"]).is_equal(NP.ERR_RECONNECT_TOKEN_EXPIRED)

func test_migrate_peer_moves_entry_to_new_peer_id() -> void:
	var ca := _make()
	ca.register_online(3, "player_alpha", 0.0)
	ca.on_disconnect(3, 0.0)
	# 重连接管：旧 3 → 新 9
	ca.migrate_peer(3, 9)
	assert_bool(ca._peers.has(3)).is_false()
	assert_bool(ca._peers.has(9)).is_true()
	assert_str(ca.get_status(9)).is_equal(CA.STATUS_GRACE)
	# guid 索引改指新 peer_id
	assert_int(ca.find_grace_peer_by_guid("player_alpha")).is_equal(9)
	# 同一 token 仍有效（条目整体迁移）
	var tok: String = ca._peers[9]["token"]
	assert_int(ca.find_grace_peer_by_token(tok)).is_equal(9)

# ---------------------------------------------------------------------------
# 主动离开
# ---------------------------------------------------------------------------

func test_leave_marks_left() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	assert_bool(ca.on_leave(1)).is_true()
	assert_str(ca.get_status(1)).is_equal(CA.STATUS_LEFT)

func test_leave_unknown_peer_false() -> void:
	var ca := _make()
	assert_bool(ca.on_leave(99)).is_false()

# ---------------------------------------------------------------------------
# 心跳 / 超时
# ---------------------------------------------------------------------------

func test_heartbeat_refreshes_last_seen() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	assert_bool(ca.check_timeout(1, 10.0)).is_false()  # 10s < 15s 超时
	assert_bool(ca.check_timeout(1, 16.0)).is_true()   # 16s > 15s 超时

func test_touch_updates_last_seen() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	ca.touch(1, 100.0)
	assert_bool(ca.check_timeout(1, 110.0)).is_false()
	assert_bool(ca.check_timeout(1, 116.0)).is_true()

func test_check_timeout_ignores_grace_peer() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	ca.on_disconnect(1, 0.0)
	# GRACE 状态下不计入心跳超时
	assert_bool(ca.check_timeout(1, 999.0)).is_false()

# ---------------------------------------------------------------------------
# GRACE 超时清理
# ---------------------------------------------------------------------------

func test_collect_expired_grace() -> void:
	var ca := _make()
	ca.register_online(1, "p1", 0.0)
	ca.register_online(2, "p2", 0.0)
	ca.on_disconnect(1, 0.0)
	ca.on_disconnect(2, 0.0)
	# 60s 内不应清理
	assert_array(ca.collect_expired_grace(59.0)).is_empty()
	# 超过 60s 应列出两个
	var expired: Array = ca.collect_expired_grace(61.0)
	assert_int(expired.size()).is_equal(2)

# ---------------------------------------------------------------------------
# 房主断线 → 结束房间
# ---------------------------------------------------------------------------

func test_host_disconnect_ends_room() -> void:
	var ca := _make()
	ca.host_peer_id = 1
	assert_bool(ca.should_end_room_on_disconnect(1)).is_true()

func test_non_host_disconnect_does_not_end_room() -> void:
	var ca := _make()
	ca.host_peer_id = 1
	assert_bool(ca.should_end_room_on_disconnect(2)).is_false()

# ---------------------------------------------------------------------------
# spawn 时预签发稳定 token（供客户端在断线前缓存）
# ---------------------------------------------------------------------------

func test_issue_token_at_spawn_is_stable_across_disconnect() -> void:
	var ca := _make()
	ca.register_online(1, "player_001", 0.0)
	var spawned: String = ca.issue_token(1, 0.0)
	assert_str(spawned).is_not_equal("")
	# 断线时复用 spawn 时签发的 token（不再重新派生）→ 客户端缓存的 token 仍可重连
	var dis: Dictionary = ca.on_disconnect(1, 50.0)
	assert_str(dis["token"]).is_equal(spawned)

func test_issue_token_returns_empty_for_unknown_peer() -> void:
	var ca := _make()
	assert_str(ca.issue_token(99, 0.0)).is_equal("")

# ---------------------------------------------------------------------------
# online_peer_ids（心跳超时扫描）
# ---------------------------------------------------------------------------

func test_online_peer_ids_lists_only_online() -> void:
	var ca := _make()
	ca.register_online(1, "p1", 0.0)
	ca.register_online(2, "p2", 0.0)
	ca.on_disconnect(1, 0.0)  # 1 进入 GRACE
	assert_array(ca.online_peer_ids()).contains_exactly([2])
