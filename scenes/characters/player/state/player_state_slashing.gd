class_name PlayerStateSlashing
extends PlayerState

func _enter_tree() -> void:
	player.animation_player.play("slash")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
