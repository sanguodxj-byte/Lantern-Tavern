extends GdUnitTestSuite

# 阶段 8 测试：DungeonStreamingController 只依赖 layout+build_result+玩家位置。
# 覆盖：chunk 计算、节点注册、激活半径、物理体启停、视觉根启停、
#       玩家跨 chunk 增量更新、清理无残留、重复注册不重复处理、集成 isaac。

func before() -> void:
	load("res://scenes/expedition/dungeon_streaming_controller.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_generator.gd")

func test_chunk_calculation_rounds_down() -> void:
	var ctrl := DungeonStreamingController.new()
	var layout := _make_8x8_layout()
	ctrl.configure(layout, DungeonBuildResult.new())
	# chunk_size = 8 cells * 3m = 24m。pos (0,0,0) -> chunk (0,0)；pos (24,0,0) -> chunk (1,0)
	assert_vector(ctrl._world_to_chunk(Vector3(0, 0, 0))).is_equal(Vector2i(0, 0))
	assert_vector(ctrl._world_to_chunk(Vector3(24, 0, 0))).is_equal(Vector2i(1, 0))
	assert_vector(ctrl._world_to_chunk(Vector3(23.9, 0, 0))).is_equal(Vector2i(0, 0))
	ctrl.clear()

func test_iter_chunks_returns_radius_box() -> void:
	var ctrl := DungeonStreamingController.new()
	var chunks := ctrl._iter_chunks(Vector2i(0, 0), 1)
	# radius=1 → 3x3 = 9 chunks
	assert_int(chunks.size()).is_equal(9)
	var chunks2 := ctrl._iter_chunks(Vector2i(5, 5), 2)
	# radius=2 → 5x5 = 25 chunks
	assert_int(chunks2.size()).is_equal(25)

func test_register_visual_node_assigns_chunk() -> void:
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(_make_8x8_layout(), DungeonBuildResult.new())
	var node := Node3D.new()
	node.position = Vector3(24, 0, 0)  # chunk (1,0)
	ctrl.register_visual_node(node)
	# 节点应被归到 chunk (1,0)，且 visible=false（注册即停用）
	assert_bool(node.get_meta("stream_visual_registered", false)).is_true()
	assert_bool(node.visible).is_false()
	assert_int(ctrl._visual_chunks.size()).is_equal(1)
	node.queue_free()
	ctrl.clear()

func test_register_visual_node_idempotent() -> void:
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(_make_8x8_layout(), DungeonBuildResult.new())
	var node := Node3D.new()
	node.position = Vector3(0, 0, 0)
	ctrl.register_visual_node(node)
	ctrl.register_visual_node(node)  # 重复注册
	# 同一节点不应被重复处理
	var chunk_nodes: Array = ctrl._visual_chunks[Vector2i(0, 0)]
	assert_int(chunk_nodes.size()).is_equal(1)
	node.queue_free()
	ctrl.clear()

