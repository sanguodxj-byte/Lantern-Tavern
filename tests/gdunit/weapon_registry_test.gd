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
	assert_str(WeaponRegistry.get_material_tier("shortsword", 2)).is_equal("mithril")


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
	var light_armor_entries := WeaponRegistry.get_gear_list_entries_by_category("armor_light")
	var heavy_armor_entries := WeaponRegistry.get_gear_list_entries_by_category("armor_heavy")
	assert_int(light_armor_entries.size()).is_equal(2)
	assert_int(heavy_armor_entries.size()).is_equal(2)


func test_registry_exposes_weapon_taxonomy_metadata() -> void:
	assert_str(WeaponRegistry.get_item_tag("shortsword")).is_equal("weapon")
	assert_array(WeaponRegistry.get_tags("shortsword")).contains("one_hand_sword")
	assert_str(WeaponRegistry.get_weapon_class("shortsword")).is_equal("one_hand_melee")
	assert_str(WeaponRegistry.get_view_model_profile("shortsword")).is_equal("shortsword")
	assert_str(WeaponRegistry.get_view_model_profile("sword")).is_equal("sword")
	assert_str(WeaponRegistry.get_attack_type("longbow")).is_equal("ranged")
	assert_str(WeaponRegistry.get_skill_school("crossbow")).is_equal("light_crossbow")
	assert_str(WeaponRegistry.get_item_tag("shield")).is_equal("shield")
	assert_str(WeaponRegistry.get_weapon_class("shield")).is_equal("shield")
	assert_array(WeaponRegistry.get_combat_styles("shield")).contains("one_hand_shield")
	assert_str(WeaponRegistry.get_proficiency_key("shield")).is_equal("shield")


func test_gear_list_entries_include_taxonomy_metadata() -> void:
	var entries := WeaponRegistry.get_gear_list_entries()
	var greatsword := _find_gear_entry(entries, "greatsword")
	assert_bool(not greatsword.is_empty()).is_true()
	assert_str(greatsword.get("item_tag", "")).is_equal("weapon")
	assert_array(greatsword.get("tags", [])).contains("two_hand_sword")
	assert_str(greatsword.get("weapon_class", "")).is_equal("two_hand")
	assert_str(greatsword.get("attack_type", "")).is_equal("melee")
	assert_str(greatsword.get("skill_school", "")).is_equal("two_hand_sword")
	assert_array(greatsword.get("combat_styles", [])).contains("two_hand")
	assert_str(greatsword.get("proficiency_key", "")).is_equal("sword")
	var shortsword := _find_gear_entry(entries, "shortsword")
	assert_str(shortsword.get("view_model_profile", "")).is_equal("shortsword")
	var sword := _find_gear_entry(entries, "sword")
	assert_str(sword.get("view_model_profile", "")).is_equal("sword")


func test_registered_shortsword_data_carries_visual_profile() -> void:
	var weapon: WeaponData = WeaponRegistry.get_weapon("shortsword") as WeaponData
	assert_object(weapon).is_not_null()
	assert_str(weapon.view_model_profile).is_equal("shortsword")


func test_armor_has_tiers() -> void:
	var cloth_tiers := WeaponRegistry.get_tiers("cloth_armor")
	assert_int(cloth_tiers.size()).is_equal(1)
	assert_float(cloth_tiers[0].get("phys_def", 0.0)).is_equal(1.0)

	var plate_tiers := WeaponRegistry.get_tiers("plate_armor")
	assert_int(plate_tiers.size()).is_equal(1)
	assert_float(plate_tiers[0].get("phys_def", 0.0)).is_equal(10.0)


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


func test_find_id_by_glb_resolves_shortsword() -> void:
	# 旧版 .tres WeaponData（如酒馆 PickableShortSword 用的 shortsword.tres）没有 id，
	# 保存装备时需按 glb_mesh 反查注册表得到可持久化的 id。
	var glb := load(WeaponRegistry.get_glb_path("shortsword")) as PackedScene
	assert_object(glb).is_not_null()
	assert_str(WeaponRegistry.find_id_by_glb(glb)).is_equal("shortsword")


