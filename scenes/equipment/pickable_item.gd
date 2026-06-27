class_name PickableItem
extends StaticBody3D

const HIGHLIGHT_MATERIAL := preload("res://materials/highlight_material.tres")

@export var mesh_node : MeshInstance3D
@export var shield_data: ShieldData
@export var weapon_data: WeaponData

@onready var collision_shape: CollisionShape3D = %CollisionShape

var highlight_material: StandardMaterial3D

func _ready() -> void:
	var pickable_object : Node3D = null
	highlight_material = HIGHLIGHT_MATERIAL.duplicate()
	if weapon_data:
		pickable_object = weapon_data.glb_mesh.instantiate()
	elif shield_data:
		pickable_object = shield_data.glb_mesh.instantiate()
	if pickable_object != null:
		add_child(pickable_object)
		mesh_node = pickable_object.get_child(0) as MeshInstance3D
	if mesh_node != null:
		collision_shape.shape = mesh_node.mesh.create_convex_shape()

func highlight() -> void:
	mesh_node.material_override = highlight_material

func unhighlight() -> void:
	mesh_node.material_override = null
