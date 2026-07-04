class_name PlayerStateCharging
extends PlayerState
## 冲撞状态：需先按 Shift 跑起来才能按 F 进入。
## 锁定朝向 + 加速移动，撞到敌人造成伤害+击退，撞墙或限时结束。

const CHARGE_SPEED := 12.0          # 冲撞速度（米/秒）
const CHARGE_MAX_DURATION := 0.8    # 最长冲撞持续时间（秒）
const CHARGE_HIT_COOLDOWN := 0.3    # 同一敌人击中冷却（秒）
const COLLISION_CHECK_DIST := 1.2   # 前方碰撞检测距离

var charge_direction: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var hit_enemies: Dictionary = {}  # enemy → 上次击中时间

func _enter_tree() -> void:
	# 锁定进入时的朝向（玩家当前面向）
	charge_direction = -player.global_transform.basis.z.normalized()
	# 冲撞不播放移动动画，可播放专属冲撞动画（暂用 run）
	if player.animation_player.has_animation("charge"):
		player.animation_player.play("charge")
	else:
		player.animation_player.play("run")
	AudioManager.play("kick-swoosh", player.action_audio_stream_player)

func _physics_process(delta: float) -> void:
	elapsed += delta
	# 持续冲撞位移（锁定方向，不允许转向）
	player.velocity.x = charge_direction.x * CHARGE_SPEED
	player.velocity.z = charge_direction.z * CHARGE_SPEED
	player.velocity.y = 0.0  # 冲撞期间禁用跳跃/重力影响
	player.move_and_slide()
	# 检测前方敌人碰撞
	_check_charge_collision()
	# 检测撞墙（前方非敌人障碍）
	if _is_blocked_by_wall():
		_end_charge()
		return
	# 限时结束
	if elapsed >= CHARGE_MAX_DURATION:
		_end_charge()

## 检测前方敌人碰撞，造成伤害+击退
func _check_charge_collision() -> void:
	if not player.kick_raycast.is_colliding():
		return
	var collider = player.kick_raycast.get_collider()
	if collider is Enemy:
		var enemy := collider as Enemy
		# 同一敌人冷却内不重复击中
		var last_hit: float = float(hit_enemies.get(enemy, -10.0))
		if elapsed - last_hit < CHARGE_HIT_COOLDOWN:
			return
		hit_enemies[enemy] = elapsed
		_apply_charge_damage(enemy)

## 对敌人施加冲撞伤害+击退
func _apply_charge_damage(enemy: Enemy) -> void:
	const CE_LIB := preload("res://globals/combat_engine.gd")
	var result := CE_LIB.DamageResult.new()
	result.hit = true
	result.final_damage = 8  # 冲撞基础伤害
	result.knockback_force = 6.0  # 强击退力（米/秒）
	result.knockback_impulse = charge_direction * 4.0
	result.stun_duration = 0.5  # 眩晕 0.5 秒
	enemy.try_receive_hit_result(player, result)
	AudioManager.play("kick", player.action_audio_stream_player)

## 检测前方是否被墙阻挡（非敌人障碍）
func _is_blocked_by_wall() -> bool:
	if not player.kick_raycast.is_colliding():
		return false
	var collider = player.kick_raycast.get_collider()
	return not (collider is Enemy)

## 结束冲撞，回到移动状态
func _end_charge() -> void:
	transition_state(Player.State.MOVING)

func can_get_hurt() -> bool:
	return false  # 冲撞期间霸体免伤

func _exit_tree() -> void:
	# 恢复正常重力/速度
	player.velocity.x = 0.0
	player.velocity.z = 0.0
