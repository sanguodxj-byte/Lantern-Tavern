class_name TavernBarInteraction
extends StaticBody3D

@export var interaction_name: String = "吧台"

func interact(_source_player: Node = null) -> void:
	var tavern: Node = _find_tavern_root()
	if tavern != null and tavern.has_method("toggle_tavern_hud"):
		tavern.toggle_tavern_hud()

func _find_tavern_root() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("toggle_tavern_hud"):
			return node
		node = node.get_parent()
	return null
