class_name EquipmentComponent
extends Node3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")

@export var is_always_in_front: bool
@export var weapon_data: WeaponData
@export var weapon_placeholder: Node3D

func _ready() -> void:
	if weapon_data != null:
		equip_weapon(weapon_data)

func equip_weapon(data: WeaponData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	weapon_data = data.duplicate()
	var weapon := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	weapon.weapon_data = weapon_data
	weapon.is_always_in_front = is_always_in_front
	weapon_placeholder.add_child(weapon)
	if pickup_transform != Transform3D.IDENTITY:
		weapon.global_transform = pickup_transform
		animate_to_hand(weapon)

func animate_to_hand(equiped_item: Node3D) -> void:
	var tween := equiped_item.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(equiped_item, "position", Vector3.ZERO, 0.4)
	tween.parallel().tween_property(equiped_item, "rotation", Vector3.ZERO, 0.2)
	
	
	
