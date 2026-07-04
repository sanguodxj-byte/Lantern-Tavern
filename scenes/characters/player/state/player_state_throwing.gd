class_name PlayerStateThrowing
extends PlayerState

var has_thrown_furniture := false

func _enter_tree() -> void:
	if player.equipment.has_furniture():
		player.animation_player.play("throw_furniture")
		player.equipment.throw_furniture()
		has_thrown_furniture = true
	elif player.equipment.has_weapon():
		player.animation_player.play("throw_weapon")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	if not has_thrown_furniture and player.equipment.has_weapon():
		player.equipment.throw_weapon()
	transition_state(Player.State.MOVING)
