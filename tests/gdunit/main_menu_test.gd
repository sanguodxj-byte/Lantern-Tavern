extends GdUnitTestSuite

# Tests for MainMenu scene loading and navigation

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
const Service := preload("res://globals/core/service.gd")


func test_world_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/world/world.tscn")) \
		.override_failure_message("World scene not found") \
		.is_true()


func test_start_opens_tutorial_choice_and_routes_via_tavern_manager() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("TutorialChoicePanel")).is_true()
	# 出身选择接入后，start_new_game 需传入 origin_id 参数
	assert_bool(source.contains("TavernManager.start_new_game(true, _pending_origin_id)")).is_true()
	assert_bool(source.contains("TavernManager.start_new_game(false, _pending_origin_id)")).is_true()
	assert_bool(source.contains("continue_in_tavern")).is_true()
	assert_bool(source.contains("res://scenes/world/world.tscn")).is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/tavern/tavern.tscn")')).is_false()


func test_gallery_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/model_viewer.tscn")).is_true()


func test_settings_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/settings_menu.tscn")).is_true()


func test_settings_button_routes_to_settings_menu() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	assert_str(script.source_code).contains("UI_ROUTES.SETTINGS")
	assert_str(script.source_code).contains("request_navigation(UI_ROUTES.SETTINGS)")


func test_main_menu_has_no_keyboard_shortcuts_or_shortcut_labels() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _input")).is_false()
	assert_bool(source.contains("KEY_S")).is_false()
	assert_bool(source.contains("[S]tart Game")).is_false()
	assert_bool(source.contains("Settin[g]s")).is_false()
	assert_bool(source.contains("E[x]it Game")).is_false()


func test_title_inside_panel_and_menu_is_compact_bottom_right() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	# 标题已移入右侧面板（与按钮同轴，形成单一视觉列）
	var title: Label = menu.get_node("SidePanel/MenuVBox/Title")
	var subtitle: Label = menu.get_node("SidePanel/MenuVBox/Subtitle")
	var side_panel: Control = menu.get_node("SidePanel")
	var start_btn: Button = menu.get_node("SidePanel/MenuVBox/StartBtn")
	assert_str(title.get_parent().name).is_equal("MenuVBox")
	assert_str(subtitle.get_parent().name).is_equal("MenuVBox")
	assert_float(title.custom_minimum_size.y).is_greater_equal(90.0)
	assert_int(title.get_theme_font_size("font_size")).is_greater_equal(40)
	assert_float(side_panel.anchor_left).is_equal(1.0)
	assert_float(side_panel.anchor_top).is_equal(1.0)
	assert_bool(side_panel.size.x >= 400.0 and side_panel.size.x <= 440.0).is_true()
	assert_int(start_btn.get_theme_font_size("font_size")).is_greater_equal(30)
	assert_bool(start_btn.custom_minimum_size.y >= 58.0 and start_btn.custom_minimum_size.y <= 62.0).is_true()
	assert_str(start_btn.text).is_not_empty()
	assert_bool(not start_btn.text.contains("[S]")).is_true()
	remove_child(menu)
	menu.free()


func test_main_menu_compacts_side_panel_at_720p() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	menu.size = Vector2(1280, 720)
	menu._apply_responsive_layout()
	var side_panel := menu.get_node("SidePanel") as Control
	var menu_box := menu.get_node("SidePanel/MenuVBox") as VBoxContainer
	assert_float(side_panel.size.y).is_equal(648.0)
	assert_float(menu_box.offset_top).is_equal(20.0)
	assert_bool(menu.get_node("SidePanel/MenuVBox/MenuHint").visible).is_false()
	assert_bool(menu.get_node("SidePanel/MenuVBox/MenuHeader").visible).is_false()
	remove_child(menu)
	menu.free()


