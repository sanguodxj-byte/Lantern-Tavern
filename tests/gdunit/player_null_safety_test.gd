extends GdUnitTestSuite
## Player 系统空值守卫综合测试
## 验证 Player 及其所有子状态中 has_method 调用前均有 null 检查，
## 防止 "Attempt to call function 'has_method' in base 'null instance'" 错误。

# ======================================================================
# 1. player.gd — 主脚本空值守卫
# ======================================================================

func test_physics_process_interact_call_guarded() -> void:
	# _physics_process 中 select_collider.has_method("interact") 受 select_collider != null 保护
	# 变量名从 collider 改为 select_collider，因交互碰撞体现在经 _get_valid_select_collider() 统一过滤
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.find("select_collider != null and not (select_collider is PickableItem) and select_collider.has_method") != -1) \
		.override_failure_message("player.gd _physics_process: select_collider.has_method 前缺少 null 检查").is_true()

func test_check_for_possible_action_interact_call_guarded() -> void:
	# check_for_possible_action 中 collider.has_method("interact") 受 collider != null 保护 (line ~204)
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.find("collider != null and collider.has_method") != -1) \
		.override_failure_message("player.gd check_for_possible_action: collider.has_method 前缺少 null 检查").is_true()

func test_both_interact_call_sites_distinct() -> void:
	# 验证 player.gd 中两处交互调用点均有独立 null 守卫：
	# - _physics_process 用 select_collider != null（经 _get_valid_select_collider 过滤）
	# - check_for_possible_action 用 collider != null
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.find("select_collider != null") != -1) \
		.override_failure_message("_physics_process 交互调用点应使用 select_collider != null 守卫").is_true()
	assert_bool(src.find("collider != null") != -1) \
		.override_failure_message("check_for_possible_action 交互调用点应使用 collider != null 守卫").is_true()

func test_physics_process_uses_valid_collider_helper() -> void:
	# 回归：_physics_process 的交互路径必须经 _get_valid_select_collider() 取有效碰撞体，
	# 该辅助统一收口 is_instance_valid 过滤，避免 Chest/Door 被 queue_free 后下一帧解引用已释放对象。
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.contains("func _get_valid_select_collider()")) \
		.override_failure_message("player.gd 应提供 _get_valid_select_collider 辅助").is_true()
	assert_bool(src.contains("is_instance_valid(collider)")) \
		.override_failure_message("_get_valid_select_collider 必须用 is_instance_valid 过滤已释放碰撞体").is_true()
	# _physics_process 交互分支应调用该辅助而非直接 select_raycast.get_collider()
	var pp_start: int = src.find("func _physics_process")
	assert_int(pp_start).is_greater(0)
	var pp_end: int = src.find("\nfunc ", pp_start + 1)
	var pp_body: String = src.substr(pp_start, pp_end - pp_start)
	assert_bool(pp_body.contains("_get_valid_select_collider()")) \
		.override_failure_message("_physics_process 交互路径必须调用 _get_valid_select_collider()，不得直接 get_collider()").is_true()

func test_check_for_selection_uses_valid_collider_helper() -> void:
	# 回归：check_for_selection 必须经 _get_valid_select_collider() 取有效碰撞体，
	# 不得直接 select_raycast.get_collider() 后自行 is_instance_valid 过滤。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func check_for_selection")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_get_valid_select_collider()")) \
		.override_failure_message("check_for_selection 必须调用 _get_valid_select_collider()，不得直接 get_collider()").is_true()
	# 不得残留直接 get_collider + 手动 is_instance_valid 过滤模式
	assert_bool(not fn_body.contains("select_raycast.get_collider()")) \
		.override_failure_message("check_for_selection 不得直接调用 select_raycast.get_collider()，应统一走 _get_valid_select_collider()").is_true()

