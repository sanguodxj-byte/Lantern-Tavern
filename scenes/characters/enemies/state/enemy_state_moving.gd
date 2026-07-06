class_name EnemyStateMoving
extends EnemyState

const SPEED_ROTATION := 10.0
const PATH_UPDATE_INTERVAL_MS := 150
const PATROL_REACH_THRESHOLD := 1.5
const PATROL_IDLE_MIN_MS := 1000
const PATROL_IDLE_MAX_MS := 3000

var last_path_update_time := 0
var patrol_target: Vector3 = Vector3.ZERO
var has_patrol_target := false
var patrol_idle_until := 0

func _enter_tree() -> void:
	_play_animation("idle")
	# 记录出生位置作为巡逻中心
	enemy.spawn_position = enemy.global_position

func _physics_process(delta: float) -> void:
	if enemy.has_registered_player():
		_chase_player(delta)
	else:
		_patrol(delta)
	enemy.process_movement(delta)

## 追击玩家：寻路 + 朝向 + 攻击判定
func _chase_player(delta: float) -> void:
	var target_position := enemy.player.global_position
	target_position.y = enemy.global_position.y
	if not enemy.global_position.is_equal_approx(target_position):
		var target_transform := enemy.global_transform.looking_at(target_position)
		enemy.global_basis = enemy.global_basis.slerp(target_transform.basis, delta * SPEED_ROTATION)
	if enemy.is_player_within_reach():
		_play_animation("idle")
		enemy.velocity = Vector3(0, enemy.velocity.y, 0)
		if can_attack():
			enemy.time_since_last_attack = Time.get_ticks_msec()
			transition_state(Enemy.State.SLASHING)
	else:
		_play_animation("run")
		var current_time := Time.get_ticks_msec()
		if current_time - last_path_update_time >= PATH_UPDATE_INTERVAL_MS:
			enemy.nav_agent.target_position = target_position
			last_path_update_time = current_time
		var next_path_position := enemy.nav_agent.get_next_path_position()
		var direction := enemy.global_position.direction_to(next_path_position)
		var speed_mult := enemy.get_combat_speed_multiplier() if enemy.has_method("get_combat_speed_multiplier") else 1.0
		enemy.velocity = direction * enemy.speed * speed_mult

## 巡逻：在出生点附近随机游走，到达后停顿再选下一个点
func _patrol(delta: float) -> void:
	# 停顿中
	if Time.get_ticks_msec() < patrol_idle_until:
		_play_animation("idle")
		enemy.velocity = Vector3(0, enemy.velocity.y, 0)
		return
	# 需要新目标
	if not has_patrol_target:
		_pick_new_patrol_target()
	# 朝巡逻点移动
	if has_patrol_target:
		var dist := enemy.global_position.distance_to(patrol_target)
		if dist < PATROL_REACH_THRESHOLD:
			# 到达，停顿
			has_patrol_target = false
			patrol_idle_until = Time.get_ticks_msec() + randi_range(PATROL_IDLE_MIN_MS, PATROL_IDLE_MAX_MS)
			_play_animation("idle")
			enemy.velocity = Vector3(0, enemy.velocity.y, 0)
		else:
			_play_animation("run")
			var current_time := Time.get_ticks_msec()
			if current_time - last_path_update_time >= PATH_UPDATE_INTERVAL_MS:
				enemy.nav_agent.target_position = patrol_target
				last_path_update_time = current_time
			var next_path_position := enemy.nav_agent.get_next_path_position()
			var direction := enemy.global_position.direction_to(next_path_position)
			# 巡逻速度为正常速度的 50%
			enemy.velocity = direction * enemy.speed * 0.5
			# 朝向移动方向（direction 为零向量时跳过，避免 looking_at 崩溃）
			if direction.length_squared() > 0.0001:
				var look_target := enemy.global_position + direction
				look_target.y = enemy.global_position.y
				var target_transform := enemy.global_transform.looking_at(look_target)
				enemy.global_basis = enemy.global_basis.slerp(target_transform.basis, delta * SPEED_ROTATION)
	else:
		_play_animation("idle")
		enemy.velocity = Vector3(0, enemy.velocity.y, 0)

## 在出生点周围 patrol_radius 范围内随机选取巡逻目标
func _pick_new_patrol_target() -> void:
	var center := enemy.spawn_position
	var angle := randf() * TAU
	var radius := randf() * enemy.patrol_radius
	patrol_target = center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	has_patrol_target = true

func can_attack() -> bool:
	return Time.get_ticks_msec() - enemy.time_since_last_attack > enemy.duration_between_attacks

func _play_animation(animation_name: String) -> void:
	if enemy == null or enemy.animation_player == null:
		return
	enemy.animation_player.play(animation_name)
