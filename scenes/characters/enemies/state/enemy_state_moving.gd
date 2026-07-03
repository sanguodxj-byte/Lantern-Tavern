class_name EnemyStateMoving
extends EnemyState

const SPEED_ROTATION := 10.0
const PATH_UPDATE_INTERVAL_MS := 150

var last_path_update_time := 0

func _enter_tree() -> void:
	enemy.animation_player.play("idle")

func _physics_process(delta: float) -> void:
	if enemy.has_registered_player():
		var target_position := enemy.player.global_position
		target_position.y = enemy.global_position.y
		var target_transform := enemy.global_transform.looking_at(target_position)
		enemy.global_basis = enemy.global_basis.slerp(target_transform.basis, delta * SPEED_ROTATION)
		if enemy.is_player_within_reach():
			enemy.animation_player.play("idle")
			enemy.velocity = Vector3(0, enemy.velocity.y, 0)
			if can_attack():
				enemy.time_since_last_attack = Time.get_ticks_msec()
				transition_state(Enemy.State.SLASHING)
		else:
			enemy.animation_player.play("run")
			
			var current_time := Time.get_ticks_msec()
			if current_time - last_path_update_time >= PATH_UPDATE_INTERVAL_MS:
				enemy.nav_agent.target_position = target_position
				last_path_update_time = current_time
				
			var next_path_position := enemy.nav_agent.get_next_path_position()
			var direction := enemy.global_position.direction_to(next_path_position)
			enemy.velocity = direction * enemy.speed
	enemy.process_movement(delta)

func can_attack() -> bool:
	return Time.get_ticks_msec() - enemy.time_since_last_attack > enemy.duration_between_attacks
