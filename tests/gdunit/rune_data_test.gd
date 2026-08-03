extends GdUnitTestSuite

const RD := preload("res://globals/combat/rune_data.gd")
const AS := preload("res://globals/combat/action_skills.gd")

func test_known_rune_resolves() -> void:
	var rune: Dictionary = RD.get_rune("ember")
	assert_bool(not rune.is_empty()).is_true()
	assert_str(rune.get("name", "")).is_equal("余烬符文")
	assert_str(rune.get("runic_name", "")).is_equal("अग्नि")

func test_get_rune_name_returns_sanskrit_display_name() -> void:
	# get_rune_name 应返回梵语 runic_name，而非拉丁转写或如尼文字
	assert_str(RD.get_rune_name("ember")).is_equal("अग्नि")
	assert_str(RD.get_rune_name("hima")).is_equal("हिम")
	assert_str(RD.get_rune_name("vajra")).is_equal("वज्र")
	assert_str(RD.get_rune_name("force")).is_equal("बल")
	assert_str(RD.get_rune_name("surge")).is_equal("प्रवाह")
	assert_str(RD.get_rune_name("quick")).is_equal("वेग")
	assert_str(RD.get_rune_name("launch")).is_equal("क्षेप")
	assert_str(RD.get_rune_name("echo")).is_equal("प्रतिध्वनि")
	assert_str(RD.get_rune_name("guardian")).is_equal("रक्षा")
	assert_str(RD.get_rune_name("ayu")).is_equal("आयु")
	assert_str(RD.get_rune_name("mrityu")).is_equal("मृत्यु")
	assert_str(RD.get_rune_name("kala")).is_equal("काल")
	assert_str(RD.get_rune_name("maya")).is_equal("माया")
	assert_str(RD.get_rune_name("dipa")).is_equal("दीप")
	# 新增符文
	assert_str(RD.get_rune_name("jala")).is_equal("जल")
	assert_str(RD.get_rune_name("pavana")).is_equal("पवन")
	assert_str(RD.get_rune_name("bhumi")).is_equal("भूमि")
	assert_str(RD.get_rune_name("tejas")).is_equal("तेजस्")
	assert_str(RD.get_rune_name("krishna")).is_equal("कृष्ण")
	assert_str(RD.get_rune_name("marichi")).is_equal("मरीचि")
	assert_str(RD.get_rune_name("kardama")).is_equal("कर्दम")
	assert_str(RD.get_rune_name("dhuma")).is_equal("धूम")
	assert_str(RD.get_rune_name("para")).is_equal("पर")
	assert_str(RD.get_rune_name("drava")).is_equal("द्रव")
	assert_str(RD.get_rune_name("spandana")).is_equal("स्पंदन")
	assert_str(RD.get_rune_name("praghana")).is_equal("प्रघान")
	assert_str(RD.get_rune_name("nighata")).is_equal("निघात")
	assert_str(RD.get_rune_name("bhedana")).is_equal("भेदन")
	assert_str(RD.get_rune_name("aghata")).is_equal("आघात")
	assert_str(RD.get_rune_name("vikshepa")).is_equal("विक्षेप")
	assert_str(RD.get_rune_name("prana")).is_equal("प्राण")
	assert_str(RD.get_rune_name("shakti")).is_equal("शक्ति")
	assert_str(RD.get_rune_name("vidya")).is_equal("विद्या")
	assert_str(RD.get_rune_name("tapas")).is_equal("तपस्")
	assert_str(RD.get_rune_name("karma")).is_equal("कर्म")
	assert_str(RD.get_rune_name("dharma")).is_equal("धर्म")
	assert_str(RD.get_rune_name("virya")).is_equal("वीर्य")
	assert_str(RD.get_rune_name("mantra")).is_equal("मन्त्र")
	assert_str(RD.get_rune_name("yantra")).is_equal("यन्त्र")
	assert_str(RD.get_rune_name("chitta")).is_equal("चित्त")
	assert_str(RD.get_rune_name("tamas")).is_equal("तमस्")
	assert_str(RD.get_rune_name("raudra")).is_equal("रौद्र")
	assert_str(RD.get_rune_name("bhaya")).is_equal("भय")
	assert_str(RD.get_rune_name("ghora")).is_equal("घोर")
	assert_str(RD.get_rune_name("nashana")).is_equal("नाशन")
	assert_str(RD.get_rune_name("vibhatsa")).is_equal("विभत्स")
	assert_str(RD.get_rune_name("siddhi")).is_equal("सिद्धि")
	assert_str(RD.get_rune_name("moksha")).is_equal("मोक्ष")
	assert_str(RD.get_rune_name("amrita")).is_equal("अमृत")

func test_to_runic_still_works_for_backward_compat() -> void:
	# to_runic 保留用于历史兼容
	assert_str(RD.to_runic("ember")).is_equal("ᛖᛗᛒᛖᚱ")
	assert_str(RD.to_runic("")).is_empty()
	assert_str(RD.to_runic("abc")).is_equal("ᚨᛒᚲ")

