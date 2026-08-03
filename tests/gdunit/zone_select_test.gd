extends GdUnitTestSuite
## 区域选择系统 (ZoneManager) + 对接测试。
## 验证六区元数据、散落材料池、chest/dungeon 接入、main_menu 跳转。

const ZM := preload("res://globals/dungeon/zone_manager.gd")
const ZONE_MAP_ASSET := "res://assets/textures/ui/expedition_zone_map.png"
var zm: Node

func before_test() -> void:
	zm = Engine.get_main_loop().root.get_node("ZoneManager")
	zm.selected_zone = 0

# ---------- ZoneManager 元数据 ----------

func test_zone_manager_autoload_exists() -> void:
	assert_object(zm).is_not_null()

func test_six_zones_defined() -> void:
	assert_int(ZM.ZONE_META.size()).is_equal(6)
	assert_int(zm.all_zones().size()).is_equal(6)

func test_zone_meta_has_required_fields() -> void:
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var meta: Dictionary = ZM.ZONE_META[zone_id]
		assert_bool(meta.has("name") and meta.name.length() > 0).is_true()
		assert_bool(meta.has("desc") and meta.desc.length() > 0).is_true()
		assert_bool(meta.has("difficulty") and meta.difficulty >= 1).is_true()
		assert_bool(meta.has("color")).is_true()

func test_zone_names_are_chinese() -> void:
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var name: String = zm.get_zone_name(zone_id)
		var has_cjk: bool = false
		for ch in name:
			if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
				has_cjk = true
				break
		assert_bool(has_cjk).is_true()

func test_difficulty_progression() -> void:
	# 难度递增：地牢1 < 森林2 < 洞窟3 < 墓园4 < 火山5 < 遗迹6
	assert_int(zm.get_zone_difficulty(0)).is_equal(1)
	assert_int(zm.get_zone_difficulty(1)).is_equal(2)
	assert_int(zm.get_zone_difficulty(2)).is_equal(3)
	assert_int(zm.get_zone_difficulty(3)).is_equal(4)
	assert_int(zm.get_zone_difficulty(4)).is_equal(5)
	assert_int(zm.get_zone_difficulty(5)).is_equal(6)

# ---------- 散落材料池 ----------

func test_scatter_materials_all_valid() -> void:
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var pool: Dictionary = zm.get_scatter_materials(zone_id)
		assert_bool(not pool.is_empty()).is_true()
		for mat_id in pool:
			assert_bool(BrewingData.MATERIALS_DB.has(mat_id)) \
				.override_failure_message("区域 %d 散落池含非法材料: %s" % [zone_id, mat_id]) \
				.is_true()

func test_scatter_materials_no_old_fictional_ids() -> void:
	var old_ids: Array = ["wild_glowcap", "frost_berry", "fire_bloom", "cave_lichen", "honeycomb", "sweet_grass", "bitter_root", "mountain_barley"]
	for zone_id in [0, 1, 2, 3, 4, 5]:
		var pool: Dictionary = zm.get_scatter_materials(zone_id)
		for mat_id in pool:
			assert_bool(not old_ids.has(mat_id)) \
				.override_failure_message("区域 %d 散落池含旧虚构材料: %s" % [zone_id, mat_id]) \
				.is_true()

func test_scatter_materials_match_zone_theme() -> void:
	# 火山区散落池应含 firegrape/lava_malt，不含 blackberry
	var volcano_pool: Dictionary = zm.get_scatter_materials(4)
	assert_bool(volcano_pool.has("firegrape")).is_true()
	assert_bool(volcano_pool.has("lava_malt")).is_true()
	assert_bool(not volcano_pool.has("blackberry")).is_true()
	# 森林区应含 blackberry，不含 firegrape
	var forest_pool: Dictionary = zm.get_scatter_materials(1)
	assert_bool(forest_pool.has("blackberry")).is_true()
	assert_bool(not forest_pool.has("firegrape")).is_true()

# ---------- set/get zone ----------

func test_set_zone_clamps_value() -> void:
	zm.set_zone(-1)
	assert_int(zm.get_zone()).is_equal(0)
	zm.set_zone(99)
	assert_int(zm.get_zone()).is_equal(5)

func test_set_zone_persists() -> void:
	zm.set_zone(3)
	assert_int(zm.get_zone()).is_equal(3)
	assert_str(zm.get_zone_name()).is_equal("荒芜墓园")

# ---------- main_menu 接入 ----------

func test_main_menu_routes_to_world_root() -> void:
	var script: Resource = load("res://scenes/ui/main_menu.gd")
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("start_new_game") != -1).is_true()
	assert_bool(source.find("res://scenes/world/world.tscn") != -1) \
		.override_failure_message("main_menu 兜底入口应进入 World 根场景").is_true()
	assert_bool(source.find('change_scene_to_file("res://scenes/tavern/tavern.tscn")') == -1) \
		.override_failure_message("main_menu 不应直接切酒馆场景").is_true()
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

