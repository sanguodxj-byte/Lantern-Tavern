extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/characters/player/player.tscn")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const SHORTSWORD := preload("res://data/weapons/shortsword.tres")
const READY_OUTPUT_PATH := "res://reports/fp_first_person_arms_ready.png"
const ATTACK_OUTPUT_PATH := "res://reports/fp_first_person_arms_attack.png"
const ARM_LAYER := 1


func test_first_person_arms_are_rendered_as_a_separated_lower_screen_pair() -> void:
	if not SUPPORT.real_renderer_available():
		return

	var player := PLAYER_SCENE.instantiate() as Node3D
	assert_object(player).is_not_null()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var view_model := player.get_node("MainCamera/ViewModel") as ViewModel
	assert_object(view_model).is_not_null()
	if view_model == null:
		player.free()
		return
	view_model.clear_weapon()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame

	var skeleton := view_model.first_person_arm_model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(skeleton).is_not_null()
	if skeleton == null:
		player.free()
		return

	var visible_arm_count := 0
	for node_name in ["LowerArm_R", "Hand_R", "LowerArm_L", "Hand_L"]:
		var node := skeleton.get_node_or_null(node_name) as Node
		if node == null:
			continue
		var mesh := node.get_child(0) as GeometryInstance3D
		if mesh != null and (mesh.layers & ARM_LAYER) != 0:
			visible_arm_count += 1
	assert_int(visible_arm_count).is_equal(4)

	# Use the real short sword resource so the capture verifies the combined
	# weapon-and-arms ready presentation, not a hand-only proxy.
	view_model.set_weapon(SHORTSWORD)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(view_model._current_weapon_node).is_not_null()
	view_model.sample_action(view_model.resolve_hold_action(), 0.0)
	await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	var ready_image := get_viewport().get_texture().get_image()
	assert_object(ready_image).is_not_null()
	if ready_image == null:
		player.free()
		return
	assert_int(_save_capture(ready_image, READY_OUTPUT_PATH)).is_equal(OK)

	var ready_bounds := _foreground_bounds(ready_image, ready_image.get_pixel(0, 0))
	assert_bool(ready_bounds.has_area()).is_true()
	var ready_inspection := SUPPORT.inspect_image_file(READY_OUTPUT_PATH, ready_image.get_pixel(0, 0))
	assert_bool(bool(ready_inspection["readable"])).is_true()
	assert_bool(bool(ready_inspection["nonblank"])).is_true()
	# Ready-state arms stay with the weapon in the lower-right presentation area;
	# attack animation is responsible for moving the action layer toward center.
	assert_float(ready_bounds.get_center().x / float(ready_image.get_width())).is_greater(0.62)
	assert_float(ready_bounds.end.x / float(ready_image.get_width())).is_greater(0.70)
	assert_float(ready_bounds.position.y / float(ready_image.get_height())).is_greater(0.60)
	assert_float(ready_bounds.end.y / float(ready_image.get_height())).is_greater(0.85)

	# The normal moving state continuously restores the ready pose. Freeze the
	# gameplay state machine so this screenshot isolates the attack visual.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	view_model.sample_action(&"vm_shortsword_thrust", 0.5)
	# The production overlay mirrors the source weapon during ViewModel process;
	# update that mirror explicitly after freezing gameplay for a deterministic
	# attack frame.
	view_model._sync_weapon_overlay(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	var attack_image := get_viewport().get_texture().get_image()
	assert_object(attack_image).is_not_null()
	if attack_image == null:
		player.free()
		return
	assert_int(_save_capture(attack_image, ATTACK_OUTPUT_PATH)).is_equal(OK)
	var attack_bounds := _foreground_bounds(attack_image, attack_image.get_pixel(0, 0))
	assert_bool(attack_bounds.has_area()).is_true()
	var attack_inspection := SUPPORT.inspect_image_file(ATTACK_OUTPUT_PATH, attack_image.get_pixel(0, 0))
	assert_bool(bool(attack_inspection["readable"])).is_true()
	assert_bool(bool(attack_inspection["nonblank"])).is_true()
	var ready_center_x := ready_bounds.get_center().x / float(ready_image.get_width())
	var attack_center_x := attack_bounds.get_center().x / float(attack_image.get_width())
	assert_float(attack_center_x).is_less(ready_center_x)
	assert_float(absf(attack_center_x - 0.50)).is_less(absf(ready_center_x - 0.50))

	player.free()


func _save_capture(image: Image, path: String) -> Error:
	var output_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	return image.save_png(output_path)


func _foreground_bounds(image: Image, background: Color) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var difference := absf(color.r - background.r) + absf(color.g - background.g) + absf(color.b - background.b)
			if color.a > 0.2 and difference > 0.10:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
