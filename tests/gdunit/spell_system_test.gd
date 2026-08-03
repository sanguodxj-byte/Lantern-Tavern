extends GdUnitTestSuite

const RecipeData := preload("res://globals/combat/spell_recipe_data.gd")
const SpellLoadoutScript := preload("res://globals/combat/spell_loadout.gd")
const AccessPolicy := preload("res://globals/combat/spell_access_policy.gd")
const SpellInterfaceScene := preload("res://scenes/ui/spell_interface.tscn")
const RuneData := preload("res://globals/combat/rune_data.gd")


func test_fixed_recipe_resolves_exact_order() -> void:
	var spell := RecipeData.resolve(["ember", "force", "launch"])
	assert_str(String(spell.get("id", ""))).is_equal("spell_fireball")
	assert_str(String(spell.get("name", ""))).is_equal("火球术")
	assert_str(String(spell.get("projectile_id", ""))).is_equal("elemental_bolt")
	assert_str(String(spell.get("status", ""))).is_equal("projectile_ready_not_wired")
	assert_bool(RecipeData.resolve(["force", "ember", "launch"]).is_empty()).is_true()


func test_every_spell_recipe_is_unique_fixed_and_has_imagery() -> void:
	var ids: Dictionary = {}
	for spell in RecipeData.get_all_recipes():
		var spell_id := String(spell.get("id", ""))
		var recipe: Array = spell.get("recipe", [])
		assert_bool(not spell_id.is_empty()).is_true()
		assert_bool(not ids.has(spell_id)) \
			.override_failure_message("法术 ID 重复: %s" % spell_id).is_true()
		ids[spell_id] = true
		assert_bool(recipe.size() >= 1 and recipe.size() <= RecipeData.RUNES_PER_SPELL).is_true()
		assert_str(String(spell.get("imagery", ""))) \
			.override_failure_message("法术缺少可绘制意象: %s" % spell_id).is_not_empty()
		assert_dict(RecipeData.resolve(recipe)).is_equal(spell)
		for rune_id in recipe:
			assert_bool(RuneData.has_rune(String(rune_id))) \
				.override_failure_message("法术 %s 引用了未知符文 %s" % [spell_id, rune_id]).is_true()


func test_loadout_has_five_spell_slots_and_three_runes_each() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_int(loadout.slot_runes.size()).is_equal(5)
	for rune_ids in loadout.slot_runes:
		assert_int(rune_ids.size()).is_equal(3)


func test_loadout_updates_spell_automatically_when_recipe_completes() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(0, 1, "force")).is_true()
	assert_bool(loadout.set_rune(0, 2, "launch")).is_true()
	assert_str(String(loadout.get_spell(0).get("id", ""))).is_equal("spell_fireball")


func test_loadout_rejects_gapped_rune_placement_and_clears_following_runes() -> void:
	var loadout := SpellLoadoutScript.new()
	assert_bool(loadout.set_rune(0, 1, "force")).is_false()
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(0, 1, "force")).is_true()
	assert_bool(loadout.set_rune(0, 0, "")).is_true()
	assert_array(loadout.get_runes(0)).is_equal(["", "", ""])


func test_loadout_inventory_limits_equipped_rune_copies() -> void:
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 1, "force": 2})
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_int(loadout.get_remaining_count("ember")).is_equal(0)
	assert_bool(loadout.set_rune(1, 0, "ember")).is_false()
	assert_bool(loadout.set_rune(1, 0, "force")).is_true()
	assert_int(loadout.get_remaining_count("force")).is_equal(1)


func test_loadout_reconciles_slots_when_inventory_shrinks() -> void:
	var loadout := SpellLoadoutScript.new()
	loadout.set_rune_inventory({"ember": 2})
	assert_bool(loadout.set_rune(0, 0, "ember")).is_true()
	assert_bool(loadout.set_rune(1, 0, "ember")).is_true()
	loadout.set_rune_inventory({"ember": 1})
	assert_array(loadout.get_runes(0)).is_equal(["ember", "", ""])
	assert_array(loadout.get_runes(1)).is_equal(["", "", ""])


func test_spell_access_policy_accepts_staff_and_grimoire() -> void:
	var staff := WeaponData.new()
	staff.id = "staff"
	staff.weapon_class = "wand"
	staff.skill_school = "staff"
	assert_bool(AccessPolicy.can_use_spell_interface(staff, false)).is_true()
	var grimoire := WeaponData.new()
	grimoire.id = "grimoire"
	grimoire.weapon_class = "grimoire"
	assert_bool(AccessPolicy.can_use_spell_interface(grimoire, false)).is_true()


func test_spell_access_policy_requires_arcane_sword_for_one_hand_sword() -> void:
	var sword := WeaponData.new()
	sword.id = "shortsword"
	sword.weapon_class = "one_hand_melee"
	sword.skill_school = "one_hand_sword"
	assert_bool(AccessPolicy.can_use_spell_interface(sword, false)).is_false()
	assert_bool(AccessPolicy.can_use_spell_interface(sword, true)).is_true()


func test_spell_access_policy_rejects_unrelated_weapon_even_with_passive() -> void:
	var bow := WeaponData.new()
	bow.id = "longbow"
	bow.weapon_class = "longbow"
	bow.skill_school = "longbow"
	assert_bool(AccessPolicy.can_use_spell_interface(bow, true)).is_false()


func test_spell_interface_builds_five_spell_rows_and_three_runes_per_row() -> void:
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	assert_int(ui._spell_buttons.size()).is_equal(5)
	assert_int(ui._rune_slot_buttons.size()).is_equal(5)
	for row in ui._rune_slot_buttons:
		assert_int(row.size()).is_equal(3)


func test_spell_interface_switches_body_orientation_at_compact_width() -> void:
	var ui := SpellInterfaceScene.instantiate()
	auto_free(ui)
	add_child(ui)
	await get_tree().process_frame
	ui.size = Vector2(1600, 900)
	ui._apply_responsive_layout()
	assert_bool(ui._body is BoxContainer).is_true()
	assert_bool(ui._body.vertical).is_false()
	assert_bool(ui._rune_panel.visible).is_true()
	ui.size = Vector2(1280, 720)
	ui._apply_responsive_layout()
	assert_bool(ui._body.vertical).is_false()
	assert_bool(ui._rune_panel.visible).is_false()
	ui.size = Vector2(960, 900)
	ui._apply_responsive_layout()
	assert_bool(ui._body.vertical).is_true()
	assert_bool(ui._rune_panel.visible).is_true()
	assert_float(ui._rune_panel.custom_minimum_size.y).is_equal(180.0)
