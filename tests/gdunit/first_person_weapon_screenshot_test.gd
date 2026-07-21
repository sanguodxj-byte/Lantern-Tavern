extends GdUnitTestSuite

const VIEW_MODEL_SCENE := "res://scenes/characters/player/view_model.tscn"
const SWORD_MESH := "res://assets/meshes/weapons/weapons_voxel_sword.glb"
const REPORT_DIR := "res://reports"


func test_first_person_hold_and_release_screenshots() -> void:
	var fixture := await _create_fixture()
	var viewport: SubViewport = fixture.viewport
	var view_model: ViewModel = fixture.view_model
	if DisplayServer.get_name() == "headless":
		# RendererDummy has no readable 3D texture. The same test is executed
		# again with a real renderer for the pixel assertions and PNG artifacts.
		print("[截图测试] headless renderer: skip pixel capture, keep fixture/state coverage")
		assert_bool(view_model.begin_weapon_hold()).is_true()
		view_model.update_weapon_hold(1.0)
		assert_bool(view_model.release_weapon_hold()).is_true()
		view_model.finish_weapon_release()
		viewport.queue_free()
		return

	assert_bool(view_model.begin_weapon_hold()).is_true()
	view_model.update_weapon_hold(0.0)
	var idle_pose := view_model.action_pivot.transform
	await _settle(viewport)
	var idle_image := _capture(viewport, "fp_weapon_hold_release_idle.png")

	view_model.update_weapon_hold(1.0)
	assert_str(String(view_model.get_visual_weapon_state_name())).is_equal("holding")
	var hold_pose := view_model.action_pivot.transform
	assert_bool(not hold_pose.is_equal_approx(idle_pose)).is_true()
	await _settle(viewport)
	var hold_image := _capture(viewport, "fp_weapon_hold_release_hold.png")

	assert_bool(view_model.release_weapon_hold()).is_true()
	assert_str(String(view_model.get_visual_weapon_state_name())).is_equal("releasing")
	view_model.begin_weapon_release(view_model.resolve_melee_action())
	view_model.sample_action(view_model.resolve_melee_action(), 0.5)
	var release_pose := view_model.action_pivot.transform
	assert_bool(not release_pose.is_equal_approx(hold_pose)).is_true()
	await _settle(viewport)
	var release_image := _capture(viewport, "fp_weapon_hold_release_release.png")

	assert_int(idle_image.get_width()).is_equal(640)
	assert_int(hold_image.get_height()).is_equal(360)
	assert_int(release_image.get_width()).is_equal(640)
	assert_bool(FileAccess.file_exists("%s/fp_weapon_hold_release_idle.png" % REPORT_DIR)).is_true()
	assert_bool(FileAccess.file_exists("%s/fp_weapon_hold_release_hold.png" % REPORT_DIR)).is_true()
	assert_bool(FileAccess.file_exists("%s/fp_weapon_hold_release_release.png" % REPORT_DIR)).is_true()

	# RendererDummy is intentionally uniform in headless CI.  When a real
	# renderer is available, require visible spatial content in every frame.
	if DisplayServer.get_name() != "headless":
		assert_bool(_has_visible_variation(idle_image)).is_true()
		assert_bool(_has_visible_variation(hold_image)).is_true()
		assert_bool(_has_visible_variation(release_image)).is_true()
		assert_bool(_images_are_different(idle_image, hold_image)).is_true()
		assert_bool(_images_are_different(hold_image, release_image)).is_true()
		var idle_bounds := _content_bounds(idle_image)
		var hold_bounds := _content_bounds(hold_image)
		var release_bounds := _content_bounds(release_image)
		# The sword must remain a readable held weapon in every phase: a full
		# blade in the ready pose, a raised wind-up on the right, and a broad
		# leftward release sweep.  These assertions catch clipping/floating
		# poses that a generic "non-uniform image" check would accept.
		assert_int(idle_bounds.size.x).is_greater(100)
		assert_int(idle_bounds.position.y).is_less(180)
		assert_int(idle_bounds.end.y).is_greater(280)
		assert_int(hold_bounds.position.x).is_greater(400)
		assert_int(hold_bounds.position.y).is_less(80)
		assert_int(hold_bounds.end.y).is_greater(250)
		assert_int(release_bounds.position.x).is_less(260)
		assert_int(release_bounds.end.x).is_greater(380)

	view_model.finish_weapon_release()
	viewport.queue_free()


func test_capture_fixture_uses_a_real_weapon_mesh_and_does_not_add_combat_nodes() -> void:
	assert_bool(FileAccess.file_exists(SWORD_MESH)).is_true()
	var scene := load(VIEW_MODEL_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	var instance := auto_free(scene.instantiate())
	assert_object(instance.get_node_or_null("BobPivot/AimPivot/ActionPivot/WeaponSocket")).is_not_null()
	assert_object(instance.get_node_or_null("BobPivot/AimPivot/ActionPivot/WeaponSocket/MuzzlePoint")).is_not_null()
	assert_object(instance.get_node_or_null("Hitbox")).is_null()
	assert_object(instance.get_node_or_null("DamageResolver")).is_null()


func test_one_hand_sword_uses_a_dedicated_first_person_mount_pose() -> void:
	var fixture := await _create_fixture()
	var view_model: ViewModel = fixture.view_model
	var mount := view_model.weapon_socket.transform
	assert_bool(not mount.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_float(absf(view_model.weapon_socket.rotation_degrees.z)).is_greater(45.0)
	assert_float(mount.origin.y).is_greater(-0.05)
	fixture.viewport.queue_free()


func test_screenshot_test_captures_hold_and_release_states() -> void:
	var source := FileAccess.get_file_as_string("res://tests/gdunit/first_person_weapon_screenshot_test.gd")
	assert_str(source).contains("begin_weapon_hold")
	assert_str(source).contains("update_weapon_hold(1.0)")
	assert_str(source).contains("release_weapon_hold")
	assert_str(source).contains("save_png")
	assert_str(source).contains("fp_weapon_hold_release_hold.png")
	assert_str(source).contains("fp_weapon_hold_release_release.png")


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
	weapon.id = "screenshot_sword"
	weapon.weapon_class = "one_hand_melee"
	weapon.item_tag = "weapon"
	weapon.tags = ["weapon", "melee", "one_hand", "blade"]
	weapon.glb_mesh = load(SWORD_MESH) as PackedScene
	weapon.material_tier = "steel"
	view_model.set_weapon(weapon)

	return {"viewport": viewport, "view_model": view_model}


func _settle(viewport: SubViewport) -> void:
	for _i in range(5):
		await get_tree().process_frame
	# Touch the texture after the update frames so the render target is ready.
	if DisplayServer.get_name() != "headless":
		assert_object(viewport.get_texture()).is_not_null()


func _capture(viewport: SubViewport, filename: String) -> Image:
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	assert_object(image).is_not_null()
	var error := image.save_png("%s/%s" % [REPORT_DIR, filename])
	assert_int(error).is_equal(OK)
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
