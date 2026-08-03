extends GdUnitTestSuite

## AttackContextFactory 单元测试（架构审查 P0-2）：
## 攻击类型/射程/风格/伤害输入必须由服务器权威 loadout 派生，绝不接受客户端 attack_type。

const ACF := preload("res://globals/combat/attack_context_factory.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")
const EquipmentLoadout := preload("res://globals/core/state/equipment_loadout.gd")

const ATTRS := {"str": 12, "dex": 14, "mag": 8, "con": 10, "agi": 10, "per": 9}

func _registry() -> Object:
	return Engine.get_main_loop().root.get_node("WeaponRegistry")

func _loadout(slots: Array, active: int = 0) -> EquipmentLoadout:
	var lo := EquipmentLoadout.new()
	for i in range(mini(slots.size(), lo.weapon_slots.size())):
		lo.weapon_slots[i] = String(slots[i])
	lo.active_weapon_slot = active
	return lo

func test_melee_weapon_derives_melee_attack_type_and_range() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["shortsword"]), _registry())
	assert_str(ctx.attack_type()).is_equal("melee")
	assert_float(ctx.attack_range()).is_equal_approx(2.5, 1e-4)
	assert_int(ctx.style()).is_equal(DR.Style.ONE_HAND)
	assert_str(ctx.weapon_id()).is_equal("shortsword")

func test_ranged_weapon_derives_ranged_attack_type_and_18m_range() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["longbow"]), _registry())
	assert_str(ctx.attack_type()).is_equal("ranged")
	assert_float(ctx.attack_range()).is_equal_approx(18.0, 1e-4)
	assert_int(ctx.style()).is_equal(DR.Style.RANGED)

func test_spell_weapon_derives_spell_attack_type_and_18m_range() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["grimoire"]), _registry())
	assert_str(ctx.attack_type()).is_equal("spell")
	assert_float(ctx.attack_range()).is_equal_approx(18.0, 1e-4)
	assert_int(ctx.style()).is_equal(DR.Style.SPELL)

func test_unarmed_loadout_derives_melee_and_short_range() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 1, _loadout([""]), _registry())
	assert_object(ctx.weapon).is_null()
	assert_str(ctx.attack_type()).is_equal("melee")
	assert_float(ctx.attack_range()).is_equal_approx(2.5, 1e-4)
	assert_int(ctx.style()).is_equal(DR.Style.UNARMED)

func test_two_hand_derives_two_hand_style() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["greatsword"]), _registry())
	assert_int(ctx.style()).is_equal(DR.Style.TWO_HAND)
	assert_bool(ctx.is_two_handed()).is_true()

func test_dual_wield_secondary_hand_derives_dual_wield_style() -> void:
	# 主手 + 副手均为单手近战 → 双持；副手攻击派生 off_hand_type=one_hand_melee。
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["shortsword", "dagger"]), _registry(), "secondary")
	assert_str(ctx.off_hand_type).is_equal("one_hand_melee")
	assert_int(ctx.style()).is_equal(DR.Style.DUAL_WIELD)

func test_shield_in_loadout_derives_one_hand_shield_style() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["shortsword", "shield"]), _registry())
	assert_str(ctx.off_hand_type).is_equal("shield")
	assert_int(ctx.style()).is_equal(DR.Style.ONE_HAND_SHIELD)

func test_attack_type_is_never_taken_from_client_command() -> void:
	# 客户端伪报 ranged：服务器仍按权威 loadout（近战武器）派生 melee。
	var command := {"attack_type": "ranged", "hand": "primary", "charge_ratio": 1.0}
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["shortsword"]), _registry(),
		String(command.get("hand", "primary")), float(command.get("charge_ratio", 1.0)))
	assert_str(ctx.attack_type()).is_equal("melee")
	assert_float(ctx.attack_range()).is_equal_approx(2.5, 1e-4)

func test_charge_ratio_and_target_hint_are_carried() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["shortsword"]), _registry(), "primary", 0.5, 1001)
	assert_float(ctx.charge_ratio).is_equal_approx(0.5, 1e-4)
	assert_int(int(ctx.target_hint)).is_equal(1001)

func test_to_attack_input_carries_attrs_style_and_weapon_stats() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["greatsword"]), _registry())
	var ai: DR.AttackInput = ACF.to_attack_input(ctx)
	assert_int(ai.attacker_str).is_equal(12)
	assert_int(ai.attacker_dex).is_equal(14)
	assert_int(ai.attacker_level).is_equal(3)
	assert_int(ai.style).is_equal(DR.Style.TWO_HAND)
	assert_str(ai.attack_type).is_equal("melee")
	# 巨剑基础骰从 weapons.json tier0 派生（1d8+0 等，具体以注册表为准）。
	var weapon_data = _registry().get_weapon_data("greatsword")
	assert_int(ai.weapon_damage_dice["count"]).is_equal(max(weapon_data.damage_dice_count, 0))
	assert_int(ai.weapon_damage_dice["sides"]).is_equal(max(weapon_data.damage_dice_sides, 0))

