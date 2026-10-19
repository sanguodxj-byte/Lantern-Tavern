extends GdUnitTestSuite

## A2（架构审查 P0）纯逻辑测试：EnemyCombatAuthority 从敌人实体 data（或可配置 profile）
## 派生攻击参数（射程/间隔/伤害），绝不在会话层硬编码；带视线遮挡检查（注入 ray_query 端口，
## 无物理世界依赖）；每敌人独立 next_attack_at 攻击节奏。
##
## 契约：
##   * decide_attack(data, players, now) 为纯函数——【不修改 data】；调用方负责把返回的
##     next_attack_at 写回实体 data（SessionRoot.tick_enemy_combat 每 tick 写回）。
##   * 攻击参数读取优先级：data.attack_* > data.attack_profile.attack_* > 构造注入 profile > 默认。

const ECA := preload("res://globals/multiplayer/enemy_combat_authority.gd")

## 最小敌人 data（kind=enemy + 位置 + 攻击节奏），extra 覆盖/追加字段。
func _enemy(pos: Vector3, extra: Dictionary = {}) -> Dictionary:
	var data := {"kind": "enemy", "current_life": 100, "max_life": 100,
		"position": pos, "next_attack_at": 0.0}
	for k in extra.keys():
		data[k] = extra[k]
	return data

func _player(peer_id: int, pos: Vector3, alive: bool = true) -> Dictionary:
	return {"peer_id": peer_id, "position": pos, "is_alive": alive}

## 无障碍 stub：命中字典为空 → 视线畅通。
func _clear_ray(_from: Vector3, _to: Vector3) -> Dictionary:
	return {}

## 有遮挡 stub：命中字典非空 → 视线被挡。
func _blocked_ray(_from: Vector3, _to: Vector3) -> Dictionary:
	return {"collider": RefCounted.new()}

# ---------------------------------------------------------------------------
# 射程：来自实体 data，而非会话常量（旧常量 1.8）
# ---------------------------------------------------------------------------

func test_attack_range_derived_from_entity_data_not_constant() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {"attack_range": 3.0})
	# 距 2.5m（旧常量 1.8 必拒；data 3.0 必须命中）。
	assert_int(auth.select_target(data, [_player(1, Vector3(2.5, 0, 0))])) \
		.override_failure_message("射程必须来自实体 data（3.0），2.5m 玩家应被选中").is_equal(1)
	# 距 3.5m（超出 data 射程）→ 不命中。
	assert_int(auth.select_target(data, [_player(1, Vector3(3.5, 0, 0))])).is_equal(0)

func test_attack_range_falls_back_to_configured_profile() -> void:
	var auth: ECA = ECA.new({"attack_range": 5.0})
	var data: Dictionary = _enemy(Vector3.ZERO)
	# 4m 玩家命中（profile 5.0，旧常量 1.8 必拒）；6m 超出。
	assert_int(auth.select_target(data, [_player(1, Vector3(4.0, 0, 0))])).is_equal(1)
	assert_int(auth.select_target(data, [_player(1, Vector3(6.0, 0, 0))])).is_equal(0)

func test_attack_range_defaults_when_no_data_or_profile() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO)
	assert_int(auth.select_target(data, [_player(1, Vector3(1.5, 0, 0))])).is_equal(1)
	assert_int(auth.select_target(data, [_player(1, Vector3(2.5, 0, 0))])).is_equal(0)

func test_nearest_player_within_range_is_selected() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {"attack_range": 4.0})
	var players := [_player(1, Vector3(3.5, 0, 0)), _player(2, Vector3(1.0, 0, 0))]
	assert_int(auth.select_target(data, players)).is_equal(2)

# ---------------------------------------------------------------------------
# 视线遮挡：ray_query stub 注入（无物理世界）
# ---------------------------------------------------------------------------

func test_occlusion_blocks_attack_when_ray_hits_obstruction() -> void:
	var auth: ECA = ECA.new()
	auth.ray_query = _blocked_ray
	var data: Dictionary = _enemy(Vector3.ZERO)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_bool(bool(dec.get("attack", true))) \
		.override_failure_message("视线被遮挡时敌人不得攻击").is_false()
	assert_int(int(dec.get("target_peer", -1))).is_equal(0)

func test_clear_line_of_sight_allows_attack() -> void:
	var auth: ECA = ECA.new()
	auth.ray_query = _clear_ray
	var data: Dictionary = _enemy(Vector3.ZERO)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_bool(bool(dec.get("attack", false))).is_true()
	assert_int(int(dec.get("target_peer", 0))).is_equal(1)