func test_check_for_possible_action_uses_valid_collider_helper() -> void:
	# 回归：check_for_possible_action 的 select_raycast 扫描必须经 _get_valid_select_collider()，
	# 不得直接 select_raycast.get_collider() 后自行 is_instance_valid 过滤。
	# kick_raycast 路径保留直接 get_collider() + is_instance_valid（Door 专用，不适用 select 辅助）。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func check_for_possible_action")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_get_valid_select_collider()")) \
		.override_failure_message("check_for_possible_action 必须调用 _get_valid_select_collider()，不得直接 get_collider()").is_true()
	# select_raycast 路径不得残留直接 get_collider 调用（kick_raycast 路径允许）
	var select_get_collider_count: int = fn_body.count("select_raycast.get_collider()")
	assert_int(select_get_collider_count).is_equal(0) \
		.override_failure_message("check_for_possible_action 不得对 select_raycast 直接调用 get_collider()，应统一走 _get_valid_select_collider()")

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
	# 验证 _physics_process 中 is_colliding、select_collider != null、not PickableItem、has_method 四重守卫
	# select_collider 经 _get_valid_select_collider() 取得，已含 is_instance_valid 过滤
	var src: String = _source("res://scenes/characters/player/player.gd")
	var guard_pattern := "select_collider != null and not (select_collider is PickableItem) and select_collider.has_method(\"interact\")"
	assert_bool(src.find(guard_pattern) != -1) \
		.override_failure_message("_physics_process 交互调用缺少完整的四重守卫（_get_valid_select_collider + select_collider != null + not PickableItem + has_method）").is_true()

# ======================================================================
# 6. _exit_tree 生命周期清理验证（源码模式）
# ======================================================================

func test_exit_tree_exists() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(src.contains("func _exit_tree()")) \
		.override_failure_message("player.gd 必须提供 _exit_tree 统一生命周期清理").is_true()

func test_exit_tree_disconnects_weapon_changed() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("weapon_changed.is_connected(_on_weapon_changed_for_view)")) \
		.override_failure_message("_exit_tree 必须检查并断开 weapon_changed 信号").is_true()
	assert_bool(fn_body.contains("weapon_changed.disconnect(_on_weapon_changed_for_view)")) \
		.override_failure_message("_exit_tree 必须断开 weapon_changed 信号").is_true()

func test_exit_tree_disconnects_chest_opened() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("chest_opened.is_connected(_on_chest_opened)")) \
		.override_failure_message("_exit_tree 必须检查并断开 chest_opened 信号").is_true()
	assert_bool(fn_body.contains("chest_opened.disconnect(_on_chest_opened)")) \
		.override_failure_message("_exit_tree 必须断开 chest_opened 信号").is_true()

func test_exit_tree_disconnects_skill_released() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("skill_released.is_connected(_on_skill_released)")) \
		.override_failure_message("_exit_tree 必须检查并断开 skill_released 信号").is_true()
	assert_bool(fn_body.contains("skill_released.disconnect(_on_skill_released)")) \
		.override_failure_message("_exit_tree 必须断开 skill_released 信号").is_true()

func test_exit_tree_calls_unregister_player() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("gs.unregister_player(self)")) \
		.override_failure_message("_exit_tree 必须调用 GameState.unregister_player(self) 清除全局引用").is_true()

func test_exit_tree_clears_focus_and_popup() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("current_pickable_focused_item = null")) \
		.override_failure_message("_exit_tree 必须清除 current_pickable_focused_item 引用").is_true()
	assert_bool(fn_body.contains("interaction_hint_changed.emit(\"\", \"\", Vector2.ZERO)")) \
		.override_failure_message("_exit_tree 必须发射空交互提示以隐藏悬浮窗").is_true()

func test_exit_tree_safely_releases_state_node() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _exit_tree")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("state_node != null and is_instance_valid(state_node)")) \
		.override_failure_message("_exit_tree 释放 state_node 前必须检查 is_instance_valid").is_true()
	assert_bool(fn_body.contains("state_node._begin_exit()")) \
		.override_failure_message("_exit_tree 必须通过 _begin_exit() 同步断开信号并清理，而非手动断开").is_true()
	assert_bool(fn_body.contains("state_node.queue_free()")) \
		.override_failure_message("_exit_tree 必须安全释放 state_node").is_true()

# ======================================================================
# 7. _begin_exit 受保护退出钩子验证（源码模式）
# ======================================================================

func test_player_state_has_begin_exit() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	assert_bool(src.contains("func _begin_exit()")) \
		.override_failure_message("PlayerState 基类必须提供 _begin_exit() 受保护退出钩子").is_true()

func test_player_state_has_on_exit_virtual() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	assert_bool(src.contains("func _on_exit()")) \
		.override_failure_message("PlayerState 基类必须提供 _on_exit() 虚方法供子类覆盖").is_true()

func test_begin_exit_sets_is_exiting_flag() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	assert_bool(src.contains("_is_exiting")) \
		.override_failure_message("PlayerState 必须有 _is_exiting 标志").is_true()
	var fn_start: int = src.find("func _begin_exit()")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_is_exiting = true")) \
		.override_failure_message("_begin_exit 必须设置 _is_exiting = true").is_true()

