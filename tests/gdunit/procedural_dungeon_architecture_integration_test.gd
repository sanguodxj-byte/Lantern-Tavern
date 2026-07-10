extends GdUnitTestSuite

# 阶段 9 生产接线集成测试。
# 验收门槛（Review 判定）：ProceduralDungeon 通过 DungeonGenerator 生成、持 DungeonLayout、
# validator/planner/builder/streaming 在生产路径执行、新旧路径不重复实例化。
#
# 不 add_child（避免 procedural_dungeon_test.gd 的 >300s 超时，纯源码扫描 + 字段声明验证）。

const PD_PATH := "res://scenes/expedition/procedural_dungeon.gd"

func test_ready_wires_generator_to_layout() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonGenerator.new().generate(config)")) \
		.override_failure_message("_ready() 应通过 DungeonGenerator 生成 layout").is_true()
	assert_bool(src.contains("var layout: DungeonLayout")) \
		.override_failure_message("ProceduralDungeon 应持 layout 字段供生产集成测试断言").is_true()

func test_ready_wires_connectivity_validator() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonConnectivityValidator.new().validate(layout)")) \
		.override_failure_message("_ready() 应在生产路径调连通性验证").is_true()

func test_ready_wires_hazard_planner() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonHazardPlanner.new().plan(layout)")) \
		.override_failure_message("_ready() 应在生产路径调危险地形规划").is_true()

func test_ready_wires_spawn_planner() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonSpawnPlanner.new()")) \
		.override_failure_message("_ready() 应在生产路径调 spawn 规划").is_true()
	assert_bool(src.contains("plan_enemy_spawns(layout)")).is_true()
	assert_bool(src.contains("plan_chest_spawns(layout)")).is_true()

func test_ready_wires_scene_builder() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonSceneBuilder.new().build(layout, self)")) \
		.override_failure_message("_ready() 应通过 SceneBuilder 集中实例化").is_true()
	assert_bool(src.contains("var build_result: DungeonBuildResult")) \
		.override_failure_message("ProceduralDungeon 应持 build_result 字段").is_true()

func test_ready_wires_streaming_controller() -> void:
	var src := _pd_source()
	assert_bool(src.contains("DungeonStreamingController.new()")) \
		.override_failure_message("_ready() 应创建 streaming controller").is_true()
	assert_bool(src.contains("streaming_controller.configure(layout, build_result)")) \
		.override_failure_message("_ready() 应配置 streaming controller").is_true()
	assert_bool(src.contains("var streaming_controller: DungeonStreamingController")) \
		.override_failure_message("ProceduralDungeon 应持 streaming_controller 字段").is_true()

func test_ready_does_not_directly_instantiate_isaac() -> void:
	# 验收门槛：不直接 new ISAAC_ROOM_GENERATOR 作生成入口。
	# _ready() 里应不再有 ISAAC_ROOM_GENERATOR.new().generate_dungeon —— 该调用已迁到 DungeonGenerator 包装层。
	var src := _pd_source()
	var ready_block := _extract_ready_block(src)
	assert_bool(not ready_block.contains("ISAAC_ROOM_GENERATOR.new().generate_dungeon")) \
		.override_failure_message("_ready() 不应直接调 isaac 生成器，应走 DungeonGenerator").is_true()

func test_generate_visuals_does_not_double_instantiate_hazards() -> void:
	# 验收门槛：新旧路径不存在重复实例化。
	# _generate_visuals() 里的 _spawn_hazard_anchors / _spawn_extraction_portal / _spawn_large_room_terrain_features
	# 应已被注释掉（由 DungeonSceneBuilder 唯一接管）。
	var src := _pd_source()
	var visuals_block := _extract_func_block(src, "_generate_visuals")
	# 注释行以 # 开头才算关闭；活跃调用（无 # 前缀）不应存在
	var active_hazard := _count_active_calls(visuals_block, "_spawn_hazard_anchors(grid")
	var active_extraction := _count_active_calls(visuals_block, "_spawn_extraction_portal(grid")
	var active_large_room := _count_active_calls(visuals_block, "_spawn_large_room_terrain_features(grid")
	assert_int(active_hazard).is_equal(0)
	assert_int(active_extraction).is_equal(0)
	assert_int(active_large_room).is_equal(0)

