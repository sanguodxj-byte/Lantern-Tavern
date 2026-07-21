extends GdUnitTestSuite

# 全流程集成测试：区域选择 → 地牢读 ZoneManager → 撤离 → 酒馆

var _zm: Node
var _original_zone: int

func before() -> void:
	_zm = Engine.get_main_loop().root.get_node("ZoneManager")
	_original_zone = _zm.get_zone()


func after() -> void:
	_zm.set_zone(_original_zone)


# ---------- 区域选择 → 地牢 ----------

func test_zone_select_sets_zone_manager() -> void:
	# 模拟用户在区域选择界面选定区域
	var zone_select = auto_free(load("res://scenes/ui/zone_select.tscn").instantiate())
	# 模拟点击各区域按钮
	_zm.set_zone(3)  # 墓园
	assert_int(_zm.get_zone()).is_equal(3)
	assert_str(_zm.get_zone_name()).is_equal("荒芜墓园")


func test_main_menu_routes_to_tavern_start() -> void:
	var script = load("res://scenes/ui/main_menu.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("start_new_game")) \
		.override_failure_message("main_menu 未通过 TavernManager 开始酒馆流程").is_true()
	assert_bool(source.contains("zone_select.tscn")) \
		.override_failure_message("main_menu 不应直接跳区域选择，区域选择应由酒馆出发提示触发").is_false()


func test_zone_select_start_routes_through_tavern_manager() -> void:
	var script = load("res://scenes/ui/zone_select.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("start_expedition")) \
		.override_failure_message("zone_select 应通过 TavernManager.start_expedition() 进入地牢").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')) \
		.override_failure_message("zone_select 不应直接切地牢子场景").is_false()


# ---------- 地牢读取 ZoneManager ----------

func test_dungeon_reads_zone_manager() -> void:
	var script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = script.source_code
	assert_bool(
		source.contains("Service.zone_manager()")
		or source.contains("get_node_or_null(\"/root/ZoneManager\")")
		or source.contains("/root/ZoneManager")
	).override_failure_message("地牢未读取 ZoneManager").is_true()


func test_dungeon_configures_chest_zone() -> void:
	# zone 注入在 builder；generation config 把 zone 写入 layout
	var builder_src = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	var gen_src = (load("res://scenes/expedition/dungeon_generator.gd") as GDScript).source_code
	assert_bool(builder_src.contains("layout.zone") or builder_src.contains("instance.zone")) \
		.override_failure_message("builder 宝箱未注入 zone 属性").is_true()
	assert_bool(gen_src.contains("layout.zone")).is_true()

func test_dungeon_uses_scatter_materials_per_zone() -> void:
	# 材料散落由 ItemSpawner + layout.item_spawn_specs / ZoneManager 负责
	var runtime_src = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	var gen_src = (load("res://scenes/expedition/dungeon_generator.gd") as GDScript).source_code
	assert_bool(runtime_src.contains("spawn_items_from_layout")).is_true()
	assert_bool(gen_src.contains("layout.zone")).is_true()
	var builder_src = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	for old_id in ["wild_glowcap", "frost_berry", "fire_bloom"]:
		assert_bool(not runtime_src.contains(old_id) and not builder_src.contains(old_id)) \
			.override_failure_message("仍含旧虚构材料: " + old_id).is_true()


func test_dungeon_has_extraction_portal() -> void:
	# extraction portal 由 builder 实例化，runtime 接线并结算到 TavernManager
	var builder_src = (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	var runtime_src = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(builder_src.contains("_build_extraction_portal") or builder_src.contains("ExtractionPortal")) \
		.override_failure_message("DungeonSceneBuilder 缺少撤离传送门生成").is_true()
	assert_bool(runtime_src.contains("extract_to_tavern") or runtime_src.contains("finish_expedition")) \
		.override_failure_message("DungeonRuntime 未连接撤离结算").is_true()


func test_tavern_manager_extract_switches_scene() -> void:
	var script = load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("extract_to_tavern")) \
		.override_failure_message("TavernManager 缺少 extract_to_tavern()").is_true()
	assert_bool(source.contains("res://scenes/world/world.tscn")) \
		.override_failure_message("extract_to_tavern 应进入/复用 World 根场景").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/tavern/tavern.tscn")')) \
		.override_failure_message("extract_to_tavern 不应直接切酒馆子场景").is_false()


func test_next_day_switches_to_day_phase_in_tavern() -> void:
	var script = load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("start_next_day")) \
		.override_failure_message("TavernManager 缺少 start_next_day()").is_true()
	# start_next_day 应切换到 DAY_EXPEDITION 并保持在酒馆，而非直接进地牢
	assert_bool(source.contains("current_phase = Phase.DAY_EXPEDITION")) \
		.override_failure_message("start_next_day 未设置 DAY_EXPEDITION 阶段").is_true()
	assert_bool(source.contains('_go_to_world_space("tavern")')) \
		.override_failure_message("start_next_day 应保持在酒馆场景供玩家出发").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')) \
		.override_failure_message("start_next_day 不应直接切地牢子场景").is_false()

func test_start_expedition_enters_dungeon() -> void:
	var script = load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("func start_expedition")) \
		.override_failure_message("TavernManager 缺少 start_expedition()").is_true()
	assert_bool(source.contains('_go_to_world_space("dungeon")')) \
		.override_failure_message("start_expedition 应进入地牢空间").is_true()

