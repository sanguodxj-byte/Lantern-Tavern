extends GdUnitTestSuite
const Access := preload("res://globals/combat/spell_access_policy.gd")
const Loadout := preload("res://globals/combat/spell_loadout.gd")
const Caster := preload("res://scenes/characters/player/player_spell_caster.gd")

func test_staff_and_grimoire_can_open_spell_interface() -> void:
	for kind in ["wand","grimoire"]:
		var weapon := WeaponData.new(); weapon.id = kind; weapon.weapon_class = kind; weapon.skill_school = "staff" if kind == "wand" else "grimoire"
		assert_bool(Access.can_use_spell_interface(weapon,false)).is_true()
	var sword := WeaponData.new(); sword.id="shortsword"; sword.weapon_class="one_hand_melee"; sword.skill_school="one_hand_sword"
	assert_bool(Access.can_use_spell_interface(sword,false)).is_false()

func test_rune_composition_resolves_and_selection_signal_is_wired() -> void:
	var loadout := Loadout.new(); loadout.set_rune_inventory({"ember":1,"force":1,"launch":1})
	assert_bool(loadout.set_rune(0,0,"ember")).is_true(); assert_bool(loadout.set_rune(0,1,"force")).is_true(); assert_bool(loadout.set_rune(0,2,"launch")).is_true()
	assert_str(String(loadout.get_spell(0).id)).is_equal("spell_fireball")
	var hud_source := (load("res://scenes/ui/combat_hud.gd") as GDScript).source_code
	assert_bool(hud_source.contains("_on_spell_slot_selected")).is_true()
	assert_bool(hud_source.contains("spell_caster.select_slot")).is_true()

func test_staff_grimoire_release_requires_full_charge() -> void:
	var caster := Caster.new()
	assert_str(String(caster.release_full_charge(null,0.5).reason)).is_equal("spell_not_fully_charged")
	var caster_source := (load("res://scenes/characters/player/player_spell_caster.gd") as GDScript).source_code
	assert_bool(caster_source.contains("charge_ratio < 1.0")).is_true()
	assert_bool(caster_source.contains("invalid_spell_focus")).is_true()
	var state_source := (load("res://scenes/characters/player/state/player_state_attack_preparing.gd") as GDScript).source_code
	assert_bool(state_source.contains("is_active_spell_focus_weapon")).is_true()
	assert_bool(state_source.contains("release_full_charge")).is_true()
	assert_bool(state_source.contains("800.0")).is_true()

func test_player_focus_detection_uses_staff_grimoire_profiles() -> void:
	var source := (load("res://scenes/characters/player/player.gd") as GDScript).source_code
	var section := source.substr(source.find("func is_active_spell_focus_weapon"), 550)
	assert_bool(section.contains("staff")).is_true()
	assert_bool(section.contains("grimoire")).is_true()
