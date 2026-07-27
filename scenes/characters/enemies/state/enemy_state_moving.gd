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
const NAVIGATION_MAP_RETRY_MS := 100
const MIN_STEER_DISTANCE_SQUARED := 0.0025

## 首次移动帧立即触发路径目标设置，避免敌人出生后短暂使用过期目标。
var last_path_update_time := -PATH_UPDATE_INTERVAL_MS
## 每实例路径重算间隔 = 基础间隔 + 随机抖动。即便多个敌人初始相位接近，
## 因间隔本身各异，长期运行也会持续漂移错开，杜绝同批敌人同帧集体 set_target_position
## （A* 全图寻路）造成的周期性 CPU 尖峰（雷群效应）。
var _path_update_interval_ms: int = PATH_UPDATE_INTERVAL_MS + randi_range(0, PATH_UPDATE_JITTER_MS)
var patrol_target: Vector3 = Vector3.ZERO
var has_patrol_target := false
var patrol_idle_until := 0

func _enter_tree() -> void:
	_play_animation("idle")

func _physics_process(delta: float) -> void:
	var ai_active := enemy.is_ai_active()
	enemy.refresh_navigation_avoidance()
	if not ai_active:
		_patrol(delta)
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
	if not enemy.has_navigation_target():
		enemy.stop_navigation()
		_play_animation("idle")
		return
	var target_position := enemy.get_navigation_target_position()
	target_position.y = enemy.global_position.y
	if enemy.is_player_within_reach():
		_face_direction(target_position - enemy.global_position, delta)
		_play_animation("idle")
		enemy.stop_navigation()
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
		var chase_speed := enemy.speed * speed_mult
		enemy.set_navigation_max_speed(chase_speed)
		enemy.submit_navigation_velocity(direction * chase_speed)
		_face_direction(direction, delta)

## 巡逻：在出生点附近随机游走，到达后停顿再选下一个点
func _patrol(delta: float) -> void:
	# 停顿中
	if Time.get_ticks_msec() < patrol_idle_until:
		_play_animation("idle")
		enemy.stop_navigation()
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
			enemy.stop_navigation()
		else:
			_play_animation("run")
			var current_time := Time.get_ticks_msec()
			if current_time - last_path_update_time >= _path_update_interval_ms:
				enemy.nav_agent.target_position = patrol_target
				last_path_update_time = current_time
			var direction := _get_steering_direction(patrol_target)
			# 巡逻速度为正常速度的 50%
			enemy.submit_navigation_velocity(direction * enemy.speed * 0.5)
			_face_direction(direction, delta)
	else:
		_play_animation("idle")
		enemy.stop_navigation()

## 在出生点周围 patrol_radius 范围内随机选取巡逻目标
func _pick_new_patrol_target() -> void:
	var center := enemy.spawn_position
	var angle := randf() * TAU
	var radius := randf() * enemy.patrol_radius
	var requested := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	patrol_target = requested
	if enemy.nav_agent != null:
		var map := enemy.nav_agent.get_navigation_map()
		if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
			# NavigationServer 在第一张同步前禁止查询地图。保持原地并稍后重试，
			# 避免把未同步的出生帧误当作可寻路目标。
			has_patrol_target = false
			patrol_idle_until = Time.get_ticks_msec() + NAVIGATION_MAP_RETRY_MS
			enemy.stop_navigation()
			return
		patrol_target = NavigationServer3D.map_get_closest_point(map, requested)
	has_patrol_target = true

func _face_direction(direction: Vector3, delta: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if not _is_finite_vector(flat) or flat.length_squared() <= 0.0001:
		return
	# 只旋转 CharacterBody3D 的水平朝向。Basis.slerp 会把接近退化的导入
	# Basis 转成轴角；满暗蚀的大群追击下这条路径可能产生 NaN，进而污染根节点。
	var target_yaw := atan2(-flat.x, -flat.z)
	if not is_finite(target_yaw):
		return
	var current_yaw := enemy.rotation.y
	if not is_finite(current_yaw):
		current_yaw = 0.0
	enemy.rotation.y = lerp_angle(current_yaw, target_yaw, clampf(delta * SPEED_ROTATION, 0.0, 1.0))

func _get_steering_direction(target_position: Vector3) -> Vector3:
	if enemy.nav_agent == null:
		return Vector3.ZERO
	# NavigationAgent3D 查询是异步的。路径尚未生成时禁止退回目标直线，
	# 否则玩家隔着墙/处于墙角时会把 CharacterBody3D 持续推向障碍物。
	# get_next_path_position() 必须每个物理帧先调用，否则代理不会刷新内部路径，
	# 后续 get_current_navigation_path() 会一直为空，导致巡逻和追击都停在原地。
	var next_path_position := enemy.nav_agent.get_next_path_position()
	var current_path := enemy.nav_agent.get_current_navigation_path()
	if current_path.is_empty() or not _is_finite_vector(next_path_position):
		return Vector3.ZERO
	next_path_position.y = enemy.global_position.y
	var offset := next_path_position - enemy.global_position
	var offset_length_squared := offset.length_squared()
	if is_finite(offset_length_squared) and offset_length_squared > MIN_STEER_DISTANCE_SQUARED:
		var direction := offset.normalized()
		return direction if _is_finite_vector(direction) else Vector3.ZERO
	return Vector3.ZERO

func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

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
