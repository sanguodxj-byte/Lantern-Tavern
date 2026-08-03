extends GdUnitTestSuite

const SETTINGS_PATH := "res://scenes/ui/settings_menu.tscn"
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

var _original_master_db: float
var _original_locale: String
var _original_pixel_shader: bool

func before() -> void:
	_original_master_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_original_locale = TranslationServer.get_locale()
	# 强制重置为 true 后再保存"原始值"，防止前一次测试运行泄漏的 false
	# 被当作原始值保存、after() 又还原成 false，形成跨运行的状态污染循环。
	Settings.set_pixel_shader_enabled(true)
	_original_pixel_shader = true

func after() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _original_master_db)
	TranslationServer.set_locale(_original_locale)
	# 使用 setter 方法还原（而非直接赋值），确保还原值被持久化到 user://settings.cfg，
	# 避免下一次测试运行时 Settings._ready() 从配置文件加载到被测试改写的 false。
	Settings.set_pixel_shader_enabled(_original_pixel_shader)

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
	assert_object(menu.get_node_or_null("%PixelShaderCheck")).is_not_null()
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

# ── 像素着色开关 ────────────────────────────────────────────

func test_pixel_shader_check_reflects_settings_value() -> void:
	# 设置菜单加载时应把 Settings.pixel_shader_enabled 同步到复选框。
	Settings.pixel_shader_enabled = true
	var menu_true: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu_true)
	assert_bool(menu_true.pixel_shader_check.button_pressed).is_true()
	remove_child(menu_true)
	menu_true.free()

	Settings.pixel_shader_enabled = false
	var menu_false: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu_false)
	assert_bool(menu_false.pixel_shader_check.button_pressed).is_false()
	remove_child(menu_false)
	menu_false.free()

func test_pixel_shader_toggle_updates_settings_and_adapter() -> void:
	# 用户拨动复选框应通过 Settings 单例持久化并同步到适配器开关。
	Settings.pixel_shader_enabled = true
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu)
	# 关闭
	menu._on_pixel_shader_toggled(false)
	assert_bool(Settings.pixel_shader_enabled).is_false()
	assert_bool(VOXEL_LIGHTING.is_pixel_shader_enabled()).is_false()
	# 重新开启
	menu._on_pixel_shader_toggled(true)
	assert_bool(Settings.pixel_shader_enabled).is_true()
	assert_bool(VOXEL_LIGHTING.is_pixel_shader_enabled()).is_true()
	remove_child(menu)
	menu.free()

func test_pixel_shader_setting_persists_to_config() -> void:
	# set_pixel_shader_enabled 应把值写入 user://settings.cfg。
	# 使用 Settings 单例本身的持久化路径，测试后还原。
	Settings.set_pixel_shader_enabled(false)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(Settings.SAVE_PATH)).is_equal(OK)
	assert_bool(cfg.get_value(Settings.SECTION, "pixel_shader_enabled", true)).is_false()
	Settings.set_pixel_shader_enabled(true)
	cfg.clear()
	assert_int(cfg.load(Settings.SAVE_PATH)).is_equal(OK)
	assert_bool(cfg.get_value(Settings.SECTION, "pixel_shader_enabled", false)).is_true()

func test_pixel_shader_toggle_clears_adapter_cache() -> void:
	# 切换开关时应清空适配器缓存，避免缓存的 toon 材质被新加载的场景复用。
	Settings.pixel_shader_enabled = true
	VOXEL_LIGHTING.set_pixel_shader_enabled(true)
	# 填充缓存：adapt_standard_material 会把 toon 材质写入 _adapt_cache。
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.5
	mat.roughness = 0.3
	VOXEL_LIGHTING.adapt_standard_material(mat)
	assert_int(VOXEL_LIGHTING.get_cache_stats()["size"]).is_greater(0)
	# 切换开关：set_pixel_shader_enabled 应调用 clear_cache。
	Settings.set_pixel_shader_enabled(false)
	assert_int(VOXEL_LIGHTING.get_cache_stats()["size"]).is_equal(0)

# ── 镜头冲击开关（B2）─────────────────────────────────────

func test_settings_menu_has_camera_impact_check() -> void:
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu)
	assert_object(menu.get_node_or_null("%CameraImpactCheck")).is_not_null()
	remove_child(menu)
	menu.free()

func test_camera_impact_check_reflects_settings_value() -> void:
	Settings.set_camera_impact_enabled(true)
	var menu_true: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu_true)
	assert_bool(menu_true.camera_impact_check.button_pressed).is_true()
	remove_child(menu_true)
	menu_true.free()

	Settings.set_camera_impact_enabled(false)
	var menu_false: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu_false)
	assert_bool(menu_false.camera_impact_check.button_pressed).is_false()
	remove_child(menu_false)
	menu_false.free()
	Settings.set_camera_impact_enabled(true)

func test_camera_impact_toggle_updates_settings() -> void:
	Settings.set_camera_impact_enabled(true)
	var menu: SettingsMenu = load(SETTINGS_PATH).instantiate()
	add_child(menu)
	menu._on_camera_impact_toggled(false)
	assert_bool(Settings.camera_impact_enabled).is_false()
	menu._on_camera_impact_toggled(true)
	assert_bool(Settings.camera_impact_enabled).is_true()
	remove_child(menu)
	menu.free()

func test_camera_impact_setting_persists_to_config() -> void:
	Settings.set_camera_impact_enabled(false)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(Settings.SAVE_PATH)).is_equal(OK)
	assert_bool(cfg.get_value(Settings.SECTION, "camera_impact_enabled", true)).is_false()
	Settings.set_camera_impact_enabled(true)
	cfg.clear()
	assert_int(cfg.load(Settings.SAVE_PATH)).is_equal(OK)
	assert_bool(cfg.get_value(Settings.SECTION, "camera_impact_enabled", false)).is_true()
