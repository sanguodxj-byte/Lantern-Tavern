extends GdUnitTestSuite

## SaveAuthority 测试（docs/25 §14 存档设计 + §17.4 安全测试）。
## 纯逻辑层：出征结算幂等账本（按 player_guid 锚定），防「重复 extract/save 刷物品」。

const SA := preload("res://globals/multiplayer/save_authority.gd")

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func test_init_empty() -> void:
	var s: SA = auto_free(SA.new())
	assert_int(s.expedition_revision).is_equal(0)
	assert_bool(s.is_settled("player_001")).is_false()
	assert_dict(s.get_settlement("player_001")).is_empty()

# ---------------------------------------------------------------------------
# 首次结算 / 幂等
# ---------------------------------------------------------------------------

func test_first_settle_records_and_returns_true() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	var settlement := {"materials": {"iron": 3}, "runes": {}, "equipment": {}}
	var newly: bool = s.mark_settled("player_001", settlement)
	assert_bool(newly).is_true()
	assert_bool(s.is_settled("player_001")).is_true()
	assert_dict(s.get_settlement("player_001")).is_equal(settlement)

func test_repeat_settle_is_idempotent() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	var first := {"materials": {"iron": 3}, "runes": {}, "equipment": {}}
	assert_bool(s.mark_settled("player_001", first)).is_true()
	# 第二次（哪怕内容不同）应被拒绝为幂等 no-op，且缓存仍是首次结算。
	var second := {"materials": {"iron": 99}, "runes": {}, "equipment": {}}
	assert_bool(s.mark_settled("player_001", second)).is_false()
	assert_dict(s.get_settlement("player_001")).is_equal(first)

func test_settlement_is_deep_copied() -> void:
	# mark_settled 深拷贝：外部后续修改原字典不污染账本。
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	var settlement := {"materials": {"iron": 3}, "runes": {}, "equipment": {}}
	s.mark_settled("player_001", settlement)
	(settlement["materials"] as Dictionary)["iron"] = 999
	assert_int(int((s.get_settlement("player_001")["materials"] as Dictionary)["iron"])).is_equal(3)

func test_empty_guid_never_settles() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	assert_bool(s.mark_settled("", {"materials": {}})).is_false()
	assert_bool(s.is_settled("")).is_false()

# ---------------------------------------------------------------------------
# 多玩家隔离
# ---------------------------------------------------------------------------

func test_per_guid_isolation() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	s.mark_settled("player_001", {"materials": {"iron": 1}})
	assert_bool(s.is_settled("player_001")).is_true()
	assert_bool(s.is_settled("player_002")).is_false()
	# player_002 仍可独立结算一次。
	assert_bool(s.mark_settled("player_002", {"materials": {"gold": 2}})).is_true()

# ---------------------------------------------------------------------------
# 新出征重置账本
# ---------------------------------------------------------------------------

func test_new_expedition_resets_ledger() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(1)
	s.mark_settled("player_001", {"materials": {"iron": 3}})
	assert_bool(s.is_settled("player_001")).is_true()
	# 开新出征后账本清空，同一玩家可再结算一次（新 run 的净获得）。
	s.begin_expedition(2)
	assert_bool(s.is_settled("player_001")).is_false()
	assert_bool(s.mark_settled("player_001", {"materials": {"iron": 5}})).is_true()

func test_begin_expedition_auto_increment() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition()
	assert_int(s.expedition_revision).is_equal(1)
	s.begin_expedition()
	assert_int(s.expedition_revision).is_equal(2)

func test_stale_revision_record_not_settled() -> void:
	# revision 前进后，旧 revision 记录视为未结算（幂等只在同一 run 内生效）。
	var s: SA = auto_free(SA.new())
	s.begin_expedition(5)
	s.mark_settled("player_001", {"materials": {"iron": 1}})
	s.expedition_revision = 6  # 模拟错位（正常应走 begin_expedition）
	assert_bool(s.is_settled("player_001")).is_false()
	assert_dict(s.get_settlement("player_001")).is_empty()

# ---------------------------------------------------------------------------
# 重连快照序列化（防断线重连绕过幂等）
# ---------------------------------------------------------------------------

func test_serialize_deserialize_preserves_settled() -> void:
	var s: SA = auto_free(SA.new())
	s.begin_expedition(3)
	s.mark_settled("player_001", {"materials": {"iron": 7}, "runes": {}, "equipment": {}})
	var blob: Dictionary = s.serialize()
	var s2: SA = auto_free(SA.new())
	s2.deserialize(blob)
	assert_int(s2.expedition_revision).is_equal(3)
	assert_bool(s2.is_settled("player_001")).is_true()
	# 重连后再结算应被幂等拒绝。
	assert_bool(s2.mark_settled("player_001", {"materials": {"iron": 100}})).is_false()

func test_deserialize_null_safe() -> void:
	var s: SA = auto_free(SA.new())
	s.deserialize({})
	assert_int(s.expedition_revision).is_equal(0)
	assert_bool(s.is_settled("player_001")).is_false()
