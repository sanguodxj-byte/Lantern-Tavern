class_name EnemyStateBlocking
extends EnemyState

const GROUND_FRICTION := 10.0
const KNOCKBACK_FORCE := 2.0

func _enter_tree() -> void:
	enemy.animation_player.play("block")
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.LOW)
	FxHelper.call_deferred("create_metal_spark", enemy.equipment.shield_placeholder.global_position)
	AudioManager.play("block", enemy.action_audio_stream_player)
	enemy.pushback_force += state_data.impact_direction * KNOCKBACK_FORCE
	var blocked_amount := state_data.damage if "damage" in state_data else 0
	FxHelper.call_deferred("create_block_number", enemy.global_position, blocked_amount)
	
func _physics_process(delta: float) -> void:
	enemy.velocity = enemy.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)
	enemy.process_movement(delta)
	if enemy.velocity == Vector3.ZERO:
		transition_state(Enemy.State.MOVING)
