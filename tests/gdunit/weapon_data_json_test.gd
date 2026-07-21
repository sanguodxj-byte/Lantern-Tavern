extends GdUnitTestSuite

const MATERIAL_TIERS := ["wood", "iron", "steel", "meteoric", "mithril", "adamantite"]

# Tests for weapons.json data integrity
# Validates that the JSON file exists, is parseable, and contains
# all required fields for every entry.

const JSON_PATH := "res://data/weapons/weapons.json"

func _load_json() -> Dictionary:
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	json.parse(text)
	return json.data


func test_json_file_exists() -> void:
	assert_bool(ResourceLoader.exists(JSON_PATH)).is_true()


func test_json_parseable() -> void:
	var data := _load_json()
	assert_bool(data.size() > 0).is_true()


func test_weapon_entries_have_required_fields() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		# Every weapon must have these fields
		assert_str(entry.get("id", "")).is_not_empty()
		assert_str(entry.get("name", "")).is_not_empty()
		assert_str(entry.get("name_zh", "")).is_not_empty()
		assert_str(entry.get("category", "")).is_not_empty()
		assert_str(entry.get("glb_path", "")).contains("res://")
		assert_str(entry.get("icon", "")).contains("res://")
		
		# Tiers array must exist and have entries
		var tiers = entry.get("tiers", [])
		assert_bool(tiers.size() >= 1).is_true()
		
		# Stats block must exist
		var stats = entry.get("stats", {})
		assert_bool(stats.has("condition")).is_true()
		assert_bool(stats.has("damage_min")).is_true()
		assert_bool(stats.has("damage_max")).is_true()


func test_weapon_entries_have_tag_and_taxonomy_fields() -> void:
	var data := _load_json()
	var valid_item_tags := ["weapon", "shield"]
	var valid_weapon_classes := ["one_hand_melee", "two_hand", "longbow", "crossbow", "wand", "grimoire", "shield"]
	var valid_attack_types := ["melee", "ranged", "spell", "shield"]
	var valid_combat_styles := ["one_hand", "one_hand_shield", "two_hand", "dual_wield", "ranged", "spell"]
	var valid_proficiency_keys := ["sword", "dagger", "axe", "hammer", "spear", "bow", "crossbow", "staff", "grimoire", "shield"]
	var valid_skill_schools := [
		"one_hand_sword",
		"two_hand_sword",
		"two_hand_axe",
		"war_hammer",
		"spear",
		"longbow",
		"light_crossbow",
		"enchant_wand",
		"grimoire",
		"",
	]

	for entry in data.get("weapons", []):
		var item_tag: String = entry.get("item_tag", "")
		var tags: Array = entry.get("tags", [])
		var weapon_class: String = entry.get("weapon_class", "")
		var attack_type: String = entry.get("attack_type", "")
		var skill_school: String = entry.get("skill_school", "")
		var combat_styles: Array = entry.get("combat_styles", [])
		var proficiency_key: String = entry.get("proficiency_key", "")

		assert_bool(valid_item_tags.has(item_tag)) \
			.override_failure_message("Invalid item_tag for %s: %s" % [entry.get("id", "?"), item_tag]) \
			.is_true()
		assert_bool(tags.size() > 0) \
			.override_failure_message("Missing tags for " + entry.get("id", "?")) \
			.is_true()
		assert_array(tags).contains(item_tag)
		assert_bool(valid_weapon_classes.has(weapon_class)) \
			.override_failure_message("Invalid weapon_class for %s: %s" % [entry.get("id", "?"), weapon_class]) \
			.is_true()
		assert_bool(valid_attack_types.has(attack_type)) \
			.override_failure_message("Invalid attack_type for %s: %s" % [entry.get("id", "?"), attack_type]) \
			.is_true()
		assert_bool(valid_skill_schools.has(skill_school)) \
			.override_failure_message("Invalid skill_school for %s: %s" % [entry.get("id", "?"), skill_school]) \
			.is_true()
		assert_bool(combat_styles.size() > 0) \
			.override_failure_message("Missing combat_styles for " + entry.get("id", "?")) \
			.is_true()
		for style in combat_styles:
			assert_bool(valid_combat_styles.has(style)) \
				.override_failure_message("Invalid combat style for %s: %s" % [entry.get("id", "?"), style]) \
				.is_true()
		assert_bool(valid_proficiency_keys.has(proficiency_key)) \
			.override_failure_message("Invalid proficiency_key for %s: %s" % [entry.get("id", "?"), proficiency_key]) \
			.is_true()


