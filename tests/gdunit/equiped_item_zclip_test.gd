extends GdUnitTestSuite

## 回归测试：EquipedItem 的 z-clip 材质处理。
## 背景：equiped_item.gd 原先用 ZCLIP_MATERIAL.duplicate() 作为 material_override，
## 该材质无 albedo 纹理/颜色，导致武器 GLB 内嵌纹理被白色方块覆盖。
## 修复后：z-clip 属性叠加到已有材质副本上，保留纹理，仅添加 depth bias。

const EQUIPED_ITEM_SCRIPT := "res://scenes/equipment/equiped_item.gd"
const ZCLIP_MATERIAL_PATH := "res://materials/zclip_material.tres"

# ---------- 源码静态检查 ----------

func test_source_no_longer_uses_blank_zclip_override() -> void:
	var source: String = (load(EQUIPED_ITEM_SCRIPT) as GDScript).source_code
	# 不应再用空白 ZCLIP_MATERIAL 直接覆盖 material_override
	assert_bool(source.find("material_override = ZCLIP_MATERIAL") == -1) \
		.override_failure_message("不应再用空白 ZCLIP_MATERIAL 覆盖 material_override，会丢失纹理") \
		.is_true()

func test_source_has_zclip_recursive_method() -> void:
	var source: String = (load(EQUIPED_ITEM_SCRIPT) as GDScript).source_code
	assert_bool(source.find("_apply_z_clip_recursive") != -1) \
		.override_failure_message("应包含 _apply_z_clip_recursive 方法") \
		.is_true()
	assert_bool(source.find("_apply_z_clip_to_mesh") != -1) \
		.override_failure_message("应包含 _apply_z_clip_to_mesh 方法") \
		.is_true()

func test_source_calls_zclip_in_ready() -> void:
	var source: String = (load(EQUIPED_ITEM_SCRIPT) as GDScript).source_code
	var ready_start := source.find("func _ready()")
	assert_int(ready_start).is_greater(-1)
	var next_func := source.find("\nfunc ", ready_start + 5)
	var ready_block: String
	if next_func > 0:
		ready_block = source.substr(ready_start, next_func - ready_start)
	else:
		ready_block = source.substr(ready_start)
	assert_bool(ready_block.find("_apply_z_clip_recursive") != -1) \
		.override_failure_message("_ready() 应在 is_always_in_front 时调用 _apply_z_clip_recursive") \
		.is_true()

# ---------- ZCLIP 材质属性检查 ----------

func test_zclip_material_has_z_clip_scale() -> void:
	var mat := load(ZCLIP_MATERIAL_PATH) as StandardMaterial3D
	assert_object(mat).is_not_null()
	assert_bool(mat.use_z_clip_scale) \
		.override_failure_message("ZCLIP_MATERIAL 应启用 use_z_clip_scale") \
		.is_true()

# ---------- 行为测试：z-clip 叠加到已有材质 ----------

func test_apply_z_clip_preserves_albedo_texture() -> void:
	var item := _create_equiped_item_with_test_mesh()
	add_child(item)
	# VoxelLightingAdapter 在 headless 模式下跳过，手动创建材质
	var mesh_inst := _find_first_mesh(item)
	assert_object(mesh_inst).is_not_null()
	if mesh_inst == null:
		item.free()
		return
	# 模拟 GLB 内嵌材质：设置 albedo_color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.1)
	mesh_inst.set_surface_override_material(0, mat)
	# 调用 z-clip 应用
	item.call("_apply_z_clip_to_mesh", mesh_inst)
	var result := mesh_inst.get_surface_override_material(0) as StandardMaterial3D
	assert_object(result).is_not_null()
	assert_bool(result.use_z_clip_scale) \
		.override_failure_message("叠加后材质应启用 z-clip") \
		.is_true()
	# albedo_color 应保留（不变成白色）
	assert_float(result.albedo_color.r).is_equal_approx(0.8, 0.001)
	assert_float(result.albedo_color.g).is_equal_approx(0.2, 0.001)
	assert_float(result.albedo_color.b).is_equal_approx(0.1, 0.001)
	item.free()

func test_apply_z_clip_recursive_processes_all_meshes() -> void:
	var item := _create_equiped_item_with_test_mesh()
	add_child(item)
	# 给第一个 mesh 设置材质
	var meshes0: Array = item.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes0.size()).is_equal(1)
	var mi1 := meshes0[0] as MeshInstance3D
	var mat1 := StandardMaterial3D.new()
	mat1.albedo_color = Color(0.5, 0.3, 0.1)
	mi1.set_surface_override_material(0, mat1)
	# 添加第二个 mesh
	var root := Node3D.new()
	item.add_child(root)
	var mi2 := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	mi2.mesh = box
	root.add_child(mi2)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.1, 0.5, 0.9)
	mi2.set_surface_override_material(0, mat2)
	# 递归应用
	item.call("_apply_z_clip_recursive", item)
	# 检查所有 mesh 的材质都有 z-clip
	var meshes: Array = item.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(2)
	for m in meshes:
		var mi := m as MeshInstance3D
		var mat := mi.get_surface_override_material(0) as StandardMaterial3D
		assert_object(mat).is_not_null()
		assert_bool(mat.use_z_clip_scale) \
			.override_failure_message("mesh %s 的材质应启用 z-clip" % mi.name) \
			.is_true()
	item.free()

func test_apply_z_clip_does_not_create_white_material() -> void:
	# 关键回归测试：确保 z-clip 不会生成纯白材质
	var item := _create_equiped_item_with_test_mesh()
	add_child(item)
	var mesh_inst := _find_first_mesh(item)
	if mesh_inst == null:
		item.free()
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 0.2)
	mat.albedo_texture = null  # 无纹理但有颜色
	mesh_inst.set_surface_override_material(0, mat)
	item.call("_apply_z_clip_to_mesh", mesh_inst)
	var result := mesh_inst.get_surface_override_material(0) as StandardMaterial3D
	assert_bool(result != null) \
		.override_failure_message("应有叠加后的材质") \
		.is_true()
	if result != null:
		# 白色 = Color(1,1,1)，确保不是白色
		assert_bool(result.albedo_color != Color.WHITE) \
			.override_failure_message("材质不应是纯白色（原始 albedo 应保留）") \
			.is_true()
	item.free()

# ---------- 辅助函数 ----------

func _create_equiped_item_with_test_mesh() -> Node:
	var script := load(EQUIPED_ITEM_SCRIPT) as GDScript
	var item := Node3D.new()
	item.set_script(script)
	item.set("is_always_in_front", true)
	# 创建带 mesh 的子节点模拟武器 GLB
	var visual := Node3D.new()
	visual.name = "WeaponVisual"
	item.add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	mi.mesh = box
	visual.add_child(mi)
	return item

func _find_first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null
