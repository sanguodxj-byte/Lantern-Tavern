extends GdUnitTestSuite

const RD := preload("res://globals/combat/rune_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")

func test_known_rune_resolves() -> void:
	var rune: Dictionary = RD.get_rune("ember")
	assert_bool(not rune.is_empty()).is_true()
	assert_str(rune.get("name", "")).is_equal("余烬符文")
	assert_str(rune.get("runic_name", "")).is_equal("ᚲ")
	assert_str(RD.get_rune_name("ember")).is_equal("ᛖᛗᛒᛖᚱ")

func test_to_runic_converts_latin_to_elder_futhark() -> void:
	assert_str(RD.to_runic("ember")).is_equal("ᛖᛗᛒᛖᚱ")
	assert_str(RD.to_runic("EMBER")).is_equal("ᛖᛗᛒᛖᚱ")
	assert_str(RD.to_runic("quick")).is_equal("ᚲᚢᛁᚲᚲ")
	assert_str(RD.to_runic("force")).is_equal("ᚠᛟᚱᚲᛖ")
	assert_str(RD.to_runic("surge")).is_equal("ᛋᚢᚱᚷᛖ")
	assert_str(RD.to_runic("guardian")).is_equal("ᚷᚢᚨᚱᛞᛁᚨᚾ")
	assert_str(RD.to_runic("")).is_empty()
	assert_str(RD.to_runic("abc")).is_equal("ᚨᛒᚲ")

func test_get_rune_name_returns_runic_spelling_for_all_runes() -> void:
	for rune_id in RD.get_all_rune_ids():
		var name := RD.get_rune_name(String(rune_id))
		assert_bool(not name.is_empty()) \
			.override_failure_message("%s 的如尼文名称不应为空" % rune_id) \
			.is_true()
		assert_bool(_contains_runic_character(name)) \
			.override_failure_message("%s 应显示卢恩文字名" % rune_id) \
			.is_true()

func test_all_rune_visible_names_use_runic_characters() -> void:
	for rune_id in RD.get_all_rune_ids():
		var display_name := RD.get_rune_name(String(rune_id))
		assert_bool(_contains_runic_character(display_name)) \
			.override_failure_message("%s 应显示卢恩文字名" % rune_id) \
			.is_true()

func test_apply_runes_modifies_numeric_values_and_mechanics() -> void:
	var skill: Dictionary = AS.get_skill_by_id("踢击")
	var effective: Dictionary = RD.apply_runes(skill, ["ember", "quick"])
	assert_float(float(effective.get("damage_mult", 0.0))).is_equal_approx(0.6, 0.001)
	assert_float(float(effective.get("cooldown", 0.0))).is_equal_approx(1.6, 0.001)
	assert_bool(effective.get("rune_effects", {}).has("burn_chance")).is_true()
	assert_bool(effective.get("rune_effects", {}).has("quickened")).is_true()

func test_velocity_rune_stacks_for_charge_impulse_build() -> void:
	var skill: Dictionary = AS.get_skill_by_id("冲撞")
	var effective: Dictionary = RD.apply_runes(skill, ["surge", "surge", "surge"])
	assert_array(effective.get("rune_ids", [])).has_size(3)
	assert_float(float(effective.get("dash_speed_mps", 0.0))).is_greater(float(skill.get("dash_speed_mps", 0.0)))
	assert_float(float(effective.get("physical_impact_damage_mult", 0.0))).is_greater(float(skill.get("physical_impact_damage_mult", 0.0)))

func test_launch_rune_stacks_for_kick_displacement_build() -> void:
	var skill: Dictionary = AS.get_skill_by_id("踢击")
	var effective: Dictionary = RD.apply_runes(skill, ["launch", "launch", "launch"])
	assert_array(effective.get("rune_ids", [])).has_size(3)
	assert_float(float(effective.get("knockback_m", 0.0))).is_greater(float(skill.get("knockback_m", 0.0)))
	assert_float(float(effective.get("physical_impact_damage_mult", 0.0))).is_greater(float(skill.get("physical_impact_damage_mult", 0.0)))

func test_unknown_rune_is_ignored() -> void:
	var skill: Dictionary = AS.get_skill_by_id("踢击")
	var effective: Dictionary = RD.apply_runes(skill, ["missing"])
	assert_float(float(effective.get("damage_mult", 0.0))).is_equal_approx(0.5, 0.001)
	assert_array(effective.get("rune_ids", [])).is_empty()

func test_roll_rune_returns_registered_rune() -> void:
	var rune: Dictionary = RD.roll_rune("elite")
	assert_bool(not rune.is_empty()).is_true()
	assert_bool(RD.has_rune(String(rune.get("id", "")))).is_true()

func _contains_runic_character(value: String) -> bool:
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code >= 0x16A0 and code <= 0x16FF:
			return true
	return false
