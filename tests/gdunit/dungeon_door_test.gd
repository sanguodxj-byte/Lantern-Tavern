extends GdUnitTestSuite

class FakeDamageResult:
	extends RefCounted
	var final_damage := 3


func test_standard_dungeon_door_opens_on_interact_and_disables_collision() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new())

	var shape := door.get_node("CollisionShape3D") as CollisionShape3D
	assert_str(door.interaction_name).is_equal("Door")
	assert_int(door.max_integrity).is_equal(1)
	assert_bool((door.collision_layer & PhysicsSetup.LAYER_SCENE_OBJECT) != 0).is_true()
	assert_bool((door.collision_layer & PhysicsSetup.LAYER_TRIGGER) != 0).is_true()
	assert_bool(shape.disabled).is_false()
	assert_float((shape.shape as BoxShape3D).size.z).is_equal_approx(DungeonDoor.THICKNESS, 0.001)

	door.interact(null)

	assert_bool(door.is_open).is_true()
	assert_bool(shape.disabled).is_true()
	assert_float(door.get_node("LeafPivot").rotation.y).is_less(PI * 0.5)
	await get_tree().create_timer(door.open_duration + 0.05).timeout
	assert_float(absf(door.get_node("LeafPivot").rotation.y)).is_equal_approx(PI * 0.5, 0.01)

	remove_child(door)
	door.free()


func test_dungeon_door_voxel_unit_is_one_pixel_not_global_four_pixels() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new())

	assert_float(DungeonDoor.VOXEL_UNIT).is_equal_approx(1.0 / 32.0, 0.0001)
	assert_int(DungeonDoor.THICKNESS_VOXELS).is_equal(4)
	assert_float(DungeonDoor.THICKNESS).is_equal_approx(4.0 / 32.0, 0.0001)
	assert_int(int(door.get_meta("voxel_unit_px"))).is_equal(1)
	assert_int(int(door.get_meta("voxel_px_per_meter"))).is_equal(32)
	assert_int(int(door.get_meta("door_thickness_px"))).is_equal(4)

	remove_child(door)
	door.free()


func test_dungeon_door_uses_front_side_and_top_materials() -> void:
	var front := StandardMaterial3D.new()
	var side := StandardMaterial3D.new()
	var top := StandardMaterial3D.new()
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), front, side, top)

	assert_object(_find_mesh(door, "LeafFront").material_override).is_equal(front)
	assert_object(_find_mesh(door, "LeafBack").material_override).is_equal(front)
	assert_object(_find_mesh(door, "LeafSide").material_override).is_equal(side)
	assert_object(_find_mesh(door, "LeafTop").material_override).is_equal(top)
	assert_float((_find_mesh(door, "LeafSide").mesh as BoxMesh).size.z) \
		.override_failure_message("门核心板必须缩进，避免和前后门皮共面闪烁") \
		.is_equal_approx(DungeonDoor.CORE_THICKNESS, 0.001)
	assert_float((_find_mesh(door, "LeafTop").mesh as BoxMesh).size.z) \
		.override_failure_message("门顶部贴图深度必须等于 4px 厚度") \
		.is_equal_approx(DungeonDoor.THICKNESS, 0.001)

	remove_child(door)
	door.free()


func test_dungeon_door_leaf_core_is_inset_from_front_and_back_faces() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new())

	var front := _find_mesh(door, "LeafFront")
	var back := _find_mesh(door, "LeafBack")
	var side := _find_mesh(door, "LeafSide")
	var front_box := front.mesh as BoxMesh
	var back_box := back.mesh as BoxMesh
	var side_box := side.mesh as BoxMesh
	var front_outer := front.position.z + front_box.size.z * 0.5
	var back_outer := back.position.z - back_box.size.z * 0.5
	var side_outer_front := side.position.z + side_box.size.z * 0.5
	var side_outer_back := side.position.z - side_box.size.z * 0.5

	assert_float(front_outer).is_equal_approx(DungeonDoor.THICKNESS * 0.5, 0.001)
	assert_float(back_outer).is_equal_approx(-DungeonDoor.THICKNESS * 0.5, 0.001)
	assert_float(side_outer_front) \
		.override_failure_message("核心侧板不应延伸到前门皮外表面，否则会 z-fighting 闪烁") \
		.is_less(front_outer - DungeonDoor.SKIN_THICKNESS * 0.5)
	assert_float(side_outer_back) \
		.override_failure_message("核心侧板不应延伸到后门皮外表面，否则会 z-fighting 闪烁") \
		.is_greater(back_outer + DungeonDoor.SKIN_THICKNESS * 0.5)

	remove_child(door)
	door.free()


