class_name PlayerStateShooting
extends PlayerState
## 远程武器射击状态。
## 进入时从 weapon_spawn_position 生成投射物（ProjectileEntity），
## 投射物沿 -Z 方向飞行，命中敌人后由 CombatBridge 结算伤害。
## 替代旧版继承 PlayerStateSlashing 的近战 hitbox 逻辑。

const WEAPON_CONDITION_WEAR := 2
const Service := preload("res://globals/core/service.gd")

var has_fired: bool = false

func _enter_tree() -> void:
	# 保持瞄准缩放（不关闭 FOV），射击后由 on_animation_finished 决定是否回到瞄准
	player.animation_player.play("slash")
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
	# 射击音效
	AudioManager.play("slash", player.action_audio_stream_player)
	# 第一人称视图模型后坐力
	if player.view_model != null and is_instance_valid(player.view_model) and player.view_model.has_method("apply_recoil"):
		player.view_model.apply_recoil()

## 获取枪口/弓口变换（投射物生成位置与朝向）
## 朝向准心（摄像机中心射线命中点），使投射物飞向准心位置
func _get_muzzle_transform() -> Transform3D:
	var eq := player.equipment
	var muzzle_pos: Vector3
	if eq != null and eq.weapon_spawn_position != null and is_instance_valid(eq.weapon_spawn_position):
		muzzle_pos = eq.weapon_spawn_position.global_position
	else:
		# 回退：玩家前方 1 米
		muzzle_pos = player.global_position + (-player.global_transform.basis.z * 1.0)
	# 使用准心瞄准方向构造发射变换
	return player.get_aim_transform(muzzle_pos)

func on_animation_finished(_anim_name: String) -> void:
	# 射击完成后：若右键仍按住且武器仍为远程，回到瞄准状态（保持连续瞄准）
	if player.is_active_weapon_ranged() and Input.is_action_pressed("block"):
		transition_state(Player.State.AIMING)
	else:
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	# 安全网：退出射击状态时若不是回到瞄准，确保关闭瞄准缩放
	if player != null and is_instance_valid(player):
		if not (player.is_active_weapon_ranged() and Input.is_action_pressed("block")):
			player.set_weapon_aiming(false)
		if player.animation_player != null:
			if player.animation_player.animation_finished.is_connected(on_animation_finished):
				player.animation_player.animation_finished.disconnect(on_animation_finished)
