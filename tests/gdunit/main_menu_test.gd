extends GdUnitTestSuite

# Tests for MainMenu scene loading and navigation

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"


func test_world_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/world/world.tscn")) \
		.override_failure_message("World scene not found") \
		.is_true()


func test_start_opens_tutorial_choice_and_routes_via_tavern_manager() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("TutorialChoicePanel")).is_true()
	assert_bool(source.contains("TavernManager.start_new_game(true)")).is_true()
	assert_bool(source.contains("TavernManager.start_new_game(false)")).is_true()
	assert_bool(source.contains("continue_in_tavern")).is_true()
	assert_bool(source.contains("res://scenes/world/world.tscn")).is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/tavern/tavern.tscn")')).is_false()


func test_gallery_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/model_viewer.tscn")).is_true()


func test_settings_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/settings_menu.tscn")).is_true()


func test_settings_button_routes_to_settings_menu() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	assert_bool(script.source_code.contains('change_scene_to_file("res://scenes/ui/settings_menu.tscn")')).is_true()


func test_main_menu_has_no_keyboard_shortcuts_or_shortcut_labels() -> void:
	var script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _input")).is_false()
	assert_bool(source.contains("KEY_S")).is_false()
	assert_bool(source.contains("[S]tart Game")).is_false()
	assert_bool(source.contains("Settin[g]s")).is_false()
	assert_bool(source.contains("E[x]it Game")).is_false()


func test_title_centered_and_menu_is_compact_bottom_right() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	var title: Label = menu.get_node("Title")
	var side_panel: Control = menu.get_node("SidePanel")
	var start_btn: Button = menu.get_node("SidePanel/MenuVBox/StartBtn")
	assert_float(title.anchor_left).is_equal(0.5)
	assert_float(title.anchor_right).is_equal(0.5)
	assert_int(title.get_theme_font_size("font_size")).is_greater_equal(80)
	assert_float(side_panel.anchor_left).is_equal(1.0)
	assert_float(side_panel.anchor_top).is_equal(1.0)
	assert_bool(side_panel.size.x >= 400.0 and side_panel.size.x <= 440.0).is_true()
	assert_int(start_btn.get_theme_font_size("font_size")).is_greater_equal(30)
	assert_bool(start_btn.custom_minimum_size.y >= 58.0 and start_btn.custom_minimum_size.y <= 62.0).is_true()
	assert_str(start_btn.text).is_not_empty()
	assert_bool(not start_btn.text.contains("[S]")).is_true()
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
