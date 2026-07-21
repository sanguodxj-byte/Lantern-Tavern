extends GdUnitTestSuite

## 全面扫描所有体素道具的正体积重叠。
## 同材质重叠 → 合并网格内部产生共面面 → 严重 z-fighting（闪烁）。
## 跨材质重叠 + 共面面 → 也会 z-fighting。
## 本测试拦截 _pending_boxes（合并前）逐盒检测，是权威检测。

const ALL_PROP_KINDS := [
	"table", "chair", "bench", "bucket", "candles", "lit_candles",
	"tankard", "goblet", "bottle_set", "wall_notice", "chandelier",
	"wall_lantern", "grate", "jail", "fireplace", "small_crate",
	"large_crate", "barrel", "chest", "large_chest", "boss_chest",
	"torch", "pillar", "banner", "bones", "plank", "rubble",
]

const VOXEL_WEAPON_GLBS := {
	"shortsword": "res://assets/meshes/weapons/weapons_voxel_shortsword.glb",
	"greatsword": "res://assets/meshes/weapons/weapons_voxel_greatsword.glb",
	"axe": "res://assets/meshes/weapons/weapons_voxel_axe.glb",
	"warhammer": "res://assets/meshes/weapons/weapons_voxel_warhammer.glb",
	"spear": "res://assets/meshes/weapons/weapons_voxel_spear.glb",
	"dagger": "res://assets/meshes/weapons/weapons_voxel_dagger.glb",
	"longbow": "res://assets/meshes/weapons/weapons_voxel_longbow.glb",
	"crossbow": "res://assets/meshes/weapons/weapons_voxel_crossbow.glb",
	"staff": "res://assets/meshes/weapons/weapons_voxel_staff.glb",
	"grimoire": "res://assets/meshes/weapons/weapons_voxel_grimoire.glb",
	"shield": "res://assets/meshes/weapons/weapons_voxel_shield.glb",
	"sword": "res://assets/meshes/weapons/weapons_voxel_sword.glb",
}


func test_no_same_material_positive_volume_overlap() -> void:
	## 同材质正体积重叠 → 合并网格内部共面面 → 必定 z-fighting。
	## 这是最严重的闪烁来源，必须全部消除。
	var prop := VoxelProp.new()
	add_child(prop)
	for kind in ALL_PROP_KINDS:
		prop.prop_kind = kind
		var boxes := prop.collect_box_bounds()
		if boxes.is_empty():
			continue
		for i in range(boxes.size()):
			for j in range(i + 1, boxes.size()):
				if not _same_material(boxes[i], boxes[j]):
					continue
				if _boxes_overlap_positive_volume(boxes[i], boxes[j]):
					var a_name: String = boxes[i]["name"]
					var b_name: String = boxes[j]["name"]
					assert_bool(false) \
						.override_failure_message(
							"[%s] 同材质正体积重叠 %s vs %s → z-fighting\n  A:%s\n  B:%s" %
							[kind, a_name, b_name, _fmt_box(boxes[i]), _fmt_box(boxes[j])]) \
						.is_true()
	prop.free()


func test_no_cross_material_coplanar_overlap() -> void:
	## 跨材质正体积重叠 + 共面面 → z-fighting。
	## 跨材质正体积重叠但无共面面 → 不 z-fight（面在不同深度），允许。
	var prop := VoxelProp.new()
	add_child(prop)
	for kind in ALL_PROP_KINDS:
		prop.prop_kind = kind
		var boxes := prop.collect_box_bounds()
		if boxes.is_empty():
			continue
		for i in range(boxes.size()):
			for j in range(i + 1, boxes.size()):
				if _same_material(boxes[i], boxes[j]):
					continue
				if _boxes_overlap_positive_volume(boxes[i], boxes[j]) and _has_coplanar_face(boxes[i], boxes[j]):
					var a_name: String = boxes[i]["name"]
					var b_name: String = boxes[j]["name"]
					assert_bool(false) \
						.override_failure_message(
							"[%s] 跨材质共面重叠 %s vs %s → z-fighting\n  A:%s\n  B:%s" %
							[kind, a_name, b_name, _fmt_box(boxes[i]), _fmt_box(boxes[j])]) \
						.is_true()
	prop.free()


