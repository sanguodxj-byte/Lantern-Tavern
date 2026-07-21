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
	add_child(rt)
	assert_bool(rt.layout == null).is_true()
	assert_bool(rt.build_result == null).is_true()
	assert_bool(rt.expedition_finished).is_false()
	rt.queue_free()

func test_configure_injects_layout_and_build_result() -> void:
	var rt := DungeonRuntime.new()
	add_child(rt)
	var layout := DungeonLayout.new()
	var build_result := DungeonBuildResult.new()
	rt.configure(layout, build_result)
	assert_bool(rt.layout == layout).is_true()
	assert_bool(rt.build_result == build_result).is_true()
	rt.queue_free()

func test_start_and_stop_are_safe_noops_in_framework() -> void:
	# 框架版 start/stop 暂空，不应崩
	var rt := DungeonRuntime.new()
	add_child(rt)
	rt.start()
	assert_bool(rt.expedition_finished).is_false()
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.queue_free()

func test_runtime_does_not_create_terrain_or_streaming() -> void:
	# 严格约束：DungeonRuntime 不应创建地形节点或维护 streaming registry
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	# 不应含 MultiMesh/StaticBody/Occluder 创建（那是 builder 范畴）
	for forbidden in ["MultiMesh.new()", "StaticBody3D.new()", "BoxOccluder3D.new()", "MultiMeshInstance3D.new()"]:
		assert_bool(src.contains(forbidden)).override_failure_message("DungeonRuntime 不应含 %s（builder 范畴）" % forbidden).is_false()
	# 不应自建 streaming chunk 管理；允许协调调用 controller.register_*/update_streaming
	for forbidden in ["_world_to_stream_chunk", "_visual_chunks", "_physics_chunks", "MultiMeshInstance3D.new()"]:
		assert_bool(src.contains(forbidden)).override_failure_message("DungeonRuntime 不应含 %s（controller/builder 范畴）" % forbidden).is_false()

func test_runtime_has_full_runtime_interface_set() -> void:
	# D 步2：DungeonRuntime 应具备 runtime 范畴的全套接口名（真迁移放下回合，框架版占位）
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	for iface in ["func spawn_player()", "func spawn_enemies(", "func spawn_items()",
			"func mount_expedition_hud()", "func setup_exploration_pressure()",
			"func wire_extraction_portal_signal()", "func finish_expedition(",
			"func on_extraction_requested(", "func on_expedition_overtime(",
			"func on_pressure_changed(", "func on_door_pressure_action(",
			"func apply_player_vision_pressure(", "func apply_environment_activity(",
			"func apply_monster_hunt_pressure("]:
		assert_bool(src.contains(iface)) \
			.override_failure_message("DungeonRuntime 缺接口 %s" % iface).is_true()

# ── 回归：地牢全黑根因（set_player 接线缺失）─────────────────────
# 修复前 start() 只 spawn_player，从不把玩家引用交给 streaming controller，
# 导致 controller._player 恒为 null → _player_position() 用地图角落 fallback →
# 玩家周围的 terrain/wall/light chunk 永不激活 → 地牢全黑无墙体无光源。
class _FakeStreamController extends Node:
	var set_player_called := false
	var received_player: Node = null
	func set_player(p) -> void:
		set_player_called = true
		received_player = p

class _FakeWorld extends Node3D:
	func transition_to_tavern() -> void: pass
	func transition_to_dungeon() -> void: pass

class _FakeLevel extends Node3D:
	var spawned: Node3D = null
	func spawn_player() -> Node3D:
		spawned = Node3D.new()
		spawned.name = "FakeSpawnedPlayer"
		add_child(spawned)
		return spawned

func test_start_wires_spawned_player_to_streaming_controller() -> void:
	# 用 _FakeWorld 作父级：_is_running_under_world() 返回 true，跳过额外 UI 场景实例化。
	var world := _FakeWorld.new()
	add_child(world)
	var level := _FakeLevel.new()
	world.add_child(level)
	var ctrl := _FakeStreamController.new()
	add_child(ctrl)
	var rt := DungeonRuntime.new()
	level.add_child(rt)
	# layout/build_result 传 null：spawn_enemies/spawn_items/wire_extraction 均安全早返回，
	# 只保留 spawn_player + streaming 接线路径。
	rt.configure(null, null, level, ctrl, null)
	rt.start()
	assert_bool(ctrl.set_player_called) \
		.override_failure_message("runtime.start() 必须把玩家引用交给 streaming controller，否则地牢全黑").is_true()
	assert_bool(ctrl.received_player == level.spawned) \
		.override_failure_message("streaming controller 收到的应是 spawn_player() 返回的玩家节点").is_true()
	rt.queue_free()
	ctrl.queue_free()
	world.queue_free()

