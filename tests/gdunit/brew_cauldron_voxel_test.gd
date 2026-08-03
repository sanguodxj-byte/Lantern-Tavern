extends GdUnitTestSuite
## 中世纪炼药锅体素模型 (brew_cauldron) 测试：
## 尺寸包络（像素锁定）、命名主形体可见、面接触连通、无静态火焰。

const CAULDRON_SCENE := "res://scenes/props/decor/brew_cauldron.tscn"

func _instantiate() -> Node:
	var inst := (load(CAULDRON_SCENE) as PackedScene).instantiate()
	add_child(inst)
	return inst

func test_cauldron_envelope_matches_pixel_table() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	var prop := inst as VoxelProp
	var boxes := prop.collect_box_bounds()
	var min_v := Vector3.INF
	var max_v := Vector3(-INF, -INF, -INF)
	for box in boxes:
		min_v = min_v.min(box["min"])
		max_v = max_v.max(box["max"])
	# 尺寸表：x[-18,18] y[0,38] z[-14,14]（像素，中世纪炼药锅）
	assert_float(max_v.x - min_v.x).is_equal_approx(36.0, 1.0)
	assert_float(max_v.y - min_v.y).is_equal_approx(38.0, 1.0)
	assert_float(max_v.z - min_v.z).is_equal_approx(28.0, 1.0)
	inst.free()

func test_cauldron_has_named_silhouette_parts() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	var prop := inst as VoxelProp
	var boxes := prop.collect_box_bounds()
	var names: Array = []
	for box in boxes:
		names.append(String(box["name"]))
	for required in ["CauldronStonePadFrontLeft", "CauldronLegFrontLeft", "CauldronLegBack", "CauldronRimFront", "CauldronMidBellyFront", "CauldronBandLowFront", "CauldronEarLeft"]:
		assert_bool(names.has(required)) \
			.override_failure_message("炼药锅缺少主形体部件: %s" % required) \
			.is_true()
	inst.free()

func test_cauldron_is_single_face_connected_component() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	var prop := inst as VoxelProp
	var boxes := prop.collect_box_bounds()
	assert_int(_count_attached_components(boxes)).is_equal(1)
	inst.free()

func test_cauldron_boxes_do_not_overlap_positive_volume() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	var prop := inst as VoxelProp
	var boxes := prop.collect_box_bounds()
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_bool(_boxes_overlap(boxes[i], boxes[j])) \
				.override_failure_message("炼药锅体素盒正体积重叠: %s vs %s" % [boxes[i]["name"], boxes[j]["name"]]) \
				.is_false()
	inst.free()

func test_cauldron_uses_only_voxel_materials() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	var prop := inst as VoxelProp
	var boxes := prop.collect_box_bounds()
	assert_int(boxes.size()).is_greater_equal(12)
	for box in boxes:
		var mat := box["material"] as ShaderMaterial
		assert_object(mat).is_not_null()
		assert_object(mat.get_shader_parameter("atlas")).is_not_null()
	inst.free()

func test_cauldron_has_no_static_flame_meshes() -> void:
	var inst := _instantiate()
	await await_idle_frame()
	for mesh_instance in _collect_meshes(inst):
		assert_bool(String(mesh_instance.name).begins_with("Flame")) \
			.override_failure_message("炼药锅静态模型不应包含火焰 mesh") \
			.is_false()
	inst.free()

# ── 辅助 ──────────────────────────────────────────────

func _collect_meshes(root: Node) -> Array:
	var result: Array = []
	if root is MeshInstance3D:
		result.append(root)
	for child in root.get_children():
		result.append_array(_collect_meshes(child))
	return result

func _boxes_overlap(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3 = a["min"]
	var amax: Vector3 = a["max"]
	var bmin: Vector3 = b["min"]
	var bmax: Vector3 = b["max"]
	return minf(amax.x, bmax.x) - maxf(amin.x, bmin.x) > 0.01 \
		and minf(amax.y, bmax.y) - maxf(amin.y, bmin.y) > 0.01 \
		and minf(amax.z, bmax.z) - maxf(amin.z, bmin.z) > 0.01

func _count_attached_components(boxes: Array) -> int:
	var visited: Array[bool] = []
	visited.resize(boxes.size())
	var components := 0
	for i in range(boxes.size()):
		if visited[i]:
			continue
		components += 1
		var queue: Array[int] = [i]
		visited[i] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for j in range(boxes.size()):
				if visited[j]:
					continue
				if _boxes_are_attached(boxes[current], boxes[j]):
					visited[j] = true
					queue.append(j)
	return components

func _boxes_are_attached(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3 = a["min"]
	var amax: Vector3 = a["max"]
	var bmin: Vector3 = b["min"]
	var bmax: Vector3 = b["max"]
	var overlaps := [
		minf(amax.x, bmax.x) - maxf(amin.x, bmin.x),
		minf(amax.y, bmax.y) - maxf(amin.y, bmin.y),
		minf(amax.z, bmax.z) - maxf(amin.z, bmin.z),
	]
	var positive_axes := 0
	var touching_axes := 0
	for overlap in overlaps:
		if overlap > 0.005:
			positive_axes += 1
		elif absf(overlap) <= 0.005:
			touching_axes += 1
		else:
			return false
	return positive_axes == 2 and touching_axes == 1
