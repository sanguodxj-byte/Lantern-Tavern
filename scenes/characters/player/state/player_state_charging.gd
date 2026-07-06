class_name PlayerStateCharging
extends PlayerState
## 冲撞状态：需先按 Shift 跑起来才能按 F 进入。
## 锁定朝向 + 加速移动，撞到敌人造成伤害+击退，撞墙或限时结束。

const CHARGE_SPEED := 12.0          # 冲撞速度（米/秒）
const CHARGE_MAX_DURATION := 0.8    # 最长冲撞持续时间（秒）
const CHARGE_HIT_COOLDOWN := 0.3    # 同一敌人击中冷却（秒）
const COLLISION_CHECK_DIST := 1.2   # 前方碰撞检测距离
const AS_DB := preload("res://globals/combat/action_skills.gd")
const Service := preload("res://globals/core/service.gd")

var charge_direction: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var hit_enemies: Dictionary = {}  # enemy → 上次击中时间
var charge_skill: Dictionary = {}
var charge_speed_mps: float = CHARGE_SPEED
var charge_max_duration: float = CHARGE_MAX_DURATION

func _enter_tree() -> void:
	# 锁定进入时的朝向（玩家当前面向）
	charge_direction = -player.global_transform.basis.z.normalized()
	charge_skill = _get_charge_skill()
	charge_speed_mps = float(charge_skill.get("dash_speed_mps", CHARGE_SPEED))
	var range_m := float(charge_skill.get("range_m", 5.0))
	charge_max_duration = maxf(range_m / maxf(charge_speed_mps, 0.1), 0.1)
	# 冲撞不播放移动动画，可播放专属冲撞动画（暂用 run）
	if player.animation_player.has_animation("charge"):
		player.animation_player.play("charge")
	else:
		player.animation_player.play("run")
	AudioManager.play("kick-swoosh", player.action_audio_stream_player)

func _physics_process(delta: float) -> void:
	elapsed += delta
	# 持续冲撞位移（锁定方向，不允许转向）
	player.velocity.x = charge_direction.x * charge_speed_mps
	player.velocity.z = charge_direction.z * charge_speed_mps
	player.velocity.y = 0.0  # 冲撞期间禁用跳跃/重力影响
	player.pushback_force = charge_direction * charge_speed_mps
	player.move_and_slide()
	# 检测前方敌人碰撞
	_check_charge_collision()
	# 检测撞墙（前方非敌人障碍）
	if _is_blocked_by_wall():
		_end_charge()
		return
	# 限时结束
	if elapsed >= charge_max_duration:
		_end_charge()

## 检测前方敌人碰撞，造成伤害+击退
func _check_charge_collision() -> void:
	if not player._raycast_is_colliding(player.kick_raycast):
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
	elif collider != null and collider.has_method("try_receive_hit"):
		collider.try_receive_hit(player, 3)
		AudioManager.play("kick", player.action_audio_stream_player)

## 对敌人施加冲撞伤害+击退
func _apply_charge_damage(enemy: Enemy) -> void:
	player.apply_action_skill_hit_to_enemy(enemy, charge_skill)
	AudioManager.play("kick", player.action_audio_stream_player)

func _get_charge_skill() -> Dictionary:
	var skill := AS_DB.get_skill_by_id("冲撞")
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("get_effective_skill_definition"):
		var effective: Dictionary = sr.get_effective_skill_definition("冲撞")
		if not effective.is_empty():
			return effective
	return skill

## 检测前方是否被墙阻挡（非敌人障碍）
func _is_blocked_by_wall() -> bool:
	if not player._raycast_is_colliding(player.kick_raycast):
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
