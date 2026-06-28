class_name PlayerStateHurt
extends PlayerState

const DURATION_HURT := 200
const PUSHBACK_FORCE := 2.5

var time_start_hurt := Time.get_ticks_msec()

func _enter_tree() -> void:
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	GameEvents.player_hurt.emit(player)
	if player.equipment.has_furniture():
		player.equipment.drop_furniture()
	player.pushback_force += state_data.impact_direction * PUSHBACK_FORCE
	player.health.take_damage(state_data.damage)
	if player.health.is_dead():
		transition_state(Player.State.DYING)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	if Time.get_ticks_msec() - time_start_hurt > DURATION_HURT:
		transition_state(Player.State.MOVING)
