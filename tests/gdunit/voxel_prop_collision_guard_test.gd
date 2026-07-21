extends GdUnitTestSuite

## 回归测试：VoxelProp 只有在「不挂在动态刚体之下」时才生成自己的静态碰撞体。
## 挂在 RigidBody3D（直接子节点或更深层的祖先）之下时，碰撞由该刚体自身提供，
## 此处若叠加独立静态碰撞体会与父刚体自碰撞弹飞（酒桶一运行就飞走的 bug）。


func test_voxel_prop_direct_child_of_rigid_body_skips_collision() -> void:
	# Arrange: RigidBody3D -> VoxelProp（与 barrel.tscn 的层级一致）
	var rb := RigidBody3D.new()
	var prop := VoxelProp.new()
	prop.prop_kind = "barrel"
	rb.add_child(prop)
	add_child(rb)
	# Assert: 不生成任何 CollisionShape3D（碰撞交给父刚体）
	var shapes := prop.find_children("*", "CollisionShape3D", true, false)
	assert_array(shapes).is_empty()
	rb.free()


func test_voxel_prop_deeply_nested_under_rigid_body_skips_collision() -> void:
	# Arrange: RigidBody3D -> Node3D（中间层） -> VoxelProp（深层嵌套，守卫必须向上遍历祖先）
	var rb := RigidBody3D.new()
	var inter := Node3D.new()
	rb.add_child(inter)
	var prop := VoxelProp.new()
	prop.prop_kind = "chair"
	inter.add_child(prop)
	add_child(rb)
	# Assert: 即使不是直接子节点，只要祖先是 RigidBody3D 就跳过碰撞
	var shapes := prop.find_children("*", "CollisionShape3D", true, false)
	assert_array(shapes).is_empty()
	rb.free()


func test_standalone_voxel_prop_keeps_its_collision() -> void:
	# Arrange: VoxelProp 直接挂在普通 Node3D 下（静态装饰，如椅子/桌子/桶）
	var holder := Node3D.new()
	var prop := VoxelProp.new()
	prop.prop_kind = "chair"
	holder.add_child(prop)
	add_child(holder)
	# Assert: 独立摆放时照常生成一份静态碰撞体（守卫不能过度跳过）
	var shapes := prop.find_children("*", "CollisionShape3D", true, false)
	assert_int(shapes.size()).is_equal(1)
	holder.free()
