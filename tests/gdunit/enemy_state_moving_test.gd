extends GdUnitTestSuite
## 怪物巡逻/追击状态安全测试
## 验证：looking_at() 在原点与目标重合时不会崩溃

func test_patrol_and_chase_share_guarded_facing_helper() -> void:
	# 巡逻和追击都应走同一个带零向量保护的朝向入口。
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_int(script.source_code.count("_face_direction(direction, delta)")) \
		.override_failure_message("巡逻和追击必须统一使用 _face_direction").is_greater_equal(2)

func test_chase_faces_only_non_zero_steering_direction() -> void:
	# 追击逻辑只应根据有效导航方向转身，目标重合或无路径时不能调用 looking_at。
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_bool(script.source_code.contains("flat.length_squared() <= 0.0001")) \
		.override_failure_message("_face_direction 必须在 looking_at 前检查水平移动方向非零") \
		.is_true()

func test_chase_rejects_non_finite_navigation_direction_before_turning() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("func _is_finite_vector")) \
		.override_failure_message("追击导航方向必须提供统一的有限数值检查").is_true()
	assert_bool(source.contains("not _is_finite_vector(flat)")) \
		.override_failure_message("非有限追击方向不能进入 looking_at/slerp 转身").is_true()
	assert_bool(source.contains("not _is_finite_vector(next_path_position)")) \
		.override_failure_message("非有限下一路径点必须被丢弃").is_true()
	assert_bool(source.contains("lerp_angle")) \
		.override_failure_message("朝向插值必须使用有限的水平角度插值").is_true()
	assert_bool(source.contains("enemy.rotation.y = lerp_angle")) \
		.override_failure_message("朝向插值只能写入敌人 rotation.y").is_true()
	assert_bool(source.contains("func _is_finite_basis")) \
		.override_failure_message("移动状态不应再依赖可退化的 Basis 校验路径").is_false()
	assert_bool(source.contains(".slerp(")) \
		.override_failure_message("移动状态不应再调用 Basis.slerp").is_false()

func test_chase_turning_uses_finite_yaw_interpolation() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("lerp_angle")) \
		.override_failure_message("追击朝向应使用有限的 rotation.y 插值，绕开 Basis.slerp 的退化旋转路径").is_true()
	assert_bool(source.contains("enemy.rotation.y = lerp_angle")) \
		.override_failure_message("追击朝向必须只写入水平 rotation.y，不能把导航方向写成退化 Basis").is_true()
	assert_bool(source.contains(".slerp(")) \
		.override_failure_message("敌人移动状态不能继续调用 Basis.slerp").is_false()

func test_patrol_waits_for_navigation_map_sync_before_query() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("NavigationServer3D.map_get_iteration_id(map)")) \
		.override_failure_message("巡逻查询最近导航点前必须确认导航图已完成首轮同步").is_true()
	assert_bool(source.contains("patrol_idle_until = Time.get_ticks_msec() + NAVIGATION_MAP_RETRY_MS")) \
		.override_failure_message("导航图未同步时应短暂等待后重试，不能持续查询或直线移动").is_true()

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

func test_inactive_chase_ai_still_runs_patrol() -> void:
	var script: GDScript = load("res://scenes/characters/enemies/state/enemy_state_moving.gd") as GDScript
	assert_int(script.source_code.count("_patrol(delta)")) \
		.override_failure_message("远距或无玩家时应跳过追击，但不能跳过自动巡逻").is_greater_equal(2)

func test_chase_stops_without_navigation_path_instead_of_steering_through_walls() -> void:
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
	assert_float(Vector2(enemy.velocity.x, enemy.velocity.z).length()) \
		.override_failure_message("nav path 不可用时，怪物不能直线冲向墙体或角落").is_less(0.001)
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
	if ap == null:
		# 资源可能没有直接暴露 AnimationPlayer；此测试只验证移动状态的去重逻辑，
		# 注入最小播放器避免把 GLB 导出结构当成测试前提。
		ap = AnimationPlayer.new()
		enemy.add_child(ap)
		enemy.animation_player = ap
		var library := AnimationLibrary.new()
		library.add_animation("idle", Animation.new())
		ap.add_animation_library("", library)
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
	var scene := load("res://scenes/characters/enemies/slime.tscn") as PackedScene
	var enemy := scene.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy

func _new_player() -> Player:
	var scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := scene.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	return player
