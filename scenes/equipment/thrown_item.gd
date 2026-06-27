class_name ThrownItem
extends RigidBody3D

const DESTRUCTIBLE_ITEM_PREFAB := preload("res://scenes/props/destructible_item.tscn")
const PICKABLE_ITEM_PREFAB := preload("res://scenes/equipment/pickable_item.tscn")

@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData

@onready var collision_shape: CollisionShape3D = %CollisionShape

var is_being_dropped: bool
var original_basis: Basis

func _ready() -> void:
	var thrown_object: Node3D = null
	original_basis = global_transform.basis
	var throw_movement_speed := 0.0
	var throw_rotation_speed := 0.0
	var gravity := 0.8
	if weapon_data != null:
		thrown_object = weapon_data.glb_mesh.instantiate()
		throw_movement_speed = weapon_data.throw_movement_speed
		throw_rotation_speed = weapon_data.throw_rotation_speed
		gravity = 0
	elif shield_data != null:
		thrown_object = shield_data.glb_mesh.instantiate()
	elif furniture_data != null:
		thrown_object = furniture_data.glb_mesh.instantiate()
		throw_movement_speed = furniture_data.throw_movement_speed
		throw_rotation_speed = furniture_data.throw_rotation_speed
	if thrown_object != null:
		add_child(thrown_object)
		var mesh_node := thrown_object.get_child(0) as MeshInstance3D
		collision_shape.shape = mesh_node.mesh.create_convex_shape()
		if not is_being_dropped:
			gravity_scale = gravity
			linear_velocity = -global_basis.z * throw_movement_speed
			angular_velocity = -global_basis.y * throw_rotation_speed
		body_entered.connect(on_body_entered)

func on_body_entered(body: Node) -> void:
	if weapon_data != null:
		if body is Enemy and not is_being_dropped:
			body.impale(self, original_basis)
		else:
			gravity_scale = 1
			if not sleeping_state_changed.is_connected(on_sleep):
				sleeping_state_changed.connect(on_sleep)
	elif furniture_data != null:
		var destructible_item := DESTRUCTIBLE_ITEM_PREFAB.instantiate() as DestructibleItem
		destructible_item.global_transform = global_transform
		destructible_item.furniture_data = furniture_data
		GameState.current_level.add_child(destructible_item)
		destructible_item.explode()
		queue_free()
	
func on_sleep() -> void:
	var pickable_item := PICKABLE_ITEM_PREFAB.instantiate()
	pickable_item.weapon_data = weapon_data
	pickable_item.shield_data = shield_data
	pickable_item.global_transform = global_transform
	GameState.current_level.add_child(pickable_item)
	queue_free()
	
	
	
	
