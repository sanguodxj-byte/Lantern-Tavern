class_name PlayerStateMoving
extends PlayerState

const DURATION_BETWEEN_FOOTSTEPS_WALK := 500
const DURATION_BETWEEN_FOOTSTEPS_RUN := 300

var time_since_last_footstep := Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		return
	if Input.is_action_just_pressed("use") and player.can_pickup_object():
		transition_state(Player.State.PICKING_UP)
	elif Input.is_action_just_pressed("throw") and player.equipment.has_weapon():
		transition_state(Player.State.THROWING)
	elif Input.is_action_just_pressed("action") and player.get_primary_weapon_action_state() != -1:
		transition_state(player.get_primary_weapon_action_state(), player.make_primary_weapon_attack_data())
	elif Input.is_action_just_pressed("block") and player.get_secondary_weapon_action_state() != -1:
		if player.get_secondary_weapon_action_state() == Player.State.ATTACK_PREPARING:
			transition_state(Player.State.ATTACK_PREPARING, player.make_secondary_weapon_attack_data())
		else:
			transition_state(player.get_secondary_weapon_action_state())
	elif player.is_on_floor() and Input.is_action_just_pressed("jump"):
		player.velocity.y = player.jump_force
		AudioManager.play("jump", player.vocal_audio_stream_player)
		
func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	var horizontal_velocity := Vector3(player.velocity.x, 0, player.velocity.z)
	if horizontal_velocity.length_squared() > 0.1 and player.is_on_floor():
		_play_animation("run")
		var duration := DURATION_BETWEEN_FOOTSTEPS_WALK
		if Input.is_action_pressed("run"):
			duration = DURATION_BETWEEN_FOOTSTEPS_RUN
		if Time.get_ticks_msec() - time_since_last_footstep > duration:
			AudioManager.play("footstep", player.footstep_audio_stream_player)
			time_since_last_footstep = Time.get_ticks_msec()
	else:
		_play_animation("idle")

func _play_animation(animation_name: String) -> void:
	if player == null or player.animation_player == null:
		return
	player.animation_player.play(animation_name)