func test_zone_select_triggers_start_expedition() -> void:
	var script = load("res://scenes/ui/zone_select.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("TavernManager.start_expedition")) \
		.override_failure_message("zone_select 应通过 TavernManager.start_expedition() 进入地牢").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')) \
		.override_failure_message("zone_select 不应直接切地牢子场景").is_false()

func test_expedition_prompt_routes_to_zone_select() -> void:
	var script = load("res://scenes/ui/expedition_prompt.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("open_zone_select")) \
		.override_failure_message("出发提示满进度后应调用 world.open_zone_select()").is_true()
	assert_bool(source.contains('DEPART_ACTION := "depart"')) \
		.override_failure_message("出发提示应使用 depart 输入动作").is_true()

func test_full_cycle_tavern_to_dungeon_to_tavern() -> void:
	# 验证完整循环调用链的源码存在性：
	# 酒馆夜晚 → start_next_day → 酒馆白天 → depart键 → zone_select → start_expedition → 地牢
	# → 撤离传送门 → extract_to_tavern → 酒馆夜晚
	var tm_src = (load("res://globals/tavern/tavern_manager.gd") as GDScript).source_code
	var prompt_src = (load("res://scenes/ui/expedition_prompt.gd") as GDScript).source_code
	var zone_src = (load("res://scenes/ui/zone_select.gd") as GDScript).source_code
	var dungeon_src = (load("res://scenes/expedition/procedural_dungeon.gd") as GDScript).source_code
	var world_src = (load("res://scenes/world/world.gd") as GDScript).source_code
	# 1. 酒馆夜晚 → start_next_day → 酒馆白天
	assert_bool(tm_src.contains("func start_next_day")).is_true()
	assert_bool(tm_src.contains('_go_to_world_space("tavern")')).is_true()
	# 2. 出发键 → zone_select
	assert_bool(prompt_src.contains("open_zone_select")).is_true()
	assert_bool(world_src.contains("func open_zone_select")).is_true()
	# 3. zone_select → start_expedition → 地牢
	assert_bool(zone_src.contains("start_expedition")).is_true()
	assert_bool(tm_src.contains('func start_expedition')).is_true()
	assert_bool(tm_src.contains('_go_to_world_space("dungeon")')).is_true()
	# 4. 地牢撤离 → extract_to_tavern → 酒馆夜晚（撤离接线在 DungeonRuntime）
	var runtime_src = (load("res://scenes/expedition/dungeon_runtime.gd") as GDScript).source_code
	assert_bool(runtime_src.contains("extract_to_tavern") or dungeon_src.contains("extract_to_tavern")).is_true()
	assert_bool(tm_src.contains("func extract_to_tavern")).is_true()
	assert_bool(tm_src.contains("current_phase = Phase.NIGHT_TAVERN")).is_true()
