class_name PlayerStateDying
extends PlayerState

func _enter_tree() -> void:
	player.equipment.drop_shield()
	player.equipment.drop_weapon()

func can_get_hurt() -> bool:
	return false

func can_die() -> bool:
	return false
