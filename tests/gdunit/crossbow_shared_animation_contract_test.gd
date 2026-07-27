extends GdUnitTestSuite

const SPEC_PATH := "res://globals/visual/voxel_animation_spec.gd"
const PLAYER_GENERATOR_PATH := "res://tools/generate_voxel_player.py"
const VIEW_MODEL_SOURCE_PATH := "res://scenes/characters/player/view_model.gd"
const SHOOTING_SOURCE_PATH := "res://scenes/characters/player/state/player_state_shooting.gd"
const MOVING_SOURCE_PATH := "res://scenes/characters/player/state/player_state_moving.gd"
const VIEW_MODEL_SCENE := "res://scenes/characters/player/view_model.tscn"
const PROFILE := preload("res://globals/visual/player_animation_profile.gd")


func test_crossbow_animation_names_are_registered_in_humanoid_contract() -> void:
	var source := FileAccess.get_file_as_string(SPEC_PATH)
	assert_str(source).contains("PLAYER_WEAPON_ANIMATIONS")
	assert_str(source).contains('"crossbow_aim"')
	assert_str(source).contains('"crossbow_fire"')
	assert_str(source).contains('"crossbow_reload"')


func test_player_generator_authors_dedicated_crossbow_actions() -> void:
	var source := FileAccess.get_file_as_string(PLAYER_GENERATOR_PATH)
	assert_str(source).contains('from voxel_character_rig import')
	assert_str(source).contains('make_action')
	assert_str(source).contains('def build_player_crossbow_actions')
	assert_str(source).contains('make_action(armature, "crossbow_aim"')
	assert_str(source).contains('make_action(armature, "crossbow_fire"')
	assert_str(source).contains('make_action(armature, "crossbow_reload"')
	assert_str(source).contains("build_player_crossbow_actions(armature)")


func test_crossbow_uses_distinct_first_and_third_person_clips() -> void:
	var source := FileAccess.get_file_as_string(VIEW_MODEL_SOURCE_PATH)
	var crossbow := _crossbow_data()
	var view_model := auto_free((load(VIEW_MODEL_SCENE) as PackedScene).instantiate()) as ViewModel
	add_child(view_model)
	assert_str(String(PROFILE.hold_animation(crossbow))).is_equal("crossbow_hold")
	assert_str(String(PROFILE.defense_animation(crossbow))).is_equal("crossbow_aim")
	assert_str(String(PROFILE.release_animation(crossbow))).is_equal("crossbow_fire")
	assert_bool(view_model.animation_player.has_animation(&"vm_crossbow_hold")).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_crossbow_aim")).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_crossbow_fire")).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_crossbow_reload")).is_true()
	assert_str(source).contains("PLAYER_ANIMATION_PROFILE")
	assert_str(source).contains('view_model_action(action)')
	assert_str(source).contains('first_person_arm_animator.play_action(action)')
	assert_str(source).contains('_weapon_subviewport.own_world_3d = true')
	assert_str(source).not_contains('_weapon_subviewport.world_3d = get_viewport().world_3d')
	assert_str(source).contains('SHADING_MODE_UNSHADED')


func test_shooting_state_selects_crossbow_fire_instead_of_throw_weapon() -> void:
	var source := FileAccess.get_file_as_string(SHOOTING_SOURCE_PATH)
	assert_str(source).contains('PLAYER_ANIMATION_PROFILE.release_animation(player.get_active_hand_weapon_data())')
	assert_str(source).contains('PLAYER_ANIMATION_PROFILE.view_model_action(')
	assert_str(source).not_contains('var shoot_animation_name := "throw_weapon"')


func test_reload_animation_cannot_be_overwritten_by_moving_idle() -> void:
	var source := FileAccess.get_file_as_string(MOVING_SOURCE_PATH)
	assert_str(source).contains('player.is_crossbow_reloading()')
	assert_str(source).contains('return')


func test_crossbow_reload_waits_for_the_imported_fire_clip() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/player.gd")
	assert_str(source).contains('animation_player.get_animation("crossbow_fire").length + 0.01')
	assert_str(source).contains('view_model.play_action_after(&"vm_crossbow_reload", fire_animation_delay')
	assert_str(source).contains('AnimationPlayer remains untouched and owns the shooting state\'s exit signal.')
	assert_str(source).not_contains('animation_player.play("crossbow_reload")')


func _crossbow_data() -> WeaponData:
	var weapon := WeaponData.new()
	weapon.id = "crossbow"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "crossbow"
	weapon.skill_school = "light_crossbow"
	weapon.tags = ["crossbow", "light_crossbow"]
	return weapon