func test_begin_exit_disconnects_transition_requested() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	var fn_start: int = src.find("func _begin_exit()")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("transition_requested.is_connected")) \
		.override_failure_message("_begin_exit 必须检查 transition_requested 连接状态").is_true()
	assert_bool(fn_body.contains("transition_requested.disconnect")) \
		.override_failure_message("_begin_exit 必须断开 transition_requested 信号").is_true()

func test_begin_exit_disables_processing() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	var fn_start: int = src.find("func _begin_exit()")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("set_process(false)")) \
		.override_failure_message("_begin_exit 必须禁用 set_process").is_true()
	assert_bool(fn_body.contains("set_physics_process(false)")) \
		.override_failure_message("_begin_exit 必须禁用 set_physics_process").is_true()

func test_begin_exit_calls_on_exit() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	var fn_start: int = src.find("func _begin_exit()")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_on_exit()")) \
		.override_failure_message("_begin_exit 必须调用 _on_exit() 子类清理钩子").is_true()

func test_transition_state_guards_is_exiting() -> void:
	var src: String = _source("res://scenes/characters/player/state/player_state.gd")
	var fn_start: int = src.find("func transition_state")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("if _is_exiting:")) \
		.override_failure_message("transition_state 必须检查 _is_exiting 标志防止重入").is_true()
	assert_bool(fn_body.contains("return")) \
		.override_failure_message("transition_state 在 _is_exiting 时必须 return 不 emit").is_true()

func test_switch_state_calls_begin_exit() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func switch_state")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("_begin_exit()")) \
		.override_failure_message("switch_state 必须调用 _begin_exit() 同步退出旧状态").is_true()
	# 不得残留手动 set_process/set_physics_process（已由 _begin_exit 统一处理）
	assert_bool(not fn_body.contains("state_node.set_process(false)")) \
		.override_failure_message("switch_state 不应手动 set_process，已由 _begin_exit 统一处理").is_true()
	assert_bool(not fn_body.contains("state_node.set_physics_process(false)")) \
		.override_failure_message("switch_state 不应手动 set_physics_process，已由 _begin_exit 统一处理").is_true()

# ======================================================================
# 8. 伤害入口生命周期守卫验证（源码模式）
# take_acid_damage / take_spike_damage 必须与 try_receive_hit 保持一致的生命周期守卫，
# 防止 state_node 为 null 或已释放时解引用崩溃，并拒绝 HURT/DYING 重入。
# ======================================================================

func test_take_acid_damage_guards_state_node_null() -> void:
	# 回归：state_node 在状态切换帧间或 _ready 完成前可能为 null，
	# 缺守卫会触发 "Cannot call method 'can_die' on a null instance" 崩溃。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func take_acid_damage")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("state_node == null or not is_instance_valid(state_node)")) \
		.override_failure_message("take_acid_damage 必须检查 state_node null/有效性").is_true()
	assert_bool(fn_body.contains("is_queued_for_deletion()")) \
		.override_failure_message("take_acid_damage 必须检查 state_node.is_queued_for_deletion()").is_true()

func test_take_acid_damage_guards_hurt_dying_reentry() -> void:
	# 回归：已在 HURT/DYING 时不应重入，避免打断当前受击/死亡动画。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func take_acid_damage")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("state == State.HURT or state == State.DYING")) \
		.override_failure_message("take_acid_damage 必须拒绝 HURT/DYING 重入").is_true()

func test_take_spike_damage_validates_parameter() -> void:
	# 回归：spikes_trap 可能已被 queue_free，必须在访问属性前校验参数。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func take_spike_damage")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("spikes_trap == null or not is_instance_valid(spikes_trap)")) \
		.override_failure_message("take_spike_damage 必须校验 spikes_trap 参数 null/有效性").is_true()

func test_take_spike_damage_guards_state_node_null() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func take_spike_damage")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("state_node == null or not is_instance_valid(state_node)")) \
		.override_failure_message("take_spike_damage 必须检查 state_node null/有效性").is_true()
	assert_bool(fn_body.contains("is_queued_for_deletion()")) \
		.override_failure_message("take_spike_damage 必须检查 state_node.is_queued_for_deletion()").is_true()

func test_take_spike_damage_guards_hurt_dying_reentry() -> void:
	# 回归：踩刺时已在受击硬直中，缺守卫会重入 HURT 打断当前受击动画，
	# 与 try_receive_hit 拒绝重入受击的行为不一致。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func take_spike_damage")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("state == State.HURT or state == State.DYING")) \
		.override_failure_message("take_spike_damage 必须拒绝 HURT/DYING 重入").is_true()