func test_zone_select_uses_pixel_map_instead_of_text_list() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/zone_select.tscn")
	assert_str(scene_source).contains("ZoneMapTexture") \
		.override_failure_message("区域选择场景必须包含像素区域地图纹理")
	assert_str(scene_source).contains("ZoneHotspots") \
		.override_failure_message("区域选择场景必须包含地图选区交互层")
	assert_str(scene_source).contains("ZoneDetails") \
		.override_failure_message("区域选择场景必须保留当前选区详情")
	assert_bool(not scene_source.contains("ZoneList")) \
		.override_failure_message("区域选择不应继续使用纵向文字列表").is_true()
	assert_bool(not scene_source.contains("ScrollContainer")) \
		.override_failure_message("区域地图不应包裹在旧文字列表滚动容器中").is_true()
	assert_str(scene_source).contains(ZONE_MAP_ASSET) \
		.override_failure_message("区域选择场景必须引用正式像素地图素材")

func test_zone_map_asset_has_transparent_cutout_and_pixel_scale() -> void:
	var absolute_path := ProjectSettings.globalize_path(ZONE_MAP_ASSET)
	assert_bool(FileAccess.file_exists(absolute_path)) \
		.override_failure_message("缺少正式区域地图素材: %s" % ZONE_MAP_ASSET).is_true()
	if not FileAccess.file_exists(absolute_path):
		return
	var image := Image.load_from_file(absolute_path)
	assert_object(image).is_not_null()
	if image == null:
		return
	assert_int(image.get_width()).is_equal(768)
	assert_int(image.get_height()).is_equal(768)
	for point in [
		Vector2i(0, 0),
		Vector2i(image.get_width() - 1, 0),
		Vector2i(0, image.get_height() - 1),
		Vector2i(image.get_width() - 1, image.get_height() - 1),
	]:
		assert_float(image.get_pixelv(point).a) \
			.override_failure_message("去绿底后的区域地图四角必须透明: %s" % point) \
			.is_less(0.05)

func test_zone_select_no_invalid_button_alignment_property() -> void:
	# 回归：Button 在 Godot 4 没有 text_vertical_alignment 属性，
	# 设置会触发 "Invalid assignment of property or key" 运行时报错。
	var script: Resource = load("res://scenes/ui/zone_select.gd") as GDScript
	var source: String = (script as GDScript).source_code
	assert_bool(source.find("text_vertical_alignment") == -1) \
		.override_failure_message("zone_select.gd 仍对 Button 设置不存在的 text_vertical_alignment 属性").is_true()

func test_zone_select_adds_to_character_panel_group() -> void:
	var zone_select = auto_free(load("res://scenes/ui/zone_select.tscn").instantiate())
	var root = Engine.get_main_loop().root
	root.add_child(zone_select)
	
	assert_bool(zone_select.is_in_group("character_panel"))\
		.override_failure_message("zone_select 节点应该被加入 character_panel 组，以防点击时被 player.gd 异常捕获鼠标")\
		.is_true()
		
	root.remove_child(zone_select)

func test_zone_select_builds_six_map_hotspots_and_details() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var zone_select := load("res://scenes/ui/zone_select.tscn").instantiate() as Control
	host.add_child(zone_select)
	await await_idle_frame()

	var hotspots := zone_select.get_node("%ZoneHotspots") as Control
	assert_int(hotspots.get_child_count()).is_equal(6)
	for zone_id in range(6):
		var hotspot := hotspots.get_node_or_null("ZoneHotspot%d" % zone_id) as Button
		assert_object(hotspot).is_not_null()
		assert_int(int(hotspot.get_meta("zone_id", -1))).is_equal(zone_id)
	assert_object(zone_select.get_node_or_null("%ZoneMapTexture")).is_not_null()
	assert_object(zone_select.get_node_or_null("%ZoneDetails")).is_not_null()
	assert_bool((zone_select.get_node("%StartBtn") as Button).disabled).is_true()
	host.queue_free()

func test_zone_select_preview_updates_details_without_committing_zone() -> void:
	var previous_zone: int = int(zm.get_zone())
	zm.set_zone(0)
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var zone_select := load("res://scenes/ui/zone_select.tscn").instantiate() as Control
	host.add_child(zone_select)
	await await_idle_frame()

	var hotspot := zone_select.get_node("%ZoneHotspots/ZoneHotspot3") as Button
	hotspot.emit_signal("pressed")
	await await_idle_frame()

	assert_int(zone_select.get_selected_zone()).is_equal(3)
	assert_int(zm.get_zone()).is_equal(0)
	assert_str((zone_select.get_node("%ZoneName") as Label).text).is_equal(zm.get_zone_name(3))
	assert_str((zone_select.get_node("%ZoneDescription") as Label).text).is_equal(zm.get_zone_desc(3))
	assert_bool((zone_select.get_node("%StartBtn") as Button).disabled).is_false()
	host.queue_free()
	zm.set_zone(previous_zone)

func test_capture_zone_select_preview_if_renderer_available() -> void:
	# headless CI cannot provide a rendered viewport; the runtime contract tests
	# above still cover the scene tree and state changes in that mode.
	if DisplayServer.get_name() == "headless":
		return
	var original_window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var zone_select := load("res://scenes/ui/zone_select.tscn").instantiate() as Control
	zone_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(zone_select)
	for _index in range(12):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	assert_object(image).is_not_null()
	if image != null and not image.is_empty():
		var output_dir := "res://reports/ui_preview"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		assert_int(image.save_png("%s/zone_select_1920x1080_zh.png" % output_dir)).is_equal(OK)
	host.queue_free()
	DisplayServer.window_set_size(original_window_size)
