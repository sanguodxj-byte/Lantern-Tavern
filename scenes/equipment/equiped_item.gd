class_name EquipedItem
extends Node3D

@export var weapon_data: WeaponData

func _ready() -> void:
	var equiped_object := weapon_data.glb_mesh.instantiate()
	if equiped_object != null:
		add_child(equiped_object)
