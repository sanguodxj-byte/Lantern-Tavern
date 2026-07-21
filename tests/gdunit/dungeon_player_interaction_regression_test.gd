extends GdUnitTestSuite


func test_player_ready_creates_single_named_vision_light() -> void:
	var packed: PackedScene = load("res://scenes/characters/player/player.tscn")
	var player := packed.instantiate()
	add_child(player)
	await await_idle_frame()

	var light := player.get_node_or_null("PlayerVisionLight") as OmniLight3D
	assert_object(light) \
		.override_failure_message("玩家必须稳定创建命名视野灯，避免地牢内偶发无自发光") \
		.is_not_null()
	assert_float(light.light_energy).is_greater_equal(2.4)
	assert_float(light.omni_range).is_greater_equal(10.0)
	assert_bool(light.distance_fade_enabled) \
		.override_failure_message("玩家主视野灯不能参与距离淡出，否则拾取/移动时会像全局光照关闭") \
		.is_false()
	assert_int(_count_named_children(player, "PlayerVisionLight")).is_equal(1)

	player.free()


func test_player_vision_light_setup_is_idempotent() -> void:
	var packed: PackedScene = load("res://scenes/characters/player/player.tscn")
	var player := packed.instantiate()
	add_child(player)
	await await_idle_frame()

	player._setup_player_light()
	player._setup_player_light()

	assert_int(_count_named_children(player, "PlayerVisionLight")) \
		.override_failure_message("重复初始化玩家时不能堆叠多个视野灯") \
		.is_equal(1)

	player.free()


func test_grabbing_throw_marks_state_as_released_before_switching() -> void:
	var src := _source("res://scenes/characters/player/state/player_state_grabbing.gd")
	assert_bool(src.contains("has_released_enemy = true")) \
		.override_failure_message("抓取投掷切换状态前必须标记已释放，否则 _exit_tree 会把投出的敌人还原") \
		.is_true()
	assert_bool(src.contains("if has_released_enemy:")) \
		.override_failure_message("GRABBING 退出时必须跳过已释放目标的异常还原逻辑") \
		.is_true()


func test_grabbed_enemy_throw_uses_stun_path_not_impale_without_thrown_item() -> void:
	var src := _source("res://scenes/characters/player/state/player_state_grabbing.gd")
	assert_bool(src.contains("Enemy.State.STUNNED")) \
		.override_failure_message("抓取投掷敌人不能直接进入需要 ThrownItem 的 IMPALING 状态") \
		.is_true()
	assert_bool(src.contains("is_thrown")) \
		.override_failure_message("抓取投掷敌人应标记为被投掷，由 Enemy 移动碰撞统一处理") \
		.is_true()


func test_thrown_item_defers_collision_resolution_and_stops_after_first_hit() -> void:
	var src := _source("res://scenes/equipment/thrown_item.gd")
	assert_bool(src.contains("has_resolved_collision")) \
		.override_failure_message("投掷物需要一次性碰撞闸门，避免多次 body_entered 重入") \
		.is_true()
	assert_bool(src.contains("call_deferred(\"_resolve_body_entered\"")) \
		.override_failure_message("投掷物碰撞结算应延迟到物理回调之后执行") \
		.is_true()


func test_enemy_has_separate_thrown_enemy_impact_handler() -> void:
	var src := _source("res://scenes/characters/enemies/enemy.gd")
	assert_bool(src.contains("func try_receive_thrown_enemy_impact")) \
		.override_failure_message("敌人之间的投掷碰撞应独立处理，不应伪装成武器 impale") \
		.is_true()


func test_player_vision_light_disabled_in_tavern() -> void:
	var packed: PackedScene = load("res://scenes/characters/player/player.tscn")
	var player := packed.instantiate() as Player
	
	# 创建一个 mock 的 TavernInterior 节点作为父节点
	var mock_tavern = load("res://scenes/tavern/tavern.tscn").instantiate()
	mock_tavern.add_child(player)
	get_tree().root.add_child(mock_tavern)
	
	# 触发 _ready 之后，由于处于 Tavern 内部，灯光应当被关闭
	await await_idle_frame()
	
	var light := player.get_node_or_null("PlayerVisionLight") as OmniLight3D
	assert_object(light).is_not_null()
	assert_bool(light.visible).is_false()
	assert_float(light.light_energy).is_equal_approx(0.0, 0.001)
	
	mock_tavern.queue_free()


static func _count_named_children(node: Node, child_name: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.name == child_name:
			count += 1
	return count


static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
