extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")


func test_tier_order_matches_docs_quality_ladder() -> void:
	assert_array(TIERS.TIER_ORDER).is_equal(["S", "A", "B", "C", "D", "other"])


func test_flagship_models_are_s_tier() -> void:
	for model_id in ["dragon", "rock_golem"]:
		assert_str(TIERS.tier_for(model_id)).is_equal(TIERS.S)
	assert_array(TIERS.model_ids_for_tier(TIERS.S)).is_equal([
		"dragon", "rock_golem",
	])


func test_visual_review_reorders_seen_models() -> void:
	assert_array(TIERS.model_ids_for_tier(TIERS.A)).is_equal([
		"bartender", "drow_blade", "minotaur", "necrolord", "orc_raider",
		"player", "rat", "skeleton", "slime", "spider", "troll",
	])
	assert_array(TIERS.model_ids_for_tier(TIERS.B)).is_equal([
		"bandit_crossbowman", "cultist_pyromancer", "duergar_miner", "goblin",
		"plague_doctor",
	])
	assert_array(TIERS.model_ids_for_tier(TIERS.C)).contains("kobold")
	assert_array(TIERS.model_ids_for_tier(TIERS.D)).is_equal(["zombie"])


func test_only_individually_accepted_models_are_runtime_eligible() -> void:
	assert_array(TIERS.ACCEPTED_IDS).is_equal([
		"goblin", "dragon", "rock_golem", "orc_raider", "skeleton", "troll", "player",
		"minotaur", "slime", "spider", "drow_blade",
	])
	for model_id in TIERS.ACCEPTED_IDS:
		assert_bool(TIERS.is_accepted(model_id)).is_true()
	for model_id in ["dragon", "rock_golem"]:
		assert_str(TIERS.tier_for(model_id)).is_equal(TIERS.S)
	for model_id in ["drow_blade", "spider", "orc_raider", "skeleton", "troll", "player", "minotaur", "slime"]:
		assert_str(TIERS.tier_for(model_id)).is_equal(TIERS.A)
	for model_id in ["necrolord", "rat", "kobold", "zombie", "not_a_real_model"]:
		assert_bool(TIERS.is_accepted(model_id)) \
			.override_failure_message("unaccepted model leaked into runtime: %s" % model_id) \
			.is_false()


func test_accepted_model_ids_returns_a_copy() -> void:
	var ids := TIERS.accepted_model_ids()
	ids.append("rat")
	assert_bool(TIERS.ACCEPTED_IDS.has("rat")).is_false()


func test_accepted_rebuilt_models_are_a_tier() -> void:
	assert_str(TIERS.tier_for("drow_blade")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("skeleton")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("troll")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("player")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("minotaur")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("slime")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("spider")).is_equal(TIERS.A)


func test_remake_queue_models_keep_historical_subtags() -> void:
	assert_str(TIERS.tier_for("player")).is_equal(TIERS.A)
	assert_str(TIERS.tier_for("plague_doctor")).is_equal(TIERS.B)
	assert_str(TIERS.tier_for("shadow_assassin")).is_equal(TIERS.C)
	assert_str(TIERS.tier_for("kobold")).is_equal(TIERS.D)
	assert_str(TIERS.tier_for("zombie")).is_equal(TIERS.D)


func test_unknown_model_falls_back_to_other() -> void:
	assert_str(TIERS.tier_for("not_a_real_model")).is_equal(TIERS.OTHER)
	assert_str(TIERS.tier_for("")).is_equal(TIERS.OTHER)


func test_display_name_uses_translation_keys() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	assert_str(TIERS.display_name(TIERS.S)).is_equal("S 档")
	assert_str(TIERS.display_name(TIERS.OTHER)).is_equal("其他")
	TranslationServer.set_locale("en")
	assert_str(TIERS.display_name(TIERS.S)).is_equal(TranslationServer.translate("S 档"))
	TranslationServer.set_locale(prev)


func test_model_ids_for_tier_are_sorted() -> void:
	var ids := TIERS.model_ids_for_tier(TIERS.S)
	assert_int(ids.size()).is_equal(2)
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).is_equal(sorted)


func test_all_by_id_entries_use_valid_tiers() -> void:
	for model_id in TIERS.BY_ID.keys():
		assert_bool(TIERS.is_valid(String(TIERS.BY_ID[model_id]))) \
			.override_failure_message("invalid tier for %s" % model_id) \
			.is_true()
