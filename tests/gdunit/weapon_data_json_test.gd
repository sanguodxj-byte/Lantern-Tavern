extends GdUnitTestSuite

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


func test_weapon_tiers_have_minimal_fields() -> void:
	var data := _load_json()
	for entry in data.get("weapons", []):
		for tier in entry.get("tiers", []):
			assert_str(tier.get("name", "")).is_not_empty()
			# Must have reach or damage_dice
			assert_bool(tier.has("reach") or tier.has("damage_dice")).is_true()


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
