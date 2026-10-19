extends GdUnitTestSuite

const REQUIRED_AUTOLOADS := {
	"TavernManager": "res://globals/tavern/tavern_manager.gd",
	"GameState": "res://globals/core/game_state.gd",
	"GameEvents": "res://globals/core/game_events.gd",
	"HitStopServer": "res://globals/core/hit_stop_server.gd",
	"FxHelper": "res://globals/core/fx_helper.gd",
	"AudioManager": "res://globals/core/audio_manager.tscn",
	"LocalizationManager": "res://globals/core/localization_manager.gd",
	"WeaponRegistry": "res://data/weapon_registry.gd",
	"BrewingData": "res://globals/tavern/brewing_data.gd",
	"TavernSettlement": "res://globals/tavern/tavern_settlement.gd",
	"FermentationSystem": "res://globals/tavern/fermentation_system.gd",
	"LootTable": "res://globals/tavern/loot_table.gd",
	"ZoneManager": "res://globals/dungeon/zone_manager.gd",
	"CombatEngine": "res://globals/combat/combat_engine.gd",
	"AttrPanel": "res://globals/combat/attr_panel.gd",
	"SkillRuntime": "res://globals/combat/skill_runtime.gd",
	"SkillIcons": "res://globals/combat/skill_icons.gd",
	"DungeonSpawner": "res://globals/dungeon/dungeon_spawner.gd",
	"ItemSpawner": "res://globals/equipment/item_spawner.gd",
	"AffixSystem": "res://globals/equipment/affix_system.gd",
	"PhysicsSetup": "res://globals/core/physics_setup.gd",
	"Settings": "res://globals/settings.gd",
	"UiNavigation": "res://globals/ui/ui_navigation.gd",
	"NetworkManager": "res://globals/core/network_manager.gd",
	"MultiplayerSession": "res://globals/multiplayer/multiplayer_session.gd",
	"SaveManager": "res://globals/core/save_manager.gd",
	"ProjectileService": "res://globals/combat/projectile_service.gd",
	"LightingController": "res://globals/lighting/lighting_controller.gd",
}


func test_project_registers_runtime_autoloads() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://project.godot")).is_equal(OK)
	for singleton_name in REQUIRED_AUTOLOADS:
		var expected := "*%s" % REQUIRED_AUTOLOADS[singleton_name]
		assert_str(String(config.get_value("autoload", singleton_name, ""))) \
			.override_failure_message("缺少或错误的 Autoload: %s" % singleton_name) \
			.is_equal(expected)


func test_project_declares_main_menu_scene() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://project.godot")).is_equal(OK)
	assert_str(String(config.get_value("application", "run/main_scene", ""))) \
		.is_equal("res://scenes/ui/main_menu.tscn")
	# 项目含 LanternTavern.csproj 与 C# 特性，dotnet 配置为必需
	assert_bool(config.has_section("dotnet")) \
		.override_failure_message("项目含 C# 工程（LanternTavern.csproj），必须声明 dotnet 配置").is_true()


func test_project_restores_1080p_canvas_window_settings() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://project.godot")).is_equal(OK)
	assert_int(int(config.get_value("display", "window/size/viewport_width", 0))) \
		.is_equal(1920)
	assert_int(int(config.get_value("display", "window/size/viewport_height", 0))) \
		.is_equal(1080)
	assert_str(String(config.get_value("display", "window/stretch/mode", ""))) \
		.is_equal("canvas_items")
	assert_str(String(config.get_value("display", "window/stretch/aspect", ""))) \
		.is_equal("expand")


func test_project_declares_player_input_actions() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://project.godot")).is_equal(OK)
	for action in [
		"forward", "backward", "strafe_left", "strafe_right",
		"kick", "use", "run", "block", "action", "throw",
		"jump", "restart", "skill_g",
	]:
		assert_bool(config.has_section_key("input", action)) \
			.override_failure_message("缺少输入动作: %s" % action) \
			.is_true()


func test_ui_navigation_base_and_main_menu_are_loadable() -> void:
	assert_object(load("res://scenes/ui/core/ui_screen.gd")).is_not_null()
	assert_object(load("res://scenes/ui/main_menu.tscn")).is_not_null()


## P0-1（1122 审查）：MultiplayerSession 生产装配——autoload 已注册且可实例，
## 多人大厅场景可加载（真实 host/join 双进程冒烟由 tests/integration/ 覆盖）。
func test_multiplayer_session_registered_and_lobby_loadable() -> void:
	assert_object(Engine.get_main_loop().root.get_node_or_null("MultiplayerSession")) \
		.override_failure_message("MultiplayerSession 必须注册为 autoload（lobby_menu 经 /root 获取）").is_not_null()
	assert_object(load("res://scenes/ui/lobby_menu.tscn")).is_not_null()
	assert_object(load("res://globals/multiplayer/multiplayer_session.gd")).is_not_null()


## E3 (review 1327 §3): 启动（autoload 就绪）不得把任何装备 GLB 加载进资源缓存。
## WeaponRegistry._ready 只登记 JSON 中的 glb_path；GLB PackedScene 一律在
## get_glb_mesh() 首次访问时按需加载。此测试是资源泄漏/全量加载门禁。
func test_bootstrap_does_not_eagerly_load_weapon_glbs() -> void:
	assert_object(WeaponRegistry).is_not_null()
	for weapon_id in ["crossbow", "shortsword", "greatsword", "shield"]:
		var path := WeaponRegistry.get_glb_path(weapon_id)
		if path.is_empty():
			continue
		assert_bool(ResourceLoader.has_cached(path)) \
			.override_failure_message("bootstrap 不应预加载装备 GLB: %s" % path).is_false()
	# 注册的 WeaponData 在首次 get_glb_mesh() 之前 glb_mesh 必须为空
	var crossbow_data: WeaponData = WeaponRegistry.get_weapon_data("crossbow")
	assert_object(crossbow_data).is_not_null()
	if crossbow_data != null:
		assert_object(crossbow_data.glb_mesh).is_null()
