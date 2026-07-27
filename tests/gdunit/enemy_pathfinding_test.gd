extends GdUnitTestSuite

## 怪物导航回归测试：导航源必须尊重墙体，且没有有效路径时不能用直线转向撞墙。

func test_navigation_floor_source_excludes_wall_cells() -> void:
	var layout := _make_layout([
		[2, 2, 2, 2, 2],
		[2, 1, 1, 1, 2],
		[2, 1, 2, 1, 2],
		[2, 1, 1, 1, 2],
		[2, 2, 2, 2, 2],
	])
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()

	builder._build_terrain(layout, result)

	# 8 walkable cells: no floor face may be generated under a wall or in the outer void.
	assert_int(result.floor_transforms.size()).is_equal(8)
	for transform in result.floor_transforms:
		var cell := _world_to_cell(transform.origin, layout)
		assert_bool(int(layout.grid[cell.y][cell.x]) != 2) \
			.override_failure_message("墙格 (%d, %d) 不能进入导航地板源" % [cell.x, cell.y]).is_true()

func test_navigation_source_contains_wall_obstacle_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	var result := DungeonBuildResult.new()
	result.wall_transforms_by_height["3,3,3"] = {
		"size": Vector3(3.0, 3.0, 3.0),
		"transforms": [Transform3D(Basis.IDENTITY, Vector3.ZERO)],
	}
	var builder := DungeonSceneBuilder.new()

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("导航源必须提供墙体障碍面片").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)

func test_navigation_source_contains_pillar_obstacle_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 5, 1], [1, 1, 1]])
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("柱体必须作为局部障碍进入导航源").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)

func test_navigation_source_contains_hazard_footprint_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	layout.hazard_anchors.append({"hazard_type": "spikes", "anchor_cell": Vector2i(1, 1)})
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("陷阱必须作为局部 footprint 进入导航源").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)

func test_hazard_navigation_footprint_matches_trap_scale() -> void:
	var builder := DungeonSceneBuilder.new()
	var spikes := float(builder.call("_hazard_navigation_footprint", "spikes", 3.0))
	var acid := float(builder.call("_hazard_navigation_footprint", "acid", 3.0))
	var flame := float(builder.call("_hazard_navigation_footprint", "flame_vent", 3.0))

	assert_float(spikes).is_equal_approx(2.25, 0.001)
	assert_float(acid).is_equal_approx(2.25, 0.001)
	assert_float(flame).is_equal_approx(1.5, 0.001)
	assert_float(spikes).is_less(3.0)
	assert_float(acid).is_less(3.0)

func test_navigation_source_contains_door_surround_collision_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()
	var stage := Node3D.new()
	add_child(stage)
	result.collision_root = Node3D.new()
	stage.add_child(result.collision_root)
	var body := StaticBody3D.new()
	body.set_meta("door_surround", true)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 3.0, 1.0)
	collision.shape = shape
	body.add_child(collision)
	result.collision_root.add_child(body)
	await get_tree().process_frame

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("门框碰撞体必须进入导航障碍源").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)
	stage.queue_free()

func test_navigation_source_contains_chest_collision_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()
	var stage := Node3D.new()
	add_child(stage)
	result.interaction_root = Node3D.new()
	stage.add_child(result.interaction_root)
	var chest := StaticBody3D.new()
	chest.set_meta("topdown_kind", "chest")
	var visual := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 0.9, 0.85)
	collision.shape = shape
	visual.add_child(collision)
	chest.add_child(visual)
	result.interaction_root.add_child(chest)
	await get_tree().process_frame

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("宝箱碰撞体必须进入导航障碍源").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)
	stage.queue_free()

func test_navigation_source_contains_decor_collision_faces() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()
	var stage := Node3D.new()
	add_child(stage)
	result.decor_root = Node3D.new()
	stage.add_child(result.decor_root)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 2.0, 1.5)
	collision.shape = shape
	body.add_child(collision)
	result.decor_root.add_child(body)
	await get_tree().process_frame

	var faces_variant: Variant = builder.call("_build_navigation_obstacle_faces", layout, result)
	assert_bool(faces_variant is PackedVector3Array) \
		.override_failure_message("装饰物实际静态碰撞体必须进入导航障碍源").is_true()
	if faces_variant is PackedVector3Array:
		assert_int((faces_variant as PackedVector3Array).size()).is_equal(36)
	stage.queue_free()

