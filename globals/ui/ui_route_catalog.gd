class_name UiRouteCatalog
extends RefCounted

## 页面路由的单一登记处。页面脚本不再散落硬编码场景路径。

const MAIN_MENU: StringName = &"main_menu"
const GALLERY: StringName = &"gallery"
const SETTINGS: StringName = &"settings"
const MULTIPLAYER_LOBBY: StringName = &"multiplayer_lobby"
const ZONE_SELECT: StringName = &"zone_select"

const ROUTES: Dictionary = {
	MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	GALLERY: "res://scenes/ui/model_viewer.tscn",
	SETTINGS: "res://scenes/ui/settings_menu.tscn",
	MULTIPLAYER_LOBBY: "res://scenes/ui/lobby_menu.tscn",
	ZONE_SELECT: "res://scenes/ui/zone_select.tscn",
}


static func path_for(route: StringName) -> String:
	return String(ROUTES.get(route, ""))


static func has_route(route: StringName) -> bool:
	return ROUTES.has(route)
