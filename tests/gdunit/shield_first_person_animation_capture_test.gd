extends GdUnitTestSuite

const CAPTURE_TOOL := "res://tools/shield_first_person_animation_capture.gd"
const VIEW_MODEL_SCENE: PackedScene = preload("res://scenes/characters/player/view_model.tscn")
const SWORD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_sword.glb")
const SHIELD_SCENE: PackedScene = preload("res://assets/meshes/weapons/weapons_voxel_shield.glb")


func test_shield_capture_uses_equipment_only_and_checks_independent_main_hand() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_TOOL)
	assert_str(source).contains("view_model.tscn")
	assert_str(source).contains("weapons_voxel_sword.glb")
	assert_str(source).contains("weapons_voxel_shield.glb")
	assert_str(source).contains("vm_shield_block")
	assert_str(source).contains("play_block_impact")
	assert_str(source).contains("_assert_weapon_unchanged")
	assert_str(source).contains("QUALITY.validate")
	assert_bool(source.find("image.save_png") < source.find("QUALITY.analyze")) \
		.override_failure_message("failed shield review frames must remain available for diagnosis") \
		.is_true()
	assert_str(source).not_contains("player.tscn")


func test_runtime_shield_block_and_impact_never_write_main_hand_pivots() -> void:
	var view_model := auto_free(VIEW_MODEL_SCENE.instantiate()) as ViewModel
	view_model.use_weapon_camera = false
	add_child(view_model)
	await get_tree().process_frame
	var sword := _weapon("sword", "weapon", "one_hand_melee", SWORD_SCENE)
	sword.skill_school = "one_hand_sword"
	sword.view_model_profile = "sword"
	view_model.set_weapon(sword)
	var shield := _weapon("shield", "shield", "shield", SHIELD_SCENE)
	shield.view_model_profile = "shield"
	view_model.set_shield(shield)
	assert_vector(view_model.shield_view_position).is_equal(Vector3(-0.30, -0.12, -0.55))
	assert_vector(view_model._current_shield_node.scale).is_equal_approx(Vector3.ONE * 0.30, Vector3.ONE * 0.001)
	view_model.sample_action(&"vm_sword_hold", 0.0)
	var action_before := view_model.action_pivot.transform
	var socket_before := view_model.weapon_socket.transform
	view_model.sample_action(&"vm_shield_block", 0.5)
	assert_bool(view_model.shield_action_pivot.transform.is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_bool(view_model.action_pivot.transform.is_equal_approx(action_before)).is_true()
	assert_bool(view_model.weapon_socket.transform.is_equal_approx(socket_before)).is_true()
	view_model.play_block_impact(1.0, 0.25)
	view_model.equipment_motion.step(1.0 / 60.0)
	view_model.shield_impact_pivot.transform = view_model.equipment_motion.get_shield_impact_transform()
	assert_bool(view_model.shield_impact_pivot.transform.is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_bool(view_model.action_pivot.transform.is_equal_approx(action_before)).is_true()


func test_shield_view_model_reset_has_no_character_geometry_or_impact_rebound() -> void:
	var view_model := auto_free(VIEW_MODEL_SCENE.instantiate()) as ViewModel
	view_model.use_weapon_camera = false
	add_child(view_model)
	await get_tree().process_frame
	var shield := _weapon("shield", "shield", "shield", SHIELD_SCENE)
	shield.view_model_profile = "shield"
	view_model.set_shield(shield)
	view_model.play_block_impact(1.0, -0.3)
	view_model.equipment_motion.step(1.0 / 60.0)
	view_model.stop_action(true)
	view_model.equipment_motion.step(1.0 / 60.0)
	assert_bool(view_model.equipment_motion.get_shield_impact_transform().is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_object(view_model.find_child("PlayerVisualModel", true, false)).is_null()
	assert_object(view_model.find_child("Skeleton3D", true, false)).is_null()
	assert_object(view_model.find_child("BoneAttachment3D", true, false)).is_null()


func _weapon(id: String, item_tag: String, weapon_class: String, mesh: PackedScene) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.id = id
	weapon.item_tag = item_tag
	weapon.weapon_class = weapon_class
	weapon.material_tier = "iron"
	weapon.glb_mesh = mesh
	return weapon
