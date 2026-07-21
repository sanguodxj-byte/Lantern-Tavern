extends GdUnitTestSuite

const SETTINGS_PATH := "res://scenes/ui/settings_menu.tscn"

var _original_master_db: float
var _original_locale: String

func before() -> void:
	_original_master_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_original_locale = TranslationServer.get_locale()

func after() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _original_master_db)
	TranslationServer.set_locale(_original_locale)

func test_settings_menu_scene_loads() -> void:
	var scene: PackedScene = load(SETTINGS_PATH)
	assert_object(scene).is_not_null()
	var menu: SettingsMenu = scene.instantiate()
	assert_object(menu).is_not_null()
	menu.free()

func test_settings_menu_has_expected_controls() -> void:
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu)
	assert_object(menu.get_node_or_null("%MasterVolumeSlider")).is_not_null()
	assert_object(menu.get_node_or_null("%MasterVolumeValue")).is_not_null()
	assert_object(menu.get_node_or_null("%FullscreenCheck")).is_not_null()
	assert_object(menu.get_node_or_null("%LanguageOption")).is_not_null()
	assert_object(menu.get_node_or_null("%BackBtn")).is_not_null()
	remove_child(menu)
	menu.free()

func test_volume_percent_maps_to_decibels() -> void:
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	assert_float(menu._volume_percent_to_db(100.0)).is_equal_approx(0.0, 0.001)
	assert_float(menu._volume_percent_to_db(0.0)).is_equal(-80.0)
	menu.free()

func test_language_option_changes_locale() -> void:
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu)
	menu._on_language_selected(1)
	assert_bool(TranslationServer.get_locale().begins_with("zh")).is_true()
	menu._on_language_selected(0)
	assert_bool(TranslationServer.get_locale().begins_with("en")).is_true()
	remove_child(menu)
	menu.free()
