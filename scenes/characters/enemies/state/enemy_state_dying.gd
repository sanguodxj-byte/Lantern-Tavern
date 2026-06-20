class_name EnemyStateDying
extends EnemyState

const DURATION_RAGDOLL_SIMULATION := 3.0

func _enter_tree() -> void:
	enemy.equipment.throw_weapon(true)
	enemy.collision_shape.disabled = true
	enemy.skeleton_simulator.active = true
	enemy.skeleton_simulator.physical_bones_start_simulation()
	enemy.physical_bone_torso.apply_impulse(state_data.impulse)
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

func freeze_ragdoll() -> void:
	transition_state(Enemy.State.DEAD)
