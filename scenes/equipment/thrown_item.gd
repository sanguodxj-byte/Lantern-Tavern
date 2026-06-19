class_name ThrownItem
extends RigidBody3D

@export var weapon_data: WeaponData

@onready var collision_shape: CollisionShape3D = %CollisionShape

func _ready() -> void:
	var thrown_object: Node3D = null
	if weapon_data != null:
		thrown_object = weapon_data.glb_mesh.instantiate()
		if thrown_object != null:
			add_child(thrown_object)
			var mesh_node := thrown_object.get_child(0) as MeshInstance3D
			collision_shape.shape = mesh_node.mesh.create_convex_shape()
