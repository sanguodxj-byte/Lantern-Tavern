extends GdUnitTestSuite

# Tests for UI resource files and scene integrity

func test_lantern_theme_exists() -> void:
	var path = "res://scenes/ui/lantern_theme.tres"
	assert_bool(ResourceLoader.exists(path)).is_true()


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


func test_tavern_ui_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/tavern_ui.tscn")).is_true()


func test_stat_indicator_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/stat_indicator.tscn")).is_true()


func test_key_texture_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/key_texture.tscn")).is_true()


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
