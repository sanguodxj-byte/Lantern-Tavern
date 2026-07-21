class_name PlayerStateKicking
extends PlayerState

const GROUND_FRICTION := 10.0
var kick_animation_name := "kick"

func _enter_tree() -> void:
	player.animation_player.play("kick")
	player.animation_player.animation_finished.connect(on_animation_finished)
	if player._raycast_is_colliding(player.kick_raycast):
		var collider := player.kick_raycast.get_collider() as Node
		if collider is Door:
			var door := collider as Door
			if door.can_open_with_kick():
				AudioManager.play("door-kick", player.action_audio_stream_player)
				door.open(player.global_transform)
			else:
				AudioManager.play("door-locked", player.action_audio_stream_player)
		elif collider is Enemy:
			var enemy := collider as Enemy
			AudioManager.play("kick", player.action_audio_stream_player)
			player.apply_kick_hit(enemy)
		elif collider != null and collider.has_method("try_receive_hit"):
			AudioManager.play("kick", player.action_audio_stream_player)
			collider.try_receive_hit(player, 2)
	else:
		AudioManager.play("kick-swoosh", player.action_audio_stream_player)

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)

func on_animation_finished(anim_name: String) -> void:
	if anim_name != kick_animation_name or player.state_node != self:
		return
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and player.animation_player != null:
		if player.animation_player.animation_finished.is_connected(on_animation_finished):
			player.animation_player.animation_finished.disconnect(on_animation_finished)
