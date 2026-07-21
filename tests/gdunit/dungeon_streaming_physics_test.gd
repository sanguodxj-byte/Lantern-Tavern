extends GdUnitTestSuite

# streaming 物理/视觉行为已迁入 DungeonStreamingController。

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_controller.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_streamed_physics_includes_character_bodies_and_stops_far_enemies() -> void:
	var ctrl := _make_controller()
	var near_body := RigidBody3D.new()
	var far_enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	near_body.position = Vector3.ZERO
	far_enemy.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	far_enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	far_enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(near_body)
	add_child(far_enemy)
	ctrl.register_physics_node(near_body)
	ctrl.register_physics_node(far_enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(near_body.freeze).is_false()
	assert_bool(far_enemy.is_physics_processing()).is_false()
	assert_int(far_enemy.collision_layer).is_equal(0)
	assert_int(far_enemy.collision_mask).is_equal(0)
	assert_bool(bool(far_enemy.get_meta("stream_physics_active", true))).is_false()
	_teardown(ctrl, [near_body, far_enemy, player])

func test_streamed_character_body_restores_collision_when_reentering_chunk() -> void:
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	enemy.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	player.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	ctrl.update_streaming(true)
	assert_bool(enemy.is_physics_processing()).is_true()
	assert_int(enemy.collision_layer).is_equal(PhysicsSetup.LAYER_ENEMY)
	assert_int(enemy.collision_mask).is_equal(PhysicsSetup.MASK_ENEMY)
	assert_bool(bool(enemy.get_meta("stream_physics_active", false))).is_true()
	_teardown(ctrl, [enemy, player])

func test_streamed_child_physics_body_hides_visual_root_outside_chunk() -> void:
	var ctrl := _make_controller()
	var visual_root := Node3D.new()
	var body := StaticBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	visual_root.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	body.collision_layer = PhysicsSetup.LAYER_SCENE_OBJECT
	body.collision_mask = PhysicsSetup.MASK_SELECTABLE
	visual_root.add_child(body)
	add_child(visual_root)
	ctrl.register_physics_node(visual_root)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(visual_root.visible) 		.override_failure_message("子 StaticBody3D 被 stream 掉时，其装饰/道具视觉根节点也应隐藏") 		.is_false()
	assert_int(body.collision_layer).is_equal(0)
	assert_int(body.collision_mask).is_equal(0)
	player.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	ctrl.update_streaming(true)
	assert_bool(visual_root.visible) 		.override_failure_message("回到对应 chunk 后，视觉根节点应恢复可见") 		.is_true()
	assert_int(body.collision_layer).is_equal(PhysicsSetup.LAYER_SCENE_OBJECT)
	assert_int(body.collision_mask).is_equal(PhysicsSetup.MASK_SELECTABLE)
	_teardown(ctrl, [visual_root, player])

func test_streamed_visual_node_hides_mesh_without_physics_outside_chunk() -> void:
	var ctrl := _make_controller()
	var mesh := MeshInstance3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	mesh.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	add_child(mesh)
	ctrl.register_visual_node(mesh)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(mesh.visible) 		.override_failure_message("无 PhysicsBody3D 的静态视觉节点也应按 chunk 隐藏") 		.is_false()
	player.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	ctrl.update_streaming(true)
	assert_bool(mesh.visible) 		.override_failure_message("回到对应 chunk 后，静态视觉节点应恢复可见") 		.is_true()
	_teardown(ctrl, [mesh, player])


func test_streamed_area_stops_monitoring_and_callbacks_outside_chunk() -> void:
	var ctrl := _make_controller()
	var trap_root := Node3D.new()
	var trap := Area3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	trap.add_child(collision)
	trap_root.add_child(trap)
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	trap_root.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	add_child(trap_root)
	ctrl.register_physics_node(trap_root)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	assert_bool(trap.monitoring).is_false()
	assert_bool(trap.monitorable).is_false()
	assert_int(trap.collision_layer).is_equal(0)
	assert_int(trap.collision_mask).is_equal(0)
	assert_bool(trap_root.visible).is_false()
	player.position = trap_root.position
	ctrl.update_streaming(true)
	assert_bool(trap.monitoring).is_true()
	assert_bool(trap.monitorable).is_true()
	assert_bool(trap_root.visible).is_true()
	_teardown(ctrl, [trap_root, player])


func test_streamed_character_also_disables_nested_detection_areas() -> void:
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var detection := Area3D.new()
	detection.collision_layer = PhysicsSetup.LAYER_TRIGGER
	detection.collision_mask = PhysicsSetup.LAYER_PLAYER
	enemy.add_child(detection)
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	enemy.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	assert_bool(detection.monitoring).is_false()
	assert_int(detection.collision_layer).is_equal(0)
	assert_int(detection.collision_mask).is_equal(0)
	player.position = enemy.position
	ctrl.update_streaming(true)
	assert_bool(detection.monitoring).is_true()
	assert_int(detection.collision_layer).is_equal(PhysicsSetup.LAYER_TRIGGER)
	assert_int(detection.collision_mask).is_equal(PhysicsSetup.LAYER_PLAYER)
	_teardown(ctrl, [enemy, player])


func test_streamed_static_root_also_disables_nested_static_colliders() -> void:
	var ctrl := _make_controller()
	var chest_root := StaticBody3D.new()
	var nested_collider := StaticBody3D.new()
	chest_root.collision_layer = PhysicsSetup.LAYER_SCENE_OBJECT
	nested_collider.collision_layer = PhysicsSetup.LAYER_SCENE_OBJECT
	chest_root.add_child(nested_collider)
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	chest_root.position = Vector3(chunk_size * 2.0 + 1.0, 0.0, 0.0)
	add_child(chest_root)
	ctrl.register_physics_node(chest_root)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	assert_int(chest_root.collision_layer).is_equal(0)
	assert_int(nested_collider.collision_layer).is_equal(0)
	player.position = chest_root.position
	ctrl.update_streaming(true)
	assert_int(chest_root.collision_layer).is_equal(PhysicsSetup.LAYER_SCENE_OBJECT)
	assert_int(nested_collider.collision_layer).is_equal(PhysicsSetup.LAYER_SCENE_OBJECT)
	_teardown(ctrl, [chest_root, player])


func _make_controller() -> DungeonStreamingController:
	var ctrl := DungeonStreamingController.new()
	add_child(ctrl)
	var layout := DungeonLayout.new()
	layout.width = 32
	layout.height = 32
	layout.tile_size = 3.0
	layout.grid = []
	layout.heights = []
	for y in range(8):
		var row := []
		var hr := []
		for x in range(8):
			row.append(1)
			hr.append(3.0)
		layout.grid.append(row)
		layout.heights.append(hr)
	ctrl.configure(layout, DungeonBuildResult.new())
	return ctrl

func _teardown(ctrl: DungeonStreamingController, nodes: Array) -> void:
	if is_instance_valid(ctrl):
		ctrl.clear()
		ctrl.queue_free()
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
