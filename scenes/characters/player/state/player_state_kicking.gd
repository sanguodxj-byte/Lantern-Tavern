class_name PlayerStateKicking
extends PlayerState

const GROUND_FRICTION := 10.0

func _enter_tree() -> void:
	player.animation_player.play("kick")
	player.animation_player.animation_finished.connect(on_animation_finished)
	if player.kick_raycast.is_colliding():
		var collider := player.kick_raycast.get_collider() as Node
		if collider is Door:
			var door := collider as Door
			door.open(player.global_transform)
		elif collider is Enemy:
			var enemy := collider as Enemy
			enemy.try_receive_kick(player)

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
