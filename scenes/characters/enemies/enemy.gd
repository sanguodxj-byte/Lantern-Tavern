class_name Enemy
extends CharacterBody3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")

@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var impaled_item := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	impaled_item.weapon_data = thrown_item.weapon_data
	physical_bone_torso.add_child(impaled_item)
	impaled_item.global_transform.basis = item_basis
	impaled_item.translate_object_local(impaled_item.weapon_data.impale_local_translation)
	impaled_item.rotate_object_local(Vector3.UP, impaled_item.weapon_data.impale_local_rotation)
	thrown_item.queue_free()
