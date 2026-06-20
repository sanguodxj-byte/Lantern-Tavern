class_name PlayerStateSlashing
extends PlayerState

const TIME_EMIT_DAMAGE := 200

var has_emitted_damage := false
var time_start_slash := Time.get_ticks_msec()

func _enter_tree() -> void:
	player.animation_player.play("slash")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _process(delta: float) -> void:
	var time_elapsed := Time.get_ticks_msec() - time_start_slash
	if not has_emitted_damage and time_elapsed > TIME_EMIT_DAMAGE:
		has_emitted_damage = true
		if player.weapon_reach_raycast.is_colliding():
			var enemy := player.weapon_reach_raycast.get_collider() as Enemy
			if enemy != null:
				enemy.try_receive_hit()

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
