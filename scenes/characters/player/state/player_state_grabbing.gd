class_name PlayerStateGrabbing
extends PlayerState
## 抓取怪物状态：F 键 GRAB_THROW 释放后进入。
## 将前方命中的敌人 reparent 到 player 的 furniture_placeholder（视觉手持），
## 左键（action）→ 切换 THROWING 状态实例化 ThrownItem 投掷，触发 enemy.impale。

const GRAB_SPEED_MULTIPLIER := 0.4  # 抓取负重移速衰减
const THROW_IMPULSE := 12.0          # 投掷初速度（米/秒）

var grabbed_enemy: Enemy = null
var enemy_original_parent: Node = null
var enemy_original_transform: Transform3D = Transform3D.IDENTITY
var enemy_original_layer := 0
var enemy_original_mask := 0
var enemy_original_collision_disabled := false
var has_released_enemy := false

func _enter_tree() -> void:
	# 从 state_data 读取目标敌人
	grabbed_enemy = state_data.grabbed_enemy if state_data != null and state_data.has_method("get_grabbed_enemy") else null
	if grabbed_enemy == null:
		# 回退：用 kick_raycast 重新探测
		if player._raycast_is_colliding(player.kick_raycast):
			grabbed_enemy = player.kick_raycast.get_collider() as Enemy
	if grabbed_enemy == null:
		transition_state(Player.State.MOVING)
		return
	# 记录原父节点与变换，供投掷/取消时还原
	enemy_original_parent = grabbed_enemy.get_parent()
	enemy_original_transform = grabbed_enemy.global_transform
	enemy_original_layer = grabbed_enemy.collision_layer
	enemy_original_mask = grabbed_enemy.collision_mask
	enemy_original_collision_disabled = grabbed_enemy.collision_shape.disabled if grabbed_enemy.collision_shape != null else false
	# reparent 到 player 手部 placeholder（视觉手持）
	enemy_original_parent.remove_child(grabbed_enemy)
	player.equipment.furniture_placeholder.add_child(grabbed_enemy)
	grabbed_enemy.position = Vector3.ZERO
	grabbed_enemy.rotation = Vector3.ZERO
	_set_grabbed_enemy_collision_enabled(false)
	# 敌人进入 STUNNED 状态（被抓时无法行动）
	grabbed_enemy.switch_state(Enemy.State.STUNNED)
	player.animation_player.play("lift")
	AudioManager.play("lift", player.vocal_audio_stream_player)

func _physics_process(delta: float) -> void:
	# 抓取负重移速衰减
	player.process_movement(delta, GRAB_SPEED_MULTIPLIER)

func _process(_delta: float) -> void:
	# 左键投掷
	if Input.is_action_just_pressed("action"):
		_perform_throw()
	# 右键/E 键取消抓取（放回原处）
	elif Input.is_action_just_pressed("use"):
		_cancel_grab()

## 投掷被抓敌人：reparent 回场景 + 实例化 ThrownItem 触发 impale
func _perform_throw() -> void:
	if grabbed_enemy == null or not is_instance_valid(grabbed_enemy):
		transition_state(Player.State.MOVING)
		return
	# reparent 回当前关卡
	var placeholder: Node3D = player.equipment.furniture_placeholder
	placeholder.remove_child(grabbed_enemy)
	_get_release_parent().add_child(grabbed_enemy)
	# 投掷方向：玩家朝向 + 抛物线
	var forward: Vector3 = -player.global_transform.basis.z.normalized()
	var spawn_transform: Transform3D = placeholder.global_transform
	grabbed_enemy.global_transform = spawn_transform
	_set_grabbed_enemy_collision_enabled(true)
	# 给敌人施加投掷速度（CharacterBody3D velocity）
	grabbed_enemy.velocity = forward * THROW_IMPULSE + Vector3(0, 4.0, 0)
	# 构造 ThrownItem 触发 enemy.impale（命中其他敌人时连锁）
	_construct_thrown_enemy_item(spawn_transform, forward)
	# 敌人进入 STUNNED 状态并由 Enemy.process_movement 处理被投掷碰撞。
	var data := EnemyStateData.new().set_impact_direction(forward).set_knockback_force(THROW_IMPULSE)
	grabbed_enemy.switch_state(Enemy.State.STUNNED, data)
	has_released_enemy = true
	grabbed_enemy = null
	player.animation_player.play("throw_furniture")
	transition_state(Player.State.MOVING)

## 构造投掷物（简化：直接给敌人 velocity，命中时由 enemy._physics_process 检测碰撞触发伤害）
func _construct_thrown_enemy_item(spawn_transform: Transform3D, forward: Vector3) -> void:
	# 投掷的敌人飞行期间，其碰撞会触发对其他敌人的伤害（通过 enemy.on_body_entered 类似机制）
	# 此处简化：标记敌人为"被投掷"状态，由 enemy_state_impaling 处理碰撞
	grabbed_enemy.set_meta("is_thrown", true)
	grabbed_enemy.set_meta("throw_velocity", forward * THROW_IMPULSE + Vector3(0, 4.0, 0))
	grabbed_enemy.set_meta("throw_source_player", player)

## 取消抓取：将敌人放回原位
func _cancel_grab() -> void:
	if grabbed_enemy == null or not is_instance_valid(grabbed_enemy):
		transition_state(Player.State.MOVING)
		return
	var placeholder: Node3D = player.equipment.furniture_placeholder
	placeholder.remove_child(grabbed_enemy)
	if enemy_original_parent and is_instance_valid(enemy_original_parent):
		enemy_original_parent.add_child(grabbed_enemy)
		grabbed_enemy.global_transform = enemy_original_transform
	else:
		_get_release_parent().add_child(grabbed_enemy)
	_set_grabbed_enemy_collision_enabled(true)
	# 敌人恢复 MOVING 状态
	grabbed_enemy.switch_state(Enemy.State.MOVING)
	grabbed_enemy = null
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if has_released_enemy:
		return
	# 状态异常退出时确保敌人不丢失
	if grabbed_enemy != null and is_instance_valid(grabbed_enemy):
		var placeholder: Node3D = player.equipment.furniture_placeholder
		if grabbed_enemy.get_parent() == placeholder:
			placeholder.remove_child(grabbed_enemy)
			if enemy_original_parent and is_instance_valid(enemy_original_parent):
				enemy_original_parent.add_child(grabbed_enemy)
				grabbed_enemy.global_transform = enemy_original_transform
			else:
				_get_release_parent().add_child(grabbed_enemy)
			_set_grabbed_enemy_collision_enabled(true)
			grabbed_enemy.switch_state(Enemy.State.MOVING)


func _set_grabbed_enemy_collision_enabled(enabled: bool) -> void:
	if grabbed_enemy == null or not is_instance_valid(grabbed_enemy):
		return
	if enabled:
		grabbed_enemy.collision_layer = enemy_original_layer
		grabbed_enemy.collision_mask = enemy_original_mask
		if grabbed_enemy.collision_shape != null:
			grabbed_enemy.collision_shape.disabled = enemy_original_collision_disabled
	else:
		grabbed_enemy.collision_layer = 0
		grabbed_enemy.collision_mask = 0
		if grabbed_enemy.collision_shape != null:
			grabbed_enemy.collision_shape.disabled = true


func _get_release_parent() -> Node:
	if GameState.current_level != null and is_instance_valid(GameState.current_level):
		return GameState.current_level
	var tree := player.get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	if player.get_parent() != null:
		return player.get_parent()
	return tree.root if tree != null else player
