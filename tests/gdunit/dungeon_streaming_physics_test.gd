extends GdUnitTestSuite

# streaming 物理/视觉行为已迁入 DungeonStreamingController。

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_controller.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_streamed_character_body_across_chunk_boundary_stays_active_when_near() -> void:
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	# 玩家与敌人各在 chunk 边界两侧，实际距离仅 1m。
	enemy.position = Vector3(chunk_size + 0.5, 0.0, 0.0)
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3(chunk_size - 0.5, 0.0, 0.0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(enemy.visible) 		.override_failure_message("跨 chunk 边界仅 1m 的敌人不应被整根隐藏") 		.is_true()
	assert_bool(enemy.is_physics_processing()).is_true()
	assert_int(enemy.collision_layer).is_equal(PhysicsSetup.LAYER_ENEMY)
	assert_int(enemy.collision_mask).is_equal(PhysicsSetup.MASK_ENEMY)
	assert_bool(bool(enemy.get_meta("stream_physics_active", false))).is_true()
	_teardown(ctrl, [enemy, player])

func test_streamed_character_body_chasing_across_chunks_is_rehomed_and_stays_active() -> void:
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	enemy.position = Vector3(chunk_size * 2.0 + 0.5, 0.0, 0.0)
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3(chunk_size * 2.0 - 0.5, 0.0, 0.0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	# 玩家跨入新 chunk，敌人追击至玩家附近（注册 chunk 已与实时位置分离）。
	player.position = Vector3(0.5, 0.0, 0.0)
	enemy.position = Vector3(1.5, 0.0, 0.0)
	ctrl.update_streaming(true)
	assert_bool(enemy.visible) 		.override_failure_message("追逐跨 chunk 后敌人应保持可见") 		.is_true()
	assert_bool(enemy.is_physics_processing()).is_true()
	assert_bool(bool(enemy.get_meta("stream_physics_active", false))).is_true()
	assert_bool(Vector2i(enemy.get_meta("stream_physics_chunk", Vector2i.ZERO)) == Vector2i.ZERO) 		.override_failure_message("追逐跨 chunk 的动态体应重新归位到当前 chunk") 		.is_true()
	# 玩家远离后，远距动态体应正确停用。
	player.position = Vector3(chunk_size * 3.0, 0.0, 0.0)
	ctrl.update_streaming(true)
	assert_bool(bool(enemy.get_meta("stream_physics_active", true))).is_false()
	_teardown(ctrl, [enemy, player])


func test_dynamic_body_in_paper_band_stays_visible_but_physics_dormant() -> void:
	# 24m 物理激活半径之外、36m 视觉半径之内的动态体：物理休眠（碰撞层清空、
	# 无 physics_process），但必须保持可见，让 billboard/imposter 纸片 LOD 接管渲染。
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	var band_distance := chunk_size * 1.25  # 30m，处于 24–36m 纸片带
	enemy.position = Vector3(band_distance, 0.0, 0.0)
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(bool(enemy.get_meta("stream_physics_active", true))) 		.override_failure_message("纸片带内的动态体物理应休眠") 		.is_false()
	assert_bool(enemy.is_physics_processing()) 		.override_failure_message("纸片带内的动态体不应跑物理 AI") 		.is_false()
	assert_int(enemy.collision_layer) 		.override_failure_message("纸片带内的动态体不应持碰撞层") 		.is_equal(0)
	assert_bool(enemy.visible) 		.override_failure_message("纸片带内的动态体应保持可见（纸片 LOD 接管远距渲染）") 		.is_true()
	assert_bool(enemy.is_processing()) 		.override_failure_message("纸片带内的动态体应保留 _process，让 billboard/imposter LOD 继续切换且正常受光") 		.is_true()
	_teardown(ctrl, [enemy, player])


func test_dynamic_body_beyond_visual_radius_is_hidden() -> void:
	# 超过 36m 视觉半径：动态体物理休眠且整根隐藏，避免远处空耗 draw call。
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	var far_distance := chunk_size * 1.75  # 42m，超出 36m 视觉半径
	enemy.position = Vector3(far_distance, 0.0, 0.0)
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(bool(enemy.get_meta("stream_physics_active", true))).is_false()
	assert_bool(enemy.is_physics_processing()).is_false()
	assert_bool(enemy.visible) 		.override_failure_message("超出 36m 视觉半径的动态体应整根隐藏") 		.is_false()
	_teardown(ctrl, [enemy, player])


func test_paper_band_body_becomes_hidden_when_player_moves_far_away() -> void:
	# 玩家从纸片带走远（>36m）时，动态体应由"可见纸片"转为整根隐藏。
	var ctrl := _make_controller()
	var enemy := CharacterBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	enemy.position = Vector3(chunk_size * 1.25, 0.0, 0.0)  # 30m 纸片带
	enemy.collision_layer = PhysicsSetup.LAYER_ENEMY
	enemy.collision_mask = PhysicsSetup.MASK_ENEMY
	add_child(enemy)
	ctrl.register_physics_node(enemy)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(enemy.visible).is_true()
	player.position = Vector3(chunk_size * 3.0, 0.0, 0.0)  # 72m；与 30m 敌人相距 42m，超出 36m 视觉半径
	ctrl.update_streaming(true)
	assert_bool(enemy.visible) 		.override_failure_message("走远后纸片带动态体应整根隐藏") 		.is_false()
	assert_bool(bool(enemy.get_meta("stream_physics_active", true))).is_false()
	_teardown(ctrl, [enemy, player])


func test_paper_band_static_body_keeps_physics_within_chunk_grid() -> void:
	# 可见性解耦只针对动态体：同一 30m 距离带内，静态体仍按物理 chunk（radius 1，
	# 含 chunk 1 即 24–48m）保持碰撞激活，不受动态体的"休眠但可见"影响。
	var ctrl := _make_controller()
	var static_body := StaticBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	static_body.position = Vector3(chunk_size * 1.25, 0.0, 0.0)  # 30m，位于 chunk 1
	static_body.collision_layer = PhysicsSetup.LAYER_SCENE_OBJECT
	add_child(static_body)
	ctrl.register_physics_node(static_body)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(static_body.visible) 		.override_failure_message("静态体在物理 chunk 网格内应保持可见") 		.is_true()
	assert_int(static_body.collision_layer) 		.override_failure_message("静态体在物理 chunk 网格内应保持碰撞激活") 		.is_equal(PhysicsSetup.LAYER_SCENE_OBJECT)
	_teardown(ctrl, [static_body, player])


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

func test_dynamic_body_in_adjacent_chunk_stays_frozen_until_player_enters() -> void:
	var ctrl := _make_controller()
	var item := RigidBody3D.new()
	var chunk_size := float(DungeonStreamingController.STREAM_CHUNK_SIZE_CELLS) * 3.0
	item.position = Vector3(chunk_size + 1.0, 0.0, 0.0)
	item.collision_layer = PhysicsSetup.LAYER_PICKABLE
	item.collision_mask = PhysicsSetup.MASK_PICKABLE
	add_child(item)
	ctrl.register_physics_node(item)
	var player := Node3D.new()
	player.position = Vector3.ZERO
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(item.freeze).is_true()
	assert_int(item.collision_layer).is_equal(0)
	player.position = item.position
	ctrl.update_streaming(true)
	assert_bool(item.freeze).is_false()
	assert_int(item.collision_layer).is_equal(PhysicsSetup.LAYER_PICKABLE)
	_teardown(ctrl, [item, player])

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
