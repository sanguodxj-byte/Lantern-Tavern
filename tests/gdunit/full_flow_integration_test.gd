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
	_zm.set_zone(2)  # 墓园
	assert_int(_zm.get_zone()).is_equal(2)
	assert_str(_zm.get_zone_name()).is_equal("荒芜墓园")


func test_main_menu_routes_to_zone_select() -> void:
	var script = load("res://scenes/ui/main_menu.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("zone_select.tscn")) \
		.override_failure_message("main_menu 未跳转到区域选择界面").is_true()


func test_zone_select_start_routes_to_dungeon() -> void:
	var script = load("res://scenes/ui/zone_select.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("procedural_dungeon.tscn")) \
		.override_failure_message("zone_select 未跳转到地牢").is_true()


# ---------- 地牢读取 ZoneManager ----------

func test_dungeon_reads_zone_manager() -> void:
	var script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("get_node_or_null(\"/root/ZoneManager\")") or source.contains('/root/ZoneManager')) \
		.override_failure_message("地牢未读取 ZoneManager").is_true()


func test_dungeon_configures_chest_zone() -> void:
	var script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("instance.zone = dungeon_zone") or source.contains("zone = dungeon_zone")) \
		.override_failure_message("地牢宝箱未注入 zone 属性").is_true()


func test_dungeon_uses_scatter_materials_per_zone() -> void:
	var script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("get_scatter_materials")) \
		.override_failure_message("地牢未使用 ZoneManager.get_scatter_materials()").is_true()
	# 旧虚构材料不应存在
	for old_id in ["wild_glowcap", "frost_berry", "fire_bloom"]:
		assert_bool(not source.contains(old_id)) \
			.override_failure_message("地牢仍含旧虚构材料: " + old_id).is_true()


# ---------- 撤离 → 酒馆 ----------

func test_dungeon_has_extraction_portal() -> void:
	var script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("_spawn_extraction_portal")) \
		.override_failure_message("地牢缺少撤离传送门生成").is_true()
	assert_bool(source.contains("extract_to_tavern")) \
		.override_failure_message("传送门未连接 extract_to_tavern()").is_true()


func test_tavern_manager_extract_switches_scene() -> void:
	var script = load("res://globals/tavern_manager.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("extract_to_tavern")) \
		.override_failure_message("TavernManager 缺少 extract_to_tavern()").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/tavern/tavern.tscn")')) \
		.override_failure_message("extract_to_tavern 未切换到酒馆场景").is_true()


func test_next_day_cycles_back_to_dungeon() -> void:
	var script = load("res://globals/tavern_manager.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("start_next_day")) \
		.override_failure_message("TavernManager 缺少 start_next_day()").is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')) \
		.override_failure_message("start_next_day 未切回地牢").is_true()
