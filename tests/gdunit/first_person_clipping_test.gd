extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/characters/player/player.tscn")
const VIEW_MODEL_SCENE := preload("res://scenes/characters/player/view_model.tscn")


func test_camera_near_plane_stays_inside_player_collision_clearance() -> void:
	var player: Node = auto_free(PLAYER_SCENE.instantiate())
	var camera := player.get_node("MainCamera") as Camera3D
	var collision_shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := collision_shape.shape as CapsuleShape3D
	var horizontal_camera_offset := Vector2(camera.position.x, camera.position.z).length()

	var maximum_impact_shake := 0.06
	assert_float(horizontal_camera_offset + camera.near + maximum_impact_shake).is_less_equal(capsule.radius - capsule.margin)


func test_main_camera_uses_stable_near_clip_distance() -> void:
	var player: Node = auto_free(PLAYER_SCENE.instantiate())
	var camera := player.get_node("MainCamera") as Camera3D

	assert_float(camera.near).is_greater_equal(0.03)


func test_weapon_overlay_uses_a_private_world_in_every_display_mode() -> void:
	var rig: Node3D = auto_free(Node3D.new()) as Node3D
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var view_model := VIEW_MODEL_SCENE.instantiate() as ViewModel
	camera.add_child(view_model)
	add_child(rig)
	await get_tree().process_frame

	assert_object(view_model._weapon_subviewport).is_not_null()
	assert_object(view_model._weapon_camera).is_not_null()
	if view_model._weapon_subviewport == null or view_model._weapon_camera == null:
		return
	assert_bool(view_model._weapon_subviewport.own_world_3d).is_true()
	assert_bool(view_model._weapon_subviewport.world_3d == get_viewport().world_3d).is_false()
	assert_int(view_model._weapon_camera.cull_mask).is_equal(view_model.VIEW_MODEL_RENDER_LAYER)


func test_weapon_visual_is_mirrored_into_the_private_overlay_world() -> void:
	var rig: Node3D = auto_free(Node3D.new()) as Node3D
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var view_model := VIEW_MODEL_SCENE.instantiate() as ViewModel
	camera.add_child(view_model)
	add_child(rig)
	await get_tree().process_frame
	if view_model._weapon_subviewport == null:
		assert_object(view_model._weapon_subviewport).is_not_null()
		return

	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.glb_mesh = _make_mock_mesh_scene()
	view_model.set_weapon(weapon)
	view_model._sync_weapon_camera()

	assert_object(view_model._weapon_overlay_node).is_not_null()
	assert_int(_first_geometry(view_model._current_weapon_node).layers).is_equal(view_model.WEAPON_VIEW_RENDER_LAYER)
	assert_int(_first_geometry(view_model._weapon_overlay_node).layers).is_equal(view_model.VIEW_MODEL_RENDER_LAYER)
	assert_bool(view_model._weapon_overlay_node.get_world_3d() == get_viewport().world_3d).is_false()


func test_weapon_obstruction_weight_tracks_surface_distance() -> void:
	var view_model := VIEW_MODEL_SCENE.instantiate() as ViewModel
	assert_bool(view_model.has_method("obstruction_weight_for_distance")).is_true()
	if not view_model.has_method("obstruction_weight_for_distance"):
		view_model.free()
		return
	assert_float(view_model.obstruction_weight_for_distance(-1.0)).is_equal(0.0)
	assert_float(view_model.obstruction_weight_for_distance(0.75)).is_equal(0.0)
	assert_float(view_model.obstruction_weight_for_distance(0.25)).is_equal(1.0)
	assert_float(view_model.obstruction_weight_for_distance(0.50)).is_equal_approx(0.5, 0.001)
	view_model.free()


func test_solid_surface_retracts_and_lowers_the_complete_view_model() -> void:
	var rig := auto_free(Node3D.new()) as Node3D
	var camera := Camera3D.new()
	camera.current = true
	rig.add_child(camera)
	var view_model := VIEW_MODEL_SCENE.instantiate() as ViewModel
	view_model.weapon_sway_strength = 0.0
	camera.add_child(view_model)

	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	obstacle.collision_mask = 0
	obstacle.position = Vector3(0.0, 0.0, -0.35)
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.1)
	collision_shape.shape = box
	obstacle.add_child(collision_shape)
	rig.add_child(obstacle)
	add_child(rig)
	await get_tree().physics_frame
	await get_tree().physics_frame

	view_model._update_weapon_obstruction(1.0)
	view_model._process(0.0)
	assert_float(view_model._weapon_obstruction_weight).is_greater(0.8)
	assert_float(view_model.bob_pivot.position.y).is_less(-0.15)
	assert_float(view_model.bob_pivot.position.z).is_greater(0.20)

	obstacle.collision_layer = 0
	await get_tree().physics_frame
	view_model._update_weapon_obstruction(1.0)
	view_model._process(0.0)
	assert_float(view_model._weapon_obstruction_weight).is_equal_approx(0.0, 0.001)
	assert_vector(view_model.bob_pivot.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_nearby_world_geometry_cannot_cover_the_weapon_overlay_pixels(
	_do_skip: bool = DisplayServer.get_name() == "headless",
	_skip_reason: String = "Pixel compositing requires a non-headless renderer."
) -> void:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	var occluder := MeshInstance3D.new()
	var occluder_mesh := BoxMesh.new()
	occluder_mesh.size = Vector3(2.0, 2.0, 0.05)
	occluder.mesh = occluder_mesh
	occluder.material_override = _unshaded_material(Color(0.9, 0.05, 0.05))
	occluder.position = Vector3(0.0, 0.0, -0.25)
	viewport.add_child(occluder)

	var view_model := VIEW_MODEL_SCENE.instantiate() as ViewModel
	view_model.weapon_sway_strength = 0.0
	camera.add_child(view_model)
	await get_tree().process_frame

	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.item_tag = "weapon"
	weapon.weapon_class = "one_hand_melee"
	weapon.glb_mesh = _make_mock_mesh_scene(Color(0.05, 0.9, 0.05))
	view_model.set_weapon(weapon)
	_first_geometry(view_model._weapon_overlay_node).material_override = _unshaded_material(Color(0.05, 0.9, 0.05))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var overlay_container := view_model.get_node("WeaponOverlay").get_child(0) as SubViewportContainer
	assert_vector(overlay_container.size).is_equal(Vector2(256.0, 256.0))
	var overlay_image := view_model._weapon_subviewport.get_texture().get_image()
	assert_bool(overlay_image != null and not overlay_image.is_empty()).is_true()
	if overlay_image == null or overlay_image.is_empty():
		return
	assert_int(_count_green_pixels(overlay_image)).is_greater(5)

	var image := viewport.get_texture().get_image()
	assert_bool(image != null and not image.is_empty()).is_true()
	if image == null or image.is_empty():
		return
	var red_pixels := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.55 and pixel.r > pixel.g * 2.0:
				red_pixels += 1
	assert_int(red_pixels).is_greater(100)
	assert_int(_count_green_pixels(image)).is_greater(5)


func _make_mock_mesh_scene(color: Color = Color.WHITE) -> PackedScene:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	mesh_instance.material_override = _unshaded_material(color)
	var scene := PackedScene.new()
	scene.pack(mesh_instance)
	mesh_instance.free()
	return scene


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _count_green_pixels(image: Image) -> int:
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if pixel.g > 0.55 and pixel.g > pixel.r * 2.0:
				count += 1
	return count


func _first_geometry(root: Node) -> GeometryInstance3D:
	if root is GeometryInstance3D:
		return root as GeometryInstance3D
	return root.find_child("*", true, false) as GeometryInstance3D
