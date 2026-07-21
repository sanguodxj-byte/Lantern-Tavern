class_name PlayerStateShooting
extends PlayerState
## 远程武器射击状态。
## 进入时从 weapon_spawn_position 生成投射物（ProjectileEntity），
## 投射物沿 -Z 方向飞行，命中敌人后由 CombatBridge 结算伤害。
## 替代旧版继承 PlayerStateSlashing 的近战 hitbox 逻辑。

const WEAPON_CONDITION_WEAR := 2
const Service := preload("res://globals/core/service.gd")
const FP_VISUAL_STATE_MACHINE := preload("res://scenes/characters/player/first_person_weapon_visual_state_machine.gd")

var has_fired: bool = false
var shoot_animation_name := "throw_weapon"

func _enter_tree() -> void:
	# 保持瞄准缩放（不关闭 FOV），射击后由 on_animation_finished 决定是否回到瞄准
	if not player.animation_player.has_animation(shoot_animation_name):
		shoot_animation_name = "slash"
	player.animation_player.play(shoot_animation_name)
	player.animation_player.animation_finished.connect(on_animation_finished)
	_fire_projectile()

func _physics_process(delta: float) -> void:
	# 射击时移速略降（0.7 倍）
	player.process_movement(delta, 0.7)

## 发射投射物
func _fire_projectile() -> void:
	if has_fired:
		return
	has_fired = true
	var weapon := player.get_active_hand_weapon_data()
	if weapon == null or weapon.is_broken:
		return
	var spawn_transform := _get_muzzle_transform()
	var ps := Service.projectile_service()
	if ps == null:
		push_warning("PlayerStateShooting: ProjectileService 不可用")
		return
	var projectile: Node = ps.spawn_for_weapon(weapon, spawn_transform, player)
	if projectile == null:
		push_warning("PlayerStateShooting: 投射物生成失败（weapon_class=%s）" % weapon.weapon_class)
		return
	# 武器耐久磨损（射击时消耗，非命中时）
	player.equipment.apply_weapon_damage(WEAPON_CONDITION_WEAR)
	# 射击音效：区分弓和弩
	var is_crossbow := false
	if weapon != null:
		var w_class := weapon.weapon_class.to_lower()
		var w_tags := weapon.tags
		if w_class == "crossbow" or "crossbow" in w_tags:
			is_crossbow = true
	if is_crossbow:
		AudioManager.play("slash", player.action_audio_stream_player)
	else:
		# 弓播放箭矢飞出的破空啸声
		AudioManager.play("sword-fly", player.action_audio_stream_player)
	# Local visual only; projectile spawning remains above in this state.
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("play_action"):
		var visual_action: StringName = &"vm_crossbow_fire" if is_crossbow else &"vm_bow_release"
		player.view_model.play_action(visual_action)

	# 弩：发射后进入装弹，装弹完成前不允许连续发射（doc21 reload_shot）
	if is_crossbow:
		player.start_crossbow_reload()

## 获取枪口/弓口变换（投射物生成位置与朝向）
## 优先使用 ViewModel 的 MuzzlePoint（跟随武器模型前端），
## 确保箭矢从弓弩模型中发出而非从右手飞出。
## 朝向准心（摄像机中心射线命中点），使投射物飞向准心位置
func _get_muzzle_transform() -> Transform3D:
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("get_muzzle_global_transform"):
		var muzzle_transform: Transform3D = player.view_model.get_muzzle_global_transform()
		return player.get_aim_transform(muzzle_transform.origin)
	var muzzle_pos: Vector3
	# 优先从 ViewModel 获取枪口位置（第一人称可见武器模型前端）
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("get_muzzle_global_position"):
		muzzle_pos = player.view_model.get_muzzle_global_position()
	elif player.equipment != null and player.equipment.weapon_spawn_position != null and is_instance_valid(player.equipment.weapon_spawn_position):
		muzzle_pos = player.equipment.weapon_spawn_position.global_position
	else:
		# 回退：玩家前方 1 米
		muzzle_pos = player.global_position + (-player.global_transform.basis.z * 1.0)
	# 使用准心瞄准方向构造发射变换
	return player.get_aim_transform(muzzle_pos)

func on_animation_finished(anim_name: String) -> void:
	if anim_name != shoot_animation_name or player.state_node != self:
		return
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("finish_weapon_release"):
		player.view_model.finish_weapon_release()
	# 射击完成后：若右键仍按住且武器仍为远程，回到瞄准状态（保持连续瞄准）
	if player.is_active_weapon_ranged() and Input.is_action_pressed("block"):
		transition_state(Player.State.AIMING)
	else:
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	# 安全网：退出射击状态时若不是回到瞄准，确保关闭瞄准缩放
	if player != null and is_instance_valid(player):
		if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("get_visual_weapon_state") and player.view_model.has_method("cancel_weapon_hold"):
			if player.view_model.get_visual_weapon_state() == FP_VISUAL_STATE_MACHINE.State.RELEASING:
				player.view_model.cancel_weapon_hold()
		if not (player.is_active_weapon_ranged() and Input.is_action_pressed("block")):
			player.set_weapon_aiming(false)
		if player.animation_player != null:
			if player.animation_player.animation_finished.is_connected(on_animation_finished):
				player.animation_player.animation_finished.disconnect(on_animation_finished)