func test_door_surround_clearance_covers_largest_enemy() -> void:
	var layout := _make_layout([[1, 1, 1], [1, 1, 1], [1, 1, 1]])
	for y in range(layout.heights.size()):
		for x in range(layout.heights[y].size()):
			layout.heights[y][x] = 4.0
	var result := DungeonBuildResult.new()
	var builder := DungeonSceneBuilder.new()
	var stage := Node3D.new()
	add_child(stage)
	result.collision_root = Node3D.new()
	result.doors_root = Node3D.new()
	stage.add_child(result.collision_root)
	stage.add_child(result.doors_root)
	builder.call(
		"_spawn_door_wall_surround",
		"Door",
		Vector3.ZERO,
		Vector2i(1, 1),
		Vector2i(1, 0),
		Vector2i(0, -1),
		false,
		3.0,
		result,
		stage,
		layout,
	)
	await get_tree().process_frame

	var lintel := result.collision_root.get_node_or_null("DoorLintelCollision") as StaticBody3D
	if lintel != null:
		var collision := lintel.get_child(0) as CollisionShape3D
		var shape := collision.shape as BoxShape3D
		var bottom := lintel.position.y - shape.size.y * 0.5
		assert_float(bottom).is_greater_equal(
			PhysicsSetup.get_character_capsule_height("huge") - 0.001)
	stage.queue_free()

func test_navigation_mesh_uses_largest_enemy_collision_envelope() -> void:
	var source := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	assert_bool(source.contains('get_character_capsule_radius("huge")')) \
		.override_failure_message("导航网格半径必须覆盖最大敌人，避免大型怪物擦入墙体").is_true()
	assert_bool(source.contains('get_character_capsule_height("huge")')) \
		.override_failure_message("导航网格高度必须覆盖最大敌人，避免大型怪物进入低矮空间").is_true()

func test_enemy_stops_when_navigation_path_is_unavailable() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	await get_tree().process_frame

	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.player = player
	(enemy.state_node as EnemyStateMoving)._chase_player(0.016)

	assert_float(Vector2(enemy.velocity.x, enemy.velocity.z).length()) \
		.override_failure_message("没有有效导航路径时不能用直线转向把怪物推入墙边/角落").is_less(0.001)
	enemy.queue_free()
	player.queue_free()

func test_enemy_navigation_agent_matches_runtime_collision_and_waits_for_map_sync() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	await get_tree().process_frame

	var capsule := enemy.collision_shape.shape as CapsuleShape3D
	assert_object(capsule).is_not_null()
	if capsule != null:
		assert_float(enemy.nav_agent.radius).is_equal_approx(capsule.radius + capsule.margin, 0.001)
		assert_float(enemy.nav_agent.height).is_equal_approx(capsule.height, 0.001)
	assert_bool(enemy.nav_agent.avoidance_enabled).is_false()
	enemy.queue_free()

func test_enemy_navigation_agent_consumes_vertical_navmesh_offset() -> void:
	var enemy := _new_enemy()
	add_child(enemy)
	await get_tree().process_frame

	assert_float(enemy.nav_agent.path_desired_distance).is_greater_equal(0.75)
	assert_float(enemy.nav_agent.path_height_offset).is_equal_approx(0.5, 0.001)
	enemy.queue_free()

