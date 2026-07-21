extends GdUnitTestSuite

# Tests for Door enum and static data (pure logic, no scene needed)

func test_key_color_none_is_zero() -> void:
	assert_int(Door.KeyColor.None).is_equal(0)


func test_color_map_contains_all_non_none_keys() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Blue)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Red)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Yellow)).is_true()
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.Purple)).is_true()
	assert_int(Door.COLOR_MAP.size()).is_equal(4)


func test_color_map_not_contains_none() -> void:
	assert_bool(Door.COLOR_MAP.has(Door.KeyColor.None)).is_false()


func test_color_map_values_are_colors() -> void:
	for color in Door.COLOR_MAP.values():
		assert_bool(color is Color).is_true()


func test_level0_dungeon_door_material_uses_one_by_two_atlas_span() -> void:
	var material := load("res://scenes/expedition/level0_dungeon_door_mat.tres") as ShaderMaterial
	assert_object(material).is_not_null()
	assert_str((material.get_shader_parameter("atlas") as Texture2D).resource_path) \
		.is_equal("res://assets/textures/terrain/level0_dungeon/level0_dungeon_terrain_atlas_32px.png")
	assert_object(material.get_shader_parameter("tile_col_row")).is_equal(Vector2(7, 1))
	assert_object(material.get_shader_parameter("tile_span")).is_equal(Vector2(1, 2))
	assert_object(material.get_shader_parameter("atlas_grid")).is_equal(Vector2(8, 4))


func test_shared_door_scene_is_voxel_box_built_not_glb() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/door/door.tscn")
	assert_bool(source.contains(".glb") or source.contains(".obj")) \
		.override_failure_message("共享门场景不能再实例化旧 GLB/OBJ 模型") \
		.is_false()
	assert_bool(source.contains("SphereMesh") or source.contains("CylinderMesh") or source.contains("ConcavePolygonShape3D")) \
		.override_failure_message("共享门场景必须使用体素 BoxMesh/BoxShape") \
		.is_false()

	var inst := (load("res://scenes/door/door.tscn") as PackedScene).instantiate()
	assert_int(int(inst.get_meta("voxel_unit_px"))).is_equal(1)
	assert_int(int(inst.get_meta("voxel_px_per_meter"))).is_equal(32)
	assert_object(inst.get_node("door/Door") as MeshInstance3D).is_not_null()
	assert_object(inst.get_node("Frame/DoorFrame") as MeshInstance3D).is_not_null()
	inst.free()


func test_shared_door_open_animation_uses_rotation_not_translation() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/door/door.tscn")
	assert_bool(source.contains(":position") or source.contains(":transform")) \
		.override_failure_message("共享门打开动画必须绕铰链旋转 90°，不能横移 position/transform") \
		.is_false()
	assert_bool(source.contains("door:rotation")) \
		.override_failure_message("共享门打开动画必须包含 rotation 轨道") \
		.is_true()

	var inst := (load("res://scenes/door/door.tscn") as PackedScene).instantiate() as Door
	add_child(inst)
	await await_idle_frame()
	var hinge := inst.get_node("door") as Node3D
	var hinge_position := hinge.position
	inst.open(Transform3D(Basis(), Vector3(0, 0, -1)))
	inst.animation_player.advance(0.15)
	assert_object(hinge.position).is_equal(hinge_position)
	assert_float(absf(hinge.rotation.y)) \
		.override_failure_message("共享门应打开为 90° 旋转") \
		.is_equal_approx(PI * 0.5, 0.01)
	inst.free()


func test_shared_door_starts_closed_even_if_hinge_was_saved_open() -> void:
	var inst := (load("res://scenes/door/door.tscn") as PackedScene).instantiate() as Door
	var hinge := inst.get_node("door") as Node3D
	var collision := inst.get_node("CollisionShape3D") as CollisionShape3D
	hinge.rotation.y = PI * 0.5
	collision.disabled = true
	add_child(inst)
	await await_idle_frame()
	assert_float(hinge.rotation.y) \
		.override_failure_message("门进入场景时必须回到关闭原位") \
		.is_equal_approx(0.0, 0.001)
	assert_bool(collision.disabled) \
		.override_failure_message("关闭状态的门碰撞必须启用") \
		.is_false()
	inst.free()
