class_name EnemyStateMoving
extends EnemyState

func _enter_tree() -> void:
	enemy.animation_player.play("idle")

func _physics_process(delta: float) -> void:
	if enemy.has_registered_player():
		if enemy.is_player_within_reach() and can_attack():
			enemy.time_since_last_attack = Time.get_ticks_msec()
			transition_state(Enemy.State.SLASHING)

func can_attack() -> bool:
	return Time.get_ticks_msec() - enemy.time_since_last_attack > enemy.duration_between_attacks
