extends GdUnitTestSuite

## Player 生命周期安全回归测试
## 验证 _get_valid_select_collider() 对已释放碰撞体的安全过滤。
## 回归向量：Chest.open_chest()（攻击破坏时 queue_free）/ close_loot_panel()（queue_free）
## 会在下一帧留下失效引用，旧实现直接 select_raycast.get_collider() 后无 is_instance_valid 守卫，
## 对已释放对象解引用会崩溃。
## 现实现经 _get_valid_select_collider() 统一 is_instance_valid 过滤。
##
## 注意：直接调用 _physics_process 会触发 move_and_slide/buffs.tick 等原生依赖，
## 在 headless 测试环境中导致引擎级崩溃（signal 11），因此本套件仅测试
## _get_valid_select_collider() 的过滤行为。_physics_process 是否调用该辅助
## 由 player_null_safety_test.gd 的源码级断言覆盖。

const PLAYER_SCENE := preload("res://scenes/characters/player/player.tscn")
const Service := preload("res://globals/core/service.gd")

## 基本契约：射线前方无碰撞体时返回 null。
func test_get_valid_select_collider_returns_null_when_no_collision() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()
	assert_object(player._get_valid_select_collider()) \
		.override_failure_message("射线未命中时 _get_valid_select_collider 应返回 null").is_null()
	_cleanup_player(player)


## 关键回归：碰撞体被 queue_free 后，_get_valid_select_collider 必须返回 null。
## 旧实现无 is_instance_valid 守卫，会在 queue_free 一帧延迟窗口内解引用已释放对象。
func test_get_valid_select_collider_returns_null_after_object_freed() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	var body := _make_select_body()
	add_child(body)
	# 必须在 add_child 后设置 global_position（Godot 要求节点在树内才能写 global_*）
	body.global_position = player.global_position + Vector3(0, 1.5, -1.0)
	await get_tree().physics_frame
	# force_raycast_update 确保射线最新结果（physics_frame 后缓存值可能延迟一帧）
	player.select_raycast.force_raycast_update()

	# 命中有效碰撞体时应返回该对象
	var collider := player._get_valid_select_collider()
	assert_object(collider) \
		.override_failure_message("射线命中有效碰撞体时应返回该对象").is_not_null()

	# queue_free 后下一物理帧应返回 null（is_instance_valid 过滤生效）
	body.queue_free()
	await get_tree().physics_frame
	player.select_raycast.force_raycast_update()
	var collider_after := player._get_valid_select_collider()
	assert_object(collider_after) \
		.override_failure_message("碰撞体被 queue_free 后 _get_valid_select_collider 必须返回 null，不得解引用已释放对象").is_null()

	_cleanup_player(player)


## 回归：Chest 被 queue_free 后，_get_valid_select_collider 必须返回 null。
## Chest.open_chest()（攻击破坏）和 close_loot_panel() 都会 queue_free，
## 下一帧射线仍可能命中已释放的 Chest，旧实现会对其解引用。
func test_get_valid_select_collider_returns_null_after_chest_freed() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	var chest := Chest.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	chest.add_child(shape)
	chest.collision_layer = 72  # 匹配 SelectRaycast.collision_mask
	chest.collision_mask = 0
	add_child(chest)
	chest.global_position = player.global_position + Vector3(0, 1.5, -1.0)
	await get_tree().physics_frame
	player.select_raycast.force_raycast_update()

	# 命中有效 Chest 时应返回该对象
	var collider := player._get_valid_select_collider()
	assert_object(collider) \
		.override_failure_message("射线命中有效 Chest 时应返回该对象").is_not_null()
	assert_object(collider) \
		.override_failure_message("命中的碰撞体应为 Chest 类型").is_instanceof(Chest)

	# 模拟 Chest 被攻击破坏后的 queue_free
	chest.queue_free()
	await get_tree().physics_frame
	player.select_raycast.force_raycast_update()
	var collider_after := player._get_valid_select_collider()
	assert_object(collider_after) \
		.override_failure_message("Chest 被 queue_free 后 _get_valid_select_collider 必须返回 null").is_null()

	_cleanup_player(player)


## 回归：SceneObject 被 queue_free 后，_get_valid_select_collider 必须返回 null。
## SceneObject.interact() 会调 destroy()->queue_free()，下一帧射线仍可能命中。
func test_get_valid_select_collider_returns_null_after_scene_object_freed() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	var body := SceneObject.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	body.collision_layer = 72  # 匹配 SelectRaycast.collision_mask
	body.collision_mask = 0
	add_child(body)
	body.global_position = player.global_position + Vector3(0, 1.5, -1.0)
	await get_tree().physics_frame
	player.select_raycast.force_raycast_update()

	# 命中有效 SceneObject 时应返回该对象
	var collider := player._get_valid_select_collider()
	assert_object(collider) \
		.override_failure_message("射线命中有效 SceneObject 时应返回该对象").is_not_null()

	# 模拟 SceneObject 被 interact/destroy 后的 queue_free
	body.queue_free()
	await get_tree().physics_frame
	player.select_raycast.force_raycast_update()
	var collider_after := player._get_valid_select_collider()
	assert_object(collider_after) \
		.override_failure_message("SceneObject 被 queue_free 后 _get_valid_select_collider 必须返回 null").is_null()

	_cleanup_player(player)


