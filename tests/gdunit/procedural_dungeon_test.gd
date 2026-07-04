extends GdUnitTestSuite

# Test suite for ProceduralDungeon

var _dungeon: ProceduralDungeon

func before() -> void:
	_dungeon = load("res://scenes/expedition/procedural_dungeon.tscn").instantiate()


func after() -> void:
	if is_instance_valid(_dungeon):
		_dungeon.queue_free()


func test_dungeon_inheritance() -> void:
	assert_object(_dungeon).is_instanceof(BaseLevel)
	assert_bool(_dungeon.is_procedural()).is_true()


func test_dungeon_ready_flow() -> void:
	# Add child to the scene tree to trigger _ready() and map generation
	add_child(_dungeon)
	
	# Verify that 3D grid visuals (floors/walls) were generated
	# The grid size is 10x10 = 100 tiles, plus lights/env nodes, so we expect at least 100 child nodes.
	var children_count = _dungeon.get_child_count()
	assert_int(children_count).is_greater_equal(100)
	
	# Verify player spawn location was updated
	assert_bool(_dungeon.player_spawn_pos != Vector3.ZERO).is_true()
	
	# Verify player was successfully instantiated as a child of the dungeon
	var player_found = false
	for child in _dungeon.get_children():
		if child is Player:
			player_found = true
			assert_float(child.global_position.x).is_equal_approx(_dungeon.player_spawn_pos.x, 0.01)
			assert_float(child.global_position.z).is_equal_approx(_dungeon.player_spawn_pos.z, 0.01)
			break
	assert_bool(player_found).is_true()


func test_dungeon_materials() -> void:
	var dungeon = load("res://scenes/expedition/procedural_dungeon.tscn").instantiate() as ProceduralDungeon
	add_child(dungeon)
	
	var wall_mat_tested := false
	var floor_mat_tested := false
	var expected_tex = dungeon.get_zone_texture(dungeon.dungeon_zone)
	
	var wall_uv = dungeon.get_terrain_uv_config("WALL", Vector3(3.0, 3.0, 3.0))
	var floor_uv = dungeon.get_terrain_uv_config("FLOOR", Vector3(3.0, 3.0, 3.0))
	
	for child in dungeon.get_children():
		if child is MultiMeshInstance3D:
			var mat = child.material_override
			if mat is StandardMaterial3D:
				if child.name == "WallMultiMesh":
					assert_object(mat.albedo_texture).is_equal(expected_tex)
					assert_object(mat.uv1_offset).is_equal(wall_uv["offset"])
					assert_object(mat.uv1_scale).is_equal(wall_uv["scale"])
					wall_mat_tested = true
				elif child.name == "FloorMultiMesh":
					assert_object(mat.albedo_texture).is_equal(expected_tex)
					assert_object(mat.uv1_offset).is_equal(floor_uv["offset"])
					assert_object(mat.uv1_scale).is_equal(floor_uv["scale"])
					floor_mat_tested = true
					
	assert_bool(wall_mat_tested).is_true()
	assert_bool(floor_mat_tested).is_true()
	
	remove_child(dungeon)
	dungeon.free()

