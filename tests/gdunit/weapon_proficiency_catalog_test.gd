extends GdUnitTestSuite

const WPC := preload("res://globals/combat/weapon_proficiency_catalog.gd")


func test_catalog_contains_only_combat_weapon_tracks() -> void:
	var keys := WPC.keys()
	assert_int(keys.size()).is_equal(10)
	for key in ["sword", "dagger", "axe", "hammer", "spear", "bow", "crossbow", "staff", "grimoire", "shield"]:
		assert_array(keys).contains(key)
	assert_bool(keys.has("light_armor")).is_false()
	assert_bool(keys.has("alchemy")).is_false()
	assert_bool(keys.has("one_hand_melee")).is_false()
	assert_bool(keys.has("two_hand")).is_false()


func test_sword_track_is_not_split_by_hands_or_school() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json")) as Dictionary
	var by_id: Dictionary = {}
	for entry in data.get("weapons", []):
		by_id[String(entry["id"])] = entry
	assert_str(String(by_id["shortsword"]["proficiency_key"])).is_equal("sword")
	assert_str(String(by_id["sword"]["proficiency_key"])).is_equal("sword")
	assert_str(String(by_id["greatsword"]["proficiency_key"])).is_equal("sword")
	assert_str(String(by_id["shortsword"]["skill_school"])).is_not_equal(String(by_id["greatsword"]["skill_school"]))


func test_value_for_reads_new_key_and_legacy_save_fallback() -> void:
	assert_int(WPC.value_for({"sword": 12}, "sword")).is_equal(12)
	assert_int(WPC.value_for({"one_hand_melee": 9}, "sword")).is_equal(9)
	assert_int(WPC.value_for({"two_hand": 7}, "axe")).is_equal(7)
	assert_int(WPC.value_for({"light_armor": 99}, "sword")).is_equal(0)