func test_find_id_by_glb_resolves_axe() -> void:
	var glb := load(WeaponRegistry.get_glb_path("axe")) as PackedScene
	assert_object(glb).is_not_null()
	assert_str(WeaponRegistry.find_id_by_glb(glb)).is_equal("axe")


func test_find_id_by_glb_returns_empty_for_null() -> void:
	assert_str(WeaponRegistry.find_id_by_glb(null)).is_empty()


func test_find_id_by_glb_returns_empty_for_empty_path() -> void:
	# 新建 PackedScene 没有资源路径，反查应返回空
	var tmp := PackedScene.new()
	assert_str(WeaponRegistry.find_id_by_glb(tmp)).is_empty()


func test_resolve_weapon_data_returns_null_unchanged() -> void:
	# null 输入应原样返回，不崩溃
	assert_object(WeaponRegistry.resolve_weapon_data(null)).is_null()


func test_resolve_weapon_data_returns_weapon_with_id_unchanged() -> void:
	# 已有 id 的注册表武器无需解析，应原样返回
	var bow := WeaponRegistry.get_weapon_data("longbow")
	assert_object(bow).is_not_null()
	var resolved := WeaponRegistry.resolve_weapon_data(bow)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_equal("longbow")


func test_resolve_weapon_data_resolves_legacy_tres_shortsword() -> void:
	# 旧版 shortsword.tres 没有 id，但 glb_mesh 指向注册表中的武器
	# resolve_weapon_data 应返回注册表的完整版本
	var legacy := WeaponData.new()
	legacy.name = "Short Sword"
	legacy.damage_min = 3
	legacy.damage_max = 5
	legacy.glb_mesh = load(WeaponRegistry.get_glb_path("shortsword")) as PackedScene
	assert_str(legacy.id).is_empty()
	var resolved := WeaponRegistry.resolve_weapon_data(legacy)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_equal("shortsword")
	assert_str(resolved.weapon_class).is_equal("one_hand_melee")
	assert_str(resolved.attack_type).is_equal("melee")
	assert_str(resolved.skill_school).is_equal("one_hand_sword")
	assert_str(resolved.proficiency_key).is_equal("sword")
	assert_str(resolved.equipment_category).is_equal("weapons")
	assert_str(resolved.item_tag).is_equal("weapon")


func test_resolve_weapon_data_resolves_legacy_tres_axe() -> void:
	# 旧版 axe.tres 同样应被解析为注册表版本
	var legacy := WeaponData.new()
	legacy.name = "Axe"
	legacy.glb_mesh = load(WeaponRegistry.get_glb_path("axe")) as PackedScene
	assert_str(legacy.id).is_empty()
	var resolved := WeaponRegistry.resolve_weapon_data(legacy)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_equal("axe")
	assert_str(resolved.weapon_class).is_equal("two_hand")


func test_resolve_weapon_data_returns_unchanged_for_unknown_glb() -> void:
	# glb_mesh 不在注册表中时，应原样返回输入数据
	var legacy := WeaponData.new()
	legacy.name = "Unknown Weapon"
	var tmp_scene := PackedScene.new()  # 无 resource_path，不在注册表中
	legacy.glb_mesh = tmp_scene
	var resolved := WeaponRegistry.resolve_weapon_data(legacy)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_empty()
	assert_str(resolved.name).is_equal("Unknown Weapon")


func test_resolve_weapon_data_returns_unchanged_for_no_glb() -> void:
	# 无 id 且无 glb_mesh 的 WeaponData 无法解析，应原样返回
	var legacy := WeaponData.new()
	legacy.name = "Bare Weapon"
	var resolved := WeaponRegistry.resolve_weapon_data(legacy)
	assert_object(resolved).is_not_null()
	assert_str(resolved.id).is_empty()
	assert_str(resolved.name).is_equal("Bare Weapon")


func test_weapon_data_carries_combat_taxonomy_and_tier_values() -> void:
	var bow := WeaponRegistry.get_weapon_data("longbow")
	assert_str(bow.id).is_equal("longbow")
	assert_str(bow.weapon_class).is_equal("longbow")
	assert_str(bow.attack_type).is_equal("ranged")
	assert_str(bow.proficiency_key).is_equal("bow")
	assert_int(bow.damage_dice_count).is_equal(1)
	assert_int(bow.damage_dice_sides).is_equal(8)
	assert_int(bow.damage_flat).is_equal(2)


