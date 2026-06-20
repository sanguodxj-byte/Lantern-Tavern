class_name PlayerStateThrowing
extends PlayerState

func _enter_tree() -> void:
	player.animation_player.play("throw_weapon")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	player.equipment.throw_weapon()
	transition_state(Player.State.MOVING)
