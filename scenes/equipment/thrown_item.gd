class_name ThrownItem
extends RigidBody3D

const DESTRUCTIBLE_ITEM_PREFAB := preload("res://scenes/props/destructible_item.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")

@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D
@onready var collision_shape: CollisionShape3D = %CollisionShape

var has_hit_world: bool = false
var has_resolved_collision: bool = false
var is_being_dropped: bool
var original_basis: Basis

func _ready() -> void:
	PhysicsSetup.setup_rigidbody(self)
	var thrown_object: Node3D = null
	original_basis = global_transform.basis if is_inside_tree() else transform.basis
	var throw_movement_speed := 0.0
	var throw_rotation_speed := 0.0
	# 重力倍率：投掷武器下坠最大（抛物线最明显）
	# 家具 0.8，投掷武器 0.55（区别于弩 0.04 / 弓 0.20）
	var gravity := 0.8
	if weapon_data != null and weapon_data.glb_mesh:
		thrown_object = weapon_data.glb_mesh.instantiate()
		throw_movement_speed = weapon_data.throw_movement_speed
		throw_rotation_speed = weapon_data.throw_rotation_speed
		gravity = 0.55
	elif shield_data != null and shield_data.glb_mesh:
		thrown_object = shield_data.glb_mesh.instantiate()
	elif furniture_data != null:
		thrown_object = _instantiate_furniture_visual()
		throw_movement_speed = furniture_data.throw_movement_speed
		throw_rotation_speed = furniture_data.throw_rotation_speed
	if thrown_object != null:
		add_child(thrown_object)
		_disable_visual_physics(thrown_object)
		if thrown_object is VoxelProp:
			_fit_collision_to_visual(thrown_object)
		else:
			var mesh_node := _find_first_mesh_instance(thrown_object)
			if mesh_node != null and mesh_node.mesh != null:
				collision_shape.shape = mesh_node.mesh.create_convex_shape()
			else:
				_fit_collision_to_visual(thrown_object)
		if collision_shape.shape == null:
			push_warning("ThrownItem: 无法从模型生成碰撞形状")
	if not is_being_dropped:
		gravity_scale = gravity
		linear_velocity = -global_basis.z * throw_movement_speed
		angular_velocity = -global_basis.y * throw_rotation_speed
		if weapon_data:
			AudioManager.play("sword-fly", audio_stream_player_3d)
	if not body_entered.is_connected(on_body_entered):
		body_entered.connect(on_body_entered)


func _instantiate_furniture_visual() -> Node3D:
	var prop_kind := _furniture_prop_kind()
	if not prop_kind.is_empty():
		var visual := VoxelProp.new()
		visual.name = "%sVoxelVisual" % prop_kind.capitalize()
		visual.prop_kind = prop_kind
		return visual
	if furniture_data.glb_mesh != null:
		return furniture_data.glb_mesh.instantiate()
	return null


func _furniture_prop_kind() -> String:
	var furniture_name := furniture_data.name.to_lower() if furniture_data != null else ""
	if furniture_name.contains("barrel"):
		return "barrel"
	if furniture_name.contains("crate"):
		return "small_crate"
	if furniture_name.contains("chest"):
		return "chest"
	return ""


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


func _fit_collision_to_visual(root: Node3D) -> void:
	if collision_shape == null:
		return
	var aabb := _combined_mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(aabb.size.x, 0.08),
		maxf(aabb.size.y, 0.08),
		maxf(aabb.size.z, 0.08)
	)
	collision_shape.shape = box
	collision_shape.position = aabb.get_center()


func _combined_mesh_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var initialized := false
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb := mesh_instance.get_aabb()
		var item_space := global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := item_space * local_aabb
		if initialized:
			combined = combined.merge(transformed)
		else:
			combined = transformed
			initialized = true
	return combined if initialized else AABB()


func _disable_visual_physics(node: Node) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_disable_visual_physics(child)

func on_body_entered(body: Node) -> void:
	if has_resolved_collision:
		return
	has_resolved_collision = true
	call_deferred("_resolve_body_entered", body)

func _resolve_body_entered(body: Node) -> void:
	if not is_instance_valid(self):
		return
	if furniture_data != null:
		if is_instance_valid(body) and body is Enemy and not is_being_dropped:
			var enemy := body as Enemy
			enemy.try_receive_furniture_impact(self)
		var destructible_item := DESTRUCTIBLE_ITEM_PREFAB.instantiate() as DestructibleItem
		destructible_item.global_transform = global_transform
		destructible_item.furniture_data = furniture_data
		_get_spawn_parent().add_child(destructible_item)
		destructible_item.explode()
		queue_free()
	else:
		if weapon_data != null and is_instance_valid(body) and body is Enemy and not is_being_dropped:
			var enemy := body as Enemy
			enemy.impale(self, original_basis)
		else:
			gravity_scale = 1
			if not has_hit_world:
				has_hit_world = true
				sleeping_state_changed.connect(on_sleep)
				if weapon_data and not is_being_dropped:
					AudioManager.play("sword-hit-wall", audio_stream_player_3d)

func on_sleep() -> void:
	if weapon_data == null and shield_data == null:
		queue_free()
		return
	var pickable_item := PICKABLE_ITEM_PREFAB.instantiate()
	pickable_item.weapon_data = weapon_data
	pickable_item.shield_data = shield_data
	pickable_item.global_transform = global_transform
	_get_spawn_parent().add_child(pickable_item)
	queue_free()

func _get_spawn_parent() -> Node:
	if GameState.current_level != null and is_instance_valid(GameState.current_level):
		return GameState.current_level
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	if get_parent() != null:
		return get_parent()
	return tree.root if tree != null else self
	
	
	
	
