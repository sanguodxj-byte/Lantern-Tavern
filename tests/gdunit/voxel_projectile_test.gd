extends GdUnitTestSuite
## 体素投射物模型测试。
## 验证：
##   1. voxel_arrow.tscn / voxel_bolt.tscn 场景文件存在且可加载
##   2. VoxelProjectileVisual 脚本正确生成体素盒网格
##   3. 所有体素盒尺寸对齐 1px = 1/32m
##   4. 所有体素盒通过面接触组成单一附着组件（无悬空/角接触）
##   5. 无正体积重叠
##   6. 箭头朝向 -Z（飞行方向），箭尾在 +Z 端
##   7. 弩箭比箭矢更短、箭头更宽
##   8. 材质使用 toon 着色（DIFFUSE_TOON / SPECULAR_DISABLED）
##   9. ProjectileService 为 arrow/bolt 设置了 visual_scene
##   10. ModelViewer 源码包含 Projectiles 扫描

const PX := 1.0 / 32.0
const ARROW_SCENE_PATH := "res://assets/meshes/projectiles/voxel_arrow.tscn"
const BOLT_SCENE_PATH := "res://assets/meshes/projectiles/voxel_bolt.tscn"
const VISUAL_SCRIPT_PATH := "res://scenes/equipment/voxel_projectile_visual.gd"
const SERVICE := preload("res://globals/core/service.gd")


# ============================================================================
# 1. 场景文件与脚本存在性
# ============================================================================

func test_arrow_scene_file_exists() -> void:
	assert_bool(ResourceLoader.exists(ARROW_SCENE_PATH)) \
		.override_failure_message("体素箭矢场景文件不存在: %s" % ARROW_SCENE_PATH) \
		.is_true()

func test_bolt_scene_file_exists() -> void:
	assert_bool(ResourceLoader.exists(BOLT_SCENE_PATH)) \
		.override_failure_message("体素弩箭场景文件不存在: %s" % BOLT_SCENE_PATH) \
		.is_true()

func test_visual_script_exists() -> void:
	assert_bool(ResourceLoader.exists(VISUAL_SCRIPT_PATH)) \
		.override_failure_message("体素投射物视觉脚本不存在: %s" % VISUAL_SCRIPT_PATH) \
		.is_true()

func test_visual_script_has_class_name() -> void:
	var script := load(VISUAL_SCRIPT_PATH) as GDScript
	assert_object(script).is_not_null()
	var source: String = script.source_code
	assert_bool(source.contains("class_name VoxelProjectileVisual")) \
		.override_failure_message("脚本必须声明 class_name VoxelProjectileVisual") \
		.is_true()


# ============================================================================
# 2. 体素盒数量与生成
# ============================================================================

func test_arrow_generates_seven_voxel_boxes() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	var meshes := _collect_meshes(inst)
	assert_int(meshes.size()) \
		.override_failure_message("体素箭矢应生成 7 个体素盒") \
		.is_equal(7)
	inst.free()

func test_bolt_generates_six_voxel_boxes() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	var meshes := _collect_meshes(inst)
	assert_int(meshes.size()) \
		.override_failure_message("体素弩箭应生成 6 个体素盒") \
		.is_equal(6)
	inst.free()

func test_arrow_mesh_names_correct() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	var names := _collect_mesh_names(inst)
	assert_array(names).contains("ArrowheadTip")
	assert_array(names).contains("ArrowheadMid")
	assert_array(names).contains("ArrowheadBase")
	assert_array(names).contains("Shaft")
	assert_array(names).contains("FletchingInner")
	assert_array(names).contains("FletchingOuter")
	assert_array(names).contains("Nock")
	inst.free()

func test_bolt_mesh_names_correct() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	var names := _collect_mesh_names(inst)
	assert_array(names).contains("BoltTip")
	assert_array(names).contains("BoltMid")
	assert_array(names).contains("BoltBase")
	assert_array(names).contains("Shaft")
	assert_array(names).contains("Fletching")
	assert_array(names).contains("Nock")
	inst.free()


