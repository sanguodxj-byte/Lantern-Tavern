class_name EquipmentComponent
extends Node3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")

@export var weapon_data: WeaponData
@export var weapon_placeholder: Node3D

func _ready() -> void:
	if weapon_data != null:
		equip_weapon(weapon_data)

func equip_weapon(data: WeaponData) -> void:
	weapon_data = data.duplicate()
	var weapon := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	weapon.weapon_data = weapon_data
	weapon_placeholder.add_child(weapon)
