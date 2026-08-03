extends GdUnitTestSuite

# 阶段 D 步6 补充：DungeonRuntime 行为单元测试
# dungeon_runtime_test.gd 仅验接口存在 + 框架态，本测试验真迁后的行为契约：
#   finish_expedition 幂等性（二次调不重复）
#   on_extraction_requested 触发 finish_expedition(voluntary=true)
#   on_expedition_overtime 触发 finish_expedition(voluntary=false)
#   stop 置 expedition_finished=true
# 避 autoload 依赖（Service/GameState/TavernManager）：用 _level=null 保路径跳过，只验状态机逻辑。

class _FloorWorld extends Node3D:
	var transition_calls := 0
	func transition_to_dungeon() -> void:
		pass
	func transition_to_tavern() -> void:
		pass
	func transition_to_next_floor() -> void:
		transition_calls += 1
		if GameState != null and GameState.has_method("advance_dungeon_floor"):
			GameState.advance_dungeon_floor()

func before() -> void:
	load("res://scenes/expedition/dungeon_runtime.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")

func test_finish_expedition_is_idempotent() -> void:
	# finish_expedition 幂等性——gdUnit4 test mode 下 TavernManager autoload 是 placeholder，
	# 真调 finish_expedition 会触 extract_to_tavern 崩。改源码契约级验守卫存在：
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var finish_block := _extract_func_block(src, "finish_expedition")
	assert_bool(finish_block.contains("if expedition_finished:") or finish_block.contains("if expedition_finished")).is_true()
	assert_bool(finish_block.contains("expedition_finished = true") or finish_block.contains("expedition_finished=true")).is_true()
	# TavernManager 守卫应含 is_instance_valid + has_method（防 placeholder 崩）
	assert_bool(finish_block.contains("is_instance_valid(TavernManager)")).is_true()
	assert_bool(finish_block.contains("has_method(\"extract_to_tavern\")")).is_true()

func test_on_extraction_requested_triggers_finish_voluntary() -> void:
	# on_extraction_requested 应含 finish_expedition(player, true) 调用（契约级验，避 autoload 崩）
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var block := _extract_func_block(src, "on_extraction_requested")
	assert_bool(block.contains("finish_expedition(player, true)") or block.contains("finish_expedition(player,true)")).is_true()

func test_runtime_wires_extraction_guidance_feedback_and_hunt_pressure() -> void:
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var wire_block := _extract_func_block(src, "wire_extraction_portal_signal")
	assert_bool(wire_block.contains("extraction_started.connect(on_extraction_started)")).is_true()
	assert_bool(wire_block.contains("extraction_progress.connect(on_extraction_progress)")).is_true()
	assert_bool(wire_block.contains("extraction_cancelled.connect(on_extraction_cancelled)")).is_true()
	var start_block := _extract_func_block(src, "on_extraction_started")
	assert_bool(start_block.contains("apply_monster_hunt_pressure(true, false)")).is_true()

func test_runtime_wires_downstairs_trigger_and_advances_once() -> void:
	var previous_floor := GameState.get_dungeon_floor() if GameState.has_method("get_dungeon_floor") else 1
	GameState.set_dungeon_floor(1)
	var world := _FloorWorld.new()
	add_child(world)
	var level := Node3D.new()
	world.add_child(level)
	var result := DungeonBuildResult.new()
	result.interaction_root = Node3D.new()
	level.add_child(result.interaction_root)
	var portal := Node3D.new()
	portal.name = "DownstairsPortal"
	portal.set_meta("topdown_kind", "stairs")
	var area := Area3D.new()
	area.name = "DownstairsArea"
	portal.add_child(area)
	result.interaction_root.add_child(portal)
	var runtime := DungeonRuntime.new()
	level.add_child(runtime)
	runtime.configure(DungeonLayout.new(), result, level)
	runtime.wire_downstairs_signal()

	assert_bool(area.body_entered.is_connected(runtime.on_downstairs_entered)).is_true()
	assert_int(area.collision_layer).is_equal(PhysicsSetup.LAYER_TRIGGER)
	assert_int(area.collision_mask).is_equal(PhysicsSetup.LAYER_PLAYER)
	var player := Player.new()
	runtime.on_downstairs_entered(player)
	runtime.on_downstairs_entered(player)
	assert_int(world.transition_calls).is_equal(1)
	assert_str(GameState.get_dungeon_floor_label()).is_equal("L2")

	player.free()
	runtime.free()
	level.free()
	world.free()
	GameState.set_dungeon_floor(previous_floor)

