#!/usr/bin/env -S godot -s
extends SceneTree

func _initialize() -> void:
	var f := FileAccess.open("res://reports/_bucket_dump.txt", FileAccess.WRITE)
	var write := func(s: String) -> void: f.store_line(s)
	var res: Resource = ResourceLoader.load("res://assets/meshes/shields/voxel_buckler.glb")
	write.call("RES TYPE: %s" % str(res))
	write.call("RES CLASS: %s" % str(res.get_class() if res else "null"))
	if res is PackedScene:
		var inst: Node = res.instantiate()
		write.call("ROOT NAME: %s  CLASS: %s" % [inst.name, inst.get_class()])
		_dump(inst, 0, write)
		inst.free()
	elif res is Mesh:
		write.call("It is a direct Mesh with %d surfaces" % (res as Mesh).get_surface_count())
	f.close()
	await process_frame
	quit(0)

func _dump(node: Node, depth: int, write: Callable) -> void:
	var info := "  ".repeat(depth) + node.name + "  [" + node.get_class() + "]"
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		info += "  mesh=%s visible=%s" % [str(vi.get("mesh") if (node is MeshInstance3D) else null), str(vi.is_visible_in_tree())]
	write.call(info)
	for c in node.get_children():
		_dump(c, depth + 1, write)