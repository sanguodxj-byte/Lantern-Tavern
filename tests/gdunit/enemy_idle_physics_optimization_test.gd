extends GdUnitTestSuite

const MOVING_STATE_PATH := "res://scenes/characters/enemies/state/enemy_state_moving.gd"
const ENEMY_PATH := "res://scenes/characters/enemies/enemy.gd"
const TARGETING_PATH := "res://scenes/characters/enemies/behavior/enemy_targeting.gd"


func test_far_settled_enemy_skips_move_and_slide() -> void:
	var source := FileAccess.get_file_as_string(MOVING_STATE_PATH)
	assert_bool(source.contains("func _requires_idle_physics_step")).is_true()
	assert_bool(source.contains("if _requires_idle_physics_step():")).is_true() \
		.override_failure_message("远距静止且已落地的敌人不应每物理帧调用 move_and_slide")
	assert_bool(source.contains("enemy.pushback_force.length_squared()")) \
		.override_failure_message("受击或投掷中的远敌仍必须保留物理步进").is_true()


func test_inactive_enemy_skips_patrol_and_navigation_avoidance() -> void:
	var source := FileAccess.get_file_as_string(MOVING_STATE_PATH)
	var inactive_start := source.find("if not ai_active:")
	var active_start := source.find("\tenemy.refresh_navigation_avoidance()", inactive_start)
	assert_int(inactive_start).is_greater_equal(0)
	assert_int(active_start).is_greater(inactive_start)
	var inactive_block := source.substr(inactive_start, active_start - inactive_start)
	assert_bool(not inactive_block.contains("_patrol(delta)")) \
		.override_failure_message("远距未交战敌人不应继续巡逻和提交寻路").is_true()
	assert_bool(not inactive_block.contains("refresh_navigation_avoidance")) \
		.override_failure_message("远距未交战敌人不应每物理帧刷新 RVO").is_true()
	assert_bool(inactive_block.contains("enemy.stop_navigation()")) \
		.override_failure_message("远距休眠前必须撤销旧导航速度").is_true()


func test_enemy_process_skips_empty_status_and_inactive_target_memory() -> void:
	var enemy_source := FileAccess.get_file_as_string(ENEMY_PATH)
	var targeting_source := FileAccess.get_file_as_string(TARGETING_PATH)
	assert_bool(enemy_source.contains("if not combat_debuffs.is_empty():")) \
		.override_failure_message("无状态效果敌人不应每帧执行空字典状态扫描").is_true()
	assert_bool(enemy_source.contains("_targeting.has_pending_memory()")) \
		.override_failure_message("目标记忆为空时不应每帧执行 targeting.tick").is_true()
	assert_bool(targeting_source.contains("func has_pending_memory()")) \
		.override_failure_message("目标模块必须提供轻量记忆活动判定").is_true()


func test_spawn_candidate_does_not_bypass_ai_radius_or_keep_detection_area_in_broadphase() -> void:
	var enemy_source := FileAccess.get_file_as_string(ENEMY_PATH)
	# P1-5：player_ref 读取已收口进 _resolve_target_player（唯一解析 helper）——
	# AI 只读生成候选，绝不将其写成已交战 player。
	assert_bool(enemy_source.contains("func _resolve_target_player()")) \
		.override_failure_message("目标解析必须经统一 helper（_resolve_target_player）").is_true()
	assert_bool(enemy_source.contains("distance_squared_to(target.global_position)")) \
		.override_failure_message("未交战敌人必须受 AI_SIM_RADIUS_M 距离门禁").is_true()
	assert_bool(enemy_source.contains("player_detection_area.monitoring = false")) \
		.override_failure_message("主动感知已替代常驻 Area3D broadphase").is_true()
	assert_bool(enemy_source.contains("body_entered.connect(on_player_detected)")) \
		.override_failure_message("不应保留每敌人 Area3D 进入回调").is_false()


func test_streaming_sleep_disables_enemy_navigation_avoidance() -> void:
	var enemy_source := FileAccess.get_file_as_string(ENEMY_PATH)
	var movement_source := FileAccess.get_file_as_string("res://scenes/characters/enemies/behavior/enemy_movement_controller.gd")
	var streaming_source := FileAccess.get_file_as_string("res://scenes/expedition/dungeon_streaming_controller.gd")
	assert_bool(enemy_source.contains("set_streaming_physics_active" )).is_true()
	assert_bool(movement_source.contains("agent.avoidance_enabled = false" )).is_true()
	assert_bool(movement_source.contains("not streaming_active" )).is_true()
	assert_bool(streaming_source.contains("set_streaming_physics_active(active)" )).is_true()