# ======================================================================
# _exit_tree 生命周期清理测试
# ======================================================================

## 回归：Player 被 free 后 _exit_tree 必须注销 GameState.current_player。
## 旧实现无 _exit_tree，Player 销毁后 GameState.current_player 仍持有失效引用。
func test_exit_tree_unregisters_from_game_state() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	var gs := Service.game_state()
	assert_object(gs).is_not_null()
	# _ready 应已注册 Player
	assert_object(gs.get("current_player")) \
		.override_failure_message("Player._ready 后 GameState.current_player 应为该 Player").is_not_null()
	assert_object(gs.get("current_player")) \
		.override_failure_message("GameState.current_player 应为该 Player 实例").is_equal(player)

	# free 触发 _exit_tree → unregister_player
	player.free()

	# current_player 必须被清空
	assert_object(gs.get("current_player")) \
		.override_failure_message("Player free 后 _exit_tree 必须注销 GameState.current_player，不得残留失效引用").is_null()


## 回归：Player 被 free 后全局信号连接必须已断开。
## 旧实现无 _exit_tree，Player 销毁后 GameEvents.weapon_changed 仍连着已释放的 _on_weapon_changed_for_view。
func test_exit_tree_disconnects_global_signals() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	# 验证 _ready 已连接信号
	var ge := Service.game_events()
	assert_object(ge).is_not_null()
	# 保存 Callable（在 player 仍有效时创建）
	var weapon_cb := Callable(player, "_on_weapon_changed_for_view")
	var chest_cb := Callable(player, "_on_chest_opened")
	assert_bool(ge.weapon_changed.is_connected(weapon_cb)) \
		.override_failure_message("_ready 后 weapon_changed 应连接到 _on_weapon_changed_for_view").is_true()
	assert_bool(ge.chest_opened.is_connected(chest_cb)) \
		.override_failure_message("_ready 后 chest_opened 应连接到 _on_chest_opened").is_true()
	# 记录连接数（断开后应减少）
	var weapon_conns_before: int = ge.weapon_changed.get_connections().size()
	var chest_conns_before: int = ge.chest_opened.get_connections().size()

	# free 触发 _exit_tree → 断开信号
	player.free()

	# 连接数必须减少（不访问已释放的 player 对象，改用连接数验证）
	var weapon_conns_after: int = ge.weapon_changed.get_connections().size()
	var chest_conns_after: int = ge.chest_opened.get_connections().size()
	assert_int(weapon_conns_after).is_less(weapon_conns_before) \
		.override_failure_message("Player free 后 weapon_changed 连接数必须减少（_exit_tree 应已断开信号）")
	assert_int(chest_conns_after).is_less(chest_conns_before) \
		.override_failure_message("Player free 后 chest_opened 连接数必须减少（_exit_tree 应已断开信号）")


## 回归：Player 被 queue_free（延迟释放）后下一帧 GameState.current_player 必须为 null。
## queue_free 是游戏中更常见的销毁路径（场景切换、重生等）。
func test_exit_tree_unregisters_after_queue_free() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()

	var gs := Service.game_state()
	assert_object(gs.get("current_player")).is_equal(player)

	player.queue_free()
	# queue_free 延迟到帧末执行，等待下一帧后 _exit_tree 应已运行
	await get_tree().process_frame

	assert_object(gs.get("current_player")) \
		.override_failure_message("Player queue_free 后下一帧 GameState.current_player 必须为 null").is_null()


# ======================================================================
# 辅助
# ======================================================================

## 创建一个匹配 SelectRaycast.collision_mask 的 StaticBody3D。
## 调用方负责 add_child 后设置 global_position。
func _make_select_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	body.collision_layer = 72  # 匹配 SelectRaycast.collision_mask（含 layer 7 = 64）
	body.collision_mask = 0
	return body


## 清理 Player 及其注册到 GameState 的全局引用。
## 候选 2 将在 Player._exit_tree 中自动完成此清理。
func _cleanup_player(player: Player) -> void:
	if player == null or not is_instance_valid(player):
		return
	var gs := Engine.get_main_loop() as SceneTree
	if gs != null:
		var game_state := gs.root.get_node_or_null("/root/GameState")
		if game_state != null and game_state.get("current_player") == player:
			game_state.call("unregister_player", player)
	player.free()