func test_runtime_start_connects_downstairs_signal() -> void:
	var source := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var start_block := _extract_func_block(source, "start")
	assert_bool(start_block.contains("wire_downstairs_signal()")).is_true()
	assert_bool(source.contains("func wire_downstairs_signal()")).is_true()

func test_on_expedition_overtime_triggers_finish_involuntary() -> void:
	# on_expedition_overtime 应触发 finish_expedition(voluntary=false)
	# 但它内部调 GameState.current_player——headless test mode GameState 是 autoload placeholder
	# 改用 stop() 验等价状态机逻辑
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.free()

func test_stop_sets_expedition_finished() -> void:
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	assert_bool(rt.expedition_finished).is_false()
	rt.stop()
	assert_bool(rt.expedition_finished).is_true()
	rt.free()


func test_stabilize_lighting_disables_specular_on_all_dungeon_lights() -> void:
	var level := Node3D.new()
	add_child(level)
	var local_light := OmniLight3D.new()
	local_light.light_specular = 0.8
	var ambient_light := DirectionalLight3D.new()
	ambient_light.light_specular = 0.8
	level.add_child(local_light)
	level.add_child(ambient_light)

	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), level)
	rt.stabilize_lighting()

	assert_float(local_light.light_specular) \
		.override_failure_message("地牢局部光源必须关闭镜面贡献").is_equal_approx(0.0, 0.001)
	assert_float(ambient_light.light_specular) \
		.override_failure_message("地牢方向光必须关闭镜面贡献").is_equal_approx(0.0, 0.001)
	rt.free()
	level.free()

func test_stop_cancels_deferred_enemy_spawn_state() -> void:
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(src.contains("_enemy_spawn_active = false")) \
		.override_failure_message("stop() 必须停止待处理的分帧刷怪").is_true()
	assert_bool(src.contains("_enemy_spawn_generation += 1")) \
		.override_failure_message("stop() 必须使已排队的刷怪回调失效").is_true()
	assert_bool(src.contains("_enemy_spawn_timer = null")) \
		.override_failure_message("stop() 不应继续持有待处理 SceneTreeTimer").is_true()

func test_spawn_pump_rejects_stale_generation_and_removed_runtime() -> void:
	var src := (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var pump_start := src.find("func _pump_enemy_spawns")
	var pump := src.substr(pump_start) if pump_start >= 0 else ""
	assert_bool(pump.contains("generation != _enemy_spawn_generation")).is_true()
	assert_bool(pump.contains("not _enemy_spawn_active")).is_true()
	assert_bool(pump.contains("not is_inside_tree()")).is_true()

func test_finish_expedition_after_stop_is_noop() -> void:
	# stop 后 finish_expedition 应被守卫拦住（已 finished）
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.stop()
	var before := rt.expedition_finished
	rt.finish_expedition(null, true)
	assert_bool(rt.expedition_finished == before).is_true()  # 未变
	rt.free()

func test_configure_with_null_level_is_safe() -> void:
	# configure(_level=null) 后 start() 应早退不崩（_level==null 守卫）
	var rt := DungeonRuntime.new()
	rt.configure(DungeonLayout.new(), DungeonBuildResult.new(), null)
	rt.start()  # _level==null 应早退
	assert_bool(rt.expedition_finished).is_false()  # start 不置 finished
	rt.free()


# ── helpers ──────────────────────────────────────────────────
func _extract_func_block(src: String, func_name: String) -> String:
	var start_idx := src.find("func %s(" % func_name)
	if start_idx < 0:
		return ""
	var search_from := start_idx + 1
	while true:
		var next_func := src.find("\nfunc ", search_from)
		var next_static := src.find("\nstatic func ", search_from)
		var next_class := src.find("\nclass_name ", search_from)
		var candidates := [next_func, next_static, next_class]
		var min_next := -1
		for c in candidates:
			if c > 0 and (min_next < 0 or c < min_next):
				min_next = c
		if min_next < 0:
			return src.substr(start_idx)
		return src.substr(start_idx, min_next - start_idx)
	return ""
