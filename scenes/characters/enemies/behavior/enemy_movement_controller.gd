class_name EnemyMovementController
extends RefCounted

## 怪物移动 Module。
## 将路径期望速度交给 NavigationAgent3D，并消费 velocity_computed 的安全速度。
## 额外提供近邻分离，避免多个 CharacterBody3D 在同一目标点互相挤压。

const SEPARATION_PADDING := 0.08
const SEPARATION_DISTANCE_MULTIPLIER := 3.5

var owner: Node3D
var agent: NavigationAgent3D
var desired_velocity := Vector3.ZERO
var last_safe_velocity := Vector3.ZERO
var movement_requested := false
var streaming_active := true

func _init(source_enemy: Node3D = null, source_agent: NavigationAgent3D = null) -> void:
	owner = source_enemy
	agent = source_agent

func configure() -> void:
	if agent == null:
		return
	if not agent.velocity_computed.is_connected(_on_velocity_computed):
		agent.velocity_computed.connect(_on_velocity_computed)
	# NavigationServer 首轮同步前，RVO 可能拿到未完成的邻居/地图数据并产生退化旋转；
	# EnemyStateMoving 会在地图 ready 后调用 refresh_navigation_avoidance() 开启它。
	agent.avoidance_enabled = false
	agent.neighbor_distance = maxf(agent.radius * SEPARATION_DISTANCE_MULTIPLIER, 1.5)
	agent.max_neighbors = 16
	agent.time_horizon_agents = 1.0
	agent.time_horizon_obstacles = 1.0
	if owner != null:
		set_max_speed(float(owner.get("speed")))

func set_streaming_active(active: bool) -> void:
	streaming_active = active
	if not active:
		_stop_navigation_request()
		if agent != null:
			agent.avoidance_enabled = false


func set_dark_erosion_hunt(active: bool) -> void:
	if agent == null:
		return
	# 满暗蚀时所有敌人都沿已验证的导航路径汇聚到玩家；RVO 避让和
	# 敌人间分离会在大群体中互相减速，甚至返回反向/零速。
	agent.avoidance_enabled = not active
	if active:
		agent.velocity = Vector3.ZERO

func refresh_navigation_avoidance() -> void:
	if agent == null or not streaming_active:
		return
	if owner != null and bool(owner.get_meta("dark_erosion_hunt", false)):
		agent.avoidance_enabled = false
		agent.velocity = Vector3.ZERO
		return
	var map := agent.get_navigation_map()
	var map_ready := map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0
	agent.avoidance_enabled = map_ready

func set_max_speed(value: float) -> void:
	if agent != null and is_finite(value):
		agent.max_speed = maxf(value, 0.1)

func submit_desired_velocity(value: Vector3) -> void:
	var flat := Vector3(value.x, 0.0, value.z)
	if not _is_finite_vector(value):
		_stop_navigation_request()
		return
	desired_velocity = flat
	movement_requested = flat.length_squared() > 0.000001
	if owner == null or not is_instance_valid(owner):
		return
	if not movement_requested:
		_stop_navigation_request()
		return

	var request := flat
	# NavigationAgent3D 的 RVO 已处理邻居分离。仅在 RVO 尚未启用/不可用时使用
	# 本地回退分离，避免密集敌群同时做 enemies group 全表扫描形成 O(N²) Process 尖峰。
	if not bool(owner.get_meta("dark_erosion_hunt", false)) \
			and (agent == null or not agent.avoidance_enabled):
		request += get_local_separation_velocity(flat.length())
	if request.length_squared() > flat.length_squared() * 1.44:
		request = request.normalized() * flat.length() * 1.2
	if agent != null and agent.avoidance_enabled:
		agent.velocity = request
	# 在 NavigationServer 回调到达前先保持期望速度；回调会在同一物理周期内覆盖它。
	# 没有导航地图时也不会让角色永久冻结，路径层仍负责禁止无路径直冲。
	owner.velocity.x = request.x
	owner.velocity.z = request.z