func test_main_menu_has_polished_visual_hierarchy_and_intro_motion() -> void:
	var scene_source := FileAccess.get_file_as_string(MAIN_MENU_PATH)
	var script_source := (load("res://scenes/ui/main_menu.gd") as GDScript).source_code
	for required_node in ["Subtitle", "MenuHeader", "MenuHint", "PanelAccent", "VersionLabel"]:
		assert_str(scene_source).contains('name="%s"' % required_node)
	assert_str(scene_source).contains("StyleBoxPrimaryNormal")
	assert_str(scene_source).contains("StyleBoxFocus")
	assert_str(script_source).contains("func _play_intro_motion()")
	assert_str(script_source).contains("create_tween()")


func test_main_menu_visual_style_uses_hard_edged_pixel_styleboxes() -> void:
	var scene_source := FileAccess.get_file_as_string(MAIN_MENU_PATH)
	assert_str(scene_source).contains("StyleBoxMainMenuPanel")
	assert_str(scene_source).contains("StyleBoxPrimaryNormal")
	assert_str(scene_source).contains("corner_detail = 1")
	assert_str(scene_source).contains("anti_aliasing = false")
	assert_bool(scene_source.contains("corner_radius_top_left")).is_false()
	assert_bool(scene_source.contains("corner_radius_top_right")).is_false()

# ---------- 继续流程（架构审查 0804 P0-1） ----------

## 点击"继续"必须打开存档读档面板（LOAD 模式），而不是直接进酒馆。
func test_continue_opens_load_panel_in_load_mode() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	await await_idle_frame()
	menu._on_continue_pressed()
	assert_object(menu._save_load_panel).is_not_null()
	assert_bool(menu._save_load_panel.visible).is_true()
	assert_int(menu._save_load_panel.mode).is_equal(menu._save_load_panel.Mode.LOAD)
	remove_child(menu)
	menu.free()


## 非 load 动作（save/delete）不得触发进入酒馆的流程。
func test_save_slot_action_ignores_non_load() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	await await_idle_frame()
	menu._show_save_load_panel(true)
	var panel: Control = menu._save_load_panel
	assert_object(panel).is_not_null()
	panel.visible = true
	menu._on_save_slot_action("save", 0)
	assert_bool(panel.visible).is_true()
	remove_child(menu)
	menu.free()


## 面板返回键隐藏面板，不切场景。
func test_save_load_back_hides_panel() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	await await_idle_frame()
	menu._show_save_load_panel(true)
	assert_bool(menu._save_load_panel.visible).is_true()
	menu._on_save_load_back()
	assert_bool(menu._save_load_panel.visible).is_false()
	remove_child(menu)
	menu.free()


## 继续按钮无存档时禁用（保持既有行为）。
func test_continue_disabled_without_any_save() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	await await_idle_frame()
	var continue_btn: Button = menu.get_node("SidePanel/MenuVBox/ContinueBtn")
	# 测试环境无存档槽位（真实 autoload SaveManager），按钮应禁用。
	assert_bool(continue_btn.disabled).is_true()
	remove_child(menu)
	menu.free()

# ---------- E2（1327 审查）：单一本地化引导 ----------

## 禁止模式守卫：主菜单不得再 new 临时 LocalizationManager 兜底加载。
func test_no_fallback_localization_loader_in_source() -> void:
	var source := (load("res://scenes/ui/main_menu.gd") as GDScript).source_code
	assert_bool(source.contains("LOCALIZATION_MANAGER_SCRIPT.new()")).is_false()
	assert_bool(source.contains("_ensure_translations_registered")).is_false()
	assert_bool(source.contains("fallback_translations_registered")).is_false()


## 主菜单订阅 LocalizationManager.initialized 信号刷新文本（单一引导）。
func test_menu_subscribes_localization_initialized_signal() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	await await_idle_frame()
	var lm: Node = Service.localization_manager()
	assert_object(lm).is_not_null()
	if lm != null and lm.has_signal("initialized"):
		assert_bool(lm.initialized.is_connected(menu._on_localization_initialized)).is_true()
	remove_child(menu)
	menu.free()
