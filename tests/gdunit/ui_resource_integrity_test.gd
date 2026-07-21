extends GdUnitTestSuite

# Tests for UI resource files and scene integrity

func test_lantern_theme_exists() -> void:
	var path = "res://scenes/ui/lantern_theme.tres"
	assert_bool(ResourceLoader.exists(path)).is_true()


func test_lantern_theme_uses_zh_pixel_font_and_larger_default_size() -> void:
	var theme := load("res://scenes/ui/lantern_theme.tres") as Theme
	assert_object(theme).is_not_null()
	assert_int(theme.get_default_font_size()).is_greater_equal(24)
	var font := theme.get_default_font() as FontFile
	assert_object(font).is_not_null()
	assert_str(font.resource_path).contains("ark-pixel-12px-proportional-zh_cn.ttf")


func test_project_uses_lantern_theme_as_default_gui_theme() -> void:
	var custom_theme = ProjectSettings.get_setting("gui/theme/custom", "")
	if typeof(custom_theme) == TYPE_STRING:
		assert_str(custom_theme).is_equal("res://scenes/ui/lantern_theme.tres")
	else:
		assert_str(custom_theme.resource_path).is_equal("res://scenes/ui/lantern_theme.tres")


func test_main_menu_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/main_menu.tscn")).is_true()


func test_ui_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/ui.tscn")).is_true()


func test_pause_menu_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/pause_menu.tscn")).is_true()


func test_character_panel_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_panel.tscn")).is_true()


func test_model_viewer_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/model_viewer.tscn")).is_true()


func test_settings_menu_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/settings_menu.tscn")).is_true()


func test_tavern_ui_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/tavern_ui.tscn")).is_true()


func test_stat_indicator_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/stat_indicator.tscn")).is_true()


func test_key_texture_scene_removed() -> void:
	# 彩色钥匙 UI 已废弃，key_texture 场景不应再存在
	assert_bool(ResourceLoader.exists("res://scenes/ui/key_texture.tscn")).is_false()


func test_cursor_texture_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/textures/cursor.png")).is_true()


func test_icon_heart_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/textures/icons/icon-heart.png")).is_true()


func test_icon_weapon_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/textures/icons/icon-weapon.png")).is_true()


func test_icon_shield_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/textures/icons/icon-shield.png")).is_true()


func test_tick_texture_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/textures/tick.png")).is_true()
