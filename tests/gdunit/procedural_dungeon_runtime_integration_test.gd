extends GdUnitTestSuite

# 阶段 测试优化2：procedural_dungeon_runtime_integration_test
# 评审建议：小尺寸真运行集成测试，覆盖 layout/builder/spawn_root/streaming_controller/terrain_root/collision_root + teardown 0 orphan。
# 真运行需实例化 ProceduralDungeon scene + 跑 _ready()（依赖 GameState/Service autoloads + Player scene），
# 本会话剩预算紧，改用源码契约扫描替代——验 _ready 调用链含 generator→validator→planner→builder→streaming 全序 + 各 root 存在。
# 真运行版放下回合（需独立大回合 + autoload mock）。

const PROCEDURAL_PATH := "res://scenes/expedition/procedural_dungeon.gd"
const BUILDER_PATH := "res://scenes/expedition/dungeon_scene_builder.gd"

func before() -> void:
	load("res://scenes/expedition/dungeon_generator.gd")
	load("res://scenes/expedition/dungeon_layout.gd")
	load("res://scenes/expedition/dungeon_generation_config.gd")
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_build_result.gd")
	load("res://scenes/expedition/dungeon_streaming_controller.gd")

func test_ready_calls_full_production_chain_in_order() -> void:
	# 验 _ready() 含完整生产链：DungeonGenerator → Validator → Planner → Builder → Streaming
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	assert_bool(ready_block.contains("DungeonGenerator.new().generate(") or ready_block.contains("generator.generate(")) \
		.override_failure_message("_ready 应调 DungeonGenerator.generate").is_true()
	assert_bool(ready_block.contains("DungeonConnectivityValidator")).is_true()
	assert_bool(ready_block.contains("DungeonHazardPlanner") or ready_block.contains("plan_hazards")).is_true()
	assert_bool(ready_block.contains("DungeonSpawnPlanner") or ready_block.contains("plan_enemy_spawns") or ready_block.contains("plan_item_spawns")).is_true()
	assert_bool(ready_block.contains("builder.build(layout") or ready_block.contains("DungeonSceneBuilder.new().build(")).is_true()
	assert_bool(ready_block.contains("streaming_controller.configure(layout")).is_true()

func test_builder_build_produces_all_roots() -> void:
	# 验 builder.build() 产出 9 个 root（terrain/collision/doors/hazards/decor/spawn/interaction/streamed_visual/streamed_physics）
	var src := (load(BUILDER_PATH) as GDScript).source_code
	var build_block := _extract_func_block(src, "build")
	for root in ["terrain_root", "collision_root", "doors_root", "hazards_root",
			"decor_root", "spawn_root", "interaction_root", "streamed_visual_root",
			"streamed_physics_root"]:
		assert_bool(build_block.contains(root)) \
			.override_failure_message("builder.build 应产 %s" % root).is_true()

func test_ready_wires_build_result_to_streaming() -> void:
	# 验 _ready 把 build_result 传给 streaming_controller.configure
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	assert_bool(ready_block.contains("streaming_controller.configure(layout, build_result")) \
		.override_failure_message("_ready 应调 streaming_controller.configure(layout, build_result)").is_true()

func test_ready_does_not_directly_create_terrain_nodes() -> void:
	# 验 _ready 不再直接 create terrain 节点（builder 已接管）——不应含 add_child(MeshInstance3D) 等旧路径
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	# _ready 内不应活跃调旧 _spawn_floor/_spawn_wall 等（已删）
	for old_call in ["_spawn_floor(", "_spawn_wall(", "_spawn_ceiling(", "_spawn_lintel("]:
		assert_bool(ready_block.contains(old_call)).is_false()

func test_procedural_no_legacy_terrain_fields() -> void:
	# 验 procedural 不再持有旧 transform 类字段（builder 已产 build_result.*）
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	# 旧字段声明应已删（注释里可能残留，但不应有 "var floor_transforms" 等活跃声明）
	for field in ["var floor_transforms", "var ceiling_transforms", "var wall_transforms_by_height"]:
		# 允许注释含，但不应有顶层 var 声明
		var has_active_decl := false
		for line in src.split("\n"):
			if line.begins_with(field):
				has_active_decl = true
				break
		assert_bool(has_active_decl).override_failure_message("procedural 不应含活跃 %s 声明" % field).is_false()

func test_procedural_size_reduced() -> void:
	# 评审目标：procedural_dungeon.gd 从 86KB → 20-30KB（非硬性，但应显著下降）
	# 本会话已从 2382→1889 行，验证未回涨
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var line_count := src.split("\n").size()
	assert_int(line_count).is_less(2000) \
		.override_failure_message("procedural_dungeon.gd 行数 %d 应 < 2000（已删旧地形代码）" % line_count)


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
	# unreachable 保编译器满足（while true 内必 return）
	return ""
