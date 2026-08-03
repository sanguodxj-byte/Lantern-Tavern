extends GdUnitTestSuite
const Context := preload("res://globals/core/player_context.gd")
const Attrs := preload("res://globals/combat/attr_panel.gd")
const Skills := preload("res://globals/combat/skill_runtime.gd")
const Inv := preload("res://globals/core/state/expedition_inventory.gd")
const Equip := preload("res://globals/core/state/equipment_loadout.gd")
const Recipes := preload("res://globals/combat/spell_recipe_data.gd")

func test_spell_state_serializes_loadout_mana_and_cooldowns() -> void:
	var attrs1 := Attrs.new(); var skills1 := Skills.new(); var inv1 := Inv.new(); var equip1 := Equip.new()
	var ctx := Context.new(attrs1, skills1, inv1, equip1)
	ctx.spell_loadout.set_rune_inventory({"ember":1,"force":1,"launch":1})
	ctx.spell_loadout.set_rune(0,0,"ember"); ctx.spell_loadout.set_rune(0,1,"force"); ctx.spell_loadout.set_rune(0,2,"launch")
	ctx.spell_mana = 42
	var spell := ctx.spell_loadout.get_spell(0)
	ctx.spell_runtime.commit_authoritative_cooldown(spell)
	var data := ctx.serialize_spell_state()
	var attrs2 := Attrs.new(); var skills2 := Skills.new(); var inv2 := Inv.new(); var equip2 := Equip.new()
	var ctx2 := Context.new(attrs2, skills2, inv2, equip2)
	ctx2.deserialize_spell_state(data)
	assert_array(ctx2.spell_loadout.get_runes(0)).is_equal(["ember","force","launch"])
	assert_int(ctx2.spell_mana).is_equal(42)
	assert_bool(ctx2.spell_runtime.is_on_cooldown("spell_fireball")).is_true()
	ctx = null; ctx2 = null
	attrs1.free(); skills1.free(); inv1 = null; equip1 = null
	attrs2.free(); skills2.free(); inv2 = null; equip2 = null

func test_recipe_count_remains_fixed_and_unique() -> void:
	var ids := {}
	for spell in Recipes.get_all_recipes():
		var id := String(spell.get("id", ""))
		assert_bool(not ids.has(id)).is_true()
		ids[id] = true
	assert_int(ids.size()).is_equal(33)
