extends GdUnitTestSuite

const EQUIPMENT_SCENE := preload("res://scenes/characters/component/equipment_component.tscn")
const LEGACY_AXE := preload("res://data/weapons/axe.tres")
const SLASH_ANIM := preload("res://globals/combat/combat_slash_animator.gd")


func test_scene_legacy_weapon_resolves_to_registry_combat_metadata() -> void:
	var equipment := auto_free(EQUIPMENT_SCENE.instantiate()) as EquipmentComponent
	equipment.weapon_data = LEGACY_AXE
	add_child(equipment)
	await get_tree().process_frame
	assert_str(equipment.weapon_data.id).is_equal("axe")
	assert_str(equipment.weapon_data.weapon_class).is_equal("two_hand")
	assert_str(equipment.weapon_data.hands).is_equal("two_hand")
	assert_str(SLASH_ANIM.enemy_animation_name(equipment.weapon_data)).is_equal("slash_heavy")
