class_name PlayerStateMoving
extends PlayerState

const DURATION_BETWEEN_FOOTSTEPS_WALK := 500
const DURATION_BETWEEN_FOOTSTEPS_RUN := 300

var time_since_last_footstep := Time.get_ticks_msec()

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
	elif Input.is_action_just_pressed("action") and player.get_primary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("primary")):
		transition_state(player.get_primary_weapon_action_state(), player.make_primary_weapon_attack_data())
	elif Input.is_action_just_pressed("block") and player.get_secondary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("secondary")):
		if player.get_secondary_weapon_action_state() == Player.State.ATTACK_PREPARING:
			transition_state(Player.State.ATTACK_PREPARING, player.make_secondary_weapon_attack_data())
		else:
			transition_state(player.get_secondary_weapon_action_state())
	elif Input.is_action_just_pressed("jump"):
		# 地面跳 + 空中二段跳（air_dash 机制被动解锁后；doc21 #4）统一由此分发
		player.do_jump()

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
	elif Input.is_action_just_pressed("action") and player.get_primary_weapon_action_state() != -1 and (player.is_active_weapon_ranged() or not player.is_melee_on_cooldown("primary")):
		if drv.has_method("send_attack"):
			var atk_type := "ranged" if player.is_active_weapon_ranged() else "melee"
			# target_hint=0：服务器依玩家朝向/射线重新判定目标（Phase 3 补全距离/视线校验）
			drv.send_attack(0, atk_type)
	elif Input.is_action_just_pressed("block") and player.get_secondary_weapon_action_state() != -1:
		if drv.has_method("send_block"):
			drv.send_block(true)
	elif Input.is_action_just_released("block"):
		if drv.has_method("send_block"):
			drv.send_block(false)
	elif Input.is_action_just_pressed("jump"):
		# 跳跃为本地物理表现；真正的服务器同步在 Phase 2 移动权威补全（暂保留本地跳）
		player.do_jump()
		
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
