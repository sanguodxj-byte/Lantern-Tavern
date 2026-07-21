extends GdUnitTestSuite

## 酒桶（barrel.tscn）物理碰撞回归测试。
## 根因：barrel.tscn 的根是 RigidBody3D（PickableItem），其子节点 BarrelVisual 又是
## StaticBody3D（VoxelProp）。两者都会生成碰撞箱，空间重叠且父刚体掩码包含子静态体所在
## 层 -> 物体一运行就被物理求解器弹飞。修复后 VoxelProp 在动态刚体下不再叠加碰撞体，
## 仅由根 RigidBody3D 提供碰撞，酒桶可正常静置在地面上。

const BARREL_SCENE := preload("res://scenes/props/barrel/barrel.tscn")


func _count_collision_shapes(node: Node) -> int:
	var count := 0
	if node is CollisionShape3D:
		count += 1
	for c in node.get_children():
		count += _count_collision_shapes(c)
	return count


func _find_node(node: Node, name_sub: String) -> Node:
	if node.name.contains(name_sub):
		return node
	for c in node.get_children():
		var found := _find_node(c, name_sub)
		if found != null:
			return found
	return null


func test_barrel_has_exactly_one_collision_shape() -> void:
	# Arrange + Act: 实例化并进入场景树以触发 _ready() 构建动态内容
	var barrel: Node3D = BARREL_SCENE.instantiate()
	add_child(barrel)
	# Assert: 只有根 RigidBody3D 提供一个碰撞体；VoxelProp 子节点不应再叠加静态碰撞体
	assert_int(_count_collision_shapes(barrel)).is_equal(1)
	barrel.free()


func test_barrel_visual_voxel_prop_adds_no_collision_shape() -> void:
	# Arrange + Act
	var barrel: Node3D = BARREL_SCENE.instantiate()
	add_child(barrel)
	var visual := _find_node(barrel, "BarrelVisual")
	assert_object(visual).is_not_null()
	# Assert: VoxelProp 子节点（StaticBody3D）在动态刚体下不应生成独立碰撞体
	var child_shapes := 0
	for c in visual.get_children():
		if c is CollisionShape3D:
			child_shapes += 1
	assert_int(child_shapes).is_equal(0)
	barrel.free()


func test_barrel_rigidbody_keeps_valid_collision_shape() -> void:
	# Arrange + Act
	var barrel: Node3D = BARREL_SCENE.instantiate()
	add_child(barrel)
	var body := barrel as PickableItem
	assert_object(body).is_not_null()
	# Assert: 根刚体仍有可用碰撞箱（由 pickable_item.gd 依据体素网格生成）
	var shape: Shape3D = body.collision_shape.shape
	assert_object(shape).is_not_null()
	assert_bool(shape is BoxShape3D).is_true()
	barrel.free()
