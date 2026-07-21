extends GdUnitTestSuite

# Phase 6（docs/25 §7/§5.2）：CombatAuthority 服务器权威战斗裁决。
# 包 DamageResolver，校验协议/修订/序列/存活，并应用扣血、产出 combat_resolved 事件。

const CombatAuthority := preload("res://globals/multiplayer/combat_authority.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")
const CV := preload("res://globals/multiplayer/command_validator.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func _make_attack_input() -> DR.AttackInput:
	var a: DR.AttackInput = DR.AttackInput.new()
	a.attacker_str = 12
	a.attacker_dex = 10
	a.attacker_mag = 10
	a.attacker_per = 10
	a.attacker_agi = 10
	a.attacker_con = 10
	a.weapon_damage_dice = {"count": 1, "sides": 6}
	a.weapon_damage_flat = 0.0
	a.weapon_damage_mult = 1.0
	a.attack_type = "melee"
	a.style = DR.Style.ONE_HAND
	return a

func _live() -> Dictionary:
	return {"peer_id": 2, "is_alive": true}

func test_resolve_attack_reduces_life() -> void:
	var ca = auto_free(CombatAuthority.new())
	var input = _make_attack_input()
	var defender := {"current_life": 100, "max_life": 100, "con": 10, "agi": 10, "per": 10, "armor_def": 0}
	var out = ca.resolve_attack(input, defender, Vector3(0, 0, -1), 2, 4312)
	assert_int(out["defender_life"]).is_less(100)
	assert_int(out["defender_life"]).is_greater_equal(0)
	assert_str(out["event"]["event"]).is_equal("combat_resolved")
	assert_int(int(out["event"]["damage"])).is_equal(out["result"].final_damage)
	assert_int(int(out["event"]["defender_life"])).is_equal(out["defender_life"])

func test_validate_attack_request_rejects_bad_protocol() -> void:
	var ca = auto_free(CombatAuthority.new())
	var tracker = CV.SequenceTracker.new()
	var req := {"protocol_version": 99, "world_revision": 1, "sequence": 1}
	assert_str(ca.validate_attack_request(req, _live(), 1, tracker)).is_equal("INVALID_PROTOCOL")

func test_validate_attack_request_accepts_then_rejects_replay() -> void:
	var ca = auto_free(CombatAuthority.new())
	var tracker = CV.SequenceTracker.new()
	var req := {"protocol_version": 1, "world_revision": 1, "sequence": 5}
	assert_str(ca.validate_attack_request(req, _live(), 1, tracker)).is_equal("")
	# 重复/更小序列应被拒（防重放）
	var req2 := {"protocol_version": 1, "world_revision": 1, "sequence": 5}
	assert_str(ca.validate_attack_request(req2, _live(), 1, tracker)).is_equal("INVALID_SEQUENCE")

func test_validate_attack_request_rejects_dead_attacker() -> void:
	var ca = auto_free(CombatAuthority.new())
	var tracker = CV.SequenceTracker.new()
	var live := _live(); live["is_alive"] = false
	var req := {"protocol_version": 1, "world_revision": 1, "sequence": 1}
	assert_str(ca.validate_attack_request(req, live, 1, tracker)).is_equal("PLAYER_NOT_ALIVE")

# ───────────────────────── Phase 3：攻击目标 / 姿态 / 状态权威校验 ─────────────────────────

# 辅助：构造一个「合法向前挥砍」快照（在范围内、朝向目标、无冷却/硬直、有视线）。
func _geo_attacker(at_pos: Vector3, yaw: float) -> Dictionary:
	return {
		"position": at_pos,
		"facing": Vector3(sin(yaw), 0.0, -cos(yaw)),
		"cooldown_remaining": 0.0,
		"stagger_remaining": 0.0,
	}
func _geo_target(at_pos: Vector3, exists := true, los_ok := true) -> Dictionary:
	return {"exists": exists, "position": at_pos, "los_ok": los_ok}
func _geo_cfg(max_range: float, half_cos: float, allow_missing := true) -> Dictionary:
	return {"max_range": max_range, "sector_half_cos": half_cos, "allow_missing_target": allow_missing}

func test_targeting_cooldown_blocks_attack() -> void:
	var ca = auto_free(CombatAuthority.new())
	var atk := _geo_attacker(Vector3.ZERO, 0.0); atk["cooldown_remaining"] = 0.3
	assert_str(ca.validate_attack_targeting(atk, _geo_target(Vector3(0, 0, 2)), _geo_cfg(5.0, 0.0))).is_equal(NP.ERR_COOLDOWN_ACTIVE)

func test_targeting_stagger_blocks_attack() -> void:
	var ca = auto_free(CombatAuthority.new())
	var atk := _geo_attacker(Vector3.ZERO, 0.0); atk["stagger_remaining"] = 0.5
	assert_str(ca.validate_attack_targeting(atk, _geo_target(Vector3(0, 0, 2)), _geo_cfg(5.0, 0.0))).is_equal(NP.ERR_INVALID_STATE)

func test_targeting_out_of_range_rejected() -> void:
	var ca = auto_free(CombatAuthority.new())
	# 攻击者面 -Z（yaw=0），目标在 (0,0,-2) 正前方，但射程只有 1.0 → 超出。
	var atk := _geo_attacker(Vector3.ZERO, 0.0)
	var tgt := _geo_target(Vector3(0, 0, -2))
	assert_str(ca.validate_attack_targeting(atk, tgt, _geo_cfg(1.0, -1.0))).is_equal(NP.ERR_OUT_OF_RANGE)

func test_targeting_not_facing_rejected() -> void:
	var ca = auto_free(CombatAuthority.new())
	# 攻击者面 +Z（yaw=π），目标在 -Z 背后 → 扇区外。
	var atk := _geo_attacker(Vector3.ZERO, PI)
	var tgt := _geo_target(Vector3(0, 0, -2))
	# half_cos=0.0 要求严格正前方（dot>0），背后 dot=-1 → 拒绝。
	assert_str(ca.validate_attack_targeting(atk, tgt, _geo_cfg(5.0, 0.0))).is_equal(NP.ERR_ATTACK_NOT_FACING)

func test_targeting_los_blocked_rejected() -> void:
	var ca = auto_free(CombatAuthority.new())
	var atk := _geo_attacker(Vector3.ZERO, 0.0)
	var tgt := _geo_target(Vector3(0, 0, -2), true, false)  # los_ok=false
	assert_str(ca.validate_attack_targeting(atk, tgt, _geo_cfg(5.0, -1.0))).is_equal(NP.ERR_LINE_OF_SIGHT_FAILED)

func test_targeting_missing_target_rejected_when_not_allowed() -> void:
	var ca = auto_free(CombatAuthority.new())
	var atk := _geo_attacker(Vector3.ZERO, 0.0)
	# 无目标且 allow_missing_target=false → 锁定类攻击拒绝空挥。
	assert_str(ca.validate_attack_targeting(atk, _geo_target(Vector3.ZERO, false), _geo_cfg(5.0, -1.0, false))).is_equal(NP.ERR_INVALID_TARGET)

func test_targeting_valid_in_range_facing_passes() -> void:
	var ca = auto_free(CombatAuthority.new())
	# 攻击者面 -Z，目标在 (0,0,-2) 正前 2m 内，射程 5，half_cos 放松到 -1（任意朝向都过），有视线。
	var atk := _geo_attacker(Vector3.ZERO, 0.0)
	var tgt := _geo_target(Vector3(0, 0, -2))
	assert_str(ca.validate_attack_targeting(atk, tgt, _geo_cfg(5.0, -1.0))).is_equal("")

func test_targeting_geometry_skipped_when_position_unknown() -> void:
	var ca = auto_free(CombatAuthority.new())
	# 双方权威位置未知（ZERO）→ 几何检查降级跳过，仅做状态校验（此处无冷却/硬直）。
	var atk := {"cooldown_remaining": 0.0, "stagger_remaining": 0.0}
	var tgt := {"exists": true, "position": Vector3.ZERO, "los_ok": true}
	assert_str(ca.validate_attack_targeting(atk, tgt, _geo_cfg(5.0, -1.0))).is_equal("")
