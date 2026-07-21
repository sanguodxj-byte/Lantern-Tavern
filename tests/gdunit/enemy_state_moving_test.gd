extends GdUnitTestSuite
## 怪物巡逻/追击状态安全测试
## 验证：looking_at() 在原点与目标重合时不会崩溃

func test_patrol_guards_looking_at_against_zero_direction() -> void:
	# 巡逻逻辑中 direction 为零向量时必须跳过 looking_at，避免 C++ 崩溃
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_bool(script.source_code.contains("direction.length_squared() > 0.0001")) \
		.override_failure_message("巡逻 _patrol() 必须在 looking_at 前检查 direction 非零") \
		.is_true()

func test_chase_guards_looking_at_against_equal_positions() -> void:
	# 追击逻辑中玩家与敌人位置重合时必须跳过 looking_at
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_bool(script.source_code.contains("is_equal_approx(target_position)")) \
		.override_failure_message("追击 _chase_player() 必须在 looking_at 前检查位置不重合") \
		.is_true()

func test_enemy_speed_multiplier_uses_environment_activity_meta() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/enemy.gd") as GDScript
	assert_bool(script.source_code.contains("environment_activity_mult")) \
		.override_failure_message("探索压力升高时，怪物移动倍率应读取 environment_activity_mult") \
		.is_true()

func test_animation_play_is_guarded_for_missing_animation_player() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _play_animation")) \
		.override_failure_message("敌人移动状态应通过统一动画播放守卫处理缺失 AnimationPlayer").is_true()
	assert_bool(source.contains("enemy == null or enemy.animation_player == null")) \
		.override_failure_message("敌人移动状态播放动画前应检查 AnimationPlayer 非空").is_true()

func test_moving_state_uses_detection_gate_before_chasing() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("enemy.should_chase_player()")) \
		.override_failure_message("移动状态必须先通过统一索敌判断，再进入追击寻路").is_true()
	assert_bool(source.contains("enemy.has_registered_player():")) \
		.override_failure_message("移动状态不能只因登记过玩家就无限追击").is_false()

func test_chase_falls_back_to_direct_steering_without_navigation_path() -> void:
	var enemy := _new_enemy()
	var player := _new_player()
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.player = player
	var moving_state := enemy.state_node as EnemyStateMoving
	assert_object(moving_state).is_not_null()
	moving_state._chase_player(0.016)
	assert_float(enemy.velocity.x) \
		.override_failure_message("nav path 不可用时，追击也应退回直接水平转向并产生速度").is_greater(0.1)
	assert_float(absf(enemy.velocity.z)).is_less(0.001)
	player.queue_free()
	enemy.queue_free()

func test_navigation_target_updates_immediately_on_first_move() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_bool(script.source_code.contains("var last_path_update_time := -PATH_UPDATE_INTERVAL_MS")) \
		.override_failure_message("第一次移动帧必须立即设置 NavigationAgent3D 目标").is_true()

func test_play_animation_dedup_skips_repeat_play() -> void:
	# 同一动画已在播放时，_play_animation 应通过 current_animation 去重，避免每物理帧重启动画
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("current_animation == animation_name")) \
		.override_failure_message("重复播放同一动画时必须比对 current_animation 去重，而非私有缓存").is_true()
	assert_bool(source.contains("enemy.animation_player.play(animation_name)")) \
		.override_failure_message("_play_animation 仅在动画变更时才调用 play()").is_true()

func test_play_animation_does_not_restart_same_animation() -> void:
	# 行为验证：连续两次调用同一动画名，第二不必重启（current_animation_position 不应归零）
	var enemy := _new_enemy()
	add_child(enemy)
	var ap := enemy.animation_player
	assert_object(ap).is_not_null()
	# 选一个真实存在的动画名
	var anim_name := ""
	if ap.has_animation("run"):
		anim_name = "run"
	elif ap.has_animation("idle"):
		anim_name = "idle"
	else:
		anim_name = ap.get_animation_list()[0]
	assert_str(anim_name).is_not_empty()
	var moving_state := enemy.state_node as EnemyStateMoving
	assert_object(moving_state).is_not_null()
	# 首次播放
	moving_state._play_animation(anim_name)
	# 推进动画，使播放位置 > 0
	ap.advance(0.1)
	var pos_before := ap.current_animation_position
	assert_float(pos_before).is_greater(0.0) \
		.override_failure_message("advance() 后动画播放位置应前进")
	# 再次请求同一动画——去重守卫应跳过 play()，位置不会被重置为 0
	moving_state._play_animation(anim_name)
	var pos_after := ap.current_animation_position
	assert_float(pos_after).is_equal_approx(pos_before, 0.02) \
		.override_failure_message("去重守卫未生效：同一动画被重复 play() 导致播放位置归零")
	enemy.queue_free()

func _new_enemy() -> Enemy:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	return scene.instantiate() as Enemy

func _new_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	return scene.instantiate() as Player