func test_enemy_patrol_moves_when_navigation_path_is_available() -> void:
	var stage := Node3D.new()
	add_child(stage)
	_add_test_floor(stage)
	_add_test_navigation_region(stage)

	var enemy := (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate() as Enemy
	enemy.patrol_radius = 4.0
	stage.add_child(enemy)
	var player := _new_player()
	player.position = Vector3(0.0, 0.5, -10.0)
	stage.add_child(player)
	GameState.current_player = player
	await _wait_physics_frames(8)

	var moving_state := enemy.state_node as EnemyStateMoving
	assert_object(moving_state).is_not_null()
	if moving_state != null:
		moving_state.patrol_target = Vector3(4.0, 0.0, 0.0)
		moving_state.has_patrol_target = true
		moving_state.patrol_idle_until = 0
	var start_position := enemy.global_position
	await _wait_physics_frames(60)

	assert_float(enemy.global_position.distance_to(start_position)) \
		.override_failure_message("有效导航路径上的巡逻敌人应实际移动").is_greater(0.05)
	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()
	stage.queue_free()

func test_enemy_patrol_runs_without_nearby_player() -> void:
	var stage := Node3D.new()
	add_child(stage)
	_add_test_floor(stage)
	_add_test_navigation_region(stage)
	GameState.current_player = null

	var enemy := (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate() as Enemy
	enemy.patrol_radius = 4.0
	stage.add_child(enemy)
	await _wait_physics_frames(8)

	var moving_state := enemy.state_node as EnemyStateMoving
	assert_object(moving_state).is_not_null()
	if moving_state != null:
		moving_state.patrol_target = Vector3(4.0, 0.0, 0.0)
		moving_state.has_patrol_target = true
		moving_state.patrol_idle_until = 0
	var start_position := Vector2(enemy.global_position.x, enemy.global_position.z)
	await _wait_physics_frames(60)

	var horizontal_distance := Vector2(enemy.global_position.x, enemy.global_position.z).distance_to(start_position)
	assert_float(horizontal_distance) \
		.override_failure_message("没有近距离玩家时，敌人仍应在出生点附近自动巡逻").is_greater(0.05)
	GameState.current_player = null
	enemy.queue_free()
	stage.queue_free()

func test_enemy_chase_closes_distance_after_player_is_detected() -> void:
	var stage := Node3D.new()
	add_child(stage)
	_add_test_floor(stage)
	_add_test_navigation_region(stage)

	var enemy := (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate() as Enemy
	enemy.position = Vector3.ZERO
	stage.add_child(enemy)
	var player := _new_player()
	player.position = Vector3(0.0, 0.5, -4.0)
	stage.add_child(player)
	GameState.current_player = player
	await _wait_physics_frames(10)

	var start_distance := enemy.global_position.distance_to(player.global_position)
	await _wait_physics_frames(60)

	assert_bool(enemy.is_target_visible()) \
		.override_failure_message("追击测试中，索敌后目标应保持可见").is_true()
	assert_float(enemy.global_position.distance_to(player.global_position)) \
		.override_failure_message("发现玩家后，怪物应沿导航路径缩短与玩家的距离").is_less(start_distance - 0.05)
	GameState.current_player = null
	player.queue_free()
	enemy.queue_free()
	stage.queue_free()

func test_runtime_snaps_enemy_spawn_to_navigation_surface() -> void:
	var stage := Node3D.new()
	add_child(stage)
	_add_test_navigation_region(stage)
	var runtime := DungeonRuntime.new()
	stage.add_child(runtime)
	runtime._level = stage
	runtime._enemy_spawn_plan = [{"enemy_type": "slime", "pos": Vector3(13.0, 0.5, 0.0)}]
	await _wait_physics_frames(10)
	runtime._snap_enemy_spawn_plan_to_navigation()
	var snapped: Vector3 = runtime._enemy_spawn_plan[0]["pos"]
	assert_bool(snapped.x <= 12.01) \
		.override_failure_message("敌人出生点必须投影到导航面，不能从导航面外开始追击").is_true()
	assert_float(snapped.y).is_equal_approx(0.5, 0.001)
	runtime.queue_free()
	stage.queue_free()

func _add_test_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsSetup.LAYER_ENVIRONMENT
	floor_body.collision_mask = PhysicsSetup.MASK_ENVIRONMENT
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24.0, 0.2, 24.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor_body.add_child(collision)
	stage.add_child(floor_body)

func _add_test_navigation_region(stage: Node3D) -> void:
	var region := NavigationRegion3D.new()
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-12.0, 0.0, -12.0),
		Vector3(12.0, 0.0, -12.0),
		Vector3(12.0, 0.0, 12.0),
		Vector3(-12.0, 0.0, 12.0),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = navigation_mesh
	stage.add_child(region)

func _wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame

func _make_layout(grid: Array) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = grid[0].size()
	layout.height = grid.size()
	layout.tile_size = 3.0
	layout.grid = grid
	layout.heights = []
	for row in grid:
		var height_row: Array[float] = []
		for _cell in row:
			height_row.append(3.0)
		layout.heights.append(height_row)
	return layout

func _world_to_cell(world_position: Vector3, layout: DungeonLayout) -> Vector2i:
	var offset_x := -(float(layout.width) * layout.tile_size) / 2.0
	var offset_z := -(float(layout.height) * layout.tile_size) / 2.0
	return Vector2i(
		roundi((world_position.x - offset_x) / layout.tile_size),
		roundi((world_position.z - offset_z) / layout.tile_size),
	)

func _new_enemy() -> Enemy:
	var enemy := (load("res://scenes/characters/enemies/slime.tscn") as PackedScene).instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _new_player() -> Player:
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player