func test_weapon_taxonomy_matches_docs_combat_styles_and_schools() -> void:
	var data := _load_json()
	var expected := {
		"shortsword": {"item_tag": "weapon", "weapon_class": "one_hand_melee", "attack_type": "melee", "skill_school": "one_hand_sword", "combat_style": "one_hand_shield", "proficiency_key": "sword"},
		"sword": {"item_tag": "weapon", "weapon_class": "one_hand_melee", "attack_type": "melee", "skill_school": "one_hand_sword", "combat_style": "one_hand_shield", "proficiency_key": "sword"},
		"dagger": {"item_tag": "weapon", "weapon_class": "one_hand_melee", "attack_type": "melee", "skill_school": "one_hand_sword", "combat_style": "dual_wield", "proficiency_key": "dagger"},
		"greatsword": {"item_tag": "weapon", "weapon_class": "two_hand", "attack_type": "melee", "skill_school": "two_hand_sword", "combat_style": "two_hand", "proficiency_key": "sword"},
		"axe": {"item_tag": "weapon", "weapon_class": "two_hand", "attack_type": "melee", "skill_school": "two_hand_axe", "combat_style": "two_hand", "proficiency_key": "axe"},
		"warhammer": {"item_tag": "weapon", "weapon_class": "two_hand", "attack_type": "melee", "skill_school": "war_hammer", "combat_style": "two_hand", "proficiency_key": "hammer"},
		"spear": {"item_tag": "weapon", "weapon_class": "two_hand", "attack_type": "melee", "skill_school": "spear", "combat_style": "two_hand", "proficiency_key": "spear"},
		"longbow": {"item_tag": "weapon", "weapon_class": "longbow", "attack_type": "ranged", "skill_school": "longbow", "combat_style": "ranged", "proficiency_key": "bow"},
		"crossbow": {"item_tag": "weapon", "weapon_class": "crossbow", "attack_type": "ranged", "skill_school": "light_crossbow", "combat_style": "ranged", "proficiency_key": "crossbow"},
		"staff": {"item_tag": "weapon", "weapon_class": "wand", "attack_type": "spell", "skill_school": "enchant_wand", "combat_style": "spell", "proficiency_key": "staff"},
		"shield": {"item_tag": "shield", "weapon_class": "shield", "attack_type": "shield", "skill_school": "", "combat_style": "one_hand_shield", "proficiency_key": "shield"},
	}

	for weapon_id in expected.keys():
		var entry := _weapon_by_id(data, weapon_id)
		var expected_meta: Dictionary = expected[weapon_id]
		assert_bool(not entry.is_empty()).is_true()
		assert_str(entry.get("item_tag", "")).is_equal(expected_meta["item_tag"])
		assert_str(entry.get("weapon_class", "")).is_equal(expected_meta["weapon_class"])
		assert_str(entry.get("attack_type", "")).is_equal(expected_meta["attack_type"])
		assert_str(entry.get("skill_school", "")).is_equal(expected_meta["skill_school"])
		assert_array(entry.get("combat_styles", [])).contains(expected_meta["combat_style"])
		assert_str(entry.get("proficiency_key", "")).is_equal(expected_meta["proficiency_key"])


func test_equipment_chinese_names_are_not_english_duplicates() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		assert_bool(entry.get("name_zh", "") != entry.get("name", "")) \
			.override_failure_message("name_zh duplicates name for " + entry.get("id", "?")) \
			.is_true()
	for entry in data.get("armor", []):
		assert_bool(entry.get("name_zh", "") != entry.get("name", "")) \
			.override_failure_message("name_zh duplicates name for " + entry.get("id", "?")) \
			.is_true()


func test_weapon_tiers_have_minimal_fields() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		for tier in entry.get("tiers", []):
			assert_str(tier.get("name", "")).is_not_empty()
			# Must have reach or damage_dice
			assert_bool(tier.has("reach") or tier.has("damage_dice")).is_true()


func test_weapon_tiers_use_canonical_material_table() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		for tier in entry.get("tiers", []):
			assert_bool(MATERIAL_TIERS.has(String(tier.get("material_tier", "")))) \
				.override_failure_message("Missing canonical material tier for %s/%s" % [entry.get("id", ""), tier.get("name", "")]).is_true()