func test_no_ray_query_defaults_to_clear_line_of_sight() -> void:
	# 未接线 ray_query 时（纯逻辑最小调用）视为无遮挡，保持旧行为不回归。
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_bool(bool(dec.get("attack", false))).is_true()

# ---------------------------------------------------------------------------
# 攻击节奏：每敌人独立 next_attack_at（实体 data 字段，服务器时间秒）
# ---------------------------------------------------------------------------

func test_interval_cadence_per_enemy() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {"attack_interval": 2.0})
	var players := [_player(1, Vector3(1, 0, 0))]
	# t=0 首次攻击 → 下次攻击时刻 = 0 + 2.0。
	var dec: Dictionary = auth.decide_attack(data, players, 0.0)
	assert_bool(bool(dec.get("attack", false))).is_true()
	assert_float(float(dec.get("next_attack_at", -1.0))) \
		.override_failure_message("下次攻击时刻 = now + 实体 interval(2.0)").is_equal(2.0)
	# 调用方写回节奏（SessionRoot.tick_enemy_combat 每 tick 写回）。
	data["next_attack_at"] = float(dec["next_attack_at"])
	# 未到点（t=1.0）→ 不攻击。
	var early: Dictionary = auth.decide_attack(data, players, 1.0)
	assert_bool(bool(early.get("attack", true))).is_false()
	# 到点（t=2.0）→ 再次攻击。
	var again: Dictionary = auth.decide_attack(data, players, 2.0)
	assert_bool(bool(again.get("attack", false))).is_true()

func test_two_enemies_have_independent_intervals() -> void:
	var auth: ECA = ECA.new()
	var fast: Dictionary = _enemy(Vector3.ZERO, {"attack_interval": 1.0})
	var slow: Dictionary = _enemy(Vector3(0, 0, 1), {"attack_interval": 3.0})
	var players := [_player(1, Vector3(1, 0, 0))]
	var d_fast: Dictionary = auth.decide_attack(fast, players, 0.0)
	var d_slow: Dictionary = auth.decide_attack(slow, players, 0.0)
	assert_float(float(d_fast["next_attack_at"])).is_equal(1.0)
	assert_float(float(d_slow["next_attack_at"])).is_equal(3.0)

# ---------------------------------------------------------------------------
# 伤害：来自实体 data / profile，而非会话常量（旧常量 8）
# ---------------------------------------------------------------------------

func test_damage_derived_from_entity_data() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {"attack_damage": 12})
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_int(int(dec.get("damage", 0))) \
		.override_failure_message("伤害必须来自实体 data（12），而非常量").is_equal(12)

func test_damage_falls_back_to_configured_profile() -> void:
	var auth: ECA = ECA.new({"attack_damage": 5})
	var data: Dictionary = _enemy(Vector3.ZERO)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_int(int(dec.get("damage", 0))).is_equal(5)

func test_damage_defaults_when_no_data_or_profile() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_int(int(dec.get("damage", 0))).is_equal(8)

# ---------------------------------------------------------------------------
# 嵌套 attack_profile（实体 data 内可携带整组攻击配置）
# ---------------------------------------------------------------------------

func test_params_read_from_nested_attack_profile() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {
		"attack_profile": {"attack_range": 4.0, "attack_interval": 3.0, "attack_damage": 9},
	})
	assert_int(auth.select_target(data, [_player(1, Vector3(3.5, 0, 0))])).is_equal(1)
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 1.0)
	assert_int(int(dec.get("damage", 0))).is_equal(9)
	assert_float(float(dec.get("next_attack_at", -1.0))).is_equal(4.0)

# ---------------------------------------------------------------------------
# 契约：decide_attack 为纯函数，不修改传入 data
# ---------------------------------------------------------------------------

func test_decide_attack_does_not_mutate_entity_data() -> void:
	var auth: ECA = ECA.new()
	var data: Dictionary = _enemy(Vector3.ZERO, {"attack_interval": 2.0})
	var next_before: float = float(data["next_attack_at"])
	var dec: Dictionary = auth.decide_attack(data, [_player(1, Vector3(1, 0, 0))], 0.0)
	assert_float(float(data["next_attack_at"])).is_equal(next_before)
	assert_float(float(dec["next_attack_at"])).is_equal(2.0)
