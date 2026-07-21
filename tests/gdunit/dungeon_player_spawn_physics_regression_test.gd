extends GdUnitTestSuite

## 回归：进入大地牢时，出生点位于负坐标 chunk，地板碰撞必须在首帧激活。
## 之前合并碰撞体都以根节点原点登记，玩家出生 chunk 的碰撞被 streaming 关闭，
## 随后 CharacterBody3D 会直接掉出地图。

func before() -> void:
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_streaming_controller.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_player_spawn_chunk_keeps_floor_collision_active() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var layout := _make_large_floor_layout()
	layout.player_spawn_cell = Vector2i(1, 1)

	var build_result := DungeonSceneBuilder.new().build(layout, parent)
	var controller := DungeonStreamingController.new()
	add_child(controller)
	controller.configure(layout, build_result)

	var player := Node3D.new()
	player.position = layout.calc_player_spawn_pos()
	add_child(player)
	controller.set_player(player)

	var expected_chunk := controller._world_to_chunk(player.global_position)
	var floor_body := build_result.collision_root.get_node_or_null(
		"FloorCollisions_%d_%d" % [expected_chunk.x, expected_chunk.y]) as StaticBody3D
	assert_object(floor_body) \
		.override_failure_message("出生点所在 chunk 应有对应地板碰撞体，实际 chunk=%s" % str(expected_chunk)) \
		.is_not_null()
	assert_int(floor_body.collision_layer) \
		.override_failure_message("出生点所在 chunk 的地板碰撞必须在首帧激活") \
		.is_equal(PhysicsSetup.LAYER_ENVIRONMENT)

	controller.clear()
	controller.queue_free()
	parent.queue_free()
	player.queue_free()

func _make_large_floor_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 32
	layout.height = 32
	layout.tile_size = 3.0
	for _y in range(layout.height):
		var row: Array = []
		var heights: Array = []
		for _x in range(layout.width):
			row.append(1)
			heights.append(3.0)
		layout.grid.append(row)
		layout.heights.append(heights)
	return layout
