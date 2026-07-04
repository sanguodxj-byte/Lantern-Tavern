class_name PlayerStateBlocking
extends PlayerState

const GROUND_FRICTION := 10.0

func _enter_tree() -> void:
	player.animation_player.play("block")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)

func can_get_hurt() -> bool:
	return false
