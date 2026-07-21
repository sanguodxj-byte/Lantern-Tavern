class_name UiNavigationService
extends Node

## 页面导航的唯一适配器。
## 未来可在这里加入转场、页面恢复和输入焦点策略，而不修改每个页面。

signal route_requested(route: StringName, path: String, payload: Dictionary)
signal navigation_rejected(route: StringName, reason: String)

const ROUTES := preload("res://globals/ui/ui_route_catalog.gd")

var last_route: StringName = &""
var _history: Array[StringName] = []


func navigate(route: StringName, payload: Dictionary = {}) -> bool:
	var path := ROUTES.path_for(route)
	if path.is_empty():
		navigation_rejected.emit(route, "unknown_route")
		return false
	if not ResourceLoader.exists(path):
		navigation_rejected.emit(route, "missing_scene")
		return false

	last_route = route
	_history.append(route)
	route_requested.emit(route, path, payload.duplicate(true))

	# Detached instances remain testable without creating a SceneTree。
	if not is_inside_tree():
		return true
	var scene_tree := get_tree()
	var result := scene_tree.change_scene_to_file(path)
	if result != OK:
		navigation_rejected.emit(route, "scene_change_failed")
		return false
	return true


func history() -> Array[StringName]:
	return _history.duplicate()


func reset_history() -> void:
	_history.clear()
	last_route = &""
