class_name CombatHitboxBuilder

const HITBOX_NAME := "CombatHitbox"
const MIN_MODEL_HITBOX_SIZE := Vector3(0.18, 0.18, 0.18)

static func ensure_hitbox(owner: Node3D, attach_to: Node3D, fallback_reach: float, target_mask: int) -> Area3D:
	var parent := attach_to if attach_to != null else owner
	var hitbox := parent.get_node_or_null(HITBOX_NAME) as Area3D
	if hitbox == null:
		hitbox = Area3D.new()
		hitbox.name = HITBOX_NAME
		hitbox.monitoring = false
		hitbox.monitorable = false
		parent.add_child(hitbox)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		hitbox.add_child(col)
	hitbox.collision_layer = 0
	hitbox.collision_mask = target_mask
	_configure_shape(hitbox, owner, parent, fallback_reach)
	return hitbox

static func set_active(hitbox: Area3D, active: bool) -> void:
	if hitbox == null or not is_instance_valid(hitbox):
		return
	hitbox.monitoring = active
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = not active

static func _configure_shape(hitbox: Area3D, owner: Node3D, parent: Node3D, fallback_reach: float) -> void:
	var col := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var aabb := _combined_mesh_aabb(parent)
	var shape := BoxShape3D.new()
	if aabb.size != Vector3.ZERO:
		shape.size = Vector3(
			maxf(aabb.size.x, MIN_MODEL_HITBOX_SIZE.x),
			maxf(aabb.size.y, MIN_MODEL_HITBOX_SIZE.y),
			maxf(aabb.size.z, MIN_MODEL_HITBOX_SIZE.z)
		)
		col.position = aabb.get_center()
	else:
		var reach := maxf(fallback_reach, 0.8)
		shape.size = Vector3(0.45, 0.7, reach)
		col.position = Vector3(0, 0.9, -reach * 0.5) if parent == owner else Vector3.ZERO
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
