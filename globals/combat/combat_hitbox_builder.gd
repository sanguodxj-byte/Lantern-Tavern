class_name CombatHitboxBuilder

const HITBOX_NAME := "CombatHitbox"
const MIN_MODEL_HITBOX_SIZE := Vector3(0.18, 0.18, 0.18)
## hitbox 默认宽高（角色本地空间，不依赖武器网格旋转）
const HITBOX_DEFAULT_WIDTH := 0.7
const HITBOX_DEFAULT_HEIGHT := 1.6
## hitbox 中心 Y 偏移（角色胸部高度）
const HITBOX_CENTER_Y := 0.9
## 武器 reach 值到实际攻击距离(米)的缩放因子。
## weapons.json 中的 reach 是设计单位（如短剑2.5、长矛4.0），
## 乘以此系数后得到合理的 hitbox 深度（短剑1.75m、长矛2.8m）。
const REACH_SCALE := 0.7

## 创建/复用攻击 hitbox。
## hitbox 始终挂在 owner（角色 CharacterBody3D）上，确保 Z 轴 = 角色前方（-Z），
## 不跟随武器骨骼旋转。武器网格（attach_to）仅用于查询 X/Y 尺寸参考。
static func ensure_hitbox(owner: Node3D, attach_to: Node3D, fallback_reach: float, target_mask: int) -> Area3D:
	# hitbox 始终挂在 owner 上，而非武器骨骼节点
	var hitbox := owner.get_node_or_null(HITBOX_NAME) as Area3D
	if hitbox == null:
		hitbox = Area3D.new()
		hitbox.name = HITBOX_NAME
		hitbox.monitoring = false
		hitbox.monitorable = false
		owner.add_child(hitbox)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		hitbox.add_child(col)
	elif hitbox.get_parent() != owner:
		# 旧版可能挂在武器节点上，迁移到 owner
		hitbox.reparent(owner)
	hitbox.collision_layer = 0
	hitbox.collision_mask = target_mask
	_configure_shape(hitbox, owner, attach_to, fallback_reach)
	return hitbox

static func set_active(hitbox: Area3D, active: bool) -> void:
	if hitbox == null or not is_instance_valid(hitbox):
		return
	hitbox.monitoring = active
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = not active

## 配置 hitbox 形状。
## hitbox 挂在 owner 上，Z 轴 = 角前方（-Z），从角色中心向前延伸 reach 距离。
## 武器网格 AABB 仅用于 X/Y 尺寸参考（取较大值），不再决定 Z 深度或位置。
static func _configure_shape(hitbox: Area3D, owner: Node3D, weapon_model: Node3D, fallback_reach: float) -> void:
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var reach := maxf(fallback_reach, 0.8)
	var shape := BoxShape3D.new()
	# X/Y 宽高：默认值确保覆盖人体目标，武器网格仅作最小值参考
	var width := HITBOX_DEFAULT_WIDTH
	var height := HITBOX_DEFAULT_HEIGHT
	if weapon_model != null:
		var aabb := _combined_mesh_aabb(weapon_model)
		if aabb.size != Vector3.ZERO:
			width = maxf(aabb.size.x, MIN_MODEL_HITBOX_SIZE.x)
			height = maxf(aabb.size.y, MIN_MODEL_HITBOX_SIZE.y)
	shape.size = Vector3(width, height, reach)
	# 位置：从角色胸部高度向前延伸 reach 距离
	col.position = Vector3(0, HITBOX_CENTER_Y, -reach * 0.5)
	col.shape = shape
	col.disabled = not hitbox.monitoring

static func _combined_mesh_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var initialized := false
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var parent_space := root.global_transform.affine_inverse() * mi.global_transform
		var transformed := parent_space * mi.get_aabb()
		if initialized:
			combined = combined.merge(transformed)
		else:
			combined = transformed
			initialized = true
	return combined if initialized else AABB()