func test_voxel_weapon_glbs_have_no_positive_overlap_and_are_face_connected() -> void:
	for weapon_id in VOXEL_WEAPON_GLBS:
		var path: String = VOXEL_WEAPON_GLBS[weapon_id]
		var packed := load(path) as PackedScene
		assert_object(packed).override_failure_message("failed weapon load: %s" % path).is_not_null()
		var instance := packed.instantiate() as Node3D
		assert_object(instance).is_not_null()
		add_child(instance)
		var boxes: Array[Dictionary] = []
		_collect_mesh_boxes(instance, boxes)
		assert_int(boxes.size()).is_greater(0)
		for i in range(boxes.size()):
			for j in range(i + 1, boxes.size()):
				assert_bool(_boxes_overlap_positive_volume(boxes[i], boxes[j])) \
					.override_failure_message(
						"[%s] weapon positive overlap %s vs %s" % [weapon_id, boxes[i]["name"], boxes[j]["name"]]
					) \
					.is_false()
		assert_bool(_boxes_are_single_face_connected_component(boxes)) \
			.override_failure_message("[%s] weapon has detached or corner-only boxes" % weapon_id) \
			.is_true()
		instance.free()


# ── 辅助函数 ──────────────────────────────────────────────

func _boxes_overlap_positive_volume(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3 = a["min"]
	var amax: Vector3 = a["max"]
	var bmin: Vector3 = b["min"]
	var bmax: Vector3 = b["max"]
	return minf(amax.x, bmax.x) - maxf(amin.x, bmin.x) > 0.01 \
		and minf(amax.y, bmax.y) - maxf(amin.y, bmin.y) > 0.01 \
		and minf(amax.z, bmax.z) - maxf(amin.z, bmin.z) > 0.01


func _same_material(a: Dictionary, b: Dictionary) -> bool:
	var ma: Material = a["material"]
	var mb: Material = b["material"]
	return ma == mb


func _has_coplanar_face(a: Dictionary, b: Dictionary) -> bool:
	## 检查两个重叠的盒是否在某个轴向上存在共面面。
	## 共面面 = 一个盒的 min/max 面与另一个盒的 min/max 面在同一坐标。
	var amin: Vector3 = a["min"]
	var amax: Vector3 = a["max"]
	var bmin: Vector3 = b["min"]
	var bmax: Vector3 = b["max"]
	# X 轴共面
	if is_equal_approx(amin.x, bmin.x) or is_equal_approx(amin.x, bmax.x) \
		or is_equal_approx(amax.x, bmin.x) or is_equal_approx(amax.x, bmax.x):
		return true
	# Y 轴共面
	if is_equal_approx(amin.y, bmin.y) or is_equal_approx(amin.y, bmax.y) \
		or is_equal_approx(amax.y, bmin.y) or is_equal_approx(amax.y, bmax.y):
		return true
	# Z 轴共面
	if is_equal_approx(amin.z, bmin.z) or is_equal_approx(amin.z, bmax.z) \
		or is_equal_approx(amax.z, bmin.z) or is_equal_approx(amax.z, bmax.z):
		return true
	return false


func _fmt_box(b: Dictionary) -> String:
	var mn: Vector3 = b["min"]
	var mx: Vector3 = b["max"]
	return "[%.1f,%.1f,%.1f]→[%.1f,%.1f,%.1f]" % [mn.x, mn.y, mn.z, mx.x, mx.y, mx.z]


func _collect_mesh_boxes(node: Node, boxes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		boxes.append({
			"name": String(mesh.name),
			"min": box.position,
			"max": box.end,
			"material": mesh.get_active_material(0),
		})
	for child in node.get_children():
		_collect_mesh_boxes(child, boxes)


func _boxes_face_contact(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3 = a["min"]
	var amax: Vector3 = a["max"]
	var bmin: Vector3 = b["min"]
	var bmax: Vector3 = b["max"]
	var overlaps := [
		minf(amax.x, bmax.x) - maxf(amin.x, bmin.x),
		minf(amax.y, bmax.y) - maxf(amin.y, bmin.y),
		minf(amax.z, bmax.z) - maxf(amin.z, bmin.z),
	]
	if overlaps.any(func(value: float) -> bool: return value < -0.005):
		return false
	var flush := overlaps.filter(func(value: float) -> bool: return absf(value) <= 0.005).size()
	var solid := overlaps.filter(func(value: float) -> bool: return value > 0.01).size()
	return flush == 1 and solid == 2


func _boxes_are_single_face_connected_component(boxes: Array[Dictionary]) -> bool:
	if boxes.is_empty():
		return false
	var visited := {0: true}
	var pending := [0]
	while not pending.is_empty():
		var current: int = pending.pop_back()
		for candidate in range(boxes.size()):
			if visited.has(candidate):
				continue
			if _boxes_face_contact(boxes[current], boxes[candidate]):
				visited[candidate] = true
				pending.append(candidate)
	return visited.size() == boxes.size()