func test_shield_weapon_data_carries_phys_def_only() -> void:
	var shield := WeaponRegistry.get_weapon_data("shield")
	assert_str(shield.item_tag).is_equal("shield")
	assert_str(shield.weapon_class).is_equal("shield")
	assert_int(shield.shield_phys_def).is_equal(1)
	# 盾无概率格挡字段：仅物理防御
	assert_bool(not "shield_block_chance_percent" in shield).is_true()
	assert_bool(not "shield_block_value" in shield).is_true()


func test_armor_weapon_data_carries_defense_stats() -> void:
	var cloth := WeaponRegistry.get_weapon_data("cloth_armor")
	var leather := WeaponRegistry.get_weapon_data("leather_armor")
	var chain := WeaponRegistry.get_weapon_data("chain_armor")
	var plate := WeaponRegistry.get_weapon_data("plate_armor")
	assert_str(cloth.equipment_category).is_equal("armor_light")
	assert_str(cloth.armor_slot).is_equal("body")
	assert_int(cloth.armor_phys_def).is_equal(1)
	assert_float(cloth.armor_move_speed_mult).is_equal(1.0)
	assert_int(leather.armor_phys_def).is_equal(3)
	assert_float(leather.armor_move_speed_mult).is_equal(0.98)
	assert_int(chain.armor_phys_def).is_equal(6)
	assert_float(chain.armor_move_speed_mult).is_equal(0.94)
	assert_int(plate.armor_phys_def).is_equal(10)
	assert_float(plate.armor_move_speed_mult).is_equal(0.88)


func test_get_display_name_localized() -> void:
	var name := WeaponRegistry.get_display_name("greatsword")
	assert_bool(name.length() > 0).is_true()


func test_get_display_name_uses_chinese_json_name_in_chinese_locale() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var greatsword_name := WeaponRegistry.get_display_name("greatsword")
	var warhammer_name := WeaponRegistry.get_display_name("warhammer")
	var sword_name := WeaponRegistry.get_display_name("sword")
	TranslationServer.set_locale(old_locale)

	assert_str(greatsword_name).is_equal("双手大剑")
	assert_str(warhammer_name).is_equal("战锤")
	assert_str(sword_name).is_equal("长剑")


func test_model_viewer_entries_use_chinese_weapon_names_in_chinese_locale() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var entries := WeaponRegistry.get_model_viewer_entries()
	var names := _collect_model_viewer_item_names(entries)
	TranslationServer.set_locale(old_locale)

	assert_bool(names.has("战锤")).is_true()
	assert_bool(names.has("长枪")).is_true()
	assert_bool(names.has("轻弩")).is_true()
	assert_bool(names.has("长剑")).is_true()
	assert_bool(names.has("Warhammer")).is_false()
	assert_bool(names.has("Spear")).is_false()
	assert_bool(names.has("Crossbow")).is_false()
	assert_bool(names.has("Sword")).is_false()


func test_get_by_category_returns_all_categories() -> void:
	var by_cat := WeaponRegistry.get_by_category()
	assert_bool(by_cat.has("weapons")).is_true()
	assert_bool(by_cat.has("armor_light")).is_true()
	assert_bool(by_cat.has("armor_heavy")).is_true()
	assert_bool(by_cat.has("shields") or by_cat.has("accessories")).is_true()


func test_get_category_name_returns_display_name() -> void:
	# get_category_name 走 tr()，固定英文 locale 验证基础 key 映射
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_str(WeaponRegistry.get_category_name("weapons")).is_equal("Weapons")
	assert_str(WeaponRegistry.get_category_name("shields")).is_equal("Shields")
	TranslationServer.set_locale(old_locale)


func _collect_model_viewer_item_names(entries: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for group in entries.values():
		if group is Dictionary:
			for item_name in group.keys():
				names.append(String(item_name))
	return names


func _find_gear_entry(entries: Array[Dictionary], entry_id: String) -> Dictionary:
	for entry in entries:
		if entry.get("id", "") == entry_id:
			return entry
	return {}
