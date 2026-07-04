extends GdUnitTestSuite

# Tests for WeaponRegistry autoload
# Covers: JSON loading, weapon registration, tier data, category grouping,
# model viewer entries, gear list entries.
#
# NOTE: JSON.parse returns all numeric values as floats, so we use
# assert_float() for JSON-derived values and int() for integer comparisons.

func test_registry_loads_all_weapons() -> void:
	assert_bool(WeaponRegistry != null).is_true()
	var ids := WeaponRegistry.get_all_ids()
	assert_int(ids.size()).is_greater_equal(10)


func test_shortsword_has_glb_and_tiers() -> void:
	assert_str(WeaponRegistry.get_glb_path("shortsword")).ends_with(".glb")
	var tiers := WeaponRegistry.get_tiers("shortsword")
	assert_int(tiers.size()).is_equal(3)
	assert_str(tiers[0].get("name", "")).contains("青铜")


func test_greatsword_has_three_tiers() -> void:
	var tiers := WeaponRegistry.get_tiers("greatsword")
	assert_int(tiers.size()).is_equal(3)
	# crit_bonus is 0.08 (8%) in JSON → stored as float
	assert_float(tiers[2].get("crit_bonus", 0.0)).is_equal(0.08)


func test_warhammer_has_knockback_and_stun() -> void:
	var tiers := WeaponRegistry.get_tiers("warhammer")
	assert_int(tiers.size()).is_equal(3)
	assert_int(int(tiers[2].get("stun", 0))).is_greater_equal(1)
	assert_int(int(tiers[2].get("knockback", 0))).is_greater_equal(1)


func test_dagger_has_high_crit() -> void:
	var tiers := WeaponRegistry.get_tiers("dagger")
	assert_float(tiers[2].get("crit_bonus", 0.0)).is_greater_equal(0.15)


func test_shield_has_three_tiers() -> void:
	var tiers := WeaponRegistry.get_tiers("shield")
	assert_int(tiers.size()).is_equal(3)
	assert_float(tiers[2].get("phys_def", 0.0)).is_greater_equal(5.0)


func test_get_model_viewer_entries_returns_categories() -> void:
	var entries := WeaponRegistry.get_model_viewer_entries()
	assert_bool(entries.size() >= 3).is_true()
	var any_have_items := false
	for cat_name in entries.keys():
		var group: Dictionary = entries[cat_name]
		if group.size() > 0:
			any_have_items = true
			break
	assert_bool(any_have_items).is_true()


func test_get_gear_list_entries_returns_objects_with_glb() -> void:
	var entries := WeaponRegistry.get_gear_list_entries()
	assert_bool(entries.size() >= 10).is_true()
	for entry in entries:
		assert_bool(entry.has("name")).is_true()
		assert_bool(entry.has("icon")).is_true()
		assert_str(entry.get("tres_path", "")).contains("res://data/weapons/")


func test_get_gear_list_by_category_filters_correctly() -> void:
	var weapon_entries := WeaponRegistry.get_gear_list_entries_by_category("weapons")
	assert_bool(weapon_entries.size() >= 9).is_true()
	var shield_entries := WeaponRegistry.get_gear_list_entries_by_category("shields")
	assert_bool(shield_entries.size() >= 1).is_true()


func test_armor_has_tiers() -> void:
	var light_tiers := WeaponRegistry.get_tiers("light_armor")
	assert_int(light_tiers.size()).is_equal(3)
	assert_float(light_tiers[0].get("phys_def", 0.0)).is_greater_equal(1.0)

	var heavy_tiers := WeaponRegistry.get_tiers("heavy_armor")
	assert_int(heavy_tiers.size()).is_equal(3)
	assert_float(heavy_tiers[2].get("phys_def", 0.0)).is_greater_equal(25.0)


func test_weight_accessory_carry_bonus() -> void:
	var tiers := WeaponRegistry.get_tiers("weight_accessory")
	assert_int(tiers.size()).is_equal(3)
	assert_float(tiers[2].get("carry_bonus", 0.0)).is_equal(25.0)


func test_get_weapon_data_returns_weapondata_resource() -> void:
	var data := WeaponRegistry.get_weapon_data("greatsword")
	assert_object(data).is_not_null()
	assert_object(data).is_instanceof(WeaponData)
	assert_str(data.name).is_equal("Greatsword")
	assert_int(data.damage_min).is_greater_equal(1)


func test_get_display_name_localized() -> void:
	var name := WeaponRegistry.get_display_name("greatsword")
	assert_bool(name.length() > 0).is_true()


func test_get_by_category_returns_all_categories() -> void:
	var by_cat := WeaponRegistry.get_by_category()
	assert_bool(by_cat.has("weapons")).is_true()
	assert_bool(by_cat.has("armor_light")).is_true()
	assert_bool(by_cat.has("armor_heavy")).is_true()
	assert_bool(by_cat.has("shields") or by_cat.has("accessories")).is_true()


func test_get_category_name_returns_display_name() -> void:
	assert_str(WeaponRegistry.get_category_name("weapons")).is_equal("Weapons")
	assert_str(WeaponRegistry.get_category_name("shields")).is_equal("Shields")
