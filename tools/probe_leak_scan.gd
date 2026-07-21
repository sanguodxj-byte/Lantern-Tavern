extends Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var p = get_node_or_null("Player")
	if p == null:
		print("NO PLAYER NODE FOUND")
		get_tree().quit()
		return
	print("=== LAYER LEAK SCAN (MainCamera sees layer 1) ===")
	_scan(p, 0)
	print("=== DONE ===")
	get_tree().quit()

func _scan(node: Node, depth: int) -> void:
	if node is GeometryInstance3D:
		var layers: int = node.layers
		if (layers & 1) != 0:
			print("LEAK@layer1: ", node.name, " | layers=", layers, " | class=", node.get_class())
	for c in node.get_children():
		_scan(c, depth + 1)