# ======================================================================
# 9. _handle_skill_input 装备空值守卫验证（源码模式）
# equipment 组件在 _ready 异常中断或场景预览模式下可能为 null，
# 访问 has_weapon/has_shield 前必须守卫。
# ======================================================================

func test_handle_skill_input_guards_equipment_null() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _handle_skill_input")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	# 每处 equipment.weapon_data 访问必须配 equipment != null and equipment.has_weapon() 守卫
	var weapon_guard_count: int = fn_body.count("equipment != null and equipment.has_weapon()")
	assert_int(weapon_guard_count).is_greater(0) \
		.override_failure_message("_handle_skill_input 访问装备前必须检查 equipment != null and has_weapon()")
	# 每处 equipment.has_shield() 访问必须配 equipment != null 守卫
	var shield_guard_count: int = fn_body.count("equipment != null and equipment.has_shield()")
	assert_int(shield_guard_count).is_greater(0) \
		.override_failure_message("_handle_skill_input 访问盾牌前必须检查 equipment != null and has_shield()")

func test_handle_skill_input_no_bare_equipment_access() -> void:
	# 回归：不得存在未守卫的 equipment.weapon_data 或 equipment.has_shield() 裸访问
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func _handle_skill_input")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	# 裸 equipment.has_weapon()（不在三元守卫内的）不应存在
	# 所有 equipment 访问应出现在 "equipment != null and equipment.has_..." 模式中
	var bare_access: int = fn_body.count("equipment.has_weapon()") + fn_body.count("equipment.has_shield()")
	var guarded_access: int = fn_body.count("equipment != null and equipment.has_weapon()") + fn_body.count("equipment != null and equipment.has_shield()")
	assert_int(bare_access).is_equal(guarded_access) \
		.override_failure_message("_handle_skill_input 中所有 equipment.has_weapon()/has_shield() 必须受 equipment != null 守卫")

# ======================================================================
# 10. check_for_possible_action 射线调用优化验证（源码模式）
# _get_valid_select_collider() 每帧仅调用一次并复用，避免重复射线碰撞查询。
# ======================================================================

func test_check_for_possible_action_calls_valid_collider_once() -> void:
	# 回归：_get_valid_select_collider() 包含射线碰撞查询，每帧重复调用造成无谓开销；
	# 修复后保存首次结果到 select_collider 并复用，函数体内仅出现一次调用。
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func check_for_possible_action")
	assert_int(fn_start).is_greater(0)
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	var call_count: int = fn_body.count("= _get_valid_select_collider()")
	# 恰好一次调用（赋值给 select_collider），后续复用变量而非再次调用
	assert_int(call_count).is_equal(1) \
		.override_failure_message("check_for_possible_action 应仅调用一次 _get_valid_select_collider() 并复用结果，实际调用 %d 次" % call_count)

func test_check_for_possible_action_reuses_select_collider_var() -> void:
	# 回归：复用 select_collider 变量构建 hint，而非重新调用 _get_valid_select_collider()
	var src: String = _source("res://scenes/characters/player/player.gd")
	var fn_start: int = src.find("func check_for_possible_action")
	var fn_end: int = src.find("\nfunc ", fn_start + 1)
	var fn_body: String = src.substr(fn_start, fn_end - fn_start)
	assert_bool(fn_body.contains("var select_collider: Object = _get_valid_select_collider()")) \
		.override_failure_message("check_for_possible_action 应将 _get_valid_select_collider() 结果存入 select_collider").is_true()
	# 后续 hint 构建应复用 select_collider 而非重新调用
	assert_bool(fn_body.contains("var collider: Object = select_collider")) \
		.override_failure_message("check_for_possible_action 应复用 select_collider 构建 hint").is_true()

# ======================================================================
# 11. 死代码移除验证（源码模式）
# _collect_visual_meshes_player / _is_inside_tavern 已无调用方，移除避免维护负担。
# ======================================================================

func test_dead_code_collect_visual_meshes_player_removed() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(not src.contains("_collect_visual_meshes_player")) \
		.override_failure_message("已移除的死代码 _collect_visual_meshes_player 不应残留").is_true()

func test_dead_code_is_inside_tavern_removed() -> void:
	var src: String = _source("res://scenes/characters/player/player.gd")
	assert_bool(not src.contains("_is_inside_tavern")) \
		.override_failure_message("已移除的死代码 _is_inside_tavern 不应残留").is_true()

# ======================================================================
# 辅助
# ======================================================================

static func _source(path: String) -> String:
	var script: Resource = load(path)
	return (script as GDScript).source_code
