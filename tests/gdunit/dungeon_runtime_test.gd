extends GdUnitTestSuite

# 阶段 D：DungeonRuntime 框架契约测试
# 真迁移放下回合（保 procedural 旧路径不破）；本测试验框架接口存在 + configure/start/stop 不崩。

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_runtime_has_configure_start_stop_interface() -> void:
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(src.contains("func configure(p_layout: DungeonLayout")) \
		.override_failure_message("DungeonRuntime 应有 configure 接口").is_true()
	assert_bool(src.contains("func start() -> void:")).is_true()
	assert_bool(src.contains("func stop() -> void:")).is_true()

func test_runtime_holds_layout_and_build_result() -> void:
	var rt := DungeonRuntime.new()
	assert_bool(rt.layout == null).is_true()
	assert_bool(rt.build_result == null).is_true()
	assert_bool(rt.expedition_finished).is_false()

func test_configure_injects_layout_and_build_result() -> void:
	var rt := DungeonRuntime.new()
	var layout := DungeonLayout.new()
	var build_result := DungeonBuildResult.new()
	rt.configure(layout, build_result)
	assert_bool(rt.layout == layout).is_true()
	assert_bool(rt.build_result == build_result).is_true()

func test_start_and_stop_are_safe_noops_in_framework() -> void:
	# 框架版 start/stop 暂空，不应崩
	var rt := DungeonRuntime.new()
	rt.start()
	assert_bool(rt.expedition_finished).is_false()
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.free()

func test_runtime_does_not_create_terrain_or_streaming() -> void:
	# 严格约束：DungeonRuntime 不应创建地形节点或管理 streaming
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	# 不应含 MultiMesh/StaticBody/Occluder 创建（那是 builder 范畴）
	for forbidden in ["MultiMesh.new()", "StaticBody3D.new()", "BoxOccluder3D.new()", "MultiMeshInstance3D.new()"]:
		assert_bool(src.contains(forbidden)).override_failure_message("DungeonRuntime 不应含 %s（builder 范畴）" % forbidden).is_false()
	# 不应含 streaming chunk 管理（那是 controller 范畴）
	for forbidden in ["register_visual_node", "register_physics_node", "update_streaming", "_world_to_stream_chunk"]:
		assert_bool(src.contains(forbidden)).override_failure_message("DungeonRuntime 不应含 %s（controller 范畴）" % forbidden).is_false()