func test_armor_entries_have_required_fields() -> void:
	var data := _load_json()
	for entry in data.get("armor", []):
		assert_str(entry.get("id", "")).is_not_empty()
		assert_str(entry.get("name", "")).is_not_empty()
		assert_str(entry.get("name_zh", "")).is_not_empty()
		
		var tiers = entry.get("tiers", [])
		assert_bool(tiers.size() >= 1).is_true()
		for tier in tiers:
			assert_str(tier.get("name", "")).is_not_empty()


func test_armor_list_contains_modeled_cloth_leather_chain_plate() -> void:
	var data := _load_json()
	var expected_ids := ["cloth_armor", "leather_armor", "chain_armor", "plate_armor"]
	var expected_def := [1, 3, 6, 10]
	var expected_move := [1.0, 0.98, 0.94, 0.88]
	for i in range(expected_ids.size()):
		var entry := _armor_by_id(data, expected_ids[i])
		assert_bool(not entry.is_empty()) \
			.override_failure_message("Missing armor entry: " + expected_ids[i]) \
			.is_true()
		assert_str(entry.get("glb_path", "")) \
			.override_failure_message("Missing armor GLB for " + expected_ids[i]) \
			.contains("res://assets/meshes/armor/")
		assert_str(entry.get("icon", "")) \
			.override_failure_message("Missing modeled armor icon for " + expected_ids[i]) \
			.contains("res://assets/textures/icons/equipment/")
		assert_bool(ResourceLoader.exists(entry.get("glb_path", ""))).is_true()
		assert_bool(ResourceLoader.exists(entry.get("icon", ""))).is_true()
		var tier: Dictionary = entry.get("tiers", [])[0]
		assert_int(int(tier.get("phys_def", 0))).is_equal(expected_def[i])
		assert_float(float(tier.get("move_speed_mult", 0.0))).is_equal(expected_move[i])


func test_glb_paths_point_to_existing_files() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		var glb: String = entry.get("glb_path", "")
		if glb.is_empty():
			continue  # armor entries have no glb
		# Convert res:// to absolute
		var abs_path: String = glb.replace("res://", "res://")
		assert_bool(ResourceLoader.exists(glb)) \
			.override_failure_message("Missing GLB: " + glb + " for " + entry.get("id", "?")) \
			.is_true()


func test_modeled_weapon_icons_point_to_existing_files() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		var icon: String = entry.get("icon", "")
		assert_str(icon) \
			.override_failure_message("Missing icon path for " + entry.get("id", "?")) \
			.contains("res://assets/textures/icons/equipment/")
		assert_bool(ResourceLoader.exists(icon)) \
			.override_failure_message("Missing modeled icon: " + icon + " for " + entry.get("id", "?")) \
			.is_true()


func test_no_duplicate_ids() -> void:
	var data := _load_json()
	var ids := PackedStringArray()
	for entry in data.get("weapons", []):
		ids.append(entry.get("id", ""))
	for entry in data.get("armor", []):
		ids.append(entry.get("id", ""))
	
	# Check for duplicates
	var seen := {}
	for id in ids:
		if seen.has(id):
			assert_str("").override_failure_message("Duplicate ID: " + id).is_not_empty()
		seen[id] = true


func test_hands_field_valid() -> void:
	var data := _load_json()
	var valid_hands := ["one_hand", "two_hand", "off_hand"]
	for entry in data.get("weapons", []):
		var hands = entry.get("hands", "")
		if not hands.is_empty():
			assert_bool(valid_hands.has(hands)) \
				.override_failure_message("Invalid hands='" + hands + "' for " + entry.get("id", "?")) \
				.is_true()


func test_version_number() -> void:
	var data := _load_json()
	assert_float(data.get("version", 0.0)).is_greater_equal(2.0)


func test_categories_array_defined() -> void:
	var data := _load_json()
	var cats = data.get("categories", [])
	assert_bool(cats.size() >= 3).is_true()
	assert_bool("weapons" in cats).is_true()
	assert_bool("shields" in cats).is_true()


func _weapon_by_id(data: Dictionary, weapon_id: String) -> Dictionary:
	for entry in data.get("weapons", []):
		if entry.get("id", "") == weapon_id:
			return entry
	return {}


func _armor_by_id(data: Dictionary, armor_id: String) -> Dictionary:
	for entry in data.get("armor", []):
		if entry.get("id", "") == armor_id:
			return entry
	return {}