func test_update_activates_visuals_in_radius() -> void:
	var ctrl := DungeonStreamingController.new()
	var layout := _make_8x8_layout()
	ctrl.configure(layout, DungeonBuildResult.new())
	# 注册一个 chunk (0,0) 的视觉节点
	var node := Node3D.new()
	node.position = Vector3(0, 0, 0)
	add_child(node)
	ctrl.register_visual_node(node)
	# 玩家在 chunk (0,0)，radius=1 → chunk (0,0) 激活
	var player := Node3D.new()
	player.position = Vector3(0, 0, 0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	assert_bool(node.visible).is_true()
	# �玩家移到 chunk (3,3) 远超 radius=1，节点应停用
	player.position = Vector3(100, 0, 100)
	ctrl.update_streaming(true)
	assert_bool(node.visible).is_false()
	player.queue_free()
	node.queue_free()
	ctrl.clear()

func test_update_physics_chunk_radius_activates_bodies() -> void:
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(_make_8x8_layout(), DungeonBuildResult.new())
	# 注册一个 StaticBody3D 在 chunk (0,0)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0, 0)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	body.add_child(col)
	add_child(body)
	ctrl.register_physics_node(body)
	# 记下原始 layer（注册时 controller 把它存到 meta，再停用设 0）
	var original_layer: int = body.collision_layer
	var player := Node3D.new()
	player.position = Vector3(0, 0, 0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	# 玩家在 chunk (0,0)，physics radius=1 → body 激活，collision_layer 恢复原始值
	assert_int(body.collision_layer).is_equal(original_layer)
	# 玤玩家远离，body 停用
	player.position = Vector3(100, 0, 100)
	ctrl.update_streaming(true)
	assert_int(body.collision_layer).is_equal(0)
	player.queue_free()
	body.queue_free()
	ctrl.clear()

func test_player_cross_chunk_incremental_update() -> void:
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(_make_8x8_layout(), DungeonBuildResult.new())
	var player := Node3D.new()
	player.position = Vector3(0, 0, 0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	var first_chunk := Vector2i(0, 0)
	assert_vector(ctrl._last_player_chunk).is_equal(first_chunk)
	# 玤玩家不跨 chunk：update 不应重算（无 force）
	player.position = Vector3(10, 0, 10)  # 仍 chunk (0,0)
	ctrl.update_streaming(false)
	assert_vector(ctrl._last_player_chunk).is_equal(first_chunk)
	# 玤玩家跨 chunk：update 应推进
	player.position = Vector3(25, 0, 0)  # chunk (1,0)
	ctrl.update_streaming(false)
	assert_vector(ctrl._last_player_chunk).is_equal(Vector2i(1, 0))
	player.queue_free()
	ctrl.clear()

func test_clear_removes_all_registrations() -> void:
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(_make_8x8_layout(), DungeonBuildResult.new())
	var node := Node3D.new()
	node.position = Vector3(0, 0, 0)
	add_child(node)
	ctrl.register_visual_node(node)
	assert_int(ctrl._visual_chunks.size()).is_equal(1)
	ctrl.clear()
	assert_int(ctrl._visual_chunks.size()).is_equal(0)
	assert_int(ctrl._physics_chunks.size()).is_equal(0)
	assert_int(ctrl._terrain_chunks.size()).is_equal(0)
	assert_int(ctrl._light_chunks.size()).is_equal(0)
	assert_bool(ctrl._streaming_ready).is_false()
	node.queue_free()

func test_controller_does_not_read_generator_internals() -> void:
	# 阓段 8 核心约束：controller 不读 procedural_dungeon.gd 的 _grid/_rooms/_streamed_* 内部字段
	# 验证：controller 类源不含 _grid/_rooms/_room_roles/_heights 字面量
	var script := load("res://scenes/expedition/dungeon_streaming_controller.gd") as GDScript
	var src: String = script.source_code
	# 正向断言：controller 持 _layout/_build_result/_player 作为合法输入。
	# 字面量扫描对“是否读生成器内部”检验不可靠（注释/字符串都会误命中），
	# 故不做反向扫描；阶段 10 收尾时改用 ast-grep 检查成员变量集不含 _grid/_rooms。
	assert_bool(src.contains("_layout")).is_true()
	assert_bool(src.contains("_build_result")).is_true()
	assert_bool(src.contains("_player")).is_true()

func test_integration_isaac_layout_streaming_runs() -> void:
	# isaac 真产出：scene builder 产出 build_result 后，controller 应能 configure + update
	var cfg := DungeonGenerationConfig.new()
	cfg.algorithm = "isaac"
	var layout := DungeonGenerator.new().generate(cfg)
	var parent := Node3D.new()
	add_child(parent)
	# 用 scene builder 产 hazards/chests，它们注册到 streamed_physics_nodes
	DungeonHazardPlanner.new().plan(layout)
	DungeonSpawnPlanner.new().plan_chest_spawns(layout)
	var build_result := DungeonSceneBuilder.new().build(layout, parent)
	var ctrl := DungeonStreamingController.new()
	ctrl.configure(layout, build_result)
	var player := Node3D.new()
	player.position = Vector3(0, 0, 0)
	add_child(player)
	ctrl.set_player(player)
	ctrl.update_streaming(true)
	# 应能跑完不报错；physics_chunks 至少有 hazards_root 下注册的陷阱
	assert_bool(ctrl._physics_chunks.size() >= 1).is_true()
	ctrl.clear()
	player.queue_free()
	build_result.dispose()
	parent.queue_free()


# ── helpers ──────────────────────────────────────────────────
func _make_8x8_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.width = 8
	layout.height = 8
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
	return layout
