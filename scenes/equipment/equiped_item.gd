class_name EquipedItem
extends Node3D

const ZCLIP_MATERIAL := preload("res://materials/zclip_material.tres")

@export var is_always_in_front: bool
@export var furniture_data: FurnitureData
@export var shield_data: ShieldData
@export var weapon_data: WeaponData

func _ready() -> void:
	var equiped_object : Node = null
	if weapon_data:
		equiped_object = weapon_data.glb_mesh.instantiate()
	elif shield_data:
		equiped_object = shield_data.glb_mesh.instantiate()
	elif furniture_data:
		equiped_object = furniture_data.glb_mesh.instantiate()
	if equiped_object != null:
		add_child(equiped_object)
		var mesh_node := equiped_object.get_child(0) as MeshInstance3D
		if mesh_node != null and is_always_in_front:
			mesh_node.material_override = ZCLIP_MATERIAL.duplicate()
