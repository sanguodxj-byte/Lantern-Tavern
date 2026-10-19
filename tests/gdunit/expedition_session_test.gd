extends GdUnitTestSuite

# 远征会话连续性测试（架构审查 1215 C1/C2/C3，G2 白名单）：
# 跨层保留压力时钟/暗蚀 + 玩家生命/buff；清除战斗瞬态；序列化 round-trip。

const ExpeditionSession = preload("res://globals/expedition/expedition_session.gd")
const ExplorationPressure = preload("res://globals/dungeon/exploration_pressure.gd")
const HealthComponentScript = preload("res://scenes/characters/component/health_component.gd")
const CombatBuffComponent = preload("res://scenes/characters/component/combat_buff_component.gd")

## 最小玩家替身：health 为 HealthComponent 属性、buffs 为 CombatBuffComponent 属性。
class MockPlayer:
	extends Node
	var health: HealthComponent = null
	var buffs = null


func _make_player(current_life: int, max_life: int, buffs_dict: Dictionary = {}) -> Node:
	var player: MockPlayer = auto_free(MockPlayer.new())
	var health: HealthComponent = auto_free(HealthComponentScript.new())
	health.max_life = max_life
	health.current_life = current_life
	player.health = health
	var buffs := CombatBuffComponent.new()
	for buff_type in buffs_dict.keys():
		var buff: Dictionary = buffs_dict[buff_type]
		buffs.add(String(buff_type), float(buff.get("remaining", 0.0)), buff.get("value", null))
	player.buffs = buffs
	return player


# ---------- 压力捕获/恢复 ----------

func test_pressure_capture_restore_roundtrip() -> void:
	var src: ExplorationPressure = auto_free(ExplorationPressure.new())
	src.elapsed_minutes = 240
	src.threat_level = 63.5
	src.opened_doors = 4
	src.broken_doors = 1
	src.set("_recommendation_sent", true)

	var session = ExpeditionSession.new()
	session.capture_pressure_from(src)

	var dst: ExplorationPressure = auto_free(ExplorationPressure.new())
	session.restore_pressure_to(dst)
	assert_int(dst.elapsed_minutes).is_equal(240)
	assert_float(dst.threat_level).is_equal_approx(63.5, 0.001)
	assert_int(dst.opened_doors).is_equal(4)
	assert_int(dst.broken_doors).is_equal(1)
	assert_bool(dst.get("_recommendation_sent")).is_true()
	assert_bool(dst.get("_overtime_sent")).is_false()


func test_pressure_capture_from_null_keeps_empty() -> void:
	var session = ExpeditionSession.new()
	session.capture_pressure_from(null)
	assert_bool(session.pressure_state.is_empty()).is_true()


func test_pressure_restore_to_null_is_noop() -> void:
	var session = ExpeditionSession.new()
	session.pressure_state = {"elapsed_minutes": 10}
	session.restore_pressure_to(null)  # 不应崩溃


# ---------- 玩家资源捕获/恢复 ----------

func test_player_capture_restore_roundtrip() -> void:
	var src := _make_player(77, 155, {"arcane_shield": {"remaining": 12.0, "value": 3}})
	var session = ExpeditionSession.new()
	session.capture_player_from(src)

	var dst := _make_player(155, 155)
	session.restore_player_to(dst)
	assert_int(dst.health.current_life).is_equal(77)
	assert_bool(dst.buffs.has("arcane_shield")).is_true()
	assert_float(float(dst.buffs.get_value("arcane_shield"))).is_equal_approx(3.0, 0.001)


func test_player_restore_clamps_to_new_max_life() -> void:
	var src := _make_player(999, 999)
	var session = ExpeditionSession.new()
	session.capture_player_from(src)

	var dst := _make_player(155, 155)
	session.restore_player_to(dst)
	assert_int(dst.health.current_life).is_equal(155)


func test_player_capture_from_null_keeps_empty() -> void:
	var session = ExpeditionSession.new()
	session.capture_player_from(null)
	assert_bool(session.player_transition_state.is_empty()).is_true()


func test_transient_runtime_state_is_not_copied() -> void:
	# G2 白名单：玩家战斗运行时（冷却/二段跳/格挡残影）不进入会话。
	var src := _make_player(100, 155)
	var runtime_stub: Node = auto_free(Node.new())
	src.set("combat_runtime", runtime_stub)
	var session = ExpeditionSession.new()
	session.capture_player_from(src)
	assert_bool(session.player_transition_state.has("combat_runtime")).is_false()
	assert_bool(session.player_transition_state.has("flurry_storm_timer")).is_false()


# ---------- 序列化 ----------

func test_to_dict_from_dict_roundtrip() -> void:
	var session = ExpeditionSession.new()
	session.active = true
	session.zone = 2
	session.floor = 3
	session.pressure_state = {"elapsed_minutes": 120, "threat_level": 40.0}
	var player := _make_player(60, 155, {"spell_power": {"remaining": 8.0, "value": 1.2}})
	session.capture_player_from(player)

	var restored = ExpeditionSession.new()
	restored.from_dict(session.to_dict())

	assert_bool(restored.active).is_true()
	assert_int(restored.zone).is_equal(2)
	assert_int(restored.floor).is_equal(3)
	assert_int(int(restored.pressure_state.get("elapsed_minutes", 0))).is_equal(120)
	assert_float(float(restored.pressure_state.get("threat_level", 0.0))).is_equal_approx(40.0, 0.001)
	var buffs: Dictionary = restored.player_transition_state.get("buffs", {})
	assert_bool(buffs.has("spell_power")).is_true()
	assert_float(float((buffs["spell_power"] as Dictionary).get("remaining", 0.0))).is_equal_approx(8.0, 0.001)


func test_to_dict_is_json_serializable() -> void:
	var session = ExpeditionSession.new()
	session.active = true
	session.pressure_state = {"elapsed_minutes": 5, "threat_level": 1.5}
	var player := _make_player(50, 155, {"dmg_buff": {"remaining": 3.0, "value": {"percent": 0.2}}})
	session.capture_player_from(player)
	var json := JSON.new()
	assert_int(json.parse(JSON.stringify(session.to_dict()))).is_equal(OK)


func test_from_dict_inactive_keeps_defaults() -> void:
	var session = ExpeditionSession.new()
	session.from_dict({"active": false})
	assert_bool(session.active).is_false()
	assert_bool(session.pressure_state.is_empty()).is_true()


func test_clear_resets_all() -> void:
	var session = ExpeditionSession.new()
	session.active = true
	session.pressure_state = {"elapsed_minutes": 9}
	session.capture_player_from(_make_player(10, 155))
	session.clear()
	assert_bool(session.active).is_false()
	assert_bool(session.pressure_state.is_empty()).is_true()
	assert_bool(session.player_transition_state.is_empty()).is_true()
