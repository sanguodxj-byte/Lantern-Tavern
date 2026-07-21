extends GdUnitTestSuite

# CommandValidator（docs/25 §5.2/§11/§12）：协议版本、world_revision、距离、冷却、序列去重。

const CV := preload("res://globals/multiplayer/command_validator.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func test_validate_protocol() -> void:
	assert_bool(CV.validate_protocol(NP.PROTOCOL_VERSION)).is_true()
	assert_bool(CV.validate_protocol(999)).is_false()

func test_validate_world_revision() -> void:
	assert_bool(CV.validate_world_revision(12, 12)).is_true()
	assert_bool(CV.validate_world_revision(11, 12)).is_false()

func test_validate_range() -> void:
	var a = Vector3(0, 0, 0)
	var b = Vector3(3, 0, 4)  # dist 5
	assert_bool(CV.validate_range(a, b, 5.0)).is_true()
	assert_bool(CV.validate_range(a, b, 4.0)).is_false()

func test_validate_cooldown() -> void:
	assert_bool(CV.validate_cooldown(0.0)).is_true()
	assert_bool(CV.validate_cooldown(-1.0)).is_true()
	assert_bool(CV.validate_cooldown(0.5)).is_false()

# ---------------------------------------------------------------------------
# Phase 2.3: 反作弊「服务器权威字段」守卫
# ---------------------------------------------------------------------------

func test_validate_no_trusted_fields_accepts_clean_command() -> void:
	var cmd := {"type": NP.CMD_SKILL, "skill_id": "fireball", "sequence": 1}
	assert_bool(CV.validate_no_trusted_fields(cmd)).is_true()

func test_validate_no_trusted_fields_rejects_each_forbidden() -> void:
	# 逐一验证每个被禁字段都会触发拒绝（穿墙 / 秒杀 / 无限资源等作弊的根防）
	for f in CV.FORBIDDEN_TRUSTED_FIELDS:
		var cmd := {"type": NP.CMD_INPUT, f: 1}
		assert_bool(CV.validate_no_trusted_fields(cmd)).is_false()

func test_validate_no_trusted_fields_allows_identifiers() -> void:
	# 标识符（只是指向服务器权威数据的键）允许携带：target_hint / item_id / slot / skill_id
	var cmd := {"type": NP.CMD_PICKUP, "target_entity_id": 5, "item_id": "x", "slot": 0, "skill_id": "y"}
	assert_bool(CV.validate_no_trusted_fields(cmd)).is_true()

func test_sequence_tracker_accepts_increasing() -> void:
	var st = auto_free(CV.SequenceTracker.new())
	assert_bool(st.accept(1, 1)).is_true()
	assert_bool(st.accept(1, 2)).is_true()
	assert_bool(st.accept(1, 3)).is_true()

func test_sequence_tracker_rejects_replay_and_old() -> void:
	var st = auto_free(CV.SequenceTracker.new())
	st.accept(1, 5)
	assert_bool(st.accept(1, 5)).is_false()  # 重复
	assert_bool(st.accept(1, 4)).is_false()  # 旧序列
	assert_bool(st.accept(1, 6)).is_true()   # 更新

func test_sequence_tracker_per_peer() -> void:
	var st = auto_free(CV.SequenceTracker.new())
	st.accept(1, 5)
	assert_bool(st.accept(2, 1)).is_true()  # 不同 peer 独立
