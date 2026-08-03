class_name PlayerStateMoving
extends PlayerState

const PLAYER_ANIMATION_PROFILE := preload("res://globals/visual/player_animation_profile.gd")

const DURATION_BETWEEN_FOOTSTEPS_WALK := 500
const DURATION_BETWEEN_FOOTSTEPS_RUN := 300

var time_since_last_footstep := Time.get_ticks_msec()
var _network_primary_attack_held := false

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		return
	# —— 联机客户端：所有权威意图上送服务器，本地只播放表现、不执行权威操作 ——
	if player.is_network_controlled() and player.multiplayer_driver != null:
		_process_network_intents()
		return
	# —— 单机 / 房主（本地即权威）：直接执行 ——
	if Input.is_action_just_pressed("use") and player.can_pickup_object():
		transition_state(Player.State.PICKING_UP)
	elif Input.is_action_just_pressed("throw") and player.equipment.has_weapon():
		transition_state(Player.State.THROWING)
	elif (player.consume_weapon_action_pressed("action") or Input.is_action_just_pressed("action")) and player.get_primary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("primary")):
		transition_state(player.get_primary_weapon_action_state(), player.make_primary_weapon_attack_data())
	elif Input.is_action_just_pressed("block") and player.get_secondary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("secondary")):
		if player.get_secondary_weapon_action_state() == Player.State.ATTACK_PREPARING:
			transition_state(Player.State.ATTACK_PREPARING, player.make_secondary_weapon_attack_data())
		else:
			transition_state(player.get_secondary_weapon_action_state())

## 联机客户端意图采集：仅上送服务器，绝不在本地执行战斗/交互/拾取/投掷/格挡结算。
## 本地预表现（挥砍动画等）由服务器回传事件驱动（见 Phase 3 战斗权威）。
func _process_network_intents() -> void:
	var drv: Node = player.multiplayer_driver
	if drv == null or not is_instance_valid(drv):
		return
	if Input.is_action_just_pressed("use") and player.can_pickup_object():
		if drv.has_method("send_pickup"):
			drv.send_pickup(player._entity_id_of(player.current_pickable_focused_item))
	elif Input.is_action_just_pressed("throw") and player.equipment.has_weapon():
		if drv.has_method("send_throw"):
			drv.send_throw("")
	elif (player.consume_weapon_action_pressed("action") or Input.is_action_just_pressed("action")) and player.get_primary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("primary")):
		# Network clients keep the same hold/release contract as local players.
		# The server receives the attack only after the release edge.
		_network_primary_attack_held = true
	elif _network_primary_attack_held and not player.is_weapon_action_held("action"):
		if drv.has_method("send_attack"):
			# P0-2：客户端只提交意图（主手/满蓄力），攻击类型由服务器从权威 loadout 派生。
			drv.send_attack(0)
		_network_primary_attack_held = false
	elif Input.is_action_just_pressed("block") and player.get_secondary_weapon_action_state() != -1:
		if drv.has_method("send_block"):
			drv.send_block(true)
	elif Input.is_action_just_released("block"):
		if drv.has_method("send_block"):
			drv.send_block(false)
		
func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	# Crossbow reload is a visual and gameplay-critical follow-up.  Let the
	# shared reload clip continue instead of restarting idle/run every physics
	# frame; the authoritative timer in Player decides when this guard clears.
	if player.is_crossbow_reloading():
		return
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
	var resolved_name := StringName(animation_name)
	if animation_name == "idle":
		# Keep the first-person ready pose alive, but still advance the
		# third-person hold clip in its own AnimationPlayer.
		var first_person_hold_active := true
		if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("ensure_weapon_hold"):
			first_person_hold_active = player.view_model.ensure_weapon_hold()
		var hold_animation := PLAYER_ANIMATION_PROFILE.hold_animation(player.get_active_hand_weapon_data())
		if first_person_hold_active and player.animation_player.has_animation(hold_animation):
			resolved_name = hold_animation
	if player.animation_player.current_animation == resolved_name and player.animation_player.is_playing():
		return
	player.animation_player.play(resolved_name)
