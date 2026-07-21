extends GdUnitTestSuite

const VIEW_MODEL_SCENE := "res://scenes/characters/player/view_model.tscn"
const SWORD_MESH := "res://assets/meshes/weapons/weapons_voxel_sword.glb"
const REPORT_DIR := "res://reports"


func test_sword_uses_dedicated_profile_and_actions() -> void:
	var fixture := await _create_fixture()
	var view_model: ViewModel = fixture.view_model
	assert_str(String(view_model.resolve_weapon_profile(fixture.weapon))).is_equal("sword")
	assert_str(String(view_model.resolve_hold_action(fixture.weapon))).is_equal("vm_sword_hold")
	assert_str(String(view_model.resolve_melee_action(fixture.weapon))).is_equal("vm_sword_slash")
	assert_object(view_model.animation_player.get_animation("vm_sword_hold")).is_not_null()
	assert_object(view_model.animation_player.get_animation("vm_sword_slash")).is_not_null()
	fixture.viewport.queue_free()


func test_sword_slash_is_a_downward_cut_not_a_short_thrust() -> void:
	var fixture := await _create_fixture()
	var animation: Animation = fixture.view_model.animation_player.get_animation("vm_sword_slash") as Animation
	var position_track := -1
	var rotation_track := -1
	for track_index in animation.get_track_count():
		var track_path := String(animation.track_get_path(track_index))
		if track_path == "ActionPivot:position":
			position_track = track_index
		elif track_path == "ActionPivot:rotation":
			rotation_track = track_index
	assert_int(position_track).is_greater_equal(0)
	assert_int(rotation_track).is_greater_equal(0)
	var start_position: Vector3 = animation.track_get_key_value(position_track, 0)
	var peak_position: Vector3 = animation.track_get_key_value(position_track, 2)
	var start_rotation: Vector3 = animation.track_get_key_value(rotation_track, 0)
	var peak_rotation: Vector3 = animation.track_get_key_value(rotation_track, 2)
	assert_float(peak_position.y).is_less(start_position.y - 0.1)
	assert_float(peak_position.z).is_less(start_position.z)
	assert_float(absf(peak_rotation.x - start_rotation.x)).is_less(0.01)
	assert_float(absf(peak_rotation.z - start_rotation.z)).is_less(0.01)
	fixture.viewport.queue_free()


func test_sword_hold_and_slash_screenshots() -> void:
	var fixture := await _create_fixture()
	var viewport: SubViewport = fixture.viewport
	var view_model: ViewModel = fixture.view_model
	if DisplayServer.get_name() == "headless":
		assert_bool(view_model.begin_weapon_hold()).is_true()
		view_model.update_weapon_hold(1.0)
		assert_bool(view_model.release_weapon_hold()).is_true()
		view_model.begin_weapon_release(view_model.resolve_melee_action())
		view_model.finish_weapon_release()
		viewport.queue_free()
		return

	assert_bool(view_model.begin_weapon_hold()).is_true()
	view_model.update_weapon_hold(0.0)
	await _settle(viewport)
	var ready_image := _capture(viewport, "fp_weapon_sword_ready_v1.png")

	view_model.update_weapon_hold(1.0)
	assert_str(String(view_model.get_visual_weapon_state_name())).is_equal("holding")
	await _settle(viewport)
	var hold_image := _capture(viewport, "fp_weapon_sword_hold_v1.png")

	assert_bool(view_model.release_weapon_hold()).is_true()
	view_model.begin_weapon_release(view_model.resolve_melee_action())
	view_model.sample_action(view_model.resolve_melee_action(), 0.5)
	await _settle(viewport)
	var slash_image := _capture(viewport, "fp_weapon_sword_slash_v1.png")

	assert_bool(_has_visible_variation(ready_image)).is_true()
	assert_bool(_has_visible_variation(hold_image)).is_true()
	assert_bool(_has_visible_variation(slash_image)).is_true()
	assert_bool(_images_are_different(ready_image, hold_image)).is_true()
	assert_bool(_images_are_different(hold_image, slash_image)).is_true()
	var ready_bounds := _content_bounds(ready_image)
	var hold_bounds := _content_bounds(hold_image)
	var slash_bounds := _content_bounds(slash_image)
	assert_int(ready_bounds.position.y).is_less(220)
	assert_int(ready_bounds.end.y).is_greater(260)
	assert_int(hold_bounds.position.x).is_greater(350)
	assert_int(hold_bounds.end.y).is_greater(230)
	assert_int(slash_bounds.size.x).is_greater(100)
	assert_int(slash_bounds.position.x).is_less(360)
	assert_int(slash_bounds.end.x).is_greater(400)
	view_model.finish_weapon_release()
	viewport.queue_free()


func _create_fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var environment_data := Environment.new()
	environment_data.background_mode = Environment.BG_COLOR
	environment_data.background_color = Color("101722")
	environment_data.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_data.ambient_light_color = Color("8090a8")
	environment_data.ambient_light_energy = 0.85
	environment.environment = environment_data
	world.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key_light.light_energy = 1.8
	key_light.shadow_enabled = false
	world.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-1.5, 0.5, 0.5)
	fill_light.light_color = Color("7895c7")
	fill_light.light_energy = 2.2
	fill_light.omni_range = 5.0
	fill_light.shadow_enabled = false
	world.add_child(fill_light)

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 72.0
	camera.near = 0.001
	camera.cull_mask = 1
	world.add_child(camera)

	var scene := load(VIEW_MODEL_SCENE) as PackedScene
	var view_model: ViewModel = scene.instantiate()
	view_model.use_weapon_camera = false
	view_model.arm_animation_enabled = true
	camera.add_child(view_model)
	var weapon := WeaponData.new()
	weapon.id = "sword"
	weapon.weapon_class = "one_hand_melee"
	weapon.item_tag = "weapon"
	weapon.tags = ["weapon", "melee", "one_hand", "blade", "one_hand_sword"]
	weapon.view_model_profile = "sword"
	weapon.glb_mesh = load(SWORD_MESH) as PackedScene
	weapon.material_tier = "steel"
	view_model.set_weapon(weapon)
	return {"viewport": viewport, "view_model": view_model, "weapon": weapon}


func _settle(viewport: SubViewport) -> void:
	for _i in range(5):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		assert_object(viewport.get_texture()).is_not_null()


func _capture(viewport: SubViewport, filename: String) -> Image:
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	assert_object(image).is_not_null()
	assert_int(image.save_png("%s/%s" % [REPORT_DIR, filename])).is_equal(OK)
	return image


func _has_visible_variation(image: Image) -> bool:
	var reference := image.get_pixel(0, 0)
	var different := 0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			if _color_distance(image.get_pixel(x, y), reference) > 0.03:
				different += 1
	return different > 8


func _images_are_different(first: Image, second: Image) -> bool:
	var different_samples := 0
	for y in range(0, first.get_height(), 8):
		for x in range(0, first.get_width(), 8):
			if _color_distance(first.get_pixel(x, y), second.get_pixel(x, y)) > 0.02:
				different_samples += 1
	return different_samples > 4


func _content_bounds(image: Image) -> Rect2i:
	var reference := image.get_pixel(0, 0)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if _color_distance(image.get_pixel(x, y), reference) > 0.03:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _color_distance(first: Color, second: Color) -> float:
	return absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) + absf(first.a - second.a)
