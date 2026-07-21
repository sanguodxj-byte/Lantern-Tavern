class_name VoxelRagdoll
extends Node3D

## 体素敌人死亡碎裂（伪布娃娃）系统。
##
## 两种碎裂模式：
## 1. 逐网格碎裂：character 下有多个 MeshInstance3D（独立体素盒）时，每盒一个 RigidBody3D 碎片。
## 2. 网格分块碎裂：character 下只有少量网格（如 Blender 管线合并的单蒙皮 _rig.glb）时，
##    按模型 AABB 切分为多个体素碎块，每块一个 BoxMesh RigidBody3D，使用原始材质。
##
## 死亡时施加冲量让碎片翻滚坠落，模拟「尸体碎裂」表现；原角色可视网格隐藏。
## 与 EnemyStateDying / EnemyStateDead 协同。

const MAX_FRAGMENTS := 40
const FRAGMENT_LIFETIME := 8.0
## 当有效网格数 >= 此值时使用逐网格碎裂（独立体素盒模型）；否则使用网格分块碎裂（单蒙皮模型）。
const MIN_MESHES_FOR_PER_PART_FRAGMENT := 2
## 网格分块碎裂的目标碎片数。
const GRID_TARGET_FRAGMENTS := 14

var _fragments: Array[RigidBody3D] = []


