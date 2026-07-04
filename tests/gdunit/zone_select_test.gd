extends GdUnitTestSuite
## 区域选择系统 (ZoneManager) + 对接测试。
## 验证四区元数据、散落材料池、chest/dungeon 接入、main_menu 跳转。

const ZM := preload("res://globals/zone_manager.gd")
var zm: Node

func before_test() -> void:
	zm = Engine.get_main_loop().root.get_node("ZoneManager")
	zm.selected_zone = 0

# ---------- ZoneManager 元数据 ----------

func test_zone_manager_autoload_exists() -> void:
	assert_object(zm).is_not_null()

func test_four_zones_defined() -> void:
	assert_int(ZM.ZONE_META.size()).is_equal(4)
	assert_int(zm.all_zones().size()).is_equal(4)

func test_zone_meta_has_required_fields() -> void:
	for zone_id in [0, 1, 2, 3]:
		var meta: Dictionary = ZM.ZONE_META[zone_id]
		assert_bool(meta.has("name") and meta.name.length() > 0).is_true()
		assert_bool(meta.has("desc") and meta.desc.length() > 0).is_true()
		assert_bool(meta.has("difficulty") and meta.difficulty >= 1).is_true()
		assert_bool(meta.has("color")).is_true()

func test_zone_names_are_chinese() -> void:
	for zone_id in [0, 1, 2, 3]:
		var name: String = zm.get_zone_name(zone_id)
		var has_cjk: bool = false
		for ch in name:
			if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
				has_cjk = true
				break
		assert_bool(has_cjk).is_true()

func test_difficulty_progression() -> void:
	# 难度递增：森林1 < 洞窟2 < 墓园3 < 火山4
	assert_int(zm.get_zone_difficulty(0)).is_equal(1)
	assert_int(zm.get_zone_difficulty(1)).is_equal(2)
	assert_int(zm.get_zone_difficulty(2)).is_equal(3)
	assert_int(zm.get_zone_difficulty(3)).is_equal(4)

# ---------- 散落材料池 ----------

func test_scatter_materials_all_valid() -> void:
	for zone_id in [0, 1, 2, 3]:
		var pool: Dictionary = zm.get_scatter_materials(zone_id)
		assert_bool(not pool.is_empty()).is_true()
		for mat_id in pool:
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("区域 %d 散落池含非法材料: %s" % [zone_id, mat_id]) \
				.is_true()

func test_scatter_materials_no_old_fictional_ids() -> void:
	var old_ids: Array = ["wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", "honeycomb", "sweet_grass", "bitter_root", "mountain_barley"]
	for zone_id in [0, 1, 2, 3]:
		var pool: Dictionary = zm.get_scatter_materials(zone_id)
		for mat_id in pool:
			assert_bool(not old_ids.has(mat_id)) \
				.override_failure_message("区域 %d 散落池含旧虚构材料: %s" % [zone_id, mat_id]) \
				.is_true()

func test_scatter_materials_match_zone_theme() -> void:
	# 火山区散落池应含 firegrape/lava_malt，不含 blackberry
	var volcano_pool: Dictionary = zm.get_scatter_materials(3)
	assert_bool(volcano_pool.has("firegrape")).is_true()
	assert_bool(volcano_pool.has("lava_malt")).is_true()
	assert_bool(not volcano_pool.has("blackberry")).is_true()
	# 森林区应含 blackberry，不含 firegrape
	var forest_pool: Dictionary = zm.get_scatter_materials(0)
	assert_bool(forest_pool.has("blackberry")).is_true()
	assert_bool(not forest_pool.has("firegrape")).is_true()

# ---------- set/get zone ----------

func test_set_zone_clamps_value() -> void:
	zm.set_zone(-1)
	assert_int(zm.get_zone()).is_equal(0)
	zm.set_zone(99)
	assert_int(zm.get_zone()).is_equal(3)

func test_set_zone_persists() -> void:
	zm.set_zone(2)
	assert_int(zm.get_zone()).is_equal(2)
	assert_str(zm.get_zone_name()).is_equal("荒芜墓园")

# ---------- main_menu 接入 ----------

func test_main_menu_routes_to_tavern() -> void:
	var script: Resource = load("res://scenes/ui/main_menu.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find('change_scene_to_file("res://scenes/tavern/tavern.tscn")') != -1) \
		.override_failure_message("main_menu 未跳转酒馆场景").is_true()
	assert_bool(source.find('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")') == -1) \
		.override_failure_message("main_menu 仍直接跳地牢").is_true()

# ---------- procedural_dungeon 接入 ----------

func test_procedural_dungeon_reads_zone_manager() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("/root/ZoneManager") != -1) \
		.override_failure_message("procedural_dungeon 未读取 ZoneManager").is_true()
	assert_bool(source.find("zm.get_zone()") != -1 or source.find("get_zone()") != -1) \
		.override_failure_message("procedural_dungeon 未调用 get_zone()").is_true()
	assert_bool(source.find("get_scatter_materials") != -1) \
		.override_failure_message("procedural_dungeon 未用区域散落材料池").is_true()

func test_procedural_dungeon_materials_config_no_old_fictional() -> void:
	var script: Resource = load("res://scenes/expedition/procedural_dungeon.gd")
	var source: String = (script as GDScript).source_code
	for old_id in ["wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", "honeycomb", "sweet_grass", "bitter_root", "mountain_barley"]:
		assert_bool(source.find(old_id) == -1) \
			.override_failure_message("procedural_dungeon 仍含旧虚构材料: %s" % old_id) \
			.is_true()

# ---------- zone_select 场景 ----------

func test_zone_select_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/zone_select.tscn")).is_true()

func test_zone_select_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/zone_select.gd")).is_true()

func test_zone_select_no_invalid_button_alignment_property() -> void:
	# 回归：Button 在 Godot 4 没有 text_vertical_alignment 属性，
	# 设置会触发 "Invalid assignment of property or key" 运行时报错。
	var script: Resource = load("res://scenes/ui/zone_select.gd") as GDScript
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("text_vertical_alignment") == -1) \
		.override_failure_message("zone_select.gd 仍对 Button 设置不存在的 text_vertical_alignment 属性").is_true()
