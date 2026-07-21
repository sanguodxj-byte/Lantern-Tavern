extends GdUnitTestSuite

## 体素敌人死亡碎裂（伪布娃娃）组件测试。
## 体素模型无 Skeleton3D，死亡时把每个 MeshInstance3D 盒子转为 RigidBody3D 碎片翻滚，
## 模拟布娃娃式死亡。本测试验证：碎片生成、原网格隐藏、冻结休眠、空源安全。

const VOXEL_RAGDOLL := preload("res://scenes/characters/component/voxel_ragdoll.gd")


func _make_box(name: String, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.position = pos
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mi.mesh = box
	return mi


func test_activate_spawns_fragments_and_hides_source() -> void:
	var source := Node3D.new()
	source.add_child(_make_box("body", Vector3(0, 0.5, 0)))
	source.add_child(_make_box("head", Vector3(0, 1.0, 0)))
	add_child(source)  # 加入测试场景树，使 get_tree()/global_transform 可用
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 4.0)
	# 每个盒子应生成一个 RigidBody3D 碎片（挂在 source 的父节点下）
	var fragments := source.get_parent().find_children("*", "RigidBody3D", true, false)
	assert_int(fragments.size()).is_equal(2)
	# 原网格已隐藏
	assert_bool(source.get_node("body").visible).is_false()
	assert_bool(source.get_node("head").visible).is_false()
	# 碎片均带可视网格与碰撞体
	for f in fragments:
		var body := f as RigidBody3D
		assert_int(body.find_children("*", "MeshInstance3D", true, false).size()).is_greater(0)
		assert_int(body.find_children("*", "CollisionShape3D", true, false).size()).is_greater(0)
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()


func test_activate_null_source_is_safe() -> void:
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(null, Vector3.ZERO, 1.0)  # 不应崩溃
	ragdoll.queue_free()
	assert_bool(true).is_true()


func test_freeze_sleeps_fragments() -> void:
	var source := Node3D.new()
	source.add_child(_make_box("a", Vector3.ZERO))
	add_child(source)
	var ragdoll := VOXEL_RAGDOLL.new()
	add_child(ragdoll)
	ragdoll.activate(source, Vector3(0, 1, 0), 3.0)
	ragdoll.freeze()
	var fragments := source.get_parent().find_children("*", "RigidBody3D", true, false)
	assert_int(fragments.size()).is_greater(0)
	# 物理服务端已将碎片置为休眠（headless 下 sleeping 属性不回写，故查服务端状态）
	for f in fragments:
		var b := f as RigidBody3D
		assert_bool(PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)).is_true()
	ragdoll.clear_fragments()
	source.queue_free()
	ragdoll.queue_free()
