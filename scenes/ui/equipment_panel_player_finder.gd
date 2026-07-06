class_name EquipmentPanelPlayerFinder
## 装备面板玩家查找工具（从 tavern_equipment_panel.gd 提取）
## 负责在场景树中查找有效的 Player 节点
extends RefCounted

const Service := preload("res://globals/core/service.gd")

static func get_current_player() -> Player:
	var gs: Node = Service.game_state()
	var current_player = gs.get("current_player") if gs != null and "current_player" in gs else null
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		if gs != null and "current_level" in gs:
			var level = gs.get("current_level")
			if level != null and is_instance_valid(level) and level is Node:
				var level_player := _find_player_recursive(level)
				if level_player != null:
					_register_current_player(gs, level_player)
					return level_player
		var nearby_player := _find_nearby_player(tree.current_scene)
		if nearby_player != null:
			_register_current_player(gs, nearby_player)
			return nearby_player
		if _is_valid_equipment_player(current_player) and current_player.is_inside_tree():
			return current_player
		var scene_players := _collect_players_recursive(tree.root)
		if scene_players.size() == 1:
			_register_current_player(gs, scene_players[0])
			return scene_players[0]
	if _is_valid_equipment_player(current_player):
		return current_player
	return null

static func _find_player_recursive(node: Node) -> Player:
	if node.is_queued_for_deletion():
		return null
	if _is_valid_equipment_player(node) and node.is_inside_tree():
		return node
	for child in node.get_children():
		var found := _find_player_recursive(child)
		if found != null:
			return found
	return null

static func _find_nearby_player(start: Node) -> Player:
	var scope := start
	while scope != null:
		var found := _find_player_recursive(scope)
		if found != null:
			return found
		scope = scope.get_parent()
	return null

static func _collect_players_recursive(node: Node) -> Array[Player]:
	var players: Array[Player] = []
	if node.is_queued_for_deletion():
		return players
	if _is_valid_equipment_player(node) and node.is_inside_tree():
		players.append(node)
	for child in node.get_children():
		players.append_array(_collect_players_recursive(child))
	return players

static func _is_valid_equipment_player(player: Variant) -> bool:
	return player != null \
		and is_instance_valid(player) \
		and player is Player \
		and not player.is_queued_for_deletion() \
		and not player.has_meta("equipment_preview") \
		and "equipment" in player \
		and player.equipment != null

static func _register_current_player(gs: Node, player: Player) -> void:
	if gs != null and "current_player" in gs:
		gs.set("current_player", player)
