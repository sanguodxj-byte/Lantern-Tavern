
extends SceneTree
func _initialize():
	call_deferred("r")
func r():
	var p = load("res://assets/meshes/armor/armor_voxel_chain_armor.glb") as PackedScene
	var n = p.instantiate()
	var names = []
	_c(n, names)
	print("NAMES:" + ",".join(names))
	quit(0)
func _c(node, names):
	names.append(str(node.name))
	for c in node.get_children():
		_c(c, names)
