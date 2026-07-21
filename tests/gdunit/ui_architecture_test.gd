extends GdUnitTestSuite

const SCREEN_PATH := "res://scenes/ui/core/ui_screen.gd"
const ROUTES_PATH := "res://globals/ui/ui_route_catalog.gd"
const NAVIGATION_PATH := "res://globals/ui/ui_navigation.gd"
const NavigationScript := preload("res://globals/ui/ui_navigation.gd")
const ScreenScript := preload("res://scenes/ui/core/ui_screen.gd")


func test_route_catalog_contains_existing_page_scenes() -> void:
	var catalog := load(ROUTES_PATH)
	assert_object(catalog).is_not_null()
	for route in [catalog.MAIN_MENU, catalog.GALLERY, catalog.SETTINGS, catalog.MULTIPLAYER_LOBBY, catalog.ZONE_SELECT]:
		assert_bool(catalog.has_route(route)).is_true()
		assert_bool(ResourceLoader.exists(catalog.path_for(route))).is_true()


func test_routed_page_scenes_can_be_instantiated() -> void:
	var catalog := load(ROUTES_PATH)
	for route in [catalog.MAIN_MENU, catalog.GALLERY, catalog.SETTINGS, catalog.MULTIPLAYER_LOBBY, catalog.ZONE_SELECT]:
		var scene := load(catalog.path_for(route)) as PackedScene
		assert_object(scene).override_failure_message("Cannot load route scene: %s" % route).is_not_null()
		var instance := scene.instantiate()
		assert_object(instance).override_failure_message("Cannot instantiate route scene: %s" % route).is_not_null()
		instance.free()


func test_navigation_rejects_unknown_routes_without_scene_changes() -> void:
	var navigation: Node = NavigationScript.new()
	var rejected := []
	navigation.navigation_rejected.connect(func(route: StringName, reason: String) -> void:
		rejected.append({"route": route, "reason": reason})
	)

	assert_bool(navigation.navigate(&"missing_page")).is_false()
	assert_array(rejected).has_size(1)
	assert_str(String(rejected[0].reason)).is_equal("unknown_route")
	navigation.free()


func test_navigation_keeps_route_history_and_payload_isolated() -> void:
	var navigation: Node = NavigationScript.new()
	var received := []
	navigation.route_requested.connect(func(route: StringName, path: String, payload: Dictionary) -> void:
		received.append({"route": route, "path": path, "payload": payload})
	)
	var payload := {"source": "test"}
	assert_bool(navigation.navigate(&"gallery", payload)).is_true()
	payload["source"] = "mutated"

	assert_array(navigation.history()).has_size(1)
	assert_str(String(navigation.history()[0])).is_equal("gallery")
	assert_str(String(received[0].payload.source)).is_equal("test")
	navigation.free()


func test_ui_screen_lifecycle_is_explicit_and_payload_is_copied() -> void:
	var screen: UiScreen = ScreenScript.new()
	add_child(screen)
	screen.visible = false
	await await_idle_frame()
	var opened_payload := {"tab": "equipment"}
	screen.open(opened_payload)
	opened_payload["tab"] = "changed"
	assert_bool(screen.is_open()).is_true()
	assert_str(String(screen.payload().tab)).is_equal("equipment")

	var close_result := {"confirmed": true}
	screen.close(close_result)
	assert_bool(screen.is_open()).is_false()
	assert_bool(screen.visible).is_false()
	screen.free()


func test_page_scripts_use_screen_contract_and_route_adapter() -> void:
	for script_path in [
		"res://scenes/ui/main_menu.gd",
		"res://scenes/ui/settings_menu.gd",
		"res://scenes/ui/lobby_menu.gd",
		"res://scenes/ui/zone_select.gd",
		"res://scenes/ui/model_viewer.gd",
	]:
		var source := FileAccess.get_file_as_string(script_path)
		assert_str(source).contains("extends UiScreen")
		assert_str(source).contains("request_navigation")


func test_pause_menu_uses_route_adapter_for_main_menu() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/pause_menu.gd")
	assert_str(source).contains("UiNavigation.navigate")
	assert_str(source).contains("UI_ROUTES.MAIN_MENU")
