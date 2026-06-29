class_name EnemyStateHurt
extends EnemyState

const KNOCKBACK_FORCE := 2.0

func _enter_tree() -> void:
	enemy.health.take_damage(state_data.damage)
	enemy.health_indicator.refresh(enemy.health.current_life, enemy.health.max_life)
	enemy.pushback_force += state_data.impact_direction * KNOCKBACK_FORCE
	if enemy.health.is_dead():
		AudioManager.play("hit-kill", enemy.action_audio_stream_player)
		var data := EnemyStateData.new().set_impulse(state_data.impact_direction * 120.0 + Vector3.UP * 80.0)
		transition_state(Enemy.State.DYING, data)
	else:
		AudioManager.play("slash-hit", enemy.action_audio_stream_player)
		GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.LOW)
		FxHelper.create_blood_fx(enemy.physical_bone_head.global_transform, false)
		enemy.animation_player.play("hurt")
		enemy.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	enemy.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Enemy.State.MOVING)