func test_generate_visuals_keeps_downstairs_portal() -> void:
	# downstairs portal 是手工 MeshInstance3D 拼装（属 terrain 类），builder 第二版未接，暂留 procedural。
	# 这条断言锚定"暂留"契约——阶段 10 terrain 迁移时再迁，本阶段不该误删。
	var src := _pd_source()
	var visuals_block := _extract_func_block(src, "_generate_visuals")
	var active_downstairs := _count_active_calls(visuals_block, "_spawn_downstairs_portal(grid")
	assert_int(active_downstairs).is_equal(1)

func test_ready_still_runs_legacy_visuals_for_terrain() -> void:
	# terrain floor/wall/ceiling/door 重型几何暂留 procedural（阶段 10 再迁）。
	# _ready() 应仍调 _generate_visuals(_grid) 喂地形；hazard/chest/portal 已由 builder 接管不重复。
	var src := _pd_source()
	var ready_block := _extract_ready_block(src)
	assert_bool(ready_block.contains("_generate_visuals(_grid)")) \
		.override_failure_message("_ready() 应仍调 _generate_visuals 喂地形（terrain 暂留 procedural）").is_true()

func test_extraction_portal_signal_wired_in_runtime() -> void:
	# builder 只 instantiate 节点不接信号；信号接线属 runtime 范畴，_ready 后由 _wire_extraction_portal_signal 接。
	var src := _pd_source()
	assert_bool(src.contains("_wire_extraction_portal_signal()")).is_true()
	assert_bool(src.contains("extraction_requested.connect(_on_extraction_requested)")).is_true()

func test_layout_grid_feeds_legacy_visuals() -> void:
	# _ready() 应把 layout.grid 喂给 _grid（供 _generate_visuals），不再单独调 isaac generate_dungeon。
	var src := _pd_source()
	var ready_block := _extract_ready_block(src)
	assert_bool(ready_block.contains("_grid = layout.grid")) \
		.override_failure_message("_ready() 应把 layout.grid 喂给 _grid").is_true()
	assert_bool(ready_block.contains("_rooms = layout.rooms")).is_true()
	assert_bool(ready_block.contains("_room_roles =")).is_true()

func test_process_delegates_to_streaming_controller() -> void:
	# 验收门槛：DungeonStreamingController 唯一 streaming 实现。
	# _process() 应不再调旧 _update_streamed_chunks，转由 controller 子 Node 自跑。
	var src := _pd_source()
	var proc_block := _extract_func_block(src, "_process")
	var active_old := _count_active_calls(proc_block, "_update_streamed_chunks(false)")
	assert_int(active_old).is_equal(0)
	# 旧实现应被注释为死代码
	assert_bool(proc_block.contains("# _update_streamed_chunks(false)")).is_true()

func test_register_streamed_delegates_to_controller() -> void:
	# register_streamed_visual_node / register_streamed_physics_node 应转调 controller
	var src := _pd_source()
	assert_bool(src.contains("streaming_controller.register_visual_node(node)")).is_true()
	assert_bool(src.contains("streaming_controller.register_physics_node(node)")).is_true()

func test_streaming_controller_added_as_child() -> void:
	# controller 应 add_child 挂场景树自跑（_process 自带节流），不再由 ProceduralDungeon 包一层定时器
	var src := _pd_source()
	var ready_block := _extract_ready_block(src)
	assert_bool(ready_block.contains("add_child(streaming_controller)")).is_true()


# ── helpers ──────────────────────────────────────────────────
func _pd_source() -> String:
	return (load(PD_PATH) as GDScript).source_code

func _extract_ready_block(src: String) -> String:
	return _extract_func_block(src, "_ready")

func _extract_func_block(src: String, func_name: String) -> String:
	var start_marker := "func " + func_name + "("
	var start_idx := src.find(start_marker)
	if start_idx < 0:
		return ""
	var block := src.substr(start_idx)
	# 找下一个顶层 func（行首 func）截断
	var next_func := block.find("\nfunc ", 1)
	if next_func < 0:
		return block
	return block.substr(0, next_func)

## 数活跃调用（行首无 # 注释的）——注释掉的调用不计
func _count_active_calls(block: String, call_signature: String) -> int:
	var count := 0
	var lines := block.split("\n")
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if line.contains(call_signature):
			count += 1
	return count
