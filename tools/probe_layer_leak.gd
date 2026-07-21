extends Node
const PlayerScene := preload("res://scenes/characters/player/player.tscn")

func _ready() -> void:
	var p = PlayerScene.instantiate()
	get_tree().root.add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	print("=== LAYER LEAK SCAN (MainCamera sees layer 1) ===")
	_scan(p, 0)
	print("=== DONE ===")
	get_tree().quit()

func _scan(node: Node, depth: int) -> void:
	if node is GeometryInstance3D:
		var layers: int = node.layers
		var on_layer1: bool = (layers & 1) != 0
		if on_layer1:
			print("LEAK@layer1: ", node.get_path(), " | name=", node.name, " | layers=", layers, " | class=", node.get_class())
	for c in node.get_children():
		_scan(c, depth + 1)
