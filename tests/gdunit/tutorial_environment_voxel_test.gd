extends GdUnitTestSuite

const ASSET_PATHS := [
	"res://assets/models/environment/environment_tutorial_cart_wreck.glb",
	"res://assets/models/environment/environment_tutorial_forest_cluster.glb",
	"res://assets/models/environment/environment_tutorial_entrance_ruins.glb",
	"res://assets/models/environment/environment_tutorial_road_blocker.glb",
]

func test_tutorial_environment_assets_are_voxel_glbs() -> void:
	for path in ASSET_PATHS:
		var scene := load(path) as PackedScene
		assert_object(scene).is_not_null()
		var instance := auto_free(scene.instantiate())
		var meshes := _collect_meshes(instance)
		assert_int(meshes.size()).is_greater(2)
		var boxes := _boxes_in_pixel_space(meshes)
		assert_int(_count_components(boxes)).is_equal(1)
		assert_bool(_has_positive_overlap(boxes)).is_false()
		for mesh in meshes:
			var size := mesh.get_aabb().size
			assert_bool(_is_px_aligned(size.x) and _is_px_aligned(size.y) and _is_px_aligned(size.z)).is_true()

func test_tutorial_set_dressing_uses_reusable_voxel_assets() -> void:
	for path in [
		"res://scenes/environment/tutorial/voxel_road_tile.tscn",
		"res://scenes/environment/tutorial/voxel_road_shoulder.tscn",
		"res://scenes/environment/tutorial/voxel_boulder.tscn",
	]:
		assert_bool(ResourceLoader.exists(path)).is_true()
	var intro_source := FileAccess.get_file_as_string("res://scenes/intro/new_game_intro.tscn")
	assert_str(intro_source).not_contains("SphereMesh")
	assert_str(intro_source).contains("voxel_road_tile.tscn")

func test_three_view_tool_includes_tutorial_voxel_models() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(source).contains("tutorial_cart_wreck")
	assert_str(source).contains("tutorial_boulder")
	assert_str(source).contains("--tutorial-only")

func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes

func _is_px_aligned(value: float) -> bool:
	return is_equal_approx(value * 32.0, roundf(value * 32.0))

func _boxes_in_pixel_space(meshes: Array[MeshInstance3D]) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for mesh in meshes:
		var aabb := mesh.get_aabb()
		boxes.append(AABB((mesh.global_position + aabb.position) * 32.0, aabb.size * 32.0))
	return boxes

func _count_components(boxes: Array[AABB]) -> int:
	var visited: Array[bool] = []
	visited.resize(boxes.size())
	var components := 0
	for index in boxes.size():
		if visited[index]:
			continue
		components += 1
		var queue := [index]
		visited[index] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for other in boxes.size():
				if not visited[other] and _face_connected(boxes[current], boxes[other]):
					visited[other] = true
					queue.append(other)
	return components

func _face_connected(a: AABB, b: AABB) -> bool:
	var overlap := [
		minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x),
		minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y),
		minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z),
	]
	var positive := 0
	var touching := 0
	for value in overlap:
		if value > 0.001:
			positive += 1
		elif absf(value) <= 0.001:
			touching += 1
		else:
			return false
	return positive == 2 and touching == 1

func _has_positive_overlap(boxes: Array[AABB]) -> bool:
	for left in boxes.size():
		for right in range(left + 1, boxes.size()):
			var a := boxes[left]
			var b := boxes[right]
			if minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) > 0.001 and minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y) > 0.001 and minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z) > 0.001:
				return true
	return false
