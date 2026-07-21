extends GdUnitTestSuite

## P1 体素道具网格合并回归测试（对齐 godot-voxel VoxelMesherBlocky：同材质方块合并为单个网格）。
## 每个体素方块原先是一个独立 MeshInstance3D(draw call)；合并后每材质仅 1 个合并网格。

const TORCH_SCENE := preload("res://scenes/props/torch/torch.tscn")
const VOXEL_PROP_PATH := "res://scenes/props/voxel_prop.gd"


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


## 只统计 P1 合并的「细节网格」(VoxelMesh_%d)，排除 P5 的 LOD 替身(VoxelMeshLOD_%d)。
func _count_detail_meshes(node: Node) -> int:
	var n := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).name.contains("LOD"):
			continue
		n += 1
	return n


func test_barrel_merges_to_one_mesh_per_material() -> void:
	var prop := VoxelProp.new()
	prop.prop_kind = "barrel"
	prop.rebuild()
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	# barrel 用 3 种材质(wood_dark/wood/iron) → 合并后应为 3 个细节网格（原 35 个方块）
	assert_int(_count_detail_meshes(prop)).is_equal(3)
	for mi in meshes:
		assert_bool(mi.get_meta("voxel_generated", false)).is_true()
	prop.free()


func test_table_merges_to_two_meshes() -> void:
	var prop := VoxelProp.new()
	prop.prop_kind = "table"
	prop.rebuild()
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	# table 用 wood + wood_dark 两种材质 → 2 个细节网格（原 9 个方块）
	assert_int(_count_detail_meshes(prop)).is_equal(2)
	prop.free()


func test_torch_scene_merges_and_keeps_light() -> void:
	var torch := TORCH_SCENE.instantiate()
	add_child(torch)  # 进场景树触发 _ready → VoxelProp.rebuild() 构建合并网格 + 点光源
	# 合并后整个火把场景的细节网格应 <=2（iron + wood_dark 两种材质，原 19 个方块）
	var meshes := torch.find_children("*", "MeshInstance3D", true, false)
	assert_int(_count_detail_meshes(torch)).is_less_equal(2)
	# 实时阴影点光源必须保留（P4 修复隔墙漏光的关键），不能因合并被误删
	var light := torch.find_child("OmniLight3D", true, false)
	assert_object(light).is_not_null()
	torch.free()


func test_voxel_prop_uses_surface_tool_merge() -> void:
	var src := _read_source(VOXEL_PROP_PATH)
	assert_bool(src.contains("func _finalize_meshes")).is_true()
	assert_bool(src.contains("SurfaceTool")).is_true()
	assert_bool(src.contains("_pending_boxes")).is_true()


## P5 大模型道具距离 LOD：堆一个远超阈值的大道具，应同时生成「细节合并网格」与「LOD 盒」，
## 且 LOD 盒在 VOXEL_LOD_FAR(25m) 处才开始显示、与细节网格交叉淡出。
func test_large_prop_generates_lod_box() -> void:
	var prop := VoxelProp.new()
	var mat := StandardMaterial3D.new()
	# 堆一个 ~3m 高的柱状体素（单一材质）；VOXEL_LOD_MIN_SIZE=1.5，应触发 LOD。
	# 直接调 _finalize_meshes（不经 rebuild，避免 _clear_generated 清空手动写入的 _pending_boxes）。
	for y in range(0, 100):
		prop._box("b%d" % y, Vector3i(8, 8, 8), Vector3(0, y, 0), mat)
	prop._finalize_meshes()
	var detail := 0
	var lod_mi: MeshInstance3D = null
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.contains("LOD"):
			lod_mi = m
		else:
			detail += 1
	assert_int(detail).is_equal(1) \
		.override_failure_message("大模型道具应合并为 1 个细节网格")
	assert_object(lod_mi).is_not_null() \
		.override_failure_message("大模型道具应生成 1 个 LOD 替身盒(VoxelMeshLOD_*)")
	assert_float(lod_mi.visibility_range_begin).is_equal_approx(25.0, 0.001) \
		.override_failure_message("LOD 替身应在 25m(VOXEL_LOD_FAR)处开始显示")
	assert_float(lod_mi.visibility_range_begin_margin).is_equal_approx(6.0, 0.001) \
		.override_failure_message("LOD 替身应设可见范围淡入边距")
	prop.free()
