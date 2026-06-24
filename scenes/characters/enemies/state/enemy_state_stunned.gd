class_name EnemyStateStunned
extends EnemyState

const KNOCKBACK_FORCE := 2.0
const GROUND_FRICTION := 10.0

var time_start := Time.get_ticks_msec()

func _enter_tree() -> void:
	enemy.animation_player.play("stunned")
	enemy.pushback_force += state_data.impact_direction * KNOCKBACK_FORCE

func _physics_process(delta: float) -> void:
	enemy.velocity = enemy.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)
	enemy.process_movement(delta)
	if Time.get_ticks_msec() - time_start > enemy.duration_stun:
		transition_state(Enemy.State.MOVING)
		
func can_get_hurt() -> bool:
	return true