# ============================================================================
# 3. 体素尺寸对齐 1px = 1/32m
# ============================================================================

func test_arrow_boxes_are_voxel_aligned() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	for mi in _collect_meshes(inst):
		var box := mi.mesh as BoxMesh
		assert_object(box).is_not_null()
		for size_val in [box.size.x, box.size.y, box.size.z]:
			assert_bool(_is_voxel_aligned(size_val)) \
				.override_failure_message("%s 尺寸未对齐 1px=1/32m: %s" % [mi.name, str(box.size)]) \
				.is_true()
	inst.free()

func test_bolt_boxes_are_voxel_aligned() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	for mi in _collect_meshes(inst):
		var box := mi.mesh as BoxMesh
		assert_object(box).is_not_null()
		for size_val in [box.size.x, box.size.y, box.size.z]:
			assert_bool(_is_voxel_aligned(size_val)) \
				.override_failure_message("%s 尺寸未对齐 1px=1/32m: %s" % [mi.name, str(box.size)]) \
				.is_true()
	inst.free()


# ============================================================================
# 4. 单一附着组件（面接触验证）
# ============================================================================

func test_arrow_boxes_form_one_attached_component() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	var boxes := _voxel_boxes(_collect_meshes(inst))
	assert_int(boxes.size()).is_greater_equal(1)
	assert_int(_count_attached_components(boxes)) \
		.override_failure_message("体素箭矢存在分离体素块；所有静态体素必须通过面接触附着成一个整体") \
		.is_equal(1)
	inst.free()

func test_bolt_boxes_form_one_attached_component() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	var boxes := _voxel_boxes(_collect_meshes(inst))
	assert_int(boxes.size()).is_greater_equal(1)
	assert_int(_count_attached_components(boxes)) \
		.override_failure_message("体素弩箭存在分离体素块；所有静态体素必须通过面接触附着成一个整体") \
		.is_equal(1)
	inst.free()


# ============================================================================
# 5. 无正体积重叠
# ============================================================================

func test_arrow_boxes_do_not_overlap_positive_volume() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	var boxes := _voxel_boxes(_collect_meshes(inst))
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_bool(_boxes_overlap_with_positive_volume(boxes[i], boxes[j])) \
				.override_failure_message("箭矢体素盒不能正体积重叠: %s vs %s" % [boxes[i].name, boxes[j].name]) \
				.is_false()
	inst.free()

func test_bolt_boxes_do_not_overlap_positive_volume() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	var boxes := _voxel_boxes(_collect_meshes(inst))
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_bool(_boxes_overlap_with_positive_volume(boxes[i], boxes[j])) \
				.override_failure_message("弩箭体素盒不能正体积重叠: %s vs %s" % [boxes[i].name, boxes[j].name]) \
				.is_false()
	inst.free()


# ============================================================================
# 6. 箭头朝向 -Z（飞行方向）
# ============================================================================

func test_arrow_arrowhead_is_at_negative_z() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	var tip := _find_mesh(inst, "ArrowheadTip")
	assert_object(tip).is_not_null()
	# 箭头尖端应在 -Z 方向
	assert_float(tip.position.z).is_less(0.0)
	var nock := _find_mesh(inst, "Nock")
	assert_object(nock).is_not_null()
	# 箭尾应在 +Z 方向
	assert_float(nock.position.z).is_greater(0.0)
	inst.free()

func test_bolt_tip_is_at_negative_z() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	var tip := _find_mesh(inst, "BoltTip")
	assert_object(tip).is_not_null()
	assert_float(tip.position.z).is_less(0.0)
	var nock := _find_mesh(inst, "Nock")
	assert_object(nock).is_not_null()
	assert_float(nock.position.z).is_greater(0.0)
	inst.free()


# ============================================================================
# 7. 弩箭比箭矢更短、箭头更宽
# ============================================================================

