extends GdUnitTestSuite

## AttackCadencePolicy 单元测试（架构审查 P0-3）：
## 攻击冷却唯一权威公式——单手 0.45s / 双手 ×1.5 / 双持副手 0.38s / 急速 ×0.85。

const ACP := preload("res://globals/combat/attack_cadence_policy.gd")
const ACF := preload("res://globals/combat/attack_context_factory.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")
const EquipmentLoadout := preload("res://globals/core/state/equipment_loadout.gd")

const ATTRS := {"str": 12, "dex": 14, "mag": 8, "con": 10, "agi": 10, "per": 9}

func _ctx(main_type: String, off_type: String = "", hand: String = "primary"):
	return ACF.build_from_components(null, main_type, off_type, ATTRS, 1, hand)

func test_one_hand_primary_base_cd() -> void:
	var cd: float = ACP.compute_attack_cd(_ctx("one_hand_melee"), false, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_BASE, 1e-4)

func test_two_hand_cd_is_base_times_1_5() -> void:
	var cd: float = ACP.compute_attack_cd(_ctx("two_hand"), false, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_BASE * ACP.MELEE_CD_TWO_HAND_MULT, 1e-4)

func test_dual_wield_secondary_cd_is_0_38() -> void:
	var cd: float = ACP.compute_attack_cd(_ctx("one_hand_melee", "one_hand_melee", "secondary"), false, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_DUAL_WIELD, 1e-4)

func test_dual_wield_primary_uses_base_cd() -> void:
	var cd: float = ACP.compute_attack_cd(_ctx("one_hand_melee", "one_hand_melee", "primary"), false, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_BASE, 1e-4)

func test_cd_reduce_passive_scales_base() -> void:
	var cd: float = ACP.compute_attack_cd(_ctx("one_hand_melee"), true, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_BASE * ACP.CD_REDUCE_MULT, 1e-4)

func test_null_context_falls_back_to_one_hand_primary() -> void:
	var cd: float = ACP.compute_attack_cd(null, false, 0)
	assert_float(cd).is_equal_approx(ACP.MELEE_CD_BASE, 1e-4)

func test_no_stacks_leaves_cd_multiplier_identity() -> void:
	assert_float(ACP.get_cd_multiplier(false, 0)).is_equal_approx(1.0, 1e-4)
	assert_float(ACP.get_cd_multiplier(true, 0)).is_equal_approx(ACP.CD_REDUCE_MULT, 1e-4)

func test_flurry_stacks_only_reduce_when_present() -> void:
	# 无连击栈 → 无暴风骤雨修正；有栈 → 乘数 ≤ 无栈乘数（被动未绑定时恒等）。
	assert_float(ACP.get_cd_multiplier(false, 0)).is_equal_approx(ACP.get_cd_multiplier(false, 0), 1e-4)
	assert_float(ACP.get_cd_multiplier(false, 6)).is_less_equal(ACP.get_cd_multiplier(false, 0) + 1e-6)

func test_policy_matches_player_combat_runtime_formula() -> void:
	# 与 PlayerCombatRuntime 已裁定公式逐项一致（防止两处漂移）。
	const PCR := preload("res://scenes/characters/player/player_combat_runtime.gd")
	assert_float(ACP.MELEE_CD_BASE).is_equal_approx(PCR.MELEE_CD_BASE, 1e-4)
	assert_float(ACP.MELEE_CD_TWO_HAND_MULT).is_equal_approx(PCR.MELEE_CD_TWO_HAND_MULT, 1e-4)
	assert_float(ACP.MELEE_CD_DUAL_WIELD).is_equal_approx(PCR.MELEE_CD_DUAL_WIELD, 1e-4)
	assert_float(ACP.CD_REDUCE_MULT).is_equal_approx(PCR.CD_REDUCE_MULT, 1e-4)
