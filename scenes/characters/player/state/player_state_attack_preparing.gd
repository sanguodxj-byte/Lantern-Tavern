class_name PlayerStateAttackPreparing
extends PlayerState

const MIN_HOLD_MSEC := 80
const CROSSBOW_MIN_HOLD_MSEC := 0

func _enter_tree() -> void:
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("begin_weapon_hold"):
		player.view_model.begin_weapon_hold()
	if player.is_active_weapon_ranged():
		player.set_weapon_aiming(true)
	else:
		player.animation_player.play("idle")

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		player.set_weapon_aiming(false)
		_restore_view_model()
		transition_state(Player.State.MOVING)
		return
	var input_action := state_data.weapon_input_action
	if input_action == "":
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	if Input.is_action_pressed(input_action):
		if player.is_active_weapon_ranged() and not player.is_active_weapon_crossbow():
			# 弓：持续按住蓄力期间驱动拉弓进度动画；弩：无需蓄力动画和颤抖
			var elapsed := Time.get_ticks_msec() - state_data.weapon_charge_started_msec
			var charge_ratio := clampf(float(elapsed) / 800.0, 0.0, 1.0)
			if player.view_model != null and is_instance_valid(player.view_model):
				if player.view_model.has_method("update_weapon_hold"):
					player.view_model.update_weapon_hold(charge_ratio)
				elif player.view_model.has_method("sample_action"):
					player.view_model.sample_action(&"vm_bow_draw", charge_ratio)
		elif not player.is_active_weapon_ranged():
			# 近战蓄力：基础操作（类似骑砍），按住记录蓄力比例；
			# 增伤仅在装备蓄力被动时生效（见 PlayerStateSlashing）。
			var elapsed := Time.get_ticks_msec() - state_data.weapon_charge_started_msec
			var charge_ratio := clampf(float(elapsed) / (player.MELEE_CHARGE_FULL_SEC * 1000.0), 0.0, 1.0)
			state_data.set_weapon_charge_ratio(charge_ratio)
			if player.view_model != null and is_instance_valid(player.view_model):
				if player.view_model.has_method("update_weapon_hold"):
					player.view_model.update_weapon_hold(charge_ratio)
				elif player.view_model.has_method("sample_action"):
					player.view_model.sample_action(&"vm_melee_charge", charge_ratio)
		return
	var elapsed := Time.get_ticks_msec() - state_data.weapon_charge_started_msec
	# 弩无需蓄力时间，立即射击；弓/近战需要最低蓄力时间
	var min_hold := CROSSBOW_MIN_HOLD_MSEC if player.is_active_weapon_crossbow() else MIN_HOLD_MSEC
	if elapsed < min_hold:
		player.set_weapon_aiming(false)
		_restore_view_model()
		transition_state(Player.State.MOVING)
		return
	var release_state := state_data.weapon_release_state
	if release_state == -1:
		player.set_weapon_aiming(false)
		_restore_view_model()
		transition_state(Player.State.MOVING)
		return
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("release_weapon_hold"):
		player.view_model.release_weapon_hold()
	# 进入攻击/射击状态（保持瞄准缩放，不关闭 FOV）
	player.set_weapon_aiming(false)
	transition_state(release_state, state_data)

## 取消蓄力时恢复第一人称武器模型到默认姿势
func _restore_view_model() -> void:
	if player.view_model == null or not is_instance_valid(player.view_model):
		return
	if player.view_model.has_method("cancel_weapon_hold"):
		player.view_model.cancel_weapon_hold()
	elif player.view_model.has_method("stop_action"):
		player.view_model.stop_action(true)

func _physics_process(delta: float) -> void:
	player.process_movement(delta, 0.65)
