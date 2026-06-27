class_name EquipmentComponent
extends Node3D

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const THROWN_ITEM_PREFAB := preload("res://scenes/equipment/thrown_item.tscn")

@export var furniture_data: FurnitureData
@export var furniture_placeholder: Node3D
@export var is_always_in_front: bool
@export var shield_data: ShieldData
@export var shield_placeholder: Node3D
@export var weapon_data: WeaponData
@export var weapon_placeholder: Node3D
@export var weapon_reach_raycast: RayCast3D
@export var weapon_spawn_position: Node3D

func _ready() -> void:
	if weapon_data != null:
		equip_weapon(weapon_data)
	if shield_data != null:
		equip_shield(shield_data)

func equip_weapon(data: WeaponData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if has_weapon():
		drop_weapon()
	weapon_data = data.duplicate()
	var weapon := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	weapon.weapon_data = weapon_data
	weapon.is_always_in_front = is_always_in_front
	weapon_placeholder.add_child(weapon)
	weapon_reach_raycast.target_position.z = -sqrt(weapon_data.reach)
	if pickup_transform != Transform3D.IDENTITY:
		weapon.global_transform = pickup_transform
		animate_to_hand(weapon)
		
func equip_shield(data: ShieldData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if has_shield():
		drop_shield()
	shield_data = data.duplicate()
	var shield := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	shield.shield_data = shield_data
	shield.is_always_in_front = is_always_in_front
	shield_placeholder.add_child(shield)
	if pickup_transform != Transform3D.IDENTITY:
		shield.global_transform = pickup_transform
		animate_to_hand(shield)

func equip_furniture(data: FurnitureData, pickup_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if has_shield():
		hide_shield()
	if has_weapon():
		hide_weapon()
	furniture_data = data.duplicate()
	var furniture := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	furniture.furniture_data = furniture_data
	furniture.is_always_in_front = is_always_in_front
	furniture_placeholder.add_child(furniture)
	if pickup_transform != Transform3D.IDENTITY:
		furniture.global_transform = pickup_transform
		animate_to_hand(furniture)

func animate_to_hand(equiped_item: Node3D) -> void:
	var tween := equiped_item.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(equiped_item, "position", Vector3.ZERO, 0.4)
	tween.parallel().tween_property(equiped_item, "rotation", Vector3.ZERO, 0.2)

func has_shield() -> bool:
	return shield_data != null and shield_placeholder.get_child_count() > 0

func hide_shield() -> void:
	shield_placeholder.visible = false

func show_shield() -> void:
	shield_placeholder.visible = true

func has_weapon() -> bool:
	return weapon_data != null and weapon_placeholder.get_child_count() > 0

func hide_weapon() -> void:
	weapon_placeholder.visible = false

func show_weapon() -> void:
	weapon_placeholder.visible = true

func throw_weapon(is_being_dropped: bool = false) -> void:
	if has_weapon():
		var thrown_item := THROWN_ITEM_PREFAB.instantiate()
		thrown_item.weapon_data = weapon_data
		thrown_item.is_being_dropped = is_being_dropped
		var spawn_transform := weapon_placeholder.global_transform
		if not is_being_dropped:
			spawn_transform = weapon_spawn_position.global_transform
		thrown_item.global_transform = spawn_transform
		GameState.current_level.add_child(thrown_item)
		weapon_data = null
		weapon_placeholder.get_child(0).queue_free()

func drop_weapon() -> void:
	throw_weapon(true)

func drop_shield() -> void:
	if has_shield():
		var dropped_item := THROWN_ITEM_PREFAB.instantiate()
		dropped_item.shield_data = shield_data
		dropped_item.is_being_dropped = true
		var spawn_transform := shield_placeholder.global_transform
		dropped_item.global_transform = spawn_transform
		GameState.current_level.add_child(dropped_item)
		shield_data = null
		shield_placeholder.get_child(0).queue_free()
