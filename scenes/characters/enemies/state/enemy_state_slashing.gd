class_name EnemyStateSlashing
extends EnemyState

const TIME_EMIT_DAMAGE := 200

var has_emitted_damage := false
var time_start_slash := Time.get_ticks_msec()

func _enter_tree() -> void:
	enemy.animation_player.play("slash")
	enemy.animation_player.animation_finished.connect(on_animation_finished)

func _process(_delta: float) -> void:
	var time_elapsed := Time.get_ticks_msec() - time_start_slash
	if not has_emitted_damage and time_elapsed > TIME_EMIT_DAMAGE:
		has_emitted_damage = true
		if enemy.weapon_reach_raycast.is_colliding():
			var player := enemy.weapon_reach_raycast.get_collider() as Player
			if player != null:
				var damage := enemy.equipment.weapon_data.get_damage_dealt()
				player.try_receive_hit(enemy, damage)


func on_animation_finished(_anim_name: String) -> void:
	transition_state(Enemy.State.MOVING)

func can_get_stunned() -> bool:
	return true
