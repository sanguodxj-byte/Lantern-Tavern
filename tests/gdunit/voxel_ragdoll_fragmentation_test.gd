extends GdUnitTestSuite

## 体素碎裂（VoxelRagdoll）死亡效果修复测试。
##
## 验证两个关键修复：
## 1. 网格分块碎裂：单蒙皮模型（如 _rig.glb）只有 1 个 MeshInstance3D 时，
##    VoxelRagdoll 按模型 AABB 切分生成多个体素碎块（而非只有 1 个碎片）。
## 2. 逐网格碎裂：多个独立 MeshInstance3D（如独立体素盒）时，每盒一个碎片（保留原始行为）。
##
## 同时验证：原网格隐藏、碎片数不超上限、freeze 冻结、null 安全。

const VOXEL_RAGDOLL := preload("res://scenes/characters/component/voxel_ragdoll.gd")


func _make_box(name: String, pos: Vector3, size: Vector3 = Vector3(0.3, 0.3, 0.3)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.position = pos
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	return mi


func _make_large_mesh(name: String) -> MeshInstance3D:
	## 模拟 _rig.glb 中的单蒙皮网格：一个大 MeshInstance3D
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.position = Vector3.ZERO
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 1.8, 0.6)
	mi.mesh = box
	return mi


# ── 网格分块碎裂（单蒙皮模型）──────────────────────────────────────

func test_single_mesh_produces_multiple_fragments() -> void:
	# 单蒙皮网格 → 网格分块碎裂应生成多个碎片（>1）
	var source := Node3D.new()
	source.add_child(_make_large_mesh("Character"))
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 4.0)
	# 单网格应走分块碎裂，生成多个碎片
	assert_int(ragdoll.get_fragment_count()).is_greater(1)
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


func test_grid_fragments_are_rigid_bodies_with_mesh_and_collision() -> void:
	var source := Node3D.new()
	source.add_child(_make_large_mesh("Body"))
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 3.0)
	var fragments := source.get_parent().find_children("*", "RigidBody3D", true, false)
	assert_int(fragments.size()).is_greater(0)
	for f in fragments:
		var body := f as RigidBody3D
		# 每个碎片应带可视网格与碰撞体
		assert_int(body.find_children("*", "MeshInstance3D", true, false).size()).is_greater(0)
		assert_int(body.find_children("*", "CollisionShape3D", true, false).size()).is_greater(0)
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


func test_grid_fragment_count_within_max() -> void:
	# 极大网格也不应超过 MAX_FRAGMENTS
	var source := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "HugeMesh"
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 10.0, 10.0)
	mi.mesh = box
	source.add_child(mi)
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 5.0)
	assert_int(ragdoll.get_fragment_count()).is_less_equal(40)
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


# ── 逐网格碎裂（多体素盒模型）──────────────────────────────────────

func test_multiple_meshes_use_per_mesh_fragmentation() -> void:
	# 2+ 个独立网格 → 逐网格碎裂，每盒一个碎片
	var source := Node3D.new()
	source.add_child(_make_box("body", Vector3(0, 0.5, 0)))
	source.add_child(_make_box("head", Vector3(0, 1.0, 0)))
	source.add_child(_make_box("arm_l", Vector3(0.3, 0.6, 0)))
	source.add_child(_make_box("arm_r", Vector3(-0.3, 0.6, 0)))
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 4.0)
	# 4 个网格 → 4 个碎片（逐网格碎裂）
	assert_int(ragdoll.get_fragment_count()).is_equal(4)
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


# ── 原网格隐藏 ──────────────────────────────────────────────────────

func test_original_meshes_hidden_after_activate() -> void:
	var source := Node3D.new()
	var m1 := _make_large_mesh("Skin")
	source.add_child(m1)
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 4.0)
	# 原始网格应被隐藏
	assert_bool(m1.visible).is_false()
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


# ── freeze 冻结 ─────────────────────────────────────────────────────

func test_freeze_stops_grid_fragments() -> void:
	var source := Node3D.new()
	source.add_child(_make_large_mesh("Body"))
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 3.0)
	ragdoll.freeze()
	var fragments := source.get_parent().find_children("*", "RigidBody3D", true, false)
	assert_int(fragments.size()).is_greater(0)
	for f in fragments:
		var b := f as RigidBody3D
		# freeze 后刚体应被冻结
		assert_bool(b.freeze).is_true()
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


# ── 空源安全 ────────────────────────────────────────────────────────

func test_activate_empty_source_is_safe() -> void:
	var source := Node3D.new()
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3.ZERO, 1.0)  # 无网格 → 不应崩溃
	assert_int(ragdoll.get_fragment_count()).is_equal(0)
	source.queue_free()
	ragdoll.queue_free()


func test_get_fragment_count_starts_at_zero() -> void:
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	assert_int(ragdoll.get_fragment_count()).is_equal(0)
	ragdoll.queue_free()