func activate(source: Node3D, impact_dir: Vector3, impulse_strength: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	var valid_meshes: Array[MeshInstance3D] = []
	for m in meshes:
		if m != null and m.mesh != null:
			valid_meshes.append(m as MeshInstance3D)
	if valid_meshes.is_empty():
		return
	var strength := maxf(impulse_strength, 2.0)
	var dir := impact_dir
	if dir == Vector3.ZERO:
		dir = Vector3(0.0, 1.0, 0.0)
	else:
		dir = dir.normalized()
	var parent := source.get_parent()

	if valid_meshes.size() >= MIN_MESHES_FOR_PER_PART_FRAGMENT:
		# 多个独立体素盒 → 每盒一个碎片（原始行为）
		_fragment_per_mesh(valid_meshes, parent, dir, strength)
	else:
		# 少量网格（如单蒙皮 _rig.glb）→ AABB 分块碎裂
		_fragment_from_grid(valid_meshes, parent, dir, strength)

	# 隐藏所有原始可视网格
	for m in valid_meshes:
		m.visible = false

	# 碎片寿命后自动清理，避免刚体堆积
	var tree := source.get_tree()
	if tree != null:
		var timer := tree.create_timer(FRAGMENT_LIFETIME)
		timer.timeout.connect(clear_fragments)


## 逐网格碎裂：每个 MeshInstance3D 生成一个 RigidBody3D 碎片。
func _fragment_per_mesh(meshes: Array[MeshInstance3D], parent: Node, dir: Vector3, strength: float) -> void:
	var step := 1
	if meshes.size() > MAX_FRAGMENTS:
		step = int(ceil(float(meshes.size()) / float(MAX_FRAGMENTS)))
	for i in meshes.size():
		if i % step != 0:
			continue
		var mi := meshes[i]
		if mi.mesh == null:
			continue
		var body := _create_fragment_body(mi.mesh, _box_shape_for(mi), _get_material(mi))
		if parent != null:
			parent.add_child(body)
		else:
			add_child(body)
		# 加入父节点后再设全局变换，确保碎片定位与原始网格世界坐标一致
		body.global_transform = mi.global_transform
		_apply_fragment_impulse(body, dir, strength)
		_fragments.append(body)


## 网格分块碎裂：将模型的组合 AABB 切分为网格，每格生成一个 BoxMesh 碎片。
## 适用于 Blender 管线合并的单蒙皮 _rig.glb（只有 1~3 个 MeshInstance3D）。
func _fragment_from_grid(meshes: Array[MeshInstance3D], parent: Node, dir: Vector3, strength: float) -> void:
	# 计算所有网格在世界空间的组合 AABB，并选取最大网格的材质作为碎片材质
	var combined_aabb := AABB()
	var best_material: Material = null
	var best_vol := 0.0
	for m in meshes:
		var local_aabb := m.get_aabb()
		if local_aabb.size == Vector3.ZERO:
			continue
		var world_aabb := _transform_aabb(m.global_transform, local_aabb)
		if combined_aabb.size == Vector3.ZERO:
			combined_aabb = world_aabb
		else:
			combined_aabb = combined_aabb.merge(world_aabb)
		var vol := local_aabb.size.x * local_aabb.size.y * local_aabb.size.z
		if vol > best_vol:
			best_vol = vol
			best_material = _get_material(m)

	if combined_aabb.size == Vector3.ZERO:
		# 无法计算 AABB，退回逐网格碎裂
		_fragment_per_mesh(meshes, parent, dir, strength)
		return

	# 根据目标碎片数计算网格分块维度
	var size := combined_aabb.size
	var cell_size := pow(size.x * size.y * size.z / float(GRID_TARGET_FRAGMENTS), 1.0 / 3.0)
	cell_size = maxf(cell_size, 0.1)
	var gx := maxi(1, int(round(size.x / cell_size)))
	var gy := maxi(1, int(round(size.y / cell_size)))
	var gz := maxi(1, int(round(size.z / cell_size)))
	# 限制总碎片数不超上限
	while gx * gy * gz > MAX_FRAGMENTS:
		if gx >= gy and gx >= gz:
			gx -= 1
		elif gy >= gx and gy >= gz:
			gy -= 1
		else:
			gz -= 1
	gx = maxi(1, gx)
	gy = maxi(1, gy)
	gz = maxi(1, gz)

	var cell_w := size.x / gx
	var cell_h := size.y / gy
	var cell_d := size.z / gz
	# 碎片略小于格元，留出间隙增强碎裂视觉
	var frag_size := Vector3(
		maxf(cell_w * 0.85, 0.03),
		maxf(cell_h * 0.85, 0.03),
		maxf(cell_d * 0.85, 0.03)
	)

	var box_mesh := BoxMesh.new()
	box_mesh.size = frag_size
	var box_shape := BoxShape3D.new()
	box_shape.size = frag_size

	for ix in range(gx):
		for iy in range(gy):
			for iz in range(gz):
				var cx := combined_aabb.position.x + (ix + 0.5) * cell_w
				var cy := combined_aabb.position.y + (iy + 0.5) * cell_h
				var cz := combined_aabb.position.z + (iz + 0.5) * cell_d
				var body := _create_fragment_body(box_mesh, box_shape, best_material)
				if parent != null:
					parent.add_child(body)
				else:
					add_child(body)
				body.global_position = Vector3(cx, cy, cz)
				_apply_fragment_impulse(body, dir, strength)
				_fragments.append(body)


## 创建一个碎片刚体：碰撞盒 + 可视网格 + 材质。
func _create_fragment_body(mesh: Mesh, shape: Shape3D, mat: Material) -> RigidBody3D:
	var body := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var frag_mesh := MeshInstance3D.new()
	frag_mesh.mesh = mesh
	frag_mesh.material_override = mat
	body.add_child(frag_mesh)
	return body


## 对碎片施加冲量和随机角速度，模拟碎裂飞溅。
func _apply_fragment_impulse(body: RigidBody3D, dir: Vector3, strength: float) -> void:
	body.apply_central_impulse(dir * strength + Vector3(0.0, strength * 0.35, 0.0))
	body.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))


## 获取 MeshInstance3D 的材质（优先 material_override，其次活跃材质）。
func _get_material(mi: MeshInstance3D) -> Material:
	var mat := mi.material_override
	if mat == null:
		mat = mi.get_active_material(0)
	return mat


## 将局部空间 AABB 变换到世界空间。
func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var corners := [
		xform * aabb.position,
		xform * Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		xform * Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		xform * Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		xform * Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		xform * Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		xform * Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		xform * Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
	]
	var result := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		result = result.expand(c)
	return result


func freeze() -> void:
	for b in _fragments:
		if is_instance_valid(b):
			b.freeze = true
			PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)


func clear_fragments() -> void:
	for b in _fragments:
		if is_instance_valid(b):
			b.queue_free()
	_fragments.clear()


## 返回当前碎片数量（供测试断言）。
func get_fragment_count() -> int:
	return _fragments.size()


func _box_shape_for(mi: MeshInstance3D) -> BoxShape3D:
	var shape := BoxShape3D.new()
	var aabb := mi.get_aabb()
	shape.size = Vector3(
		maxf(aabb.size.x, 0.05),
		maxf(aabb.size.y, 0.05),
		maxf(aabb.size.z, 0.05)
	)
	return shape
