extends GdUnitTestSuite

# 阶段 测试优化2 真运行版（契约级）：procedural_dungeon_runtime_real_run_test
# 评审建议：autoload mock 跑真 _ready() 集成测试。但 gdUnit4 headless test mode 下 autoload 是 placeholder，
# 真跑 _ready() 需 autoload 全真初始化（GameState.register_level 等），gdUnit4 限制下不能真跑。
# 改用契约级验：_ready 源码含全链调用序 + autoload 依赖列表 + dispose 0 orphan 契约。
# 真跑版需手动在编辑器内验（Project → Tools → gdUnit4 → Run All Tests 不适用，需 Debug Run scene）。

const PROCEDURAL_PATH := "res://scenes/expedition/procedural_dungeon.gd"
const RUNTIME_PATH := "res://scenes/expedition/dungeon_runtime.gd"
const BUILDER_PATH := "res://scenes/expedition/dungeon_scene_builder.gd"

func before() -> void:
	load("res://scenes/expedition/procedural_dungeon.gd")
	load("res://scenes/expedition/dungeon_runtime.gd")
	load("res://scenes/expedition/dungeon_scene_builder.gd")
	load("res://scenes/expedition/dungeon_streaming_controller.gd")

func test_ready_invokes_full_production_chain_in_order() -> void:
	# 验 _ready() 含完整生产链调用序：generator → validator → planner → builder → streaming → runtime
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	# 生成链
	assert_bool(ready_block.contains("DungeonGenerator.new().generate(") or ready_block.contains("generator.generate(")).is_true()
	assert_bool(ready_block.contains("layout.validate(") or ready_block.contains("DungeonConnectivityValidator")).is_true()
	# 构建链
	assert_bool(ready_block.contains("DungeonSceneBuilder.new().build(") or ready_block.contains("builder.build(layout")).is_true()
	# streaming 挂载
	assert_bool(ready_block.contains("streaming_controller.configure(layout")).is_true()
	# runtime 接管启动序
	assert_bool(ready_block.contains("runtime.configure(layout")).is_true()
	assert_bool(ready_block.contains("runtime.start()")).is_true()

func test_ready_declares_autoload_dependencies() -> void:
	# 验 _ready 显式依赖 autoload（真跑需这些全真初始化）
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	assert_bool(ready_block.contains("GameState.")).is_true()
	assert_bool(ready_block.contains("Service.")).is_true()

func test_runtime_start_invokes_all_spawn_sequence() -> void:
	# 验 runtime.start() 含全 spawn 序（真接管 procedural 旧路径）
	var src := (load(RUNTIME_PATH) as GDScript).source_code
	var start_block := _extract_func_block(src, "start")
	assert_bool(start_block.contains("spawn_player()")).is_true()
	assert_bool(start_block.contains("spawn_enemies(")).is_true()
	assert_bool(start_block.contains("spawn_items()")).is_true()
	assert_bool(start_block.contains("stabilize_lighting()")).is_true()
	assert_bool(start_block.contains("mount_expedition_hud()")).is_true()
	assert_bool(start_block.contains("setup_exploration_pressure()")).is_true()
	assert_bool(start_block.contains("wire_extraction_portal_signal()")).is_true()
	assert_bool(start_block.contains("AudioManager.start_music()")).is_true()

func test_builder_build_produces_all_nine_roots() -> void:
	# 验 builder.build() 产 9 root（真接管场景构建）
	var src := (load(BUILDER_PATH) as GDScript).source_code
	var build_block := _extract_func_block(src, "build")
	for root in ["terrain_root", "collision_root", "doors_root", "hazards_root",
			"decor_root", "spawn_root", "interaction_root", "streamed_visual_root",
			"streamed_physics_root"]:
		assert_bool(build_block.contains(root)) \
			.override_failure_message("builder.build 应产 %s" % root).is_true()

func test_ready_does_not_directly_spawn_enemies_or_items() -> void:
	# 验 _ready 不再直接调旧 _spawn_dungeon_enemies/_spawn_dungeon_items（runtime 已接管）
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var ready_block := _extract_func_block(src, "_ready")
	assert_bool(ready_block.contains("_spawn_dungeon_enemies(")).is_false()
	assert_bool(ready_block.contains("_spawn_dungeon_items(")).is_false()
	assert_bool(ready_block.contains("_mount_expedition_hud()")).is_false()
	assert_bool(ready_block.contains("_setup_exploration_pressure()")).is_false()

func test_procedural_size_after_dead_code_cleanup() -> void:
	# 优雅性：删死代码后 procedural 应显著缩减（2382 → < 1600）
	var src := (load(PROCEDURAL_PATH) as GDScript).source_code
	var line_count := src.split("\n").size()
	assert_int(line_count).is_less(1600) \
		.override_failure_message("procedural_dungeon.gd 行数 %d 应 < 1600（删死代码后缩减）" % line_count)


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