func test_boss_dungeon_door_takes_multiple_hits_before_breaking() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_BOSS, Vector2i(1, 0), StandardMaterial3D.new())

	var shape := door.get_node("CollisionShape3D") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	assert_str(door.interaction_name).is_equal("Boss Door")
	assert_int(door.max_integrity).is_equal(3)
	assert_float(box.size.y).is_equal_approx(2.0, 0.01)
	assert_float(maxf(box.size.x, box.size.z)).is_equal_approx(2.0, 0.01)
	assert_float(minf(box.size.x, box.size.z)).is_equal_approx(DungeonDoor.THICKNESS, 0.001)

	door.try_receive_hit(null, 2)
	assert_bool(door.is_broken).is_false()
	assert_bool(shape.disabled).is_false()

	door.try_receive_hit(null, 1)
	assert_bool(door.is_broken).is_true()
	assert_bool(shape.disabled).is_true()

	remove_child(door)
	door.free()


func test_boss_dungeon_door_leaves_rotate_90_degrees_from_outer_hinges() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_BOSS, Vector2i(0, 1), StandardMaterial3D.new())

	var left_pivot := door.get_node("LeftLeafPivot") as Node3D
	var right_pivot := door.get_node("RightLeafPivot") as Node3D
	assert_float(left_pivot.position.x) \
		.override_failure_message("Boss 左门铰链应在外侧门框，不应在中缝或中心横移") \
		.is_equal_approx(-1.0, 0.01)
	assert_float(right_pivot.position.x) \
		.override_failure_message("Boss 右门铰链应在外侧门框，不应在中缝或中心横移") \
		.is_equal_approx(1.0, 0.01)
	var left_position := left_pivot.position
	var right_position := right_pivot.position

	door.open()
	await get_tree().create_timer(door.open_duration + 0.05).timeout

	assert_object(left_pivot.position).is_equal(left_position)
	assert_object(right_pivot.position).is_equal(right_position)
	assert_float(absf(left_pivot.rotation.y)).is_equal_approx(PI * 0.5, 0.01)
	assert_float(absf(right_pivot.rotation.y)).is_equal_approx(PI * 0.5, 0.01)

	remove_child(door)
	door.free()


func test_dungeon_door_open_code_does_not_tween_position() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/expedition/dungeon_door.gd")
	assert_bool(source.contains("tween_property(pivot, \"position") or source.contains("tween_property(pivot, \"global_position")) \
		.override_failure_message("DungeonDoor 打开必须只旋转 pivot，不能 tween position 横移") \
		.is_false()
	assert_bool(source.contains("\"rotation:y\"")) \
		.override_failure_message("DungeonDoor 打开必须 tween rotation:y 到 90°") \
		.is_true()


func _find_mesh(root: Node, node_name: String) -> MeshInstance3D:
	var found := root.find_child(node_name, true, false) as MeshInstance3D
	assert_object(found) \
		.override_failure_message("缺少门面 mesh: %s" % node_name) \
		.is_not_null()
	return found


func test_dungeon_door_accepts_damage_result_interface_from_skills() -> void:
	var door := DungeonDoor.new()
	add_child(door)
	door.configure(DungeonDoor.KIND_BOSS, Vector2i(0, -1), StandardMaterial3D.new())

	door.try_receive_hit_result(null, FakeDamageResult.new())

	assert_bool(door.is_broken).is_true()

	remove_child(door)
	door.free()


func test_dungeon_door_emits_pressure_actions_for_open_and_break() -> void:
	var opened_actions: Array[String] = []
	var opened_door := DungeonDoor.new()
	add_child(opened_door)
	opened_door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new())
	opened_door.pressure_action.connect(func(action: String) -> void:
		opened_actions.append(action)
	)

	opened_door.open()

	assert_array(opened_actions).contains(DungeonDoor.PRESSURE_ACTION_OPEN)

	var broken_actions: Array[String] = []
	var broken_door := DungeonDoor.new()
	add_child(broken_door)
	broken_door.configure(DungeonDoor.KIND_STANDARD, Vector2i(0, 1), StandardMaterial3D.new())
	broken_door.pressure_action.connect(func(action: String) -> void:
		broken_actions.append(action)
	)

	broken_door.apply_damage(1)

	assert_array(broken_actions).contains(DungeonDoor.PRESSURE_ACTION_BREAK)

	remove_child(opened_door)
	remove_child(broken_door)
	opened_door.free()
	broken_door.free()