func apply_safe_velocity(value: Vector3) -> void:
	if not _is_finite_vector(value):
		return
	# 满暗蚀关闭 RVO 后由 submit_desired_velocity 直接驱动 CharacterBody3D；
	# NavigationServer 仍可能投递一帧旧的 velocity_computed，不能让它把追击速度清零。
	# 普通模式仍允许消费显式提交的安全速度，避免把有效回调和迟到回调混为一谈。
	if agent != null and not agent.avoidance_enabled \
			and owner != null and bool(owner.get_meta("dark_erosion_hunt", false)):
		return
	var safe_velocity := Vector3(value.x, 0.0, value.z)
	if _should_preserve_hunt_progress(safe_velocity):
		safe_velocity = desired_velocity
	last_safe_velocity = safe_velocity
	if owner == null or not is_instance_valid(owner):
		return
	# NavigationServer 回调可能晚于 stop_navigation()；停止后不得让旧安全速度重新推动角色。
	if not movement_requested:
		return
	owner.velocity.x = last_safe_velocity.x
	owner.velocity.z = last_safe_velocity.z

func _stop_navigation_request() -> void:
	desired_velocity = Vector3.ZERO
	last_safe_velocity = Vector3.ZERO
	movement_requested = false
	if agent != null:
		agent.velocity = Vector3.ZERO
	if owner != null and is_instance_valid(owner):
		owner.velocity.x = 0.0
		owner.velocity.z = 0.0

func _should_preserve_hunt_progress(safe_velocity: Vector3) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not bool(owner.get_meta("dark_erosion_hunt", false)):
		return false
	if desired_velocity.length_squared() <= 0.000001:
		return false
	# 满暗蚀时，零速、反向或几乎没有前进分量的避让会让远处敌人停滞/远离目标；
	# 期望速度仍来自已验证的导航路径，因此只在没有前进分量时回退到该方向。
	var desired_speed := desired_velocity.length()
	var forward_speed := safe_velocity.dot(desired_velocity.normalized())
	return not is_finite(forward_speed) or forward_speed <= desired_speed * 0.15

func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func get_local_separation_velocity(max_speed: float = 1.0) -> Vector3:
	if owner == null or not owner.is_inside_tree():
		return Vector3.ZERO
	if bool(owner.get_meta("dark_erosion_hunt", false)):
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var own_radius := agent.radius if agent != null else 0.25
	var scan_distance := maxf(own_radius * SEPARATION_DISTANCE_MULTIPLIER, 1.5)
	for node in owner.get_tree().get_nodes_in_group("enemies"):
		var other := node as Node3D
		if other == null or other == owner or not is_instance_valid(other) or other.is_queued_for_deletion():
			continue
		if not other.has_method("get_local_separation_velocity"):
			continue
		var offset := owner.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if not _is_finite_vector(offset) or not is_finite(distance):
			continue
		if distance > scan_distance:
			continue
		var other_radius := 0.25
		var other_agent := other.get("nav_agent") as NavigationAgent3D
		if other_agent != null:
			other_radius = other_agent.radius
		var minimum_distance := own_radius + other_radius + SEPARATION_PADDING
		var comfort_distance := minimum_distance + maxf(own_radius, other_radius) * 0.75
		if distance >= comfort_distance:
			continue
		var away := offset.normalized() if distance > 0.001 else _stable_overlap_direction(other)
		var proximity := clampf((comfort_distance - distance) / comfort_distance, 0.0, 1.0)
		sum += away * proximity
	if not _is_finite_vector(sum) or sum.length_squared() <= 0.000001:
		return Vector3.ZERO
	var separation := sum.normalized() * minf(max_speed * 0.8, max_speed)
	return separation if _is_finite_vector(separation) else Vector3.ZERO

func _stable_overlap_direction(other: Node3D) -> Vector3:
	# 完全重叠时没有几何方向，用实例 ID 建立成对且相反的确定方向。
	return Vector3.LEFT if owner.get_instance_id() < other.get_instance_id() else Vector3.RIGHT

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	apply_safe_velocity(safe_velocity)
