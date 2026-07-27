extends GdUnitTestSuite

const VIEW_MODEL_SCENE := "res://scenes/characters/player/view_model.tscn"
const VIEW_MODEL_SCRIPT := "res://scenes/characters/player/view_model.gd"
const PLAYER_SCRIPT := "res://scenes/characters/player/player.gd"

func test_production_player_does_not_bind_first_person_to_third_person_player() -> void:
	var player_source := FileAccess.get_file_as_string(PLAYER_SCRIPT)
	var view_model_source := FileAccess.get_file_as_string(VIEW_MODEL_SCRIPT)
	assert_str(player_source).not_contains("bind_shared_character_animation(")
	assert_str(player_source).contains("view_model.set_weapon")
	assert_str(view_model_source).contains("first_person_arm_animator")
	assert_str(view_model_source).contains("_configure_first_person_arms")
	assert_str(view_model_source).contains("visual_only")

func test_view_model_owns_an_independent_animation_player_and_complete_style_library() -> void:
	var view_model := _create_view_model()
	assert_bool(view_model._uses_shared_character_animation).is_false()
	assert_bool(view_model.animation_player.has_animation(&"vm_greatsword_heavy_swing")).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_bow_aim")).is_true()
	assert_bool(view_model.animation_player.has_animation(&"vm_shield_block")).is_true()

func test_view_model_action_does_not_move_a_third_person_animation_player() -> void:
	var view_model := _create_view_model()
	var third_person_player := AnimationPlayer.new()
	add_child(third_person_player)
	var placeholder := Node3D.new()
	add_child(placeholder)
	view_model.bind_shared_character_animation(third_person_player, placeholder)
	view_model.play_action(&"vm_sword_slash")
	assert_str(String(third_person_player.current_animation)).is_empty()
	assert_str(String(view_model.animation_player.current_animation)).is_equal("vm_sword_slash")
	third_person_player.queue_free()
	placeholder.queue_free()

func test_first_person_weapon_is_visual_only_and_separate_from_gameplay_mount() -> void:
	var view_model := _create_view_model()
	var weapon := WeaponData.new()
	weapon.id = "first-person-test-sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.skill_school = "one_hand_sword"
	weapon.glb_mesh = _make_mock_mesh_scene()
	view_model.set_weapon(weapon)

	assert_object(view_model._current_weapon_node).is_not_null()
	assert_bool(view_model._current_weapon_node.get_meta("visual_only", false)).is_true()
	assert_object(view_model._current_weapon_node.find_child("Area3D", true, false)).is_null()
	assert_object(view_model._current_weapon_node.find_child("CollisionShape3D", true, false)).is_null()

func test_legacy_shared_bind_cannot_disable_local_first_person_library() -> void:
	var view_model := _create_view_model()
	var third_person_player := AnimationPlayer.new()
	add_child(third_person_player)
	var placeholder := Node3D.new()
	add_child(placeholder)
	view_model.bind_shared_character_animation(third_person_player, placeholder)
	assert_bool(view_model._uses_shared_character_animation).is_false()
	assert_bool(view_model.animation_player.has_animation(&"vm_crossbow_reload")).is_true()
	third_person_player.queue_free()
	placeholder.queue_free()

func test_first_person_state_cleanup_stops_only_local_visual_action() -> void:
	var source := FileAccess.get_file_as_string(VIEW_MODEL_SCRIPT)
	assert_str(source).contains("func finish_weapon_release()")
	assert_str(source).contains("first_person_arm_animator.reset_pose()")
	assert_str(source).contains("func finish_weapon_defense")

func _create_view_model() -> ViewModel:
	var scene := load(VIEW_MODEL_SCENE) as PackedScene
	var view_model: ViewModel = auto_free(scene.instantiate())
	add_child(view_model)
	return view_model

func _make_mock_mesh_scene() -> PackedScene:
	var mock_mesh := MeshInstance3D.new()
	mock_mesh.mesh = BoxMesh.new()
	var mock_scene := PackedScene.new()
	mock_scene.pack(mock_mesh)
	mock_mesh.free()
	return mock_scene
