class_name EnemyStateDying
extends EnemyState

const DURATION_RAGDOLL_SIMULATION := 3.0

func _enter_tree() -> void:
	enemy.health.current_life = 0
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	FxHelper.create_blood_fx(enemy.physical_bone_head.global_transform)	
	AudioManager.play("orc-die", enemy.vocal_audio_stream_player)
	enemy.healthbar.visible = false
	enemy.dead.emit(enemy.global_transform)
	enemy.equipment.drop_weapon()
	enemy.equipment.drop_shield()
	enemy.presence_light.visible = false
	enemy.collision_shape.disabled = true
	enemy.skeleton_simulator.active = true
	enemy.skeleton_simulator.physical_bones_start_simulation()
	enemy.physical_bone_torso.apply_impulse(state_data.impulse)
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

func freeze_ragdoll() -> void:
	transition_state(Enemy.State.DEAD)

func can_die() -> bool:
	return false