func test_all_rune_display_names_use_devanagari() -> void:
	for rune_id in RD.get_all_rune_ids():
		var display_name := RD.get_rune_name(String(rune_id))
		assert_bool(not display_name.is_empty()) \
			.override_failure_message("%s 的梵语名不应为空" % rune_id) \
			.is_true()
		assert_bool(_contains_devanagari(display_name)) \
			.override_failure_message("%s 应显示天城文梵语名，实际: %s" % [rune_id, display_name]) \
			.is_true()

func test_rune_count_is_fifty() -> void:
	assert_array(RD.get_all_rune_ids()).has_size(50)

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

func test_roll_unique_rune_ids_returns_three_deterministic_distinct_candidates() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 112233
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 112233
	var first: Array[String] = RD.roll_unique_rune_ids("chest", 3, rng_a)
	var second: Array[String] = RD.roll_unique_rune_ids("chest", 3, rng_b)
	assert_array(first).has_size(3)
	assert_array(first).is_equal(second)
	assert_bool(first[0] != first[1] and first[0] != first[2] and first[1] != first[2]).is_true()
	for rune_id in first:
		assert_bool(RD.has_rune(rune_id)).is_true()

func test_get_rune_color_returns_assigned_color_for_known_runes() -> void:
	assert_str(RD.get_rune_color("ember")).is_equal("#FF5252")
	assert_str(RD.get_rune_color("hima")).is_equal("#448AFF")
	assert_str(RD.get_rune_color("vajra")).is_equal("#FFEA00")
	assert_str(RD.get_rune_color("visha")).is_equal("#69F0AE")
	assert_str(RD.get_rune_color("force")).is_equal("#FF9100")
	assert_str(RD.get_rune_color("quick")).is_equal("#00E5FF")
	assert_str(RD.get_rune_color("surge")).is_equal("#76FF03")
	assert_str(RD.get_rune_color("launch")).is_equal("#E040FB")
	assert_str(RD.get_rune_color("echo")).is_equal("#FF6E40")
	assert_str(RD.get_rune_color("guardian")).is_equal("#64FFDA")
	assert_str(RD.get_rune_color("ayu")).is_equal("#FF80AB")
	assert_str(RD.get_rune_color("mrityu")).is_equal("#BDBDBD")
	assert_str(RD.get_rune_color("kala")).is_equal("#7C4DFF")
	assert_str(RD.get_rune_color("maya")).is_equal("#CC66FF")
	assert_str(RD.get_rune_color("dipa")).is_equal("#FFD740")

func test_get_rune_color_returns_white_for_unknown_rune() -> void:
	assert_str(RD.get_rune_color("nonexistent")).is_equal("#FFFFFF")

func test_all_registered_runes_have_unique_color() -> void:
	var seen_colors: Array = []
	for rune_id in RD.get_all_rune_ids():
		var color := RD.get_rune_color(String(rune_id))
		assert_str(color).is_not_equal("#FFFFFF") \
			.override_failure_message("%s 应有专属颜色，不应回退白色" % rune_id)
		assert_bool(not seen_colors.has(color)) \
			.override_failure_message("%s 的颜色 %s 与其他符文重复" % [rune_id, color]) \
			.is_true()
		seen_colors.append(color)

func test_all_source_weights_contain_all_runes() -> void:
	for source in RD.SOURCE_WEIGHTS.keys():
		var weights: Dictionary = RD.SOURCE_WEIGHTS[source]
		for rune_id in RD.get_all_rune_ids():
			assert_bool(weights.has(String(rune_id))) \
				.override_failure_message("source=%s 缺少符文 %s 的掉落权重" % [source, rune_id]) \
				.is_true()

func test_new_runes_have_mechanics_defined() -> void:
	# 新增的 35 个符文应有 mechanics 定义
	for rune_id in ["jala", "pavana", "bhumi", "tejas", "krishna", "marichi", "kardama", "dhuma",
		"para", "drava", "spandana", "praghana", "nighata", "bhedana", "aghata", "vikshepa",
		"prana", "shakti", "vidya", "tapas", "karma", "dharma", "virya", "mantra", "yantra", "chitta",
		"tamas", "raudra", "bhaya", "ghora", "nashana", "vibhatsa",
		"siddhi", "moksha", "amrita"]:
		var rune: Dictionary = RD.get_rune(rune_id)
		var mechanics: Dictionary = rune.get("mechanics", {})
		assert_bool(not mechanics.is_empty()) \
			.override_failure_message("%s 应有 mechanics 定义" % rune_id) \
			.is_true()

func _contains_devanagari(value: String) -> bool:
	# Devanagari Unicode range: U+0900–U+097F
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code >= 0x0900 and code <= 0x097F:
			return true
	return false
