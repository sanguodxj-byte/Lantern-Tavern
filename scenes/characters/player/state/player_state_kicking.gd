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
			if door.door_color != Door.KeyColor.None and GameState.has_key(door.door_color):
				AudioManager.play("door-kick", player.action_audio_stream_player)
				door.open(player.global_transform)
				GameState.use_key(door.door_color)
			else:
				AudioManager.play("door-locked", player.action_audio_stream_player)
		elif collider is Enemy:
			var enemy := collider as Enemy
			AudioManager.play("kick", player.action_audio_stream_player)
			enemy.try_receive_kick(player)
	else:
		AudioManager.play("kick-swoosh", player.action_audio_stream_player)

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
