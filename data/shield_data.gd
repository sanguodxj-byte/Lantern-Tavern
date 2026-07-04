class_name ShieldData
extends Resource

@export var name: String
@export var condition: int
@export var max_condition: int
@export var glb_mesh: PackedScene

func decrease_condition(amount: int) -> void:
	condition = clampi(condition - amount, 0, max_condition)
