class_name HealthComponent
extends Node

@export var max_life: int
@export var current_life: int

func take_damage(damage: int) -> void:
	current_life = clampi(current_life - damage, 0, max_life)

func is_dead() -> bool:
	return current_life == 0