func test_unarmed_to_attack_input_uses_fist_dice() -> void:
	var ctx = ACF.build_from_player_state(ATTRS, 1, _loadout([""]), _registry())
	var ai: DR.AttackInput = ACF.to_attack_input(ctx)
	assert_int(ai.weapon_damage_dice["count"]).is_equal(1)
	assert_int(ai.weapon_damage_dice["sides"]).is_equal(4)

func test_build_from_components_matches_player_state_path_for_same_weapon() -> void:
	# 单机（components 路径）与联机（player_state 路径）对同一武器产生同一装配结果。
	var via_state = ACF.build_from_player_state(ATTRS, 3, _loadout(["longbow"]), _registry())
	var via_components = ACF.build_from_components(
		_registry().get_weapon_data("longbow"), "longbow", "", ATTRS, 3)
	assert_str(via_state.attack_type()).is_equal(via_components.attack_type())
	assert_int(via_state.style()).is_equal(via_components.style())
	var ai_state: DR.AttackInput = ACF.to_attack_input(via_state)
	var ai_components: DR.AttackInput = ACF.to_attack_input(via_components)
	assert_int(ai_state.weapon_damage_dice["count"]).is_equal(ai_components.weapon_damage_dice["count"])
	assert_float(ai_state.weapon_damage_flat).is_equal_approx(ai_components.weapon_damage_flat, 1e-4)

func test_all_seven_styles_declare_damage_mult_contract() -> void:
	# P1-3 契约：七流派必须在 STYLE_META 显式声明 damage_mult（单一真相，无隐式缺省）。
	var styles: Array = [
		DR.Style.ONE_HAND, DR.Style.ONE_HAND_SHIELD, DR.Style.TWO_HAND,
		DR.Style.DUAL_WIELD, DR.Style.UNARMED, DR.Style.RANGED, DR.Style.SPELL,
	]
	assert_int(styles.size()).is_equal(7)
	for style in styles:
		var meta: Dictionary = DR.STYLE_META.get(style, {})
		assert_bool(meta.has("damage_mult")) \
			.override_failure_message("流派 %d 缺少显式 damage_mult" % int(style)).is_true()
		assert_float(float(meta.get("damage_mult", -1.0))).is_greater(0.0)

func test_style_damage_mult_matches_decided_table() -> void:
	# P1-2：docs/战斗数值体系.md §2.5【✅ 已决定】七流派武器伤害倍率——
	# 单手 1.00 / 持盾 0.80 / 双手 1.35 / 双持 1.00（副手 0.60 由 offhand_damage_pct 承载）
	# / 徒手 0.80 / 远程 1.00 / 法系 0.50。数值只应来自 STYLE_META 单一真相。
	var decided := {
		DR.Style.ONE_HAND: 1.0,
		DR.Style.ONE_HAND_SHIELD: 0.8,
		DR.Style.TWO_HAND: 1.35,
		DR.Style.DUAL_WIELD: 1.0,
		DR.Style.UNARMED: 0.8,
		DR.Style.RANGED: 1.0,
		DR.Style.SPELL: 0.5,
	}
	assert_int(decided.size()).is_equal(7)
	for style in decided.keys():
		assert_float(float(DR.STYLE_META[style].get("damage_mult", -1.0))) \
			.override_failure_message("流派 %d 倍率未对齐已决定表（期望 %.2f）" % [int(style), decided[style]]) \
			.is_equal_approx(float(decided[style]), 1e-4)
	# 双持副手倍率由 offhand_damage_pct 承载（60%）。
	assert_float(float(DR.STYLE_META[DR.Style.DUAL_WIELD].get("offhand_damage_pct", 0.0))) \
		.is_equal_approx(0.6, 1e-4)

func test_style_damage_mult_applied_to_weapon_damage_only() -> void:
	# P1-3：to_attack_input 必须把流派 damage_mult 乘入 weapon_damage_mult
	# （与武器词缀 damage_mult 叠乘；法术卡路径不经过 AttackInput，天然不乘）。
	var style_mult: float = float(DR.STYLE_META[DR.Style.TWO_HAND].get("damage_mult", 1.0))
	var ctx = ACF.build_from_player_state(ATTRS, 3, _loadout(["greatsword"]), _registry())
	var ai: DR.AttackInput = ACF.to_attack_input(ctx)
	var weapon_data = _registry().get_weapon_data("greatsword")
	assert_float(ai.weapon_damage_mult).is_equal_approx(style_mult * float(weapon_data.damage_mult), 1e-4) \
		.override_failure_message("流派倍率必须乘入武器伤害倍率（style=%s × affix=%s）" % [style_mult, weapon_data.damage_mult])