# ======================================================================
# _begin_exit 受保护退出钩子测试
# ======================================================================

## 回归：_begin_exit 必须断开 transition_requested 信号。
## 旧实现仅 queue_free，信号在帧末实际释放前仍连着 switch_state，
## 旧状态在此窗口内 emit 会导致重入切换。
func test_begin_exit_disconnects_transition_requested() -> void:
	var player := Player.new()
	var state := PlayerStateMoving.new(player, PlayerStateData.new())
	player.state_node = state
	# 模拟 switch_state 中的连接
	state.transition_requested.connect(player.switch_state)
	assert_bool(state.transition_requested.is_connected(Callable(player, "switch_state"))) \
		.override_failure_message("_begin_exit 前信号应已连接").is_true()

	state._begin_exit()

	assert_bool(state.transition_requested.is_connected(Callable(player, "switch_state"))) \
		.override_failure_message("_begin_exit 后 transition_requested 必须断开，防止重入").is_false()
	assert_bool(state._is_exiting) \
		.override_failure_message("_begin_exit 后 _is_exiting 必须为 true").is_true()
	state.free()
	player.free()


## 回归：_begin_exit 后 transition_state 不得 emit 信号。
## 旧状态在退出中不应再触发切换，防止 queue_free 延迟窗口内重入。
func test_transition_state_blocked_after_begin_exit() -> void:
	var player := Player.new()
	var state := PlayerStateMoving.new(player, PlayerStateData.new())
	player.state_node = state
	var transitions: Array = []
	state.transition_requested.connect(func(new_state, _data): transitions.append(new_state))

	state._begin_exit()
	# 退出后再调 transition_state 不应 emit
	state.transition_state(Player.State.BLOCKING)

	assert_array(transitions).is_empty()
	state.free()
	player.free()


## 回归：_begin_exit 必须幂等（重复调用不崩溃、不重复断开）。
func test_begin_exit_is_idempotent() -> void:
	var player := Player.new()
	var state := PlayerStateMoving.new(player, PlayerStateData.new())
	player.state_node = state
	state.transition_requested.connect(player.switch_state)

	state._begin_exit()
	# 第二次调用不应崩溃（信号已断开，is_connected 返回 false）
	state._begin_exit()

	assert_bool(state._is_exiting).is_true()
	state.free()
	player.free()


## 回归：快速连续 switch_state 不崩溃，最终状态正确。
## 旧实现 queue_free 旧状态后立即 add_child 新状态，
## 若新状态 _enter_tree 同步 emit transition_requested，
## 旧状态的信号可能在此窗口内重入。_begin_exit 确保旧状态同步退出。
func test_rapid_switch_state_no_crash() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()
	# _ready 已调 switch_state(State.MOVING)

	# 快速连续切换多个状态
	player.switch_state(Player.State.BLOCKING)
	player.switch_state(Player.State.HURT)
	player.switch_state(Player.State.KICKING)
	player.switch_state(Player.State.MOVING)
	player.switch_state(Player.State.GRABBING)
	player.switch_state(Player.State.MOVING)

	# 最终状态必须为 MOVING
	assert_int(player.state).is_equal(Player.State.MOVING)
	assert_object(player.state_node).is_not_null()
	assert_bool(is_instance_valid(player.state_node)).is_true()

	_cleanup_player(player)


## 回归：switch_state 后旧状态的 transition_requested 必须已断开。
func test_switch_state_disconnects_old_state_signal() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await await_idle_frame()
	# _ready 已创建 PlayerStateMoving
	var old_state := player.state_node
	assert_object(old_state).is_not_null()
	# _ready 中已连接 transition_requested → switch_state
	assert_bool(old_state.transition_requested.is_connected(Callable(player, "switch_state"))).is_true()

	player.switch_state(Player.State.BLOCKING)

	# 旧状态信号必须已断开
	assert_bool(old_state.transition_requested.is_connected(Callable(player, "switch_state"))) \
		.override_failure_message("switch_state 后旧状态 transition_requested 必须已断开").is_false()
	assert_bool(old_state._is_exiting) \
		.override_failure_message("旧状态 _is_exiting 必须为 true").is_true()

	_cleanup_player(player)


## 回归：_begin_exit 必须禁用 process 和 physics_process。
func test_begin_exit_disables_processing() -> void:
	var player := Player.new()
	var state := PlayerStateMoving.new(player, PlayerStateData.new())
	player.state_node = state
	state.set_process(true)
	state.set_physics_process(true)

	state._begin_exit()

	assert_bool(state.is_processing()).is_false()
	assert_bool(state.is_physics_processing()).is_false()
	state.free()
	player.free()
