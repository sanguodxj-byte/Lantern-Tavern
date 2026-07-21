class_name EnemyStateMoving
extends EnemyState

const SPEED_ROTATION := 10.0
const PATH_UPDATE_INTERVAL_MS := 150
## 路径重算节流抖动：错开各敌人的 set_target_position(A* 全图寻路) 触发帧，
## 避免同批生成/同时索敌的敌人在同一帧集体重算路径造成周期性 CPU 尖峰（雷群效应）。
const PATH_UPDATE_JITTER_MS := 50
const PATROL_REACH_THRESHOLD := 1.5
const PATROL_IDLE_MIN_MS := 1000
const PATROL_IDLE_MAX_MS := 3000
const MIN_STEER_DISTANCE_SQUARED := 0.0025

## 初始相位随机化，使同批敌人的首次路径重算分散在不同帧（配合下方节流抖动持久错开）。
var last_path_update_time := -randi_range(0, PATH_UPDATE_INTERVAL_MS)
## 每实例路径重算间隔 = 基础间隔 + 随机抖动。即便多个敌人初始相位接近，
## 因间隔本身各异，长期运行也会持续漂移错开，杜绝同批敌人同帧集体 set_target_position
## （A* 全图寻路）造成的周期性 CPU 尖峰（雷群效应）。
var _path_update_interval_ms: int = PATH_UPDATE_INTERVAL_MS + randi_range(0, PATH_UPDATE_JITTER_MS)
var patrol_target: Vector3 = Vector3.ZERO
var has_patrol_target := false
var patrol_idle_until := 0

func _enter_tree() -> void:
	_play_animation("idle")
	# 记录出生位置作为巡逻中心
	enemy.spawn_position = enemy.global_position

func _physics_process(delta: float) -> void:
	# P-C：远距未交战敌人（18–36m 替身带）跳过寻路/巡逻 AI，仅保持物理静止。
	# 仍调用 process_movement 维持重力/碰撞一致性，但不做 A* 与导航查询，省下整图寻路 CPU。
	if not enemy.is_ai_active():
		enemy.velocity = Vector3(0.0, enemy.velocity.y, 0.0)
		if _requires_idle_physics_step():
			enemy.process_movement(delta)
		return
	if enemy.should_chase_player():
		_chase_player(delta)
	else:
		_patrol(delta)
	enemy.process_movement(delta)

func _requires_idle_physics_step() -> bool:
	return not enemy.is_on_floor() \
		or enemy.pushback_force.length_squared() > 0.0001 \
		or enemy.has_meta("is_thrown")

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
		if current_time - last_path_update_time >= _path_update_interval_ms:
			enemy.nav_agent.target_position = target_position
			last_path_update_time = current_time
		var direction := _get_steering_direction(target_position)
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
			if current_time - last_path_update_time >= _path_update_interval_ms:
				enemy.nav_agent.target_position = patrol_target
				last_path_update_time = current_time
			var direction := _get_steering_direction(patrol_target)
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

func _get_steering_direction(target_position: Vector3) -> Vector3:
	var next_path_position := target_position
	if enemy.nav_agent != null:
		next_path_position = enemy.nav_agent.get_next_path_position()
	next_path_position.y = enemy.global_position.y
	var offset := next_path_position - enemy.global_position
	if offset.length_squared() > MIN_STEER_DISTANCE_SQUARED:
		return offset.normalized()
	var fallback_target := target_position
	fallback_target.y = enemy.global_position.y
	offset = fallback_target - enemy.global_position
	if offset.length_squared() > MIN_STEER_DISTANCE_SQUARED:
		return offset.normalized()
	return Vector3.ZERO

func can_attack() -> bool:
	return Time.get_ticks_msec() - enemy.time_since_last_attack > enemy.duration_between_attacks

func _play_animation(animation_name: String) -> void:
	if enemy == null or enemy.animation_player == null:
		return
	# 去重：同一动画已在播放时不再重复 play()，避免每物理帧重启动画。
	# 比对 AnimationPlayer.current_animation 而非私有缓存，可正确跨越其他状态直接 play() 的动画
	# （如 SLASHING/HURT 状态直接 play 后回到移动态，私有缓存会误判导致 idle/run 无法重新播放）。
	if enemy.animation_player.current_animation == animation_name:
		return
	enemy.animation_player.play(animation_name)
