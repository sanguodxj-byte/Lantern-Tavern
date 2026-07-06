class_name PlayerStateAttackPreparing
extends PlayerState

const MIN_HOLD_MSEC := 80

func _enter_tree() -> void:
	if player.is_active_weapon_ranged():
		player.set_weapon_aiming(true)
	else:
		player.animation_player.play("idle")

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	var input_action := state_data.weapon_input_action
	if input_action == "":
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	if Input.is_action_pressed(input_action):
		return
	var elapsed := Time.get_ticks_msec() - state_data.weapon_charge_started_msec
	if elapsed < MIN_HOLD_MSEC:
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	var release_state := state_data.weapon_release_state
	if release_state == -1:
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	# 进入射击状态（保持瞄准缩放，不关闭 FOV）
	transition_state(release_state, state_data)

func _physics_process(delta: float) -> void:
	player.process_movement(delta, 0.65)
