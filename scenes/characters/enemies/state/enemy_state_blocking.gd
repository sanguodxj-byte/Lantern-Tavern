class_name EnemyStateBlocking
extends EnemyState

const GROUND_FRICTION := 10.0
const KNOCKBACK_FORCE := 2.0

func _enter_tree() -> void:
	enemy.animation_player.play("block")
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.LOW)
	FxHelper.create_metal_spark(enemy.equipment.shield_placeholder.global_position)
	AudioManager.play("block", enemy.action_audio_stream_player)
	enemy.pushback_force += state_data.impact_direction * KNOCKBACK_FORCE
	
func _physics_process(delta: float) -> void:
	enemy.velocity = enemy.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)
	enemy.process_movement(delta)
	if enemy.velocity == Vector3.ZERO:
		transition_state(Enemy.State.MOVING)
