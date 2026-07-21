extends GdUnitTestSuite

## PickableItem.pop_out 物理爆出测试（Barony 风格死亡掉落）。
## 验证：施加冲量后物体获得明显速度，并在水平方向被推离源点散开。

const PICKABLE := preload("res://scenes/equipment/pickable_item.tscn")


func test_pop_out_applies_burst_velocity() -> void:
	var item := PICKABLE.instantiate() as PickableItem
	item.material_id = "goblin_ear"
	var level := Node3D.new()
	add_child(level)
	level.add_child(item)
	await get_tree().physics_frame   # _ready + 落入静止
	var start := item.global_position
	item.pop_out(level.global_position, 4.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 冲量应使物体获得明显速度
	assert_float(item.linear_velocity.length()).is_greater(1.0)
	# 水平方向应被推离源点（爆出散开，而非仅受重力下落）
	var horiz := Vector2(item.global_position.x - start.x, item.global_position.z - start.z).length()
	assert_float(horiz).is_greater(0.03)
	item.queue_free()
	level.queue_free()


func test_pop_out_no_tree_is_safe() -> void:
	# 未进树的物体调用 pop_out 不应崩溃（直接 return）
	var item := PICKABLE.instantiate() as PickableItem
	item.material_id = "goblin_ear"
	item.pop_out(Vector3.ZERO, 4.0)
	item.free()
	assert_bool(true).is_true()