func test_bolt_is_shorter_than_arrow() -> void:
	var arrow := _instantiate_arrow()
	add_child(arrow)
	await await_idle_frame()
	var bolt := _instantiate_bolt()
	add_child(bolt)
	await await_idle_frame()
	var arrow_len := _model_length_z(arrow)
	var bolt_len := _model_length_z(bolt)
	assert_float(bolt_len).is_less(arrow_len)
	arrow.free()
	bolt.free()

func test_bolt_base_is_wider_than_arrow_head() -> void:
	var arrow := _instantiate_arrow()
	add_child(arrow)
	await await_idle_frame()
	var bolt := _instantiate_bolt()
	add_child(bolt)
	await await_idle_frame()
	var arrow_base := _find_mesh(arrow, "ArrowheadBase")
	var bolt_base := _find_mesh(bolt, "BoltBase")
	assert_object(arrow_base).is_not_null()
	assert_object(bolt_base).is_not_null()
	var arrow_box := arrow_base.mesh as BoxMesh
	var bolt_box := bolt_base.mesh as BoxMesh
	assert_float(bolt_box.size.x).is_greater(arrow_box.size.x)
	arrow.free()
	bolt.free()


# ============================================================================
# 8. 材质使用 toon 着色
# ============================================================================

func test_arrow_materials_use_toon_shading() -> void:
	var inst := _instantiate_arrow()
	add_child(inst)
	await await_idle_frame()
	for mi in _collect_meshes(inst):
		var mat := mi.material_override as StandardMaterial3D
		assert_object(mat).is_not_null()
		assert_int(mat.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
		assert_int(mat.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
	inst.free()

func test_bolt_materials_use_toon_shading() -> void:
	var inst := _instantiate_bolt()
	add_child(inst)
	await await_idle_frame()
	for mi in _collect_meshes(inst):
		var mat := mi.material_override as StandardMaterial3D
		assert_object(mat).is_not_null()
		assert_int(mat.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
		assert_int(mat.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
	inst.free()


# ============================================================================
# 9. ProjectileService visual_scene 验证
# ============================================================================

func test_arrow_projectile_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	assert_object(ps).is_not_null()
	var arrow: Resource = ps.get_data("arrow")
	assert_object(arrow).is_not_null()
	assert_object(arrow.visual_scene).is_not_null()

func test_bolt_projectile_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	assert_object(ps).is_not_null()
	var bolt: Resource = ps.get_data("bolt")
	assert_object(bolt).is_not_null()
	assert_object(bolt.visual_scene).is_not_null()

func test_piercing_arrow_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	var pierce: Resource = ps.get_data("piercing_arrow")
	assert_object(pierce).is_not_null()
	assert_object(pierce.visual_scene).is_not_null()

func test_barbed_bolt_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	var barbed: Resource = ps.get_data("barbed_bolt")
	assert_object(barbed).is_not_null()
	assert_object(barbed.visual_scene).is_not_null()

func test_volley_arrow_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	var volley: Resource = ps.get_data("volley_arrow")
	assert_object(volley).is_not_null()
	assert_object(volley.visual_scene).is_not_null()

func test_volley_bolt_has_visual_scene() -> void:
	var ps: Node = Service.projectile_service()
	var volley: Resource = ps.get_data("volley_bolt")
	assert_object(volley).is_not_null()
	assert_object(volley.visual_scene).is_not_null()


# ============================================================================
# 10. ModelViewer 包含 Projectiles 扫描
# ============================================================================

func test_model_viewer_source_has_projectiles_scan() -> void:
	var source: String = load("res://scenes/ui/model_viewer.gd").source_code
	assert_bool(source.contains("_scan_projectile_scenes")) \
		.override_failure_message("模型图鉴源码必须包含投射物扫描方法") \
		.is_true()
	assert_bool(source.contains("Projectiles")) \
		.override_failure_message("模型图鉴源码必须包含 Projectiles 分类") \
		.is_true()
	assert_bool(source.contains("res://assets/meshes/projectiles/")) \
		.override_failure_message("模型图鉴源码必须扫描投射物目录") \
		.is_true()

func test_projectiles_directory_exists() -> void:
	var dir := DirAccess.open("res://assets/meshes/projectiles/")
	assert_object(dir) \
		.override_failure_message("投射物模型目录不存在: res://assets/meshes/projectiles/") \
		.is_not_null()

func test_projectiles_dir_has_scene_files() -> void:
	var count := _count_tscns_in_projectiles_dir("res://assets/meshes/projectiles/")
	assert_int(count).is_greater_equal(2)


# ============================================================================
# 辅助函数
# ============================================================================

func _instantiate_arrow() -> Node3D:
	var scene := load(ARROW_SCENE_PATH) as PackedScene
	return scene.instantiate()

func _instantiate_bolt() -> Node3D:
	var scene := load(BOLT_SCENE_PATH) as PackedScene
	return scene.instantiate()

func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.get_children():
		result.append_array(_collect_meshes(child))
	return result

func _collect_mesh_names(root: Node) -> Array[String]:
	var result: Array[String] = []
	for mi in _collect_meshes(root):
		result.append(String(mi.name))
	return result

func _find_mesh(root: Node, name: String) -> MeshInstance3D:
	for mi in _collect_meshes(root):
		if String(mi.name) == name:
			return mi
	return null

func _model_length_z(root: Node) -> float:
	var boxes := _voxel_boxes(_collect_meshes(root))
	if boxes.is_empty():
		return 0.0
	var min_z: int = boxes[0]["min"].z
	var max_z: int = boxes[0]["max"].z
	for box in boxes:
		min_z = min(min_z, box["min"].z)
		max_z = max(max_z, box["max"].z)
	return float(max_z - min_z) / 64.0  # 转换回米（_voxel_boxes 使用 64 倍缩放）

func _voxel_boxes(meshes: Array[MeshInstance3D]) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for mi in meshes:
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		var min_v := (mi.global_position + aabb.position) * 64.0
		var max_v := (mi.global_position + aabb.position + aabb.size) * 64.0
		boxes.append({
			"name": String(mi.name),
			"min": Vector3i(roundi(min_v.x), roundi(min_v.y), roundi(min_v.z)),
			"max": Vector3i(roundi(max_v.x), roundi(max_v.y), roundi(max_v.z)),
		})
	return boxes

func _count_attached_components(boxes: Array[Dictionary]) -> int:
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
	var amin: Vector3i = a["min"]
	var amax: Vector3i = a["max"]
	var bmin: Vector3i = b["min"]
	var bmax: Vector3i = b["max"]
	var overlaps := [
		mini(amax.x, bmax.x) - maxi(amin.x, bmin.x),
		mini(amax.y, bmax.y) - maxi(amin.y, bmin.y),
		mini(amax.z, bmax.z) - maxi(amin.z, bmin.z),
	]
	var positive_axes := 0
	var touching_axes := 0
	for overlap in overlaps:
		if overlap > 0:
			positive_axes += 1
		elif overlap == 0:
			touching_axes += 1
		else:
			return false
	return positive_axes == 3 or (positive_axes == 2 and touching_axes == 1)

func _boxes_overlap_with_positive_volume(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3i = a["min"]
	var amax: Vector3i = a["max"]
	var bmin: Vector3i = b["min"]
	var bmax: Vector3i = b["max"]
	return mini(amax.x, bmax.x) - maxi(amin.x, bmin.x) > 0 \
		and mini(amax.y, bmax.y) - maxi(amin.y, bmin.y) > 0 \
		and mini(amax.z, bmax.z) - maxi(amin.z, bmin.z) > 0

func _is_voxel_aligned(value: float) -> bool:
	return is_equal_approx(value * 32.0, roundf(value * 32.0))

func _count_tscns_in_projectiles_dir(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tscn") and not fn.ends_with(".import"):
			count += 1
		fn = dir.get_next()
	dir.list_dir_end()
	return count
