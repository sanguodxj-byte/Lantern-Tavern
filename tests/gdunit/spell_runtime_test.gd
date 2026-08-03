extends GdUnitTestSuite
const Runtime := preload("res://globals/combat/spell_runtime.gd")
const Loadout := preload("res://globals/combat/spell_loadout.gd")
const Mana := preload("res://scenes/characters/component/mana_component.gd")

class FakeCaster:
	extends Node
	var mana: ManaComponent
	func _init() -> void:
		mana = Mana.new()
		add_child(mana)

func test_prepare_and_commit_fixed_fireball() -> void:
	var loadout := Loadout.new()
	loadout.set_rune_inventory({"ember":1,"force":1,"launch":1})
	loadout.set_rune(0,0,"ember"); loadout.set_rune(0,1,"force"); loadout.set_rune(0,2,"launch")
	var caster := FakeCaster.new(); add_child(caster)
	var runtime := Runtime.new()
	var plan := runtime.prepare_cast(loadout, 0, caster, Vector3.ZERO, Vector3.FORWARD)
	assert_bool(bool(plan.get("ok", false))).is_true()
	assert_str(String(plan.get("spell_id", ""))).is_equal("spell_fireball")
	assert_str(String(plan.get("imagery", ""))).is_equal("fireball")
	var result := runtime.commit_cast(plan, caster)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(caster.mana.current_mana).is_equal(80)
	assert_bool(bool(Dictionary(result.get("effect_plan", {})).get("fx_is_cosmetic", false))).is_true()
	caster.queue_free()

func test_runtime_rejects_empty_slot_and_bad_direction() -> void:
	var loadout := Loadout.new(); var caster := FakeCaster.new(); add_child(caster); var runtime := Runtime.new()
	assert_str(String(runtime.prepare_cast(loadout,0,caster,Vector3.ZERO,Vector3.FORWARD).reason)).is_equal("empty_spell_slot")
	loadout.set_rune_inventory({"ember":1}); loadout.set_rune(0,0,"ember")
	assert_str(String(runtime.prepare_cast(loadout,0,caster,Vector3.ZERO,Vector3.ZERO).reason)).is_equal("invalid_direction")
	caster.queue_free()

func test_runtime_rejects_insufficient_mana_and_cooldown() -> void:
	var loadout := Loadout.new(); loadout.set_rune_inventory({"ember":1}); loadout.set_rune(0,0,"ember")
	var caster := FakeCaster.new(); add_child(caster); caster.mana.current_mana = 5
	var runtime := Runtime.new()
	assert_str(String(runtime.prepare_cast(loadout,0,caster,Vector3.ZERO,Vector3.FORWARD).reason)).is_equal("insufficient_mana")
	caster.mana.current_mana = 100
	assert_bool(bool(runtime.cast_slot(loadout,0,caster,Vector3.ZERO,Vector3.FORWARD).ok)).is_true()
	assert_str(String(runtime.prepare_cast(loadout,0,caster,Vector3.ZERO,Vector3.FORWARD).reason)).is_equal("cooldown")
	caster.queue_free()

func test_all_implementation_categories_produce_authority_plan() -> void:
	var runtime := Runtime.new()
	for implementation in ["projectile","ray","area","ground","barrier","heal","movement","buff","summon"]:
		var plan := {"implementation":implementation,"spell":{},"spell_id":"x","imagery":"x","mana_cost":0,"cooldown_sec":0.0,"origin":Vector3.ZERO,"direction":Vector3.FORWARD,"ok":true,"visual_event":{}}
		var caster := FakeCaster.new(); add_child(caster)
		var result := runtime.commit_cast(plan,caster)
		assert_bool(bool(Dictionary(result.effect_plan).authoritative)).is_true()
		caster.queue_free()
