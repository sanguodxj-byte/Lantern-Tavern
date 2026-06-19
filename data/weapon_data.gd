class_name WeaponData
extends Resource

@export var name: String
@export var condition: int
@export var max_condition: int
@export var damage_min: int
@export var damage_max: int
@export var impale_local_translation: Vector3
@export var impale_local_rotation: float
@export var reach: float
@export var throw_rotation_speed: float
@export var throw_movement_speed: float
@export var glb_mesh: PackedScene

func get_damage_dealt() -> int:
	return randi_range(damage_min, damage_max)

func decrease_condition(amount: int) -> void:
	condition = clampi(condition - amount, 0, max_condition)
