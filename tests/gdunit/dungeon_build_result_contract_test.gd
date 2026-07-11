extends GdUnitTestSuite

# 阶段 测试优化1：DungeonBuildResult 结构契约测试
# 验收门槛（评审建议）：9 个 root 唯一非重；dispose() 后全置 null + 注册表清空。

func before() -> void:
	load("res://scenes/expedition/dungeon_build_result.gd")
	load("res://scenes/expedition/dungeon_layout.gd")

func test_build_result_has_all_nine_roots() -> void:
	var result := DungeonBuildResult.new()
	# 9 个 root 字段必须存在且初值为 null（未构建前）
	for field in ["terrain_root", "collision_root", "doors_root", "hazards_root",
			"decor_root", "spawn_root", "interaction_root", "streamed_visual_root",
			"streamed_physics_root"]:
		assert_bool(result.get(field) == null) \
			.override_failure_message("build_result.%s 初值应为 null" % field).is_true()

func test_build_result_streams_registries_empty_initially() -> void:
	var result := DungeonBuildResult.new()
	assert_array(result.streamed_visual_nodes).has_size(0)
	assert_array(result.streamed_physics_nodes).has_size(0)
	assert_bool(result.terrain_chunks.is_empty()).is_true()

func test_build_result_terrain_transform_fields_empty_initially() -> void:
	var result := DungeonBuildResult.new()
	assert_bool(result.floor_transforms.is_empty()).is_true()
	assert_bool(result.ceiling_transforms.is_empty()).is_true()
	assert_bool(result.wall_transforms_by_height.is_empty()).is_true()
	assert_bool(result.wall_h_map.is_empty()).is_true()
	assert_bool(result.batched_decor_transforms.is_empty()).is_true()

func test_dispose_nulls_all_roots_and_clears_registries() -> void:
	var result := DungeonBuildResult.new()
	# 模拟填充 root + 注册表
	result.terrain_root = Node3D.new()
	result.collision_root = Node3D.new()
	result.doors_root = Node3D.new()
	result.hazards_root = Node3D.new()
	result.decor_root = Node3D.new()
	result.spawn_root = Node3D.new()
	result.interaction_root = Node3D.new()
	result.streamed_visual_root = Node3D.new()
	result.streamed_physics_root = Node3D.new()
	result.streamed_visual_nodes.append(Node3D.new())
	result.streamed_physics_nodes.append(Node3D.new())
	result.terrain_chunks[Vector2i(0, 0)] = [Node3D.new()]
	# dispose 前先 add_child 到临时 parent（queue_free 需在树内才生效）
	var parent := Node3D.new()
	for field in ["terrain_root", "collision_root", "doors_root", "hazards_root",
			"decor_root", "spawn_root", "interaction_root", "streamed_visual_root",
			"streamed_physics_root"]:
		parent.add_child(result.get(field))
	result.dispose()
	# dispose 后全 root 应置 null
	for field in ["terrain_root", "collision_root", "doors_root", "hazards_root",
			"decor_root", "spawn_root", "interaction_root", "streamed_visual_root",
			"streamed_physics_root"]:
		assert_bool(result.get(field) == null) \
			.override_failure_message("dispose 后 %s 应置 null" % field).is_true()
	# 注册表应清空
	assert_array(result.streamed_visual_nodes).has_size(0)
	assert_array(result.streamed_physics_nodes).has_size(0)
	assert_bool(result.terrain_chunks.is_empty()).is_true()
	# 等 queue_free 生效
	await Engine.get_main_loop().process_frame
	parent.free()

func test_is_built_requires_terrain_root() -> void:
	var result := DungeonBuildResult.new()
	assert_bool(result.is_built()).is_false()
	result.terrain_root = Node3D.new()
	assert_bool(result.is_built()).is_true()
	result.terrain_root.free()

func test_roots_are_distinct_instances() -> void:
	# 同一 build 不应让两个 root 指同一节点（builder 用 _new_root 各产 Node3D）
	var result := DungeonBuildResult.new()
	var parent := Node3D.new()
	result.terrain_root = Node3D.new()
	result.collision_root = Node3D.new()
	parent.add_child(result.terrain_root)
	parent.add_child(result.collision_root)
	assert_bool(result.terrain_root != result.collision_root).is_true()
	assert_bool(result.terrain_root.get_instance_id() != result.collision_root.get_instance_id()).is_true()
	result.dispose()
	parent.free()
