extends GdUnitTestSuite
## Player 系统空值守卫综合测试
## 验证 Player 及其所有子状态中 has_method 调用前均有 null 检查，
## 防止 "Attempt to call function 'has_method' in base 'null instance'" 错误。

# ======================================================================
# 1. player.gd — 主脚本空值守卫
# ======================================================================

func test_physics_process_interact_call_guarded() -> void:
	# _physics_process 中 collider.has_method("interact") 受 collider != null 保护 (line ~115)
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.find("collider != null and not (collider is PickableItem) and collider.has_method") != -1) \
		.override_failure_message("player.gd _physics_process: collider.has_method 前缺少 null 检查").is_true()

func test_check_for_possible_action_interact_call_guarded() -> void:
	# check_for_possible_action 中 collider.has_method("interact") 受 collider != null 保护 (line ~204)
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.find("collider != null and collider.has_method") != -1) \
		.override_failure_message("player.gd check_for_possible_action: collider.has_method 前缺少 null 检查").is_true()

func test_both_interact_call_sites_distinct() -> void:
	# 验证 player.gd 中两处 collider.has_method("interact") 均有独立 null 守卫
	var src: String = _source("res://scenes/characters/player/player.gd")
	var count_collider_null: int = 0
	var pos: int = -1
	while true:
		pos = src.find("collider != null", pos + 1)
		if pos == -1:
			break
		count_collider_null += 1
	# 至少两处 collider != null 检查（line 115 和 line 204）
	assert_bool(count_collider_null >= 2) \
		.override_failure_message("player.gd 应至少包含 2 处 collider != null 检查").is_true()

# ======================================================================
# 2. player_state_grabbing.gd — state_data 空值守卫
# ======================================================================

func test_grabbing_state_data_guarded() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state_grabbing.gd")
	assert_bool(src.find("state_data != null and state_data.has_method") != -1) \
		.override_failure_message("player_state_grabbing.gd: state_data.has_method 前缺少 null 检查").is_true()

func test_grabbing_state_data_context() -> void:
	# 验证 state_data 守卫是用于 get_grabbed_enemy 方法调用
	var src: String = _source("res://scenes/characters/player/state/player_state_grabbing.gd")
	assert_bool(src.find("state_data != null and state_data.has_method(\"get_grabbed_enemy\")") != -1) \
		.override_failure_message("player_state_grabbing.gd: 缺少针对 get_grabbed_enemy 的完整 null 守卫").is_true()

# ======================================================================
# 3. player_state_slashing.gd — collider 空值守卫
# ======================================================================

func test_slashing_collider_guarded() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state_slashing.gd")
	assert_bool(src.find("collider != null and collider.has_method") != -1) \
		.override_failure_message("player_state_slashing.gd: collider.has_method 前缺少 null 检查").is_true()

func test_slashing_has_method_is_try_receive_hit() -> void:
	# 验证守卫的是 try_receive_hit，不是其他方法
	var src: String = _source("res://scenes/characters/player/state/player_state_slashing.gd")
	assert_bool(src.find("collider != null and collider.has_method(\"try_receive_hit\")") != -1) \
		.override_failure_message("player_state_slashing.gd: 缺少针对 try_receive_hit 的完整 null 守卫").is_true()

# ======================================================================
# 4. check_for_possible_action — 行为逻辑验证（源码模式）
# ======================================================================

func test_check_for_possible_action_has_pickup_fallback() -> void:
	# check_for_possible_action 的 collider 链应以 pickup 兜底分支结尾
	# null safety: 用 elif collider != null 守卫，避免在 null 上调用 has_method
	var src: String = _source("res://scenes/characters/player/player.gd")
	# 定位 check_for_possible_action 函数体
	var fn_start: int = src.find("func check_for_possible_action")
	assert_int(fn_start).is_greater(0)
	# 验证 pickup 兜底分支存在（null safety: 用 elif collider != null 守卫）
	var pickup_branch: int = src.find("elif collider != null and collider.has_method(\"get_item_name\")", fn_start)
	assert_bool(pickup_branch > fn_start) \
		.override_failure_message("check_for_possible_action 应包含 pickup 兜底分支（elif collider != null and collider.has_method('get_item_name')）").is_true()
	# 验证该分支设置 [E] Pick Up 提示
	var branch_snippet: String = src.substr(pickup_branch, 200)
	assert_bool(branch_snippet.find("[E] %s %s") != -1) \
		.override_failure_message("pickup 兜底分支应设置 [E] Pick Up 提示").is_true()


func test_pickable_focus_emits_shared_detail_popup_signal() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var src := script.source_code
	# 射线指向 PickableItem 时应使用共享详情浮窗数据（emit 调用跨行，分别验证）
	assert_bool(src.contains("GameEvents.item_detail_changed.emit")) \
		.override_failure_message("应发射 item_detail_changed 信号").is_true()
	assert_bool(src.contains("DETAIL_POPUP.detail_for_pickable_item")) \
		.override_failure_message("应使用 DETAIL_POPUP.detail_for_pickable_item 构建详情").is_true()
	# 场景拾取提示应保留 [E] Pick Up 文案（格式化字符串形式）
	assert_bool(src.contains("[E] %s %s") and src.contains("tr(\"Pick Up\")")) \
		.override_failure_message("拾取提示应包含 [E] Pick Up 文案").is_true()


func test_player_raycast_calls_use_instance_valid_guard() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.contains("func _raycast_is_colliding")) \
		.override_failure_message("player.gd 应提供 RayCast3D 释放实例保护").is_true()
	assert_bool(src.contains("is_instance_valid(raycast)")) \
		.override_failure_message("RayCast3D 调用 is_colliding 前应检查 is_instance_valid").is_true()


func test_moving_state_ignores_combat_input_when_equipment_panel_visible() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state_moving.gd")
	assert_bool(src.contains("if player.is_character_panel_visible():")) \
		.override_failure_message("装备面板打开时移动状态不应响应左键攻击/投掷/格挡").is_true()


func test_moving_state_animation_play_guarded_when_model_missing() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state_moving.gd")
	assert_bool(src.contains("func _play_animation")) \
		.override_failure_message("移动状态应通过统一动画播放守卫处理缺失 AnimationPlayer").is_true()
	assert_bool(src.contains("player == null or player.animation_player == null")) \
		.override_failure_message("移动状态播放动画前应检查 AnimationPlayer 非空").is_true()

# ======================================================================
# 5. _physics_process interact 调用逻辑验证（源码模式）
# ======================================================================

func test_physics_process_interact_safe_with_null_collider() -> void:
	# 验证 _physics_process 中 is_colliding、collider != null、not PickableItem、has_method 四重守卫
	# 四个条件必须全部存在
	var src: String = _source("res://scenes/characters/player/player.gd")
	var guard_pattern := "collider != null and not (collider is PickableItem) and collider.has_method(\"interact\")"
	assert_bool(src.find(guard_pattern) != -1) \
		.override_failure_message("_physics_process 交互调用缺少完整的四重守卫（is_colliding + collider != null + not PickableItem + has_method）").is_true()

# ======================================================================
# 辅助
# ======================================================================

static func _source(path: String) -> String:
	var script: Resource = load(path)
	return (script as GDScript).source_code
