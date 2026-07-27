extends SceneTree

const BATCHED_SCENES := [
	"res://scenes/props/decor/bones.tscn",
	"res://scenes/props/decor/bench.tscn",
	"res://scenes/props/decor/chair.tscn",
	"res://scenes/props/decor/table.tscn",
	"res://scenes/props/crates/small_crate.tscn",
	"res://scenes/props/decor/iron_bar_grate.tscn",
	"res://scenes/props/structures/pillar.tscn",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for scene_path in BATCHED_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			print("DECOR_PROBE missing=%s" % scene_path)
			continue
		var root_node := packed.instantiate() as Node3D
		_scan_node(scene_path, root_node, Transform3D.IDENTITY)
		root_node.free()
	quit()

func _scan_node(scene_path: String, node: Node, parent_transform: Transform3D) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
				for vertex_index in vertices.size():
					if vertex_index >= normals.size():
						continue
					var normal := normals[vertex_index]
					var transformed := current_transform.basis * normal
					if not _is_finite_vector(normal) or not _is_finite_vector(transformed):
						print("DECOR_PROBE nonfinite scene=%s node=%s surface=%d vertex=%d normal=%s transform=%s" % [
							scene_path, String(mesh_instance.get_path()), surface_index, vertex_index, str(normal), str(current_transform),
						])
	for child in node.get_children():
		_scan_node(scene_path, child, current_transform)

func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
