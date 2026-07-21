extends GdUnitTestSuite
## 攻击 hitbox 攻击范围测试
## 验证：hitbox 始终挂在 owner 上，Z 轴延伸到 fallback_reach，位置从角色中心向前

const HITBOX_BUILDER := preload("res://globals/combat/combat_hitbox_builder.gd")

## 创建一个模拟体素武器的节点：网格从 z=0.1（握柄）延伸到 z=-0.6（刀尖），总长 0.7m
func _create_small_weapon_model() -> Node3D:
	var weapon := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.05, 0.7)
	mi.mesh = box
	mi.position = Vector3(0, 0, -0.25)
	weapon.add_child(mi)
	return weapon

func test_hitbox_always_attached_to_owner() -> void:
	# Arrange
	var owner := Node3D.new()
	add_child(owner)
	var weapon_model := _create_small_weapon_model()
	owner.add_child(weapon_model)

	# Act
	var hitbox := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, 2.0, 0)

	# Assert: hitbox 的父节点应该是 owner，而非 weapon_model
	assert_object(hitbox.get_parent()).is_equal(owner)

	# Cleanup
	owner.queue_free()

func test_hitbox_z_size_equals_fallback_reach() -> void:
	# Arrange
	var owner := Node3D.new()
	add_child(owner)
	var weapon_model := _create_small_weapon_model()
	owner.add_child(weapon_model)
	var fallback_reach := 3.0

	# Act
	var hitbox := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, fallback_reach, 0)
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := col.shape as BoxShape3D

	# Assert: Z 尺寸 = fallback_reach（不再被 sqrt 压缩，不再被网格尺寸截断）
	assert_float(shape.size.z).is_equal_approx(fallback_reach, 0.01)

	# Cleanup
	owner.queue_free()

func test_hitbox_position_extends_forward_from_owner_center() -> void:
	# Arrange
	var owner := Node3D.new()
	add_child(owner)
	var weapon_model := _create_small_weapon_model()
	owner.add_child(weapon_model)
	var fallback_reach := 2.5

	# Act
	var hitbox := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, fallback_reach, 0)
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D

	# Assert: 位置在角色胸部前方
	# Z 中心 = -reach * 0.5 = -1.25
	assert_float(col.position.z).is_equal_approx(-fallback_reach * 0.5, 0.01)
	# Y 中心 = HITBOX_CENTER_Y (0.9)
	assert_float(col.position.y).is_equal_approx(0.9, 0.01)
	# X 中心 = 0
	assert_float(col.position.x).is_equal_approx(0.0, 0.01)

	# Cleanup
	owner.queue_free()

func test_hitbox_far_edge_reaches_fallback_reach() -> void:
	# Arrange
	var owner := Node3D.new()
	add_child(owner)
	var weapon_model := _create_small_weapon_model()
	owner.add_child(weapon_model)
	var fallback_reach := 3.0

	# Act
	var hitbox := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, fallback_reach, 0)
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := col.shape as BoxShape3D

	# Assert: hitbox 最远端（刀尖方向）应达到 -fallback_reach
	var z_far := col.position.z - shape.size.z * 0.5
	assert_float(z_far).is_equal_approx(-fallback_reach, 0.01)

	# Cleanup
	owner.queue_free()

func test_hitbox_fallback_when_no_weapon_model() -> void:
	# Arrange: 无武器网格
	var owner := Node3D.new()
	add_child(owner)
	var fallback_reach := 1.5

	# Act: attach_to = null
	var hitbox := HITBOX_BUILDER.ensure_hitbox(owner, null, fallback_reach, 0)
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := col.shape as BoxShape3D

	# Assert: 使用默认宽高 + fallback reach
	assert_float(shape.size.z).is_equal_approx(1.5, 0.01)
	assert_float(shape.size.x).is_equal_approx(HITBOX_BUILDER.HITBOX_DEFAULT_WIDTH, 0.01)
	assert_float(shape.size.y).is_equal_approx(HITBOX_BUILDER.HITBOX_DEFAULT_HEIGHT, 0.01)
	assert_object(hitbox.get_parent()).is_equal(owner)

	# Cleanup
	owner.queue_free()

func test_hitbox_reuses_existing_node_on_owner() -> void:
	# Arrange
	var owner := Node3D.new()
	add_child(owner)
	var weapon_model := _create_small_weapon_model()
	owner.add_child(weapon_model)

	# Act: 第一次调用创建 hitbox
	var hitbox1 := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, 2.0, 0)
	# 第二次调用应复用同一个 hitbox（不同 reach）
	var hitbox2 := HITBOX_BUILDER.ensure_hitbox(owner, weapon_model, 3.0, 0)

	# Assert: 同一个节点
	assert_object(hitbox2).is_equal(hitbox1)
	# 尺寸应更新为新的 reach
	var col := hitbox2.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := col.shape as BoxShape3D
	assert_float(shape.size.z).is_equal_approx(3.0, 0.01)

	# Cleanup
	owner.queue_free()

func test_source_code_has_owner_attached_hitbox() -> void:
	# 源码级断言：确保修复逻辑存在
	var source := _source("res://globals/combat/combat_hitbox_builder.gd")
	# hitbox 挂在 owner 上
	assert_bool(source.contains("owner.get_node_or_null(HITBOX_NAME)")).is_true()
	# 不再使用 attach_to 作为 parent
	assert_bool(source.contains("attach_to if attach_to != null else owner")).is_false()
	# 有固定宽高常量
	assert_bool(source.contains("HITBOX_DEFAULT_WIDTH")).is_true()
	assert_bool(source.contains("HITBOX_DEFAULT_HEIGHT")).is_true()
	# 位置从角色中心向前延伸
	assert_bool(source.contains("-reach * 0.5")).is_true()

func test_equipment_component_uses_reach_directly_not_sqrt() -> void:
	# 确保 sqrt 压缩已移除；允许 reach * REACH_SCALE 后的下限钳制
	var source := _source("res://scenes/characters/component/equipment_component.gd")
	assert_bool(source.contains("sqrt(weapon_data.reach)")).is_false()
	assert_bool(source.contains("maxf(weapon_data.reach")).is_true()
	assert_bool(source.contains("0.8")).is_true()

static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
